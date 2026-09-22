#!/usr/bin/env python3
"""
Notion (or any KaTeX-rendered page) -> local markdown wiki.

The hard part of this job is not fetching the page, it is that KaTeX renders
every formula three times in the DOM (MathML text, the LaTeX annotation, and
the visual HTML layer). A markdown converter concatenates all three, so
"O(n^2)" arrives as "O(n2)O(n^2)O(n2)". This script pulls the real LaTeX out of
<annotation encoding="application/x-tex"> in the raw HTML and splices it back
into the markdown, then downloads images locally and splits the page into files.

Subcommands:
  build      scrape files -> wiki files + report.json
  digest     print each section's headings and opening lines (to write summaries)
  summaries  apply a JSON of per-section summaries and regenerate index.md
  verify     re-run the integrity checks against an existing output directory

Run `python notion_to_md.py <subcommand> --help` for arguments.
"""

import argparse
import html as htmllib
import json
import os
import re
import sys
import urllib.request
from html.parser import HTMLParser

# A backslash must be built via chr(92): some shells mangle it inside heredocs,
# and this file gets copied around a lot.
BACKSLASH = chr(92)

# Same trick for the letter yo: the repo keeps its own text free of it, but
# wikis built before that rule carry the section marker spelled with yo. It is
# matched in both spellings, so a rebuild replaces the old header line instead
# of stacking a second one on top of it.
YO = chr(1105)
DROP = set('​⁡⁢⁣﻿' + BACKSLASH)
UA = {'User-Agent': 'Mozilla/5.0'}


# --------------------------------------------------------------------------
# loading scrape artifacts
# --------------------------------------------------------------------------

def load_scrape(path, key):
    """Accept either a firecrawl JSON result or a raw .md/.html file.

    Large firecrawl results get spilled to a file by the tool layer; that file
    is JSON with a 'markdown' or 'rawHtml' key. Small ones may be pasted raw.
    """
    raw = open(path, encoding='utf-8').read()
    stripped = raw.lstrip()
    if stripped.startswith('{'):
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            return raw
        if key in data:
            return data[key]
        for alt in ('markdown', 'rawHtml', 'html', 'content'):
            if alt in data:
                return data[alt]
        raise SystemExit('No %s in %s (keys: %s)' % (key, path, list(data)))
    return raw


def norm_map(s):
    """Strip whitespace, zero-width chars and backslashes; keep an index map.

    Backslashes go because markdown escapes them inconsistently (`\\times` vs
    `\times`), and we only use the normalized form for *locating* text - the
    LaTeX we splice in comes from the HTML annotation, which is clean.
    """
    out, idx = [], []
    for i, ch in enumerate(s):
        if ch.isspace() or ch in DROP:
            continue
        out.append(ch)
        idx.append(i)
    return ''.join(out), idx


# --------------------------------------------------------------------------
# KaTeX extraction
# --------------------------------------------------------------------------

class KatexParser(HTMLParser):
    """Collect (visible_text, latex, is_display) for every .katex span."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.pairs = []
        self.depth = 0
        self.vis = []
        self.tex = []
        self.in_annotation = False
        self.pending_display = False
        self.is_display = False

    def handle_starttag(self, tag, attrs):
        cls = dict(attrs).get('class', '')
        if self.depth == 0:
            # .katex-display wraps the .katex span for block formulas
            if 'katex-display' in cls:
                self.pending_display = True
                return
            if re.search(r'(^| )katex( |$)', cls):
                self.depth = 1
                self.vis, self.tex = [], []
                self.is_display = self.pending_display
                self.pending_display = False
        else:
            self.depth += 1
            if tag == 'annotation':
                self.in_annotation = True

    def handle_endtag(self, tag):
        if self.depth > 0:
            if tag == 'annotation':
                self.in_annotation = False
            self.depth -= 1
            if self.depth == 0:
                latex = ''.join(self.tex).strip()
                if latex:
                    self.pairs.append((''.join(self.vis), latex, self.is_display))
                self.is_display = False

    def handle_data(self, data):
        if self.depth > 0:
            self.vis.append(data)
            if self.in_annotation:
                self.tex.append(data)


def boundary_ok(md, s, e, vn, strict):
    """Decide whether replacing md[s:e] with a formula is safe.

    Two failure modes, both seen in practice:
      - a one-char formula like `n` matching inside the word "position",
        producing "at positio$n$n"
      - a formula `0` matching three of the four zeros in "0.0001",
        producing "0.$0$1" and silently deleting digits
    Guarding the surrounding characters prevents both.
    """
    left = md[s - 1] if s > 0 else ''
    right = md[e] if e < len(md) else ''
    # never cut into a number
    if vn.replace('.', '').isdigit() and (left.isdigit() or right.isdigit()):
        return False
    # a very short formula sitting between two letters is almost certainly
    # a slice of a word, not a formula
    if len(vn) <= 3 and left.isalpha() and right.isalpha():
        return False
    if strict and left.isalnum():
        return False
    return True


def restore_math(md, pairs):
    """Splice real LaTeX back into the markdown. Returns (md, stats)."""
    # Key by the *normalized* text, not the raw one: Notion happily renders
    # `R^2` and `R^2 ` as two DOM nodes that collapse to the same search key,
    # and keying on the raw text would report the second one as "unmatched"
    # even though every occurrence was placed correctly.
    uniq = {}
    occurrences = {}
    for vis, tex, disp in pairs:
        vn, _ = norm_map(vis)
        if not vn:
            continue
        if vn not in uniq:
            uniq[vn] = (tex, disp)
        occurrences[vn] = occurrences.get(vn, 0) + 1

    mdn, imap = norm_map(md)
    taken = [False] * len(mdn)
    spans = []
    placed_count = {}

    def place(vn, strict):
        """Replace at most as many occurrences as the page actually contains.

        Without the cap, a formula that appears once replaces every textual
        match of itself. The formula `0` then eats three of the four zeros in
        "10,000" somewhere else on the page and the digits are gone for good -
        a silent corruption that reads perfectly fine.
        """
        tex, disp = uniq[vn]
        if not vn:
            return 0
        limit = occurrences.get(vn, 1) - placed_count.get(vn, 0)
        placed, j = 0, 0
        while placed < limit:
            j = mdn.find(vn, j)
            if j < 0:
                break
            if any(taken[j:j + len(vn)]):
                j += 1
                continue
            s, e = imap[j], imap[j + len(vn) - 1] + 1
            if not boundary_ok(md, s, e, vn, strict):
                j += 1
                continue
            for q in range(j, j + len(vn)):
                taken[q] = True
            repl = ('\n\n$$\n%s\n$$\n\n' % tex) if disp else ('$%s$' % tex)
            spans.append((s, e, repl))
            placed += 1
            j += len(vn)
        placed_count[vn] = placed_count.get(vn, 0) + placed
        return placed

    # Longest first: a long formula must claim its text before a short one
    # can match a fragment of it.
    by_len = sorted(uniq, key=len, reverse=True)
    for v in by_len:
        place(v, strict=True)
    # anything still short of its occurrence count gets a second, looser try
    remaining = [v for v in by_len if placed_count.get(v, 0) < occurrences[v]]
    for v in remaining:
        place(v, strict=False)
    unmatched = [v for v in by_len if placed_count.get(v, 0) == 0]

    spans.sort(key=lambda t: t[0], reverse=True)
    prev, applied = len(md), 0
    for s, e, r in spans:
        if e > prev:          # overlapping match, skip
            continue
        md = md[:s] + r + md[e:]
        prev = s
        applied += 1

    md = md.replace('​', '').replace('⁡', '')
    md = re.sub(r'[ \t]+\n', '\n', md)
    md = re.sub(r'\n{4,}', '\n\n\n', md)

    stats = {
        'katex_blocks': len(pairs),
        'unique_formulas': len(uniq),
        'replacements_applied': applied,
        'unmatched_unique': len(unmatched),
    }
    if unmatched:
        # Usually harmless: a short formula whose text was already consumed by
        # a longer one that contains it. It matters only if the integrity
        # checks below also complain, so say so rather than alarm the reader.
        stats['unmatched_note'] = ('formulas whose text was claimed by a longer '
                                   'overlapping one; harmless unless a check below fails')
    return md, stats


# --------------------------------------------------------------------------
# images
# --------------------------------------------------------------------------

IMG_RE = re.compile(r'!\[([^\]]*)\]\(([^)]+)\)')


def full_url_from_html(url, raw_html):
    """Firecrawl truncates image URLs at '(' - e.g. '...rnn_(2'.

    The page's raw HTML still has the whole thing, so look it up by the
    attachment UUID and recover it.
    """
    m = re.search(r'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})', url)
    if not m or not raw_html:
        return url
    hit = re.search(r'https://[^"\'\\ >]*' + re.escape(m.group(1)) + r'[^"\'\\ >]*', raw_html)
    return htmllib.unescape(hit.group(0)) if hit else url


def fetch_image(url, dest, raw_html=None):
    """Download one image. Notion signs image URLs with an expiring token, so
    the file must be stored locally - the link itself goes stale within hours.
    """
    attempts = [url]
    recovered = full_url_from_html(url, raw_html)
    if recovered != url:
        attempts.append(recovered)
    attempts.append(recovered.replace('(', '%28').replace(')', '%29'))
    last = None
    for candidate in attempts:
        try:
            req = urllib.request.Request(candidate, headers=UA)
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            if data:
                open(dest, 'wb').write(data)
                return len(data), None
        except Exception as exc:                      # noqa: BLE001
            last = '%s' % exc
    return 0, last or 'no data'


def localize_images(body, section_no, slug, att_dir, raw_html, report):
    counter = [0]

    def repl(m):
        alt, url = m.group(1), m.group(2)
        if '/icons/' in url:            # Notion's own UI icons, not content
            return ''
        # Firecrawl strips data-URIs and leaves this literal behind. It is
        # always a Notion emoji (callout icons and the like), never content,
        # and trying to fetch it throws "unknown url type".
        if 'Base64-Image-Removed' in url or not url.lower().startswith('http'):
            return ''
        counter[0] += 1
        ext_m = re.search(r'%3A[^%?]+?\.(png|jpg|jpeg|gif|webp|svg)', url) or \
            re.search(r'\.(png|jpg|jpeg|gif|webp|svg)', url)
        ext = '.' + ext_m.group(1) if ext_m else '.png'
        name = '%02d-%s-%d%s' % (section_no, slug, counter[0], ext)
        path = os.path.join(att_dir, name)
        if not os.path.exists(path) or os.path.getsize(path) == 0:
            size, err = fetch_image(url, path, raw_html)
            report.append({'file': name, 'bytes': size, 'error': err})
            if err:
                return m.group(0)       # leave the remote link, flag in report
        return '![%s](attachments/%s)' % (alt or slug, name)

    return IMG_RE.sub(repl, body)


# --------------------------------------------------------------------------
# splitting
# --------------------------------------------------------------------------

def slugify(title):
    s = title.lower()
    s = re.sub(r'[^a-z0-9]+', '-', s).strip('-')
    s = re.sub(r'^(the|a|an)-', '', s)
    return s or 'section'


TOC_LINK = re.compile(r'^\[[^\]]*\]\([^)]*#[0-9a-f]{8,}\)$')
PAGE_ICON = re.compile(r'^!\[[^\]]*[Ii]con[^\]]*\]\(')


def strip_chrome(md):
    """Remove Notion's page furniture, keeping everything that is content.

    Deliberately narrow: only the skip-link, page/callout icons and the
    anchor-link table of contents. Cutting at the first H2 instead - the
    obvious shortcut - silently eats real content that sits above it, such as
    an author line or an overview diagram.
    """
    # Firecrawl replaces data-URI images with this literal. They are Notion's
    # inline emoji (callout icons), so they go - and they must go here, not
    # only at image-download time, or the prose check will flag every line
    # that contained one as missing.
    md = re.sub(r'!\[[^\]]*\]\(<Base64-Image-Removed>\)', '', md)
    out = []
    for line in md.split('\n'):
        s = line.strip()
        if s.startswith('[Skip to content]'):
            continue
        if TOC_LINK.match(s):
            continue
        if PAGE_ICON.match(s):
            continue
        out.append(line)
    return '\n'.join(out)


def split_sections(md):
    """Split into (intro, [(title, body), ...]).

    `intro` is whatever content precedes the first H2 once the page furniture
    and the H1 title are gone - often empty, sometimes an author line and a
    diagram that would otherwise be lost.
    """
    md = strip_chrome(md)
    head, sep, rest = md.partition('\n## ')
    intro = '\n'.join(l for l in head.split('\n') if not l.startswith('# ')).strip()
    if not sep:
        return intro, []
    out = []
    for chunk in re.split(r'\n## ', rest):
        if not chunk.strip():
            continue
        title, _, body = chunk.partition('\n')
        out.append((title.strip(), body.strip()))
    return intro, out


def write_index(dst, title, source_url, saved_on, entries, note=None):
    lines = ['# %s' % title, '']
    if source_url:
        lines.append('Локальная копия: [%s](%s).' % (title, source_url))
    if saved_on:
        lines.append('Сохранено %s. Формулы восстановлены как LaTeX, картинки — в `attachments/`.' % saved_on)
    lines += ['', '## Разделы', '']
    for n, stem, sec_title, summary in entries:
        # section 0 is the intro that preceded the first heading - it has no
        # number in the original, so it gets none here either
        label = '**[[%s|%s]]**' % (stem, sec_title if n else 'Вступление')
        prefix = '' if n == 0 else '%d. ' % n
        lines.append('%s%s — %s' % (prefix, label, summary) if summary
                     else '%s%s' % (prefix, label))
        lines.append('')
    if note:
        lines += [note, '']
    lines += ['> Формулы в формате `$...$` и `$$...$$` — Obsidian рендерит их из коробки;',
              '> другому редактору нужен MathJax или KaTeX.', '']
    open(os.path.join(dst, 'index.md'), 'w', encoding='utf-8').write('\n'.join(lines))


# --------------------------------------------------------------------------
# verification
# --------------------------------------------------------------------------

def verify(source_md, out_text, dst, pairs=None):
    """Catch the failure modes that are silent otherwise.

    A wrong formula is obvious on sight; a *deleted digit* is not. These checks
    are what turn "looks fine" into "verified".

    `pairs` (from KatexParser) lets the prose check know which source lines
    carried formulas - those lines changed on purpose and comparing them would
    only produce noise.
    """
    issues = {}

    # 1. LaTeX commands that ended up outside math delimiters
    outside = re.sub(r'\$\$.*?\$\$|\$[^$\n]*\$', '', out_text, flags=re.S)
    issues['latex_outside_math'] = re.findall(BACKSLASH + r'[a-zA-Z]{2,}', outside)[:20]

    # 2. words cut in half by a short formula
    issues['split_words'] = re.findall(
        r'[a-zA-Z]\$[A-Za-z0-9]{1,2}\$|\$[A-Za-z0-9]{1,2}\$[a-zA-Z]', out_text)[:20]

    # 3. numbers that lost digits (compare against the original scrape).
    #    Count only prose occurrences - URLs carry numbers like width=2000
    #    that never belong in the output anyway.
    lost = []
    if source_md:
        prose_lines = [l for l in source_md.split('\n') if 'http' not in l]
        prose = '\n'.join(prose_lines)
        for num in set(re.findall(r'\d[\d,.]*0{3}[\d,.]*', prose)):
            if out_text.count(num) < prose.count(num):
                lost.append(num)
    issues['numbers_lost'] = lost

    # 4. images that never made it to disk
    broken = []
    for fn in sorted(f for f in os.listdir(dst) if f.endswith('.md')):
        text = open(os.path.join(dst, fn), encoding='utf-8').read()
        for link in IMG_RE.findall(text):
            url = link[1]
            if url.startswith('http'):
                broken.append('%s: remote link left: %s' % (fn, url[:70]))
                continue
            p = os.path.join(dst, url.replace('/', os.sep))
            if not os.path.exists(p) or os.path.getsize(p) == 0:
                broken.append('%s: %s' % (fn, url))
    issues['broken_images'] = broken

    # 5. prose that vanished.
    #    Any source line that held a formula was rewritten on purpose, so
    #    comparing it is meaningless. Skip exactly those lines - identified by
    #    the KaTeX text we extracted - and demand that everything else survived
    #    verbatim. Without `pairs` there is no reliable way to tell the two
    #    apart, so the check reports itself as skipped rather than guessing.
    if not source_md:
        issues['prose_missing'] = []
    elif pairs is None:
        issues['prose_missing'] = []
        issues['prose_check'] = ['skipped: pass --html to enable']
    else:
        norm = lambda s: re.sub(r'[^a-z0-9]', '', s.lower())   # noqa: E731
        formula_texts = {n for n in (norm(v) for v, _, _ in pairs) if len(n) >= 3}
        # Check the whole document, not just from the first H2 down. Anchoring
        # the check to the same cut the splitter makes would make it blind to
        # exactly the content the splitter might drop.
        body = strip_chrome(source_md)
        outn = norm(out_text)
        missing = []
        for line in body.split('\n'):
            line = line.strip()
            if len(line) < 46 or 'http' in line:
                continue
            ln = norm(line)
            # either the line contains a formula, or - for a display formula
            # that markdown broke across several lines - the line is a slice
            # of one
            if not ln or any(f in ln or ln in f for f in formula_texts):
                continue
            if ln not in outn:
                missing.append(line[:100])
        issues['prose_missing'] = missing[:20]

    counts = {k: len(v) for k, v in issues.items()}
    return counts, issues


def print_report(stats, counts, issues, images):
    print('\n=== formulas ===')
    for k, v in stats.items():
        print('  %-24s %s' % (k, v))
    print('\n=== images ===')
    ok = sum(1 for i in images if not i['error'])
    print('  downloaded %d / %d' % (ok, len(images)))
    for i in images:
        if i['error']:
            print('    FAILED %s: %s' % (i['file'], i['error']))
    print('\n=== integrity checks ===')
    labels = {
        'latex_outside_math': 'LaTeX leaking outside math',
        'split_words': 'words split by a formula',
        'numbers_lost': 'numbers that lost digits',
        'broken_images': 'broken image links',
        'prose_missing': 'prose lines missing',
    }
    clean = True
    for k, label in labels.items():
        n = counts.get(k, 0)
        print('  %-30s %s' % (label, n if n else 'none'))
        if n:
            clean = False
            for item in issues[k][:5]:
                print('      - %s' % item)
    if issues.get('prose_check'):
        print('  %-30s %s' % ('prose check', issues['prose_check'][0]))
    print('\n%s' % ('ALL CHECKS CLEAN' if clean else 'ISSUES FOUND - see above'))
    return clean


# --------------------------------------------------------------------------
# subcommands
# --------------------------------------------------------------------------

def cmd_build(a):
    md = load_scrape(a.markdown, 'markdown')
    raw_html = load_scrape(a.html, 'rawHtml') if a.html else ''
    source_md = md

    pairs = None
    if raw_html:
        parser = KatexParser()
        parser.feed(raw_html)
        pairs = parser.pairs
        md, stats = restore_math(md, pairs)
    else:
        stats = {'katex_blocks': 0, 'note': 'no --html given, formulas left as-is'}

    dst = a.out
    att = os.path.join(dst, 'attachments')
    os.makedirs(att, exist_ok=True)

    # Rebuilds must be idempotent. Image filenames are positional, so editing
    # the input shifts them and orphaned files pile up; clear what a previous
    # run of this script created (and nothing else) before writing again.
    prev = os.path.join(dst, 'report.json')
    if os.path.exists(prev):
        try:
            old = json.load(open(prev, encoding='utf-8'))
            for sec in old.get('sections', []):
                f = os.path.join(dst, '%s.md' % sec['stem'])
                if os.path.exists(f):
                    os.remove(f)
            for img in old.get('images', []):
                f = os.path.join(att, img['file'])
                if os.path.exists(f):
                    os.remove(f)
            for f in ('index.md', 'report.json'):
                p = os.path.join(dst, f)
                if os.path.exists(p):
                    os.remove(p)
        except Exception:                             # noqa: BLE001
            pass

    intro, sections = split_sections(md)
    if not sections:
        raise SystemExit('No H2 sections found - is this the right markdown?')

    images = []
    entries = []
    if a.split == 'single':
        slug = slugify(a.title or 'notes')
        body = '\n\n'.join('## %s\n\n%s' % (t, b) for t, b in sections)
        if intro:
            body = intro + '\n\n' + body
        body = localize_images(body, 1, slug, att, raw_html, images)
        header = '# %s\n\n' % (a.title or 'Notes')
        if a.source_url:
            header += '> Источник: [%s](%s)\n\n' % (a.title or a.source_url, a.source_url)
        open(os.path.join(dst, '%s.md' % slug), 'w', encoding='utf-8').write(header + body + '\n')
        entries.append((1, slug, a.title or 'Notes', ''))
    else:
        # Content above the first H2 - author line, an overview diagram -
        # is real content, not furniture. Give it file 00 rather than dropping it.
        if intro:
            intro_body = localize_images(intro, 0, 'intro', att, raw_html, images)
            stem = '00-intro'
            header = '# %s\n\n' % (a.title or 'Вступление')
            if a.source_url:
                header += '> Источник: [%s](%s) · оглавление: [[index]]\n\n' % (
                    a.title or 'оригинал', a.source_url)
            open(os.path.join(dst, '%s.md' % stem), 'w', encoding='utf-8').write(
                header + intro_body.strip() + '\n')
            entries.append((0, stem, a.title or 'Вступление', ''))

        for n, (title, body) in enumerate(sections, 1):
            slug = slugify(title)
            body = localize_images(body, n, slug, att, raw_html, images)
            body = re.sub(r'\n{3,}', '\n\n', body).strip()
            stem = '%02d-%s' % (n, slug)
            header = '# %s\n\n' % title
            if a.source_url:
                header += '> Источник: [%s](%s) · раздел %d из %d · оглавление: [[index]]\n\n' % (
                    a.title or 'оригинал', a.source_url, n, len(sections))
            open(os.path.join(dst, '%s.md' % stem), 'w', encoding='utf-8').write(header + body + '\n')
            entries.append((n, stem, title, ''))

    write_index(dst, a.title or 'Конспект', a.source_url, a.saved_on, entries)

    out_text = ''.join(
        open(os.path.join(dst, f), encoding='utf-8').read()
        for f in sorted(os.listdir(dst)) if f.endswith('.md'))
    counts, issues = verify(source_md, out_text, dst, pairs)
    clean = print_report(stats, counts, issues, images)

    json.dump({'stats': stats, 'images': images, 'checks': counts, 'details': issues,
               'sections': [{'n': n, 'stem': s, 'title': t} for n, s, t, _ in entries]},
              open(os.path.join(dst, 'report.json'), 'w', encoding='utf-8'),
              ensure_ascii=False, indent=2)
    print('\nreport: %s' % os.path.join(dst, 'report.json'))
    return 0 if clean else 1


def cmd_digest(a):
    """Headings plus opening lines per section - enough to write an accurate
    summary without pulling the whole document into context."""
    for fn in sorted(f for f in os.listdir(a.out) if re.match(r'\d\d-.*\.md$', f)):
        text = open(os.path.join(a.out, fn), encoding='utf-8').read()
        lines = [l.strip() for l in text.split('\n')]
        print('=' * 70)
        print(fn)
        subs = [i for i, l in enumerate(lines) if l.startswith('###')]
        if not subs:
            shown = 0
            for l in lines[1:]:
                if l and not l.startswith('>') and not l.startswith('#'):
                    print('    %s' % l[:130])
                    shown += 1
                    if shown >= 6:
                        break
            continue
        for i in subs:
            print('  %s' % lines[i])
            shown = 0
            for l in lines[i + 1:]:
                if l.startswith('###'):
                    break
                if l and not l.startswith('$') and not l.startswith('!['):
                    print('      - %s' % l[:120])
                    shown += 1
                    if shown >= 2:
                        break


def cmd_summaries(a):
    """Apply {"01-slug": "текст саммари", ...} to file headers and the index."""
    data = json.load(open(a.summaries, encoding='utf-8'))
    report = json.load(open(os.path.join(a.out, 'report.json'), encoding='utf-8'))
    entries = []
    total = sum(1 for s in report['sections'] if s['n'])      # intro is not a numbered section
    for sec in report['sections']:
        stem, n, title = sec['stem'], sec['n'], sec['title']
        summary = data.get(stem) or data.get(str(n)) or ''
        path = os.path.join(a.out, '%s.md' % stem)
        text = open(path, encoding='utf-8').read()
        body = text.split('\n', 1)[1]
        # Оба регэкспа заякорены на начало, а в файле маркер стоит выше строки Источника,
        # поэтому снимать его надо первым: в обратном порядке повторный прогон
        # дописывал вторую строку Источника.
        body = re.sub(r'^\s*> \*\*О ч[%sе]м раздел\.\*\*[^\n]*\n(>\n)?' % YO, '', body)
        body = re.sub(r'^\s*> Источник:[^\n]*\n+', '', body)
        where = ('раздел %d из %d · ' % (n, total)) if n else ''
        head = '# %s\n\n' % title
        if summary:
            head += '> **О чем раздел.** %s\n>\n' % summary
        if summary or a.source_url:
            head += '> Источник: [%s](%s) · %sоглавление: [[index]]\n\n' % (
                a.title or 'оригинал', a.source_url or '', where)
        open(path, 'w', encoding='utf-8').write(head + body.lstrip('\n'))
        entries.append((n, stem, title, summary))
    write_index(a.out, a.title or 'Конспект', a.source_url, a.saved_on, entries)
    print('summaries applied to %d sections, index.md regenerated' % len(entries))


def cmd_verify(a):
    source_md = load_scrape(a.markdown, 'markdown') if a.markdown else ''
    pairs = None
    if a.html:
        parser = KatexParser()
        parser.feed(load_scrape(a.html, 'rawHtml'))
        pairs = parser.pairs
    out_text = ''.join(
        open(os.path.join(a.out, f), encoding='utf-8').read()
        for f in sorted(os.listdir(a.out)) if f.endswith('.md'))
    counts, issues = verify(source_md, out_text, a.out, pairs)
    clean = print_report({}, counts, issues, [])
    return 0 if clean else 1


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd', required=True)

    b = sub.add_parser('build', help='scrape files -> wiki files')
    b.add_argument('--markdown', required=True, help='firecrawl markdown result (JSON or raw)')
    b.add_argument('--html', help='firecrawl rawHtml result - required for formulas')
    b.add_argument('--out', required=True, help='destination directory')
    b.add_argument('--title', help='page title')
    b.add_argument('--source-url', help='original URL, used in headers')
    b.add_argument('--saved-on', help='date string for the index')
    b.add_argument('--split', choices=['h2', 'single'], default='h2')
    b.set_defaults(func=cmd_build)

    d = sub.add_parser('digest', help='print section topics for writing summaries')
    d.add_argument('--out', required=True)
    d.set_defaults(func=cmd_digest)

    s = sub.add_parser('summaries', help='apply summaries JSON and rebuild index')
    s.add_argument('--out', required=True)
    s.add_argument('--summaries', required=True)
    s.add_argument('--title')
    s.add_argument('--source-url')
    s.add_argument('--saved-on')
    s.set_defaults(func=cmd_summaries)

    v = sub.add_parser('verify', help='re-run integrity checks')
    v.add_argument('--out', required=True)
    v.add_argument('--markdown', help='original scrape, enables the number check')
    v.add_argument('--html', help='original rawHtml, enables the prose check')
    v.set_defaults(func=cmd_verify)

    a = p.parse_args()
    sys.exit(a.func(a) or 0)


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    main()
