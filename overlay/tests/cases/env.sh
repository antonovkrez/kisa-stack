test_env_plan_ok_on_clean_sandbox() {
  run_ok plan
  assert_contains "$SB/out.log" 'RUNTIME claude'
  assert_contains "$SB/out.log" 'RUNTIME codex'
  assert_contains "$SB/out.log" 'RUNTIME hermes'
}

test_env_profile_missing() {
  rm -f "$HARNESS_PROFILE"
  run_fail E_PROFILE plan
}

test_env_bad_flag() {
  write_profile 'WIKI_ENABLED=yes'
  run_fail E_PROFILE plan
}

test_env_backslash_path() {
  write_profile "WIKI_DIR='C:\\Users\\me\\wiki'"
  run_fail E_PROFILE plan
}

test_env_wiki_dir_missing() {
  rm -rf "$SB/wiki"
  run_fail E_WIKI_DIR plan
}

test_env_wiki_off_needs_no_dir() {
  rm -rf "$SB/wiki"
  write_profile 'WIKI_ENABLED=0'
  run_ok plan
}

test_env_explicit_style_needs_bash() {
  write_profile 'HOOK_COMMAND_STYLE=explicit'
  run_fail E_PROFILE plan
}

test_env_runtime_skipped() {
  rm -rf "$HERMES_HOME"
  run_ok plan
  assert_contains "$SB/out.log" 'SKIP    runtime hermes'
}

test_env_no_runtimes() {
  rm -rf "$HOME/.claude" "$CODEX_HOME" "$HERMES_HOME"
  run_fail E_PREREQ plan
}

test_env_unknown_mode() {
  if run_harness frobnicate; then fail "неизвестный режим должен падать"; fi
}

test_env_jq_missing() {
  (
    load_libs
    command() { if [ "${2:-}" = jq ]; then return 1; fi; builtin command "$@"; }
    check_prereqs
  ) > "$SB/out.log" 2>&1 && fail "без jq проверка должна падать"
  assert_contains "$SB/out.log" E_PREREQ
}

test_env_profile_cannot_override_build_dir() {
  write_profile "BUILD_DIR=\"$SB/evil\""
  run_fail E_PROFILE plan
  assert_no_path "$SB/evil"
}

test_env_profile_cannot_override_render_dir() {
  write_profile "RENDER_DIR=\"$SB/evil-render\""
  run_ok plan
  assert_no_path "$SB/evil-render"
}

test_env_profile_cannot_override_upstream_dir() {
  write_profile "UPSTREAM_DIR=\"$SB/evil-upstream\""
  run_fail E_PROFILE plan
}

test_env_profile_cannot_override_claude_bin() {
  write_profile "CLAUDE_BIN=\"$SB/evil-claude\""
  run_fail E_PROFILE plan
}
