# Установка правил: рендер шаблона апстрима + личный блок -> управляемый блок
# в CLAUDE.md (Claude Code) и AGENTS.md (Codex). Для Hermes апстрим правил не дает.

RULES_BEGIN='<!-- kisa-harness:begin -->'
RULES_END='<!-- kisa-harness:end -->'

plan_rules() {
  local rt="$1" kind template extra target block out
  case "$rt" in
    claude)
      kind=claude
      template="$UPSTREAM_DIR/global-config/CLAUDE.md"
      extra="$OVERLAY_RULES_DIR/claude.md"
      target="$(runtime_home claude)/CLAUDE.md"
      ;;
    codex)
      kind=agents
      template="$UPSTREAM_DIR/global-config/AGENTS.md"
      extra="$OVERLAY_RULES_DIR/agents.md"
      target="$(runtime_home codex)/AGENTS.md"
      ;;
    *) return 0 ;;
  esac
  [ -f "$template" ] || die "E_ANCHOR нет шаблона апстрима: $template"
  block="$RENDER_DIR/$rt/rules.block.md"
  out="$RENDER_DIR/$rt/$(basename "$target")"
  render_rules "$kind" "$template" "$extra" "$block"
  upsert_block "$target" "$block" "$out" "$RULES_BEGIN" "$RULES_END"
  propose_file "$out" "$target"
}
