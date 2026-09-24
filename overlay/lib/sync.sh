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

# Каталог: строка на пак, id и описание через табуляцию.
sync_catalog() {
  python3 "$OVERLAY_DIR/lib/sync.py" catalog "$MCP_URL"
}

# Отрендерить пак в каталог сборки. Печатает sha256 содержимого.
sync_render() {
  local id="$1"
  python3 "$OVERLAY_DIR/lib/sync.py" render "$MCP_URL" "$id" "$BUILD_DIR/sync/$id"
}

# Перенести отрендеренное в слой и записать маркер.
sync_write() {
  # dst объявлен отдельным local: в одном local все значения раскрываются до
  # присваивания, и $id взялся бы из вызывающей функции. После цикла read там
  # пусто, и отложенная запись фазы 2 ушла бы в корень слоя.
  local id="$1" hash="$2"
  local dst="$OVERLAY_SKILLS_DIR/$id"
  mkdir -p "$dst"
  cp "$BUILD_DIR/sync/$id/SKILL.md" "$dst/SKILL.md"
  printf 'deploychan:%s sha256:%s %s\n' "$id" "$hash" "$(date +%Y-%m-%d)" > "$dst/.harness-origin"
  info "WROTE   $dst"
}

# Состояние пака в слое относительно свежеотрендеренного.
# Печатает одно слово: new | foreign | same | updated | edited.
sync_state() {
  local id="$1" hash="$2"
  local dst="$OVERLAY_SKILLS_DIR/$id" marker recorded actual
  if [ ! -d "$dst" ]; then printf 'new'; return 0; fi
  marker="$dst/.harness-origin"
  if [ ! -f "$marker" ] || ! grep -qF "deploychan:$id " "$marker"; then
    printf 'foreign'; return 0
  fi
  # Маркер синка на месте, а файла нет: его удалили руками. Это тоже правка.
  if [ ! -f "$dst/SKILL.md" ]; then printf 'edited'; return 0; fi
  recorded="$(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^sha256:/) { sub(/^sha256:/, "", $i); print $i; exit } }' "$marker")"
  actual="$(sync_file_hash "$dst/SKILL.md")"
  if [ "$recorded" != "$actual" ]; then printf 'edited'; return 0; fi
  if [ "$recorded" = "$hash" ]; then printf 'same'; else printf 'updated'; fi
}

sync_file_hash() {
  python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
}

# Дифф файла в слое (или пустоты, если файла нет) против свежеотрендеренного.
sync_show_diff() {
  local id="$1" old="$OVERLAY_SKILLS_DIR/$1/SKILL.md"
  [ -f "$old" ] || old=/dev/null
  diff -u "$old" "$BUILD_DIR/sync/$id/SKILL.md" || true
}

# Паки, пришедшие из синка, которых больше нет в составе. Синк их не удаляет.
sync_report_orphans() {
  local declared="$1" dir name
  for dir in "$OVERLAY_SKILLS_DIR"/*/; do
    [ -f "$dir.harness-origin" ] || continue
    name="$(basename "$dir")"
    grep -qF "deploychan:$name " "$dir.harness-origin" || continue
    if ! grep -qxF -- "$name" <<< "$declared"; then
      warn "$name пришел из синка, но в $(basename "$SYNC_CONF") его нет. Удалите overlay/skills/$name, если он больше не нужен."
    fi
  done
}

run_sync() {
  local mode="$1" entries rc=0 kind id url rev hash state catalog declared known cid csummary i
  local n_new=0 n_updated=0 n_edited=0 n_foreign=0 n_same=0 n_undeclared=0
  local -a write_ids=() write_hashes=()
  info "режим: sync $mode"
  command -v python3 >/dev/null 2>&1 ||
    die "E_PREREQ не найден python3. Он нужен только синку; plan и apply работают без него."
  entries="$(sync_entries)" || rc=$?
  [ "$rc" -eq 0 ] || exit 1
  declared="$(awk '{ print $2 }' <<< "$entries")"

  # Фаза 1: вся сеть и все решения. Здесь ничего не пишется в слой, поэтому
  # любая остановка с E_MCP честно оставляет его нетронутым.
  catalog="$(sync_catalog)" ||
    die "E_MCP не удалось получить каталог. Синк остановлен, ничего не записано."
  known="$(cut -f1 <<< "$catalog")"
  while read -r kind id url rev; do
    [ "$kind" = text ] || continue
    grep -qxF -- "$id" <<< "$known" ||
      die "E_MCP пака $id нет в каталоге deploychan. Проверьте $SYNC_CONF: пак могли переименовать. Синк остановлен, ничего не записано."
  done <<< "$entries"
  while read -r kind id url rev; do
    [ -n "$kind" ] || continue
    if [ "$kind" != text ]; then
      info "SYNC    $id: софт, ревизия $rev: софтовая ветка не реализована, пропущен"
      continue
    fi
    hash="$(sync_render "$id")" ||
      die "E_MCP не удалось получить пак $id. Синк остановлен, ничего не записано."
    state="$(sync_state "$id" "$hash")"
    info "SYNC    $id: $state"
    case "$state" in
      new)
        sync_show_diff "$id"
        write_ids+=("$id"); write_hashes+=("$hash")
        n_new=$((n_new + 1))
        ;;
      updated)
        sync_show_diff "$id"
        write_ids+=("$id"); write_hashes+=("$hash")
        n_updated=$((n_updated + 1))
        ;;
      edited)
        sync_show_diff "$id"
        warn "$id правили руками, не перезаписываю. Удалите каталог и синкните заново, чтобы принять обновление. Свою правку видно в git log -p overlay/skills/$id/SKILL.md."
        n_edited=$((n_edited + 1))
        ;;
      foreign)
        warn "$id в слое пришел не из синка, не трогаю. Переименуйте свой скилл или уберите пак из $SYNC_CONF."
        n_foreign=$((n_foreign + 1))
        ;;
      same)
        n_same=$((n_same + 1))
        ;;
    esac
  done <<< "$entries"

  # Фаза 2: запись. Только в apply и только после того, как фаза 1 прошла целиком.
  if [ "$mode" = apply ]; then
    for i in "${!write_ids[@]}"; do
      sync_write "${write_ids[$i]}" "${write_hashes[$i]}"
    done
  fi

  sync_report_orphans "$declared"
  while IFS=$'\t' read -r cid csummary; do
    [ -n "$cid" ] || continue
    if grep -qxF -- "$cid" <<< "$declared"; then continue; fi
    n_undeclared=$((n_undeclared + 1))
    if [ -n "$csummary" ]; then
      info "SKIP    $cid: нет в $(basename "$SYNC_CONF") — $csummary"
    else
      info "SKIP    $cid: нет в $(basename "$SYNC_CONF")"
    fi
  done <<< "$catalog"

  info "итог: новых $n_new, обновлено $n_updated, правлено руками $n_edited, чужих $n_foreign, без изменений $n_same, не объявлено $n_undeclared"
  if [ $((n_new + n_updated + n_edited)) -gt 0 ]; then
    info "Диффы выше - инструкции, которым будет следовать агент. Читайте их как код."
  fi
  if [ "$mode" = plan ]; then
    info "это был plan: ничего не записано. Применить: overlay/harness.sh sync apply"
  elif [ "${#write_ids[@]}" -gt 0 ]; then
    info "записано в overlay/skills. Дальше: git diff, коммит, overlay/harness.sh apply. До этого рантаймы новых скиллов не видят."
  fi
}
