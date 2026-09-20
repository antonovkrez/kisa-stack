_TOML() { printf '%s' "$CODEX_HOME/config.toml"; }

_stub_claude() {
  cat > "$SB/claude" <<'STUB'
#!/usr/bin/env bash
here="$(dirname "$0")"
printf '%s\n' "$*" >> "$here/claude.log"
if [ "${1:-} ${2:-}" = "mcp list" ] && [ -f "$here/connected" ]; then
  echo "deploychan: https://mcp.deploychan.webcam/mcp (HTTP) - Connected"
fi
exit 0
STUB
  chmod +x "$SB/claude"
  : > "$SB/claude.log"
  export HARNESS_CLAUDE_BIN="$SB/claude"
}

test_mcp_codex_block_created() {
  run_ok apply
  assert_contains "$(_TOML)" '# >>> kisa-harness >>>'
  assert_contains "$(_TOML)" '[mcp_servers.deploychan]'
  assert_contains "$(_TOML)" 'url = "https://mcp.deploychan.webcam/mcp"'
  assert_contains "$(_TOML)" '# <<< kisa-harness <<<'
  assert_not_contains "$(_TOML)" 'transport'
}

test_mcp_codex_existing_config_preserved() {
  printf 'model = "gpt-5"\n\n[tools]\nweb_search = true\n' > "$(_TOML)"
  cp "$(_TOML)" "$SB/orig.toml"
  run_ok apply
  head -c "$(wc -c < "$SB/orig.toml")" "$(_TOML)" | cmp -s - "$SB/orig.toml" || fail "чужой config.toml изменен"
  assert_contains "$(_TOML)" '[mcp_servers.deploychan]'
  local before; before="$(cksum < "$(_TOML)")"
  export HARNESS_TS="20260101-000001"
  run_ok apply
  assert_eq "$(cksum < "$(_TOML)")" "$before"
}

test_mcp_codex_foreign_section_untouched() {
  printf '[mcp_servers.deploychan]\nurl = "https://example.com/own"\n' > "$(_TOML)"
  local before; before="$(cksum < "$(_TOML)")"
  run_ok apply
  assert_eq "$(cksum < "$(_TOML)")" "$before"
  assert_contains "$SB/out.log" 'MCP     codex: deploychan уже описан'
}

test_mcp_codex_foreign_subtable_untouched() {
  printf '[mcp_servers.deploychan.env]\nFOO = "bar"\n' > "$(_TOML)"
  local before; before="$(cksum < "$(_TOML)")"
  run_ok apply
  assert_eq "$(cksum < "$(_TOML)")" "$before"
  assert_contains "$SB/out.log" 'MCP     codex: deploychan уже описан'
}

test_mcp_claude_no_cli_gives_instruction() {
  run_ok apply
  assert_contains "$SB/out.log" 'claude mcp add --transport http --scope user deploychan https://mcp.deploychan.webcam/mcp'
}

test_mcp_claude_plan_does_not_add() {
  _stub_claude
  run_ok plan
  assert_contains "$SB/claude.log" 'mcp list'
  assert_not_contains "$SB/claude.log" 'mcp add'
}

test_mcp_claude_apply_adds() {
  _stub_claude
  run_ok apply
  assert_contains "$SB/claude.log" 'mcp add --transport http --scope user deploychan https://mcp.deploychan.webcam/mcp'
}

test_mcp_claude_already_connected() {
  _stub_claude
  : > "$SB/connected"
  run_ok apply
  assert_not_contains "$SB/claude.log" 'mcp add'
  assert_contains "$SB/out.log" 'MCP     claude: deploychan уже подключен'
}

test_mcp_hermes_instruction() {
  run_ok plan
  assert_contains "$SB/out.log" 'Hermes'
  assert_contains "$SB/out.log" '"url":"https://mcp.deploychan.webcam/mcp"'
}
