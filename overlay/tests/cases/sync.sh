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
}

test_sync_conf_bad_field_count() {
  _write_sync_conf 'x-content-advisor' 'zaebal https://example.com/z.git'
  run_fail E_PROFILE sync
  assert_contains "$SB/out.log" 'строка 2'
}

test_sync_py_catalog_from_fixture() {
  local out
  out="$(python3 "$OVERLAY_DIR/lib/sync.py" catalog unused 2>&1)" || fail "sync.py упал: $out"
  assert_eq "$out" 'alpha'$'\n''beta'
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
