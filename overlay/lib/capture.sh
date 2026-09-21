# Переезд скиллов с этой машины в overlay/skills/.
# Разовая операция: после нее источник истины - репозиторий, а не машина.
# Отбор - денилист, три правила из четырех засеваются автоматически.

# Значение description: из фронтматтера SKILL.md. Блочный скаляр (description: |)
# собирается в одну строку: (gstack) может стоять на строке продолжения, и правило
# D2 обязано его увидеть. Пусто, если фронтматтера нет.
skill_description() {
  awk '
    NR == 1 && $0 !~ /^---[[:space:]]*$/ { exit }
    NR > 1 && $0 ~ /^---[[:space:]]*$/ { exit }
    /^description:/ && !collecting {
      out = $0
      sub(/^description:[[:space:]]*/, "", out)
      if (out ~ /^[|>][0-9+-]*$/) out = ""
      collecting = 1
      next
    }
    collecting && /^[[:space:]]/ {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      out = (out == "" ? line : out " " line)
      next
    }
    collecting { exit }
    END { if (collecting) print out }
  ' "$1"
}

# capture_decision <имя> <путь-к-SKILL.md> -> "capture" | "deny:<причина>"
capture_decision() {
  local name="$1" skill_md="$2" desc lower denied
  if [ -d "$UPSTREAM_DIR/skills/$name" ]; then
    printf 'deny:апстрим'; return 0
  fi
  desc="$(skill_description "$skill_md")"
  lower="$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *"(gstack)"*) printf 'deny:метка gstack'; return 0 ;;
  esac
  if [ -d "$OVERLAY_SKILLS_DIR/$name" ]; then
    printf 'deny:уже в overlay'; return 0
  fi
  for denied in $CAPTURE_DENY; do
    if [ "$denied" = "$name" ]; then
      printf 'deny:профиль'; return 0
    fi
  done
  printf 'capture'
}

# Скопировать скилл в слой. Файлы .env не переезжают: overlay/skills
# коммитится в git, а README апстрима велит класть туда ключи.
capture_one() {
  local name="$1" src="$2" dst="$OVERLAY_SKILLS_DIR/$name" f rel
  mkdir -p "$dst"
  while IFS= read -r f; do
    if [ "$(basename "$f")" = .env ]; then
      warn "в $name пропущен .env: секреты не переезжают"
      continue
    fi
    rel="${f#"$src"}"
    mkdir -p "$(dirname "$dst/$rel")"
    cp -p "$f" "$dst/$rel"
  done < <(find "$src" -type f)
  printf 'capture %s %s\n' "${HOSTNAME:-unknown}" "$(date +%Y-%m-%d)" > "$dst/.harness-origin"
  info "WROTE   $dst"
}

run_capture() {
  local mode="$1" root d name decision captured=0
  root="$(runtime_home "$CAPTURE_FROM")/skills"
  info "режим: capture $mode"
  info "источник: $root"
  if [ ! -d "$root" ]; then
    info "SKIP    нет каталога скиллов: $root"
    return 0
  fi
  for d in "$root"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    if [ ! -f "$d/SKILL.md" ]; then
      info "SKIP    $name: нет SKILL.md"
      continue
    fi
    decision="$(capture_decision "$name" "$d/SKILL.md")"
    if [ "$decision" != capture ]; then
      info "DENY    $name: ${decision#deny:}"
      continue
    fi
    info "CAPTURE $name"
    captured=$((captured + 1))
    if [ "$mode" = apply ]; then
      capture_one "$name" "$d"
    fi
  done
  if [ "$mode" = plan ]; then
    info "это был plan: ничего не записано. Применить: overlay/harness.sh capture apply"
  else
    info "переехало скиллов: $captured"
  fi
}
