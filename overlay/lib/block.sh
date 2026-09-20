# Управляемый блок: харнес владеет только текстом между своими маркерами.

# Номера строк, равных маркеру. Хвостовой \r игнорируется: редактор мог
# перевести файл в CRLF, и без этого мы бы дописали второй блок.
marker_lines() {
  M="$2" awk '{ l = $0; sub(/\r$/, "", l); if (l == ENVIRON["M"]) print NR }' "$1"
}

# Содержимое файла без управляемого блока и его маркеров.
outside_block() {
  B="$2" E="$3" awk '
    { l = $0; sub(/\r$/, "", l) }
    l == ENVIRON["B"] { skip = 1 }
    !skip { print }
    l == ENVIRON["E"] { skip = 0 }
  ' "$1"
}

# out_file обязан отличаться от target: перенаправление > усекает файл до того,
# как его прочитают, и все вне управляемого блока пропадет. Вызывающий рендерит
# в каталог сборки, а копирует поверх target уже commit_pending.
# upsert_block <target> <content_file> <out_file> <begin> <end>
upsert_block() {
  local target="$1" content="$2" out="$3" begin="$4" end="$5" nb ne b e
  mkdir -p "$(dirname "$out")"

  if [ ! -s "$target" ]; then
    { printf '%s\n' "$begin"; cat "$content"; printf '%s\n' "$end"; } > "$out"
    return 0
  fi

  nb="$(marker_lines "$target" "$begin" | wc -l | tr -d ' ')"
  ne="$(marker_lines "$target" "$end" | wc -l | tr -d ' ')"

  if [ "$nb" = 0 ] && [ "$ne" = 0 ]; then
    {
      cat "$target"
      [ -z "$(tail -c1 "$target")" ] || printf '\n'
      printf '\n%s\n' "$begin"; cat "$content"; printf '%s\n' "$end"
    } > "$out"
    return 0
  fi

  if [ "$nb" != 1 ] || [ "$ne" != 1 ]; then
    die "E_MARKER в $target непарные маркеры ($begin: $nb, $end: $ne). Исправьте файл вручную."
  fi
  b="$(marker_lines "$target" "$begin")"
  e="$(marker_lines "$target" "$end")"
  [ "$b" -lt "$e" ] || die "E_MARKER в $target маркер конца стоит раньше маркера начала."

  {
    head -n "$((b - 1))" "$target"
    printf '%s\n' "$begin"; cat "$content"; printf '%s\n' "$end"
    tail -n "+$((e + 1))" "$target"
  } > "$out"
}
