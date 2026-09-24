# Синк каталога deploychan. Сеть и JSON делает sync.py, bash решает и пишет.

SYNC_CONF="${HARNESS_SYNC_CONF:-$OVERLAY_DIR/sync.conf}"
MCP_URL="${HARNESS_MCP_URL:-https://mcp.deploychan.webcam/mcp}"

# Разобранный состав дистрибутива, по строке на пак:
#   text <id> - -
#   software <id> <url> <ревизия>
sync_entries() {
  [ -f "$SYNC_CONF" ] ||
    die "E_PROFILE нет файла состава: $SYNC_CONF. Создайте его и перечислите паки."
  awk -v conf="$SYNC_CONF" '
    { sub(/\r$/, "") }
    /^[[:space:]]*(#|$)/ { next }
    NF == 1 { printf "text %s - -\n", $1; next }
    NF == 3 { printf "software %s %s %s\n", $1, $2, $3; next }
    {
      printf "E_PROFILE %s строка %d: нужно 1 поле (текстовый пак) или 3 (софтовый), а их %d\n",
             conf, FNR, NF > "/dev/stderr"
      exit 1
    }
  ' "$SYNC_CONF"
}

# Отрендерить пак в каталог сборки. Печатает sha256 содержимого.
sync_render() {
  local id="$1"
  python3 "$OVERLAY_DIR/lib/sync.py" render "$MCP_URL" "$id" "$BUILD_DIR/sync/$id"
}

# Перенести отрендеренное в слой и записать маркер.
sync_write() {
  local id="$1" hash="$2" dst="$OVERLAY_SKILLS_DIR/$id"
  mkdir -p "$dst"
  cp "$BUILD_DIR/sync/$id/SKILL.md" "$dst/SKILL.md"
  printf 'deploychan:%s sha256:%s %s\n' "$id" "$hash" "$(date +%Y-%m-%d)" > "$dst/.harness-origin"
  info "WROTE   $dst"
}

run_sync() {
  local mode="$1" entries rc=0 kind id url rev hash
  info "режим: sync $mode"
  command -v python3 >/dev/null 2>&1 ||
    die "E_PREREQ не найден python3. Он нужен только синку; plan и apply работают без него."
  entries="$(sync_entries)" || rc=$?
  [ "$rc" -eq 0 ] || exit 1
  while read -r kind id url rev; do
    [ -n "$kind" ] || continue
    if [ "$kind" != text ]; then
      info "SYNC    $id: софт, ревизия $rev"
      continue
    fi
    hash="$(sync_render "$id")"
    info "SYNC    $id: new"
    if [ "$mode" = apply ]; then
      sync_write "$id" "$hash"
    fi
  done <<< "$entries"
}
