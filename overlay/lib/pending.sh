# Реестр предложенных записей. plan и apply проходят один путь: шаги готовят
# желаемое содержимое в .build/render/ и регистрируют его здесь. plan только
# показывает диффы, apply после показа делает бэкап и пишет.

PENDING_SRC=()
PENDING_DST=()
PENDING_MODE=()
CHANGED_COUNT=0

propose_file() {
  PENDING_SRC+=("$1")
  PENDING_DST+=("$2")
  PENDING_MODE+=("${3:-644}")
}

show_pending() {
  local i src dst
  CHANGED_COUNT=0
  for i in "${!PENDING_SRC[@]}"; do
    src="${PENDING_SRC[$i]}"; dst="${PENDING_DST[$i]}"
    if [ ! -e "$dst" ]; then
      info "NEW     $dst"
      diff -u /dev/null "$src" || true
      CHANGED_COUNT=$((CHANGED_COUNT + 1))
    elif cmp -s "$src" "$dst"; then
      info "SAME    $dst"
    else
      info "CHANGED $dst"
      diff -u "$dst" "$src" || true
      CHANGED_COUNT=$((CHANGED_COUNT + 1))
    fi
  done
}

commit_pending() {
  local i src dst mode
  for i in "${!PENDING_SRC[@]}"; do
    src="${PENDING_SRC[$i]}"; dst="${PENDING_DST[$i]}"; mode="${PENDING_MODE[$i]}"
    if [ -e "$dst" ] && cmp -s "$src" "$dst"; then continue; fi
    backup_file "$dst"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    if [ "$mode" = 755 ]; then chmod 755 "$dst"; fi
    info "WROTE   $dst"
  done
}
