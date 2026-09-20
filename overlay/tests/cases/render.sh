_render_defaults() {
  WIKI_ENABLED=1; WIKI_DIR="$SB/wiki"; AUTO_MEMORY_OFF=0; MCP_OBSIDIAN=0
  DATAWEAVE_ENABLED=0; DATAWEAVE_REPO=""; RTK_ENABLED=0
}
_CLAUDE_TPL() { printf '%s' "$REPO_DIR/global-config/CLAUDE.md"; }
_AGENTS_TPL() { printf '%s' "$REPO_DIR/global-config/AGENTS.md"; }

test_render_claude_defaults() {
  load_libs; _render_defaults
  ( render_rules claude "$(_CLAUDE_TPL)" "" "$SB/o.md" ) || fail "рендер упал"
  assert_eq "$(head -n1 "$SB/o.md")" '# Кто ты'
  assert_contains "$SB/o.md" '# LLM Wiki'
  assert_contains "$SB/o.md" "$SB/wiki/claude-code/"
  assert_contains "$SB/o.md" '<проект-2>'
  assert_not_contains "$SB/o.md" '<!--'
  assert_not_contains "$SB/o.md" 'ПУТЬ_К'
  assert_not_contains "$SB/o.md" '## Память'
  assert_not_contains "$SB/o.md" '## ObsidianDataWeave'
  assert_not_contains "$SB/o.md" 'Проверка структуры vault'
}

test_render_claude_wiki_off() {
  load_libs; _render_defaults; WIKI_ENABLED=0
  ( render_rules claude "$(_CLAUDE_TPL)" "" "$SB/o.md" ) || fail "рендер упал"
  assert_not_contains "$SB/o.md" '# LLM Wiki'
  assert_contains "$SB/o.md" '# Скиллы и инструменты'
  [ "$(tail -n1 "$SB/o.md")" != '---' ] || fail "в конце остался повисший разделитель"
}

test_render_claude_all_on() {
  load_libs; _render_defaults
  AUTO_MEMORY_OFF=1; MCP_OBSIDIAN=1; DATAWEAVE_ENABLED=1; DATAWEAVE_REPO="C:/src"
  ( render_rules claude "$(_CLAUDE_TPL)" "" "$SB/o.md" ) || fail "рендер упал"
  assert_contains "$SB/o.md" '## Память'
  assert_contains "$SB/o.md" 'Проверка структуры vault'
  assert_contains "$SB/o.md" 'C:/src/ObsidianDataWeave'
  assert_not_contains "$SB/o.md" 'ПУТЬ_К'
}

test_render_agents_defaults() {
  load_libs; _render_defaults
  ( render_rules agents "$(_AGENTS_TPL)" "" "$SB/o.md" ) || fail "рендер упал"
  assert_contains "$SB/o.md" '# Память и LLM Wiki'
  assert_contains "$SB/o.md" "$SB/wiki/codex/pages/overview.md"
  assert_contains "$SB/o.md" '# Skills'
  assert_not_contains "$SB/o.md" 'Для шумных команд предпочитай'
  assert_not_contains "$SB/o.md" 'Предпочитай пайплайн ObsidianDataWeave'
  assert_not_contains "$SB/o.md" 'ПУТЬ_К'
  assert_not_contains "$SB/o.md" '<!--'
}

test_render_agents_wiki_off() {
  load_libs; _render_defaults; WIKI_ENABLED=0
  ( render_rules agents "$(_AGENTS_TPL)" "" "$SB/o.md" ) || fail "рендер упал"
  assert_not_contains "$SB/o.md" '# Память и LLM Wiki'
  assert_contains "$SB/o.md" '# Skills'
  assert_not_contains "$SB/o.md" 'ПУТЬ_К'
}

test_render_path_with_ampersand() {
  load_libs; _render_defaults; WIKI_DIR='C:/Users/me/My & Wiki'
  ( render_rules claude "$(_CLAUDE_TPL)" "" "$SB/o.md" ) || fail "рендер упал"
  assert_contains "$SB/o.md" 'C:/Users/me/My & Wiki/claude-code/'
}

test_render_crlf_template_same_result() {
  load_libs; _render_defaults
  sed 's/$/\r/' "$(_CLAUDE_TPL)" > "$SB/CLAUDE.md"
  ( render_rules claude "$(_CLAUDE_TPL)" "" "$SB/lf.md" ) || fail "рендер LF упал"
  ( render_rules claude "$SB/CLAUDE.md" "" "$SB/crlf.md" ) || fail "рендер CRLF упал"
  cmp -s "$SB/lf.md" "$SB/crlf.md" || fail "CRLF-шаблон дал другой результат"
}

test_render_extra_appended() {
  load_libs; _render_defaults
  printf 'MY-OVERLAY-RULE' > "$SB/extra.md"      # без перевода строки в конце
  ( render_rules claude "$(_CLAUDE_TPL)" "$SB/extra.md" "$SB/o.md" ) || fail "рендер упал"
  assert_eq "$(tail -n1 "$SB/o.md")" 'MY-OVERLAY-RULE'
  [ -z "$(tail -c1 "$SB/o.md")" ] || fail "результат не заканчивается переводом строки"
}

test_render_missing_anchor_fails() {
  load_libs; _render_defaults; WIKI_ENABLED=0
  printf '# Кто ты\n\nтекст без вики-секции\n' > "$SB/t.md"
  ( render_rules claude "$SB/t.md" "" "$SB/o.md" ) > "$SB/out.log" 2>&1 \
    && fail "шаблон без якоря должен давать ошибку"
  assert_contains "$SB/out.log" E_ANCHOR
}

test_render_leftover_placeholder_fails() {
  load_libs; _render_defaults
  AUTO_MEMORY_OFF=1; MCP_OBSIDIAN=1; DATAWEAVE_ENABLED=1; DATAWEAVE_REPO="C:/src"
  printf '# LLM Wiki\n\nпуть: <ПУТЬ_К_ЧЕМУ_ТО>\n' > "$SB/t.md"
  ( render_rules claude "$SB/t.md" "" "$SB/o.md" ) > "$SB/out.log" 2>&1 \
    && fail "недозамененный плейсхолдер должен давать ошибку"
  assert_contains "$SB/out.log" E_PLACEHOLDER
}
