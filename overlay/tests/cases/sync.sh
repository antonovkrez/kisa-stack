_write_sync_conf() {
  printf '%s\n' "$@" > "$HARNESS_SYNC_CONF"
}

test_sync_mode_accepted() {
  _write_sync_conf '# пусто'
  run_ok sync
  assert_contains "$SB/out.log" 'режим: sync plan'
}

test_sync_apply_submode_accepted() {
  _write_sync_conf '# пусто'
  run_ok sync apply
  assert_contains "$SB/out.log" 'режим: sync apply'
}

test_sync_rejects_extra_arg() {
  _write_sync_conf '# пусто'
  if run_harness sync apply extra; then fail "лишний аргумент должен падать"; fi
}

test_sync_conf_missing_is_error() {
  rm -f "$HARNESS_SYNC_CONF"
  run_fail E_PROFILE sync
}

test_sync_conf_parses_text_and_software() {
  _write_sync_conf '# комментарий' '' 'alpha' 'zaebal  https://example.com/z.git  v1.0'
  run_ok sync
  assert_contains "$SB/out.log" 'SYNC    alpha: new'
  assert_contains "$SB/out.log" 'SYNC    zaebal: софт, ревизия v1.0'
  assert_contains "$SB/out.log" 'софтовая ветка не реализована, пропущен'
}

test_sync_conf_bad_field_count() {
  _write_sync_conf 'x-content-advisor' 'zaebal https://example.com/z.git'
  run_fail E_PROFILE sync
  assert_contains "$SB/out.log" 'строка 2'
}

test_sync_conf_ignores_bom() {
  printf '\357\273\277alpha\n' > "$HARNESS_SYNC_CONF"
  run_ok sync
  assert_contains "$SB/out.log" 'SYNC    alpha: new'
}

test_sync_conf_rejects_inline_comment() {
  _write_sync_conf 'alpha # моя заметка'
  run_fail E_PROFILE sync
  assert_contains "$SB/out.log" 'комментарий пишется отдельной строкой'
}

test_sync_conf_rejects_duplicate_pack() {
  _write_sync_conf 'alpha' 'alpha'
  run_fail E_PROFILE sync
  assert_contains "$SB/out.log" 'пак alpha уже объявлен в строке 1'
}

test_sync_py_catalog_from_fixture() {
  local out
  out="$(python3 "$OVERLAY_DIR/lib/sync.py" catalog unused 2>&1)" || fail "sync.py упал: $out"
  assert_eq "$out" 'alpha'$'\t''Первый тестовый пак.'$'\n''beta'$'\t''Второй тестовый пак.'
}

test_sync_py_unknown_pack_is_e_mcp() {
  local out rc=0
  out="$(python3 "$OVERLAY_DIR/lib/sync.py" render unused nosuch "$SB/out" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || fail "неизвестный пак должен давать ненулевой код"
  case "$out" in
    E_MCP*) ;;
    *) fail "ожидался E_MCP, получено: $out" ;;
  esac
}

test_sync_materializes_text_pack() {
  _write_sync_conf 'alpha'
  run_ok sync apply
  assert_file "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md"
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" 'name: alpha'
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" 'description: "Первый тестовый пак."'
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" 'tags: ["one", "two"]'
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" 'Тело первого пака.'
}

test_sync_puts_triggers_under_deploychan() {
  _write_sync_conf 'alpha'
  run_ok sync apply
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" '  deploychan:'
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" 'triggers: ["запусти альфу", "нужна альфа"]'
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" 'reminder: "Помни про альфу."'
}

test_sync_normalizes_summary_and_skips_null_reminder() {
  _write_sync_conf 'beta'
  run_ok sync apply
  assert_contains "$HARNESS_OVERLAY_SKILLS/beta/SKILL.md" 'description: "Второй тестовый пак с \"кавычками\" и переводом строки."'
  assert_not_contains "$HARNESS_OVERLAY_SKILLS/beta/SKILL.md" 'reminder:'
  assert_not_contains "$HARNESS_OVERLAY_SKILLS/beta/SKILL.md" 'triggers:'
}

test_sync_writes_origin_marker() {
  _write_sync_conf 'alpha'
  run_ok sync apply
  assert_file "$HARNESS_OVERLAY_SKILLS/alpha/.harness-origin"
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/.harness-origin" 'deploychan:alpha sha256:'
}

test_sync_plan_writes_nothing() {
  _write_sync_conf 'alpha'
  local before; before="$(tree_hash "$HARNESS_OVERLAY_SKILLS")"
  run_ok sync
  assert_contains "$SB/out.log" 'SYNC    alpha: new'
  assert_eq "$(tree_hash "$HARNESS_OVERLAY_SKILLS")" "$before"
  assert_no_path "$HARNESS_OVERLAY_SKILLS/alpha"
}

test_sync_second_run_is_same() {
  _write_sync_conf 'alpha'
  run_ok sync apply
  local before; before="$(tree_hash "$HARNESS_OVERLAY_SKILLS")"
  run_ok sync apply
  assert_contains "$SB/out.log" 'SYNC    alpha: same'
  assert_eq "$(tree_hash "$HARNESS_OVERLAY_SKILLS")" "$before"
}

test_sync_updates_when_catalog_changed() {
  _write_sync_conf 'alpha'
  run_ok sync apply
  local fixture="$SB/catalog.json"
  sed 's/Тело первого пака./Тело первого пака, версия два./' \
    "$REPO_DIR/overlay/tests/fixtures/catalog.json" > "$fixture"
  export HARNESS_MCP_FIXTURE="$fixture"
  run_ok sync apply
  assert_contains "$SB/out.log" 'SYNC    alpha: updated'
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" 'версия два'
  run_ok sync apply
  assert_contains "$SB/out.log" 'SYNC    alpha: same'
}

test_sync_does_not_overwrite_edited_file() {
  _write_sync_conf 'alpha'
  run_ok sync apply
  printf 'МОЯ ПРАВКА\n' >> "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md"
  local before; before="$(cksum < "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md")"
  run_ok sync apply
  assert_contains "$SB/out.log" 'SYNC    alpha: edited'
  assert_eq "$(cksum < "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md")" "$before"
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" 'МОЯ ПРАВКА'
  assert_contains "$SB/out.log" 'git log -p overlay/skills/alpha/SKILL.md'
  assert_contains "$SB/out.log" '-МОЯ ПРАВКА'
}

test_sync_does_not_touch_foreign_skill() {
  mkdir -p "$HARNESS_OVERLAY_SKILLS/alpha"
  printf -- '---\nname: alpha\ndescription: мой скилл\n---\nМОЕ ТЕЛО\n' \
    > "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md"
  printf 'capture DESKTOP 2026-09-21\n' > "$HARNESS_OVERLAY_SKILLS/alpha/.harness-origin"
  _write_sync_conf 'alpha'
  local before; before="$(cksum < "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md")"
  run_ok sync apply
  assert_contains "$SB/out.log" 'SYNC    alpha: foreign'
  assert_eq "$(cksum < "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md")" "$before"
}

test_sync_lists_undeclared_catalog_packs() {
  _write_sync_conf 'alpha'
  run_ok sync
  assert_contains "$SB/out.log" 'SKIP    beta: нет в sync.conf'
  assert_not_contains "$SB/out.log" 'SKIP    alpha:'
  assert_contains "$SB/out.log" 'SKIP    beta: нет в sync.conf — Второй тестовый пак.'
}

test_sync_declared_pack_missing_from_catalog() {
  _write_sync_conf 'nosuch'
  run_fail E_MCP sync
  assert_contains "$SB/out.log" 'Синк остановлен, ничего не записано'
}

test_sync_unreachable_server_writes_nothing() {
  _write_sync_conf 'alpha'
  export HARNESS_MCP_FIXTURE=""
  export HARNESS_SYNC_MCP_URL="http://127.0.0.1:9/mcp"
  local before; before="$(tree_hash "$HARNESS_OVERLAY_SKILLS")"
  run_fail E_MCP sync apply
  assert_contains "$SB/out.log" 'Синк остановлен, ничего не записано'
  assert_eq "$(tree_hash "$HARNESS_OVERLAY_SKILLS")" "$before"
  assert_contains "$SB/out.log" 'сервер http://127.0.0.1:9/mcp недоступен'
}

test_sync_url_does_not_leak_into_rollout() {
  export HARNESS_SYNC_MCP_URL="http://127.0.0.1:9/mock"
  run_ok apply
  assert_contains "$CODEX_HOME/config.toml" 'url = "https://mcp.deploychan.webcam/mcp"'
  assert_not_contains "$CODEX_HOME/config.toml" '127.0.0.1:9'
}

test_sync_bad_url_is_e_mcp_without_traceback() {
  _write_sync_conf 'alpha'
  export HARNESS_MCP_FIXTURE=""
  export HARNESS_SYNC_MCP_URL="not-a-url"
  run_fail E_MCP sync
  assert_contains "$SB/out.log" 'сервер not-a-url недоступен'
  assert_not_contains "$SB/out.log" 'Traceback'
}

test_sync_does_not_touch_runtime_skills() {
  _write_sync_conf 'alpha'
  mkdir -p "$HOME/.claude/skills" "$HOME/.codex/skills"
  local before_claude before_codex
  before_claude="$(tree_hash "$HOME/.claude")"
  before_codex="$(tree_hash "$HOME/.codex")"
  run_ok sync apply
  assert_eq "$(tree_hash "$HOME/.claude")" "$before_claude"
  assert_eq "$(tree_hash "$HOME/.codex")" "$before_codex"
}

test_sync_missing_pack_writes_nothing() {
  _write_sync_conf 'alpha' 'nosuch'
  local before; before="$(tree_hash "$HARNESS_OVERLAY_SKILLS")"
  run_fail E_MCP sync apply
  assert_contains "$SB/out.log" 'пака nosuch нет в каталоге deploychan'
  assert_eq "$(tree_hash "$HARNESS_OVERLAY_SKILLS")" "$before"
}

test_sync_catalog_failure_writes_nothing() {
  _write_sync_conf 'alpha'
  local fixture="$SB/catalog.json"
  sed 's/"list_skills"/"list_skills_gone"/' \
    "$REPO_DIR/overlay/tests/fixtures/catalog.json" > "$fixture"
  export HARNESS_MCP_FIXTURE="$fixture"
  local before; before="$(tree_hash "$HARNESS_OVERLAY_SKILLS")"
  run_fail E_MCP sync apply
  assert_contains "$SB/out.log" 'не удалось получить каталог'
  assert_eq "$(tree_hash "$HARNESS_OVERLAY_SKILLS")" "$before"
}

test_sync_prints_summary_line() {
  _write_sync_conf 'alpha'
  run_ok sync
  assert_contains "$SB/out.log" 'итог: новых 1, обновлено 0, правлено руками 0, чужих 0, без изменений 0, не объявлено 1'
}

test_sync_reminds_to_read_diffs_only_when_changed() {
  _write_sync_conf 'alpha'
  run_ok sync apply
  assert_contains "$SB/out.log" 'Читайте их как код'
  run_ok sync apply
  assert_contains "$SB/out.log" 'без изменений 1'
  assert_not_contains "$SB/out.log" 'Читайте их как код'
}

test_sync_apply_prints_next_step() {
  _write_sync_conf 'alpha'
  run_ok sync
  assert_not_contains "$SB/out.log" 'Дальше: git diff'
  run_ok sync apply
  assert_contains "$SB/out.log" 'Дальше: git diff, коммит, overlay/harness.sh apply'
  run_ok sync apply
  assert_not_contains "$SB/out.log" 'Дальше: git diff'
}

test_sync_warns_about_pack_removed_from_conf() {
  _write_sync_conf 'alpha'
  run_ok sync apply
  _write_sync_conf '# пусто'
  run_ok sync apply
  assert_contains "$SB/out.log" 'alpha пришел из синка, но в sync.conf его нет'
  assert_file "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md"
}

test_sync_foreign_without_marker() {
  mkdir -p "$HARNESS_OVERLAY_SKILLS/alpha"
  printf -- '---\nname: alpha\ndescription: мой скилл\n---\nМОЕ ТЕЛО\n' \
    > "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md"
  _write_sync_conf 'alpha'
  local before; before="$(cksum < "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md")"
  run_ok sync apply
  assert_contains "$SB/out.log" 'SYNC    alpha: foreign'
  assert_eq "$(cksum < "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md")" "$before"
  assert_no_path "$HARNESS_OVERLAY_SKILLS/alpha/.harness-origin"
}

test_sync_marker_without_skill_file_is_edited() {
  _write_sync_conf 'alpha'
  run_ok sync apply
  rm "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md"
  run_ok sync apply
  assert_contains "$SB/out.log" 'SYNC    alpha: edited'
  assert_not_contains "$SB/out.log" 'Traceback'
  assert_no_path "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md"
}

test_sync_rejects_malformed_pack() {
  _write_sync_conf 'alpha'
  local fixture="$SB/catalog.json"
  sed 's/"tags": \["one", "two"\]/"tags": "one"/' \
    "$REPO_DIR/overlay/tests/fixtures/catalog.json" > "$fixture"
  export HARNESS_MCP_FIXTURE="$fixture"
  run_fail E_MCP sync apply
  assert_contains "$SB/out.log" 'формат ответа каталога изменился: у пака alpha поле tags не список строк'
  assert_not_contains "$SB/out.log" 'Traceback'
  assert_no_path "$HARNESS_OVERLAY_SKILLS/alpha"
}

test_sync_rejects_control_characters_in_body() {
  _write_sync_conf 'alpha'
  local fixture="$SB/catalog.json"
  sed 's/Тело первого пака\./Тело \\u001b[8mскрыто\\u001b[0m первого пака./' \
    "$REPO_DIR/overlay/tests/fixtures/catalog.json" > "$fixture"
  export HARNESS_MCP_FIXTURE="$fixture"
  run_fail E_MCP sync apply
  assert_contains "$SB/out.log" 'пак alpha отклонен: в поле body управляющий символ U+001B'
  assert_no_path "$HARNESS_OVERLAY_SKILLS/alpha"
}

test_sync_rejects_bidi_characters_in_catalog() {
  _write_sync_conf 'alpha'
  local fixture="$SB/catalog.json"
  sed 's/"summary": "Второй тестовый пак\."/"summary": "Второй \\u202eтестовый пак."/' \
    "$REPO_DIR/overlay/tests/fixtures/catalog.json" > "$fixture"
  export HARNESS_MCP_FIXTURE="$fixture"
  run_fail E_MCP sync
  assert_contains "$SB/out.log" 'пак beta отклонен: в поле summary управляющий символ U+202E'
}

test_sync_second_pack_failure_writes_nothing() {
  _write_sync_conf 'alpha' 'beta'
  local fixture="$SB/catalog.json"
  sed 's/"body": "# Beta/"body_gone": "# Beta/' \
    "$REPO_DIR/overlay/tests/fixtures/catalog.json" > "$fixture"
  export HARNESS_MCP_FIXTURE="$fixture"
  local before; before="$(tree_hash "$HARNESS_OVERLAY_SKILLS")"
  run_fail E_MCP sync apply
  assert_contains "$SB/out.log" 'у пака beta нет поля body'
  assert_eq "$(tree_hash "$HARNESS_OVERLAY_SKILLS")" "$before"
  assert_no_path "$HARNESS_OVERLAY_SKILLS/alpha"
}

test_sync_py_catalog_truncates_long_summary() {
  local fixture="$SB/catalog.json" out
  sed 's/"summary": "Второй тестовый пак\."/"summary": "Описание длиннее восьмидесяти символов, чтобы проверить, что строка SKIP в выводе синка обрезается аккуратно."/' \
    "$REPO_DIR/overlay/tests/fixtures/catalog.json" > "$fixture"
  out="$(HARNESS_MCP_FIXTURE="$fixture" python3 "$OVERLAY_DIR/lib/sync.py" catalog unused 2>&1)" ||
    fail "sync.py упал: $out"
  assert_eq "$out" 'alpha'$'\t''Первый тестовый пак.'$'\n''beta'$'\t''Описание длиннее восьмидесяти символов, чтобы проверить, что строка SKIP в вы...'
}

test_sync_py_sends_own_user_agent() {
  local out
  out="$(HARNESS_MCP_FIXTURE="" python3 -c '
import sys, urllib.request
sys.path.insert(0, sys.argv[1])
import sync
seen = {}
def fake_urlopen(request, timeout=None):
    seen["ua"] = request.get_header("User-agent")
    raise OSError("остановлено тестом")
urllib.request.urlopen = fake_urlopen
try:
    sync.call("http://127.0.0.1:9/mcp", "list_skills", {})
except sync.McpError:
    pass
print(seen.get("ua"))
' "$OVERLAY_DIR/lib" 2>&1)" || fail "python упал: $out"
  assert_eq "$out" 'kisa-harness-sync/1.0'
}
