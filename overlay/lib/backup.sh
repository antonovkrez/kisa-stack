# Бэкапы. Один запуск - один каталог ~/.kisa-harness/backups/<timestamp>/
# с зеркалом путей от $HOME. Каталог создается только при первой записи.

HARNESS_TS="${HARNESS_TS:-$(date +%Y%m%d-%H%M%S)}"

backup_dir() { printf '%s' "$HOME/.kisa-harness/backups/$HARNESS_TS"; }

backup_file() {
  local path="$1" rel dest
  [ -e "$path" ] || return 0
  case "$path" in
    "$HOME"/*) rel="${path#"$HOME"/}" ;;
    *) rel="_abs/$(printf '%s' "$path" | sed 's|^/||; s|:||g')" ;;
  esac
  dest="$(backup_dir)/$rel"
  mkdir -p "$(dirname "$dest")"
  cp -p "$path" "$dest"
  info "BACKUP  $path -> $dest"
}

# Папки вида <skill>.backup-<timestamp>, которые install.sh апстрима оставляет
# прямо в каталоге скиллов рантайма.
list_skill_backups() {
  local root d
  root="$(runtime_home "$1")/skills"
  [ -d "$root" ] || return 0
  for d in "$root"/*.backup-*; do
    if [ -d "$d" ]; then printf '%s\n' "$d"; fi
  done
  return 0
}
