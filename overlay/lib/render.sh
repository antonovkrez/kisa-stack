# Рендеринг правил из шаблонов апстрима.
# Якоря - заголовки и начала пунктов. Не найден якорь или остался плейсхолдер -
# падаем громко: остановленная установка лучше молча испорченных правил.

RENDER_LABEL=""

strip_html_comments() {
  awk '{
    line = $0; out = ""; touched = in_c
    while (line != "") {
      if (in_c) {
        e = index(line, "-->")
        if (e == 0) { line = "" } else { line = substr(line, e + 3); in_c = 0 }
      } else {
        s = index(line, "<!--")
        if (s == 0) { out = out line; line = "" }
        else { touched = 1; out = out substr(line, 1, s - 1); line = substr(line, s + 4); in_c = 1 }
      }
    }
    if (touched && out ~ /^[ \t]*$/) next
    print out
  }'
}

squeeze_blank() { awk 'NF == 0 { b++; if (b > 1) next } NF > 0 { b = 0 } { print }'; }

# Убрать пустые строки в начале, пустые строки и повисшие "---" в конце.
trim_edges() {
  awk '{ l[NR] = $0 }
    END {
      s = 1; while (s <= NR && l[s] ~ /^[ \t]*$/) s++
      n = NR; while (n >= s && (l[n] ~ /^[ \t]*$/ || l[n] == "---")) n--
      for (i = s; i <= n; i++) print l[i]
    }'
}

_finish_cut() {
  if [ "$1" -ne 0 ]; then rm -f "$2.tmp"; exit 1; fi
  mv "$2.tmp" "$2"
}

# cut_to_eof <file> <anchor>: удалить от строки, равной anchor, до конца файла.
cut_to_eof() {
  local rc=0
  A="$2" L="$RENDER_LABEL" awk '
    $0 == ENVIRON["A"] { found = 1 }
    !found { print }
    END { if (!found) { printf "[harness] E_ANCHOR в %s не найден якорь: %s\n", ENVIRON["L"], ENVIRON["A"] > "/dev/stderr"; exit 3 } }
  ' "$1" > "$1.tmp" || rc=$?
  _finish_cut "$rc" "$1"
}

# cut_until <file> <anchor> <stop>: удалить от anchor до строки перед stop.
cut_until() {
  local rc=0
  A="$2" B="$3" L="$RENDER_LABEL" awk '
    !fa && $0 == ENVIRON["A"] { fa = 1; skip = 1 }
    skip && $0 == ENVIRON["B"] { fb = 1; skip = 0 }
    !skip { print }
    END {
      if (!fa) { printf "[harness] E_ANCHOR в %s не найден якорь: %s\n", ENVIRON["L"], ENVIRON["A"] > "/dev/stderr"; exit 3 }
      if (!fb) { printf "[harness] E_ANCHOR в %s не найден якорь: %s\n", ENVIRON["L"], ENVIRON["B"] > "/dev/stderr"; exit 3 }
    }
  ' "$1" > "$1.tmp" || rc=$?
  _finish_cut "$rc" "$1"
}

# cut_line <file> <prefix>: удалить строки, начинающиеся с prefix.
cut_line() {
  local rc=0
  A="$2" L="$RENDER_LABEL" awk '
    index($0, ENVIRON["A"]) == 1 { found = 1; next }
    { print }
    END { if (!found) { printf "[harness] E_ANCHOR в %s не найден якорь: %s\n", ENVIRON["L"], ENVIRON["A"] > "/dev/stderr"; exit 3 } }
  ' "$1" > "$1.tmp" || rc=$?
  _finish_cut "$rc" "$1"
}

# cut_bullet <file> <prefix>: удалить пункт списка и его строки с отступом 2+ пробела.
cut_bullet() {
  local rc=0
  A="$2" L="$RENDER_LABEL" awk '
    skip && /^  / { next }
    { skip = 0 }
    index($0, ENVIRON["A"]) == 1 { found = 1; skip = 1; next }
    { print }
    END { if (!found) { printf "[harness] E_ANCHOR в %s не найден якорь: %s\n", ENVIRON["L"], ENVIRON["A"] > "/dev/stderr"; exit 3 } }
  ' "$1" > "$1.tmp" || rc=$?
  _finish_cut "$rc" "$1"
}

# Буквальная замена: в путях бывают & и другие символы, особые для sed и gsub.
replace_literal() {
  FROM="$2" TO="$3" awk '{
    s = $0; out = ""; n = length(ENVIRON["FROM"])
    while ((i = index(s, ENVIRON["FROM"])) > 0) {
      out = out substr(s, 1, i - 1) ENVIRON["TO"]
      s = substr(s, i + n)
    }
    print out s
  }' "$1" > "$1.tmp"
  mv "$1.tmp" "$1"
}

# Плейсхолдер апстрима - токен <...> без пробелов с подчеркиванием внутри.
# Иллюстративные <проект-2> и <project> под правило не попадают.
check_placeholders() {
  local hits
  hits="$(grep -nE '<[^<> ]*_[^<> ]*>' "$1" || true)"
  [ -z "$hits" ] || die "E_PLACEHOLDER в $RENDER_LABEL остались плейсхолдеры:"$'\n'"$hits"
}

# render_rules <claude|agents> <template> <extra_file_or_empty> <out_file>
render_rules() {
  local kind="$1" template="$2" extra="$3" out="$4" work
  RENDER_LABEL="$(basename "$template")"
  mkdir -p "$(dirname "$out")"
  work="$out.work"
  sed 's/\r$//' "$template" | strip_html_comments > "$work"

  if [ "$kind" = claude ]; then
    if [ "$WIKI_ENABLED" = 0 ]; then
      cut_to_eof "$work" '# LLM Wiki'
    else
      [ "$MCP_OBSIDIAN" = 1 ]      || cut_line   "$work" '**Проверка структуры vault'
      [ "$AUTO_MEMORY_OFF" = 1 ]   || cut_until  "$work" '## Память' '## ObsidianDataWeave'
      [ "$DATAWEAVE_ENABLED" = 1 ] || cut_to_eof "$work" '## ObsidianDataWeave'
    fi
  else
    [ "$RTK_ENABLED" = 1 ] || cut_bullet "$work" '- Для шумных команд предпочитай'
    if [ "$WIKI_ENABLED" = 0 ]; then
      cut_until "$work" '# Память и LLM Wiki' '# Skills'
    else
      [ "$DATAWEAVE_ENABLED" = 1 ] || cut_bullet "$work" '- Предпочитай пайплайн ObsidianDataWeave:'
    fi
  fi

  if [ "$WIKI_ENABLED" = 1 ]; then
    replace_literal "$work" '<ПУТЬ_К_VAULT>/LLM Wiki' "$WIKI_DIR"
  fi
  if [ "$DATAWEAVE_ENABLED" = 1 ]; then
    replace_literal "$work" '<ПУТЬ_К_КЛОНУ>' "$DATAWEAVE_REPO"
  fi
  check_placeholders "$work"

  {
    squeeze_blank < "$work" | trim_edges
    if [ -n "$extra" ] && [ -s "$extra" ]; then
      printf '\n'
      sed 's/\r$//' "$extra"
      [ -z "$(tail -c1 "$extra")" ] || printf '\n'
    fi
  } > "$out"
  rm -f "$work"
}
