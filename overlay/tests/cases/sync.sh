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
  _write_sync_conf '# комментарий' '' 'x-content-advisor' 'zaebal  https://example.com/z.git  v1.0'
  run_ok sync
  assert_contains "$SB/out.log" 'ENTRY   text x-content-advisor'
  assert_contains "$SB/out.log" 'ENTRY   software zaebal https://example.com/z.git v1.0'
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
