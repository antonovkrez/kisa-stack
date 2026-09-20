# Хуки-якоря вики для Claude Code и слияние settings.json.
# Скрипты хуков копируются из апстрима без правок (кроме \r): путь к вики
# уходит в env.WIKI_VAULT, который wiki-anchor.sh уже читает.

HOOK_SCRIPTS="wiki-anchor.sh wiki-reminder.sh"

hook_command() {
  local name="$1"
  if [ "$HOOK_COMMAND_STYLE" = explicit ]; then
    printf '"%s" "%s"' "$HOOK_BASH" "$(native_path "$(runtime_home claude)/hooks/$name")"
  else
    printf '%s' "\$HOME/.claude/hooks/$name"
  fi
}

plan_hooks() {
  local claude_home name src settings cur merged example
  claude_home="$(runtime_home claude)"

  for name in overview.md components.md; do
    [ -f "$WIKI_DIR/claude-code/pages/$name" ] ||
      warn "в вики нет claude-code/pages/$name - хук сошлется на несуществующую страницу"
  done

  for name in $HOOK_SCRIPTS; do
    src="$RENDER_DIR/claude/hooks/$name"
    copy_lf "$UPSTREAM_DIR/global-config/hooks/$name" "$src"
    propose_file "$src" "$claude_home/hooks/$name" 755
  done

  settings="$claude_home/settings.json"
  cur="$RENDER_DIR/claude/settings.current.json"
  merged="$RENDER_DIR/claude/settings.json"
  if [ -s "$settings" ]; then
    jq empty "$settings" >/dev/null 2>&1 ||
      die "E_JSON невалидный JSON: $settings. Исправьте файл вручную, харнес его не трогает."
    copy_lf "$settings" "$cur"
  else
    mkdir -p "$(dirname "$cur")"
    printf '{}\n' > "$cur"
  fi

  example="$(native_path "$UPSTREAM_DIR/global-config/settings.hooks.example.json")"
  jqx --slurpfile ex "$example" \
      --arg wiki "$WIKI_DIR" \
      --arg anchor "$(hook_command wiki-anchor.sh)" \
      --arg reminder "$(hook_command wiki-reminder.sh)" \
      --arg automem_off "$AUTO_MEMORY_OFF" \
      -f "$(native_path "$OVERLAY_DIR/lib/settings.jq")" < "$cur" > "$merged"

  # jq переформатирует файл. Если по смыслу ничего не изменилось - не трогаем,
  # иначе первый же запуск переписал бы settings.json ради пробелов.
  if [ -s "$settings" ] && [ "$(jqx -S . < "$cur")" = "$(jqx -S . < "$merged")" ]; then
    info "SAME    $settings"
  else
    propose_file "$merged" "$settings"
  fi
}
