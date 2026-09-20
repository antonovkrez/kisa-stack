# Скиллы: стейджинг вокруг install.sh апстрима.
# install.sh ставит все из папки skills/ рядом с собой, поэтому мы собираем
# .build/stage/<rt>/{install.sh,skills/} только из новых и измененных скиллов
# и запускаем его оттуда. Сам install.sh не правится.

declare -gA SKILL_STAGED=()

skill_names() {
  local d
  {
    for d in "$UPSTREAM_DIR/skills"/*/ "$OVERLAY_SKILLS_DIR"/*/; do
      if [ -f "${d}SKILL.md" ]; then basename "$d"; fi
    done
  } | sort -u
}

# Отличается ли хоть один файл источника от установленной копии.
# Лишние файлы в установленной копии (например .env) изменением не считаются.
skill_differs() {
  local src="$1" installed="$2" f
  while IFS= read -r f; do
    cmp -s "$f" "$installed/${f#"$src"/}" || return 0
  done < <(find "$src" -type f)
  return 1
}

plan_skills() {
  local rt="$1" root stage name src status tag staged=0
  root="$(runtime_home "$rt")/skills"
  stage="$BUILD_DIR/stage/$rt"
  mkdir -p "$stage/skills"
  while IFS= read -r name; do
    tag=""
    if [ -f "$OVERLAY_SKILLS_DIR/$name/SKILL.md" ]; then
      src="$OVERLAY_SKILLS_DIR/$name"; tag=" (overlay)"
    else
      src="$UPSTREAM_DIR/skills/$name"
    fi
    if [ ! -d "$root/$name" ]; then
      status=new
    elif skill_differs "$src" "$root/$name"; then
      status=changed
    else
      status=same
    fi
    if [ "$status" != same ]; then
      cp -R "$src" "$stage/skills/$name"
      staged=$((staged + 1))
    fi
    info "SKILL   $rt/$name: $status$tag"
  done < <(skill_names)
  copy_lf "$UPSTREAM_DIR/install.sh" "$stage/install.sh"
  SKILL_STAGED[$rt]="$staged"
}

# Вернуть в новую копию скилла файлы .env из прежней.
restore_env_files() {
  local old="$1" new="$2" f rel
  while IFS= read -r f; do
    rel="${f#"$old"/}"
    if [ -e "$new/$rel" ]; then continue; fi
    mkdir -p "$(dirname "$new/$rel")"
    cp -p "$f" "$new/$rel"
    info "KEPT    $new/$rel"
  done < <(find "$old" -type f -name '.env')
}

apply_skills() {
  local rt="$1" stage before d name dest
  if [ "${SKILL_STAGED[$rt]:-0}" -eq 0 ]; then
    info "SKILL   $rt: без изменений"
    return 0
  fi
  stage="$BUILD_DIR/stage/$rt"
  before="$(list_skill_backups "$rt")"
  "$BASH" "$stage/install.sh" all "--$rt"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if grep -Fxq -- "$d" <<< "$before"; then continue; fi
    name="$(basename "$d")"
    name="${name%.backup-*}"
    restore_env_files "$d" "$(runtime_home "$rt")/skills/$name"
    dest="$(backup_dir)/skills/$rt"
    mkdir -p "$dest"
    mv "$d" "$dest/"
    info "SWEPT   $d -> $dest/"
  done < <(list_skill_backups "$rt")
}
