# Подключение MCP deploychan. Правило: путь или формат не подтвержден -
# печатаем инструкцию человеку, а не пишем наугад.

MCP_NAME="deploychan"
MCP_URL="https://mcp.deploychan.webcam/mcp"
CLAUDE_BIN="${HARNESS_CLAUDE_BIN:-claude}"
MCP_CLAUDE_TODO=0
TOML_BEGIN='# >>> kisa-harness >>>'
TOML_END='# <<< kisa-harness <<<'

plan_mcp() {
  local rt
  for rt in "${ACTIVE_RUNTIMES[@]}"; do
    case "$rt" in
      claude) plan_mcp_claude ;;
      codex)  plan_mcp_codex ;;
      hermes) note "Hermes: путь к MCP-конфигу не подтвержден, добавьте сервер вручную: {\"mcpServers\":{\"$MCP_NAME\":{\"type\":\"http\",\"url\":\"$MCP_URL\"}}}" ;;
    esac
  done
}

plan_mcp_claude() {
  local cmd="claude mcp add --transport http --scope user $MCP_NAME $MCP_URL" listed
  if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
    note "Claude Code: CLI не найден в PATH. Подключите MCP вручную: $cmd (если $MCP_NAME уже подключен как коннектор claude.ai - пропустите)"
    return 0
  fi
  listed="$("$CLAUDE_BIN" mcp list 2>/dev/null || true)"
  if grep -qw -- "$MCP_NAME" <<< "$listed"; then
    info "MCP     claude: $MCP_NAME уже подключен"
  else
    info "MCP     claude: будет выполнено: $cmd"
    MCP_CLAUDE_TODO=1
  fi
}

plan_mcp_codex() {
  local cfg content out outside
  cfg="$(runtime_home codex)/config.toml"
  if [ -f "$cfg" ]; then
    outside="$(outside_block "$cfg" "$TOML_BEGIN" "$TOML_END")"
    if grep -qE "^[[:space:]]*\[mcp_servers\.$MCP_NAME[].]" <<< "$outside"; then
      info "MCP     codex: $MCP_NAME уже описан в $cfg вне блока харнеса, не трогаю"
      return 0
    fi
  fi
  content="$RENDER_DIR/codex/mcp.block.toml"
  out="$RENDER_DIR/codex/config.toml"
  mkdir -p "$(dirname "$content")"
  printf '[mcp_servers.%s]\nurl = "%s"\n' "$MCP_NAME" "$MCP_URL" > "$content"
  upsert_block "$cfg" "$content" "$out" "$TOML_BEGIN" "$TOML_END"
  propose_file "$out" "$cfg"
}

apply_mcp() {
  [ "$MCP_CLAUDE_TODO" = 1 ] || return 0
  if "$CLAUDE_BIN" mcp add --transport http --scope user "$MCP_NAME" "$MCP_URL"; then
    info "MCP     claude: $MCP_NAME подключен"
  else
    warn "claude mcp add завершился с ошибкой"
    note "Claude Code: подключите MCP вручную: claude mcp add --transport http --scope user $MCP_NAME $MCP_URL"
  fi
}
