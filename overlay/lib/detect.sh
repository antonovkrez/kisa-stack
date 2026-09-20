# Пререквизиты, профиль, обнаружение рантаймов.

check_prereqs() {
  if [ "${BASH_VERSINFO[0]}" -lt 4 ] ||
     { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
    die "E_PREREQ нужен bash >= 4.4, сейчас $BASH_VERSION"
  fi
  local c
  for c in diff sed awk find mktemp cmp; do
    command -v "$c" >/dev/null 2>&1 || die "E_PREREQ не найдена команда: $c"
  done
  command -v jq >/dev/null 2>&1 || die "E_PREREQ не найден jq. Установите: winget install jqlang.jq | sudo apt install jq | sudo pacman -S jq. На Windows после установки перезапустите терминал."
}

load_profile() {
  PROFILE_FILE="${HARNESS_PROFILE:-$OVERLAY_DIR/profile.env}"
  [ -f "$PROFILE_FILE" ] || die "E_PROFILE нет профиля: $PROFILE_FILE. Скопируйте overlay/profile.example.env в overlay/profile.env и заполните."
  RUNTIMES="claude codex hermes"
  WIKI_ENABLED=1
  WIKI_DIR=""
  AUTO_MEMORY_OFF=0
  MCP_OBSIDIAN=0
  DATAWEAVE_ENABLED=0
  DATAWEAVE_REPO=""
  RTK_ENABLED=0
  HOOK_COMMAND_STYLE=direct
  HOOK_BASH=""
  # shellcheck disable=SC1090
  source <(sed 's/\r$//' "$PROFILE_FILE")
  WIKI_DIR="${WIKI_DIR%/}"
  DATAWEAVE_REPO="${DATAWEAVE_REPO%/}"
}

validate_profile() {
  local k
  for k in WIKI_ENABLED AUTO_MEMORY_OFF MCP_OBSIDIAN DATAWEAVE_ENABLED RTK_ENABLED; do
    case "${!k}" in
      0|1) ;;
      *) die "E_PROFILE $k должен быть 0 или 1, сейчас: ${!k}" ;;
    esac
  done
  case "$HOOK_COMMAND_STYLE" in
    direct|explicit) ;;
    *) die "E_PROFILE HOOK_COMMAND_STYLE должен быть direct или explicit, сейчас: $HOOK_COMMAND_STYLE" ;;
  esac
  if [ "$HOOK_COMMAND_STYLE" = explicit ] && [ -z "$HOOK_BASH" ]; then
    die "E_PROFILE HOOK_COMMAND_STYLE=explicit требует HOOK_BASH"
  fi
  for k in WIKI_DIR DATAWEAVE_REPO HOOK_BASH; do
    case "${!k}" in
      *\\*) die "E_PROFILE $k: пишите путь с прямыми слэшами, сейчас: ${!k}" ;;
    esac
  done
  if [ "$WIKI_ENABLED" = 1 ]; then
    [ -n "$WIKI_DIR" ] || die "E_PROFILE WIKI_ENABLED=1 требует WIKI_DIR"
    [ -d "$WIKI_DIR" ] || die "E_WIKI_DIR нет папки вики: $WIKI_DIR. Создайте ее или выставьте WIKI_ENABLED=0."
  fi
  if [ "$DATAWEAVE_ENABLED" = 1 ] && [ -z "$DATAWEAVE_REPO" ]; then
    die "E_PROFILE DATAWEAVE_ENABLED=1 требует DATAWEAVE_REPO"
  fi
}

detect_runtimes() {
  ACTIVE_RUNTIMES=()
  local rt home
  for rt in $RUNTIMES; do
    case "$rt" in
      claude|codex|hermes) ;;
      *) die "E_PROFILE неизвестный рантайм в RUNTIMES: $rt" ;;
    esac
    home="$(runtime_home "$rt")"
    if [ -d "$home" ]; then
      ACTIVE_RUNTIMES+=("$rt")
      info "RUNTIME $rt: $home"
    else
      info "SKIP    runtime $rt: нет каталога $home"
    fi
  done
  [ "${#ACTIVE_RUNTIMES[@]}" -gt 0 ] || die "E_PREREQ не найден ни один рантайм из RUNTIMES: $RUNTIMES"
}

has_runtime() {
  local r
  for r in "${ACTIVE_RUNTIMES[@]}"; do
    if [ "$r" = "$1" ]; then return 0; fi
  done
  return 1
}
