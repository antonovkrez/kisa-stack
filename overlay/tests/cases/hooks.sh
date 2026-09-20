_SETTINGS() { printf '%s' "$HOME/.claude/settings.json"; }

test_hooks_installed() {
  run_ok apply
  assert_file "$HOME/.claude/hooks/wiki-anchor.sh"
  assert_file "$HOME/.claude/hooks/wiki-reminder.sh"
  [ -x "$HOME/.claude/hooks/wiki-anchor.sh" ] || fail "хук не исполняемый"
  if has_cr "$HOME/.claude/hooks/wiki-anchor.sh"; then fail "в хуке остались CR"; fi
  assert_eq "$(jqt -r '.env.WIKI_VAULT' < "$(_SETTINGS)")" "$SB/wiki"
  assert_eq "$(jqt -r '.hooks.SessionStart[0].matcher' < "$(_SETTINGS)")" 'startup|resume|compact'
  assert_eq "$(jqt -r '.hooks.SessionStart[0].hooks[0].command' < "$(_SETTINGS)")" '$HOME/.claude/hooks/wiki-anchor.sh'
  assert_eq "$(jqt -r '.hooks.UserPromptSubmit[0].hooks[0].command' < "$(_SETTINGS)")" '$HOME/.claude/hooks/wiki-reminder.sh'
  assert_eq "$(jqt -r 'has("autoMemoryEnabled")' < "$(_SETTINGS)")" 'false'
}

test_hooks_foreign_preserved_no_dupes() {
  cat > "$(_SETTINGS)" <<'JSON'
{
  "model": "opus",
  "env": { "FOO": "1" },
  "hooks": {
    "SessionStart": [ { "matcher": "startup", "hooks": [ { "type": "command", "command": "echo mine" } ] } ],
    "Stop": [ { "hooks": [ { "type": "command", "command": "echo stop" } ] } ]
  }
}
JSON
  run_ok apply
  export HARNESS_TS="20260101-000001"
  run_ok apply
  assert_eq "$(jqt -r '.model' < "$(_SETTINGS)")" 'opus'
  assert_eq "$(jqt -r '.env.FOO' < "$(_SETTINGS)")" '1'
  assert_eq "$(jqt -r '.hooks.SessionStart | length' < "$(_SETTINGS)")" '2'
  assert_eq "$(jqt -r '.hooks.SessionStart[0].hooks[0].command' < "$(_SETTINGS)")" 'echo mine'
  assert_eq "$(jqt -r '.hooks.UserPromptSubmit | length' < "$(_SETTINGS)")" '1'
  assert_eq "$(jqt -r '.hooks.Stop[0].hooks[0].command' < "$(_SETTINGS)")" 'echo stop'
  assert_file "$HOME/.kisa-harness/backups/20260101-000000/.claude/settings.json"
  assert_no_path "$HOME/.kisa-harness/backups/20260101-000001"
}

test_hooks_wiki_off() {
  write_profile 'WIKI_ENABLED=0'
  run_ok apply
  assert_no_path "$HOME/.claude/hooks"
  assert_no_path "$(_SETTINGS)"
}

test_hooks_no_claude_runtime() {
  rm -rf "$HOME/.claude"
  run_ok apply
  assert_no_path "$HOME/.claude"
  assert_file "$CODEX_HOME/AGENTS.md"
}

test_hooks_invalid_json_stops_before_any_write() {
  printf '{broken' > "$(_SETTINGS)"
  local before; before="$(tree_hash "$HOME")"
  run_fail E_JSON apply
  assert_eq "$(tree_hash "$HOME")" "$before"
}

test_hooks_explicit_style() {
  write_profile 'HOOK_COMMAND_STYLE=explicit' 'HOOK_BASH="C:/Program Files/Git/bin/bash.exe"'
  run_ok apply
  local cmd; cmd="$(jqt -r '.hooks.SessionStart[0].hooks[0].command' < "$(_SETTINGS)")"
  case "$cmd" in
    '"C:/Program Files/Git/bin/bash.exe" "'*'/.claude/hooks/wiki-anchor.sh"') ;;
    *) fail "неожиданная команда: $cmd" ;;
  esac
}

test_hooks_style_switch_updates_in_place() {
  run_ok apply
  write_profile 'HOOK_COMMAND_STYLE=explicit' 'HOOK_BASH="C:/Program Files/Git/bin/bash.exe"'
  export HARNESS_TS="20260101-000001"
  run_ok apply
  assert_eq "$(jqt -r '.hooks.SessionStart | length' < "$(_SETTINGS)")" '1'
  assert_eq "$(jqt -r '.hooks.UserPromptSubmit | length' < "$(_SETTINGS)")" '1'
  assert_contains "$(_SETTINGS)" 'bash.exe'
}

test_hooks_automem_off() {
  write_profile 'AUTO_MEMORY_OFF=1'
  run_ok apply
  assert_eq "$(jqt -r '.autoMemoryEnabled' < "$(_SETTINGS)")" 'false'
  assert_contains "$HOME/.claude/CLAUDE.md" '## Память'
}

test_hooks_same_semantics_not_rewritten() {
  run_ok apply
  jqt -c . < "$(_SETTINGS)" > "$SB/compact.json"
  cp "$SB/compact.json" "$(_SETTINGS)"
  export HARNESS_TS="20260101-000001"
  run_ok apply
  cmp -s "$(_SETTINGS)" "$SB/compact.json" || fail "файл с той же семантикой был переписан"
}

test_hooks_missing_wiki_pages_warn() {
  run_ok plan
  assert_contains "$SB/out.log" 'WARN'
  assert_contains "$SB/out.log" 'claude-code/pages/overview.md'
}

test_hooks_foreign_non_string_command_survives() {
  cat > "$(_SETTINGS)" <<'JSON'
{
  "hooks": {
    "SessionStart": [ { "matcher": "startup", "hooks": [ { "type": "command", "command": 123 } ] } ]
  }
}
JSON
  run_ok apply
  assert_eq "$(jqt -r '.hooks.SessionStart | length' < "$(_SETTINGS)")" '2'
  assert_eq "$(jqt -r '.hooks.SessionStart[0].hooks[0].command' < "$(_SETTINGS)")" '123'
  assert_eq "$(jqt -r '.hooks.SessionStart[1].hooks[0].command' < "$(_SETTINGS)")" '$HOME/.claude/hooks/wiki-anchor.sh'
}

test_hooks_foreign_null_hooks_survives() {
  cat > "$(_SETTINGS)" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [ { "matcher": "foo", "hooks": null } ]
  }
}
JSON
  run_ok apply
  export HARNESS_TS="20260101-000001"
  run_ok apply
  assert_eq "$(jqt -r '.hooks.UserPromptSubmit | length' < "$(_SETTINGS)")" '2'
  assert_eq "$(jqt -r '.hooks.UserPromptSubmit[0].matcher' < "$(_SETTINGS)")" 'foo'
  assert_eq "$(jqt -r '.hooks.UserPromptSubmit[0].hooks' < "$(_SETTINGS)")" 'null'
  assert_eq "$(jqt -r '.hooks.UserPromptSubmit[1].hooks[0].command' < "$(_SETTINGS)")" '$HOME/.claude/hooks/wiki-reminder.sh'
}
