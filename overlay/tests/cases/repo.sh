# Конвенция апстрима: без букв U+0451 и U+0401. Байты заданы escape-последовательностями,
# чтобы сам тест не содержал запрещенных букв.
test_repo_no_yo_letters() {
  local hits
  hits="$(grep -rlI -e $'\xd1\x91' -e $'\xd0\x81' "$OVERLAY_DIR" --exclude-dir=.build || true)"
  [ -z "$hits" ] || fail "буква U+0451/U+0401 в файлах:"$'\n'"$hits"
}

test_repo_lf_only() {
  local f hits=""
  while IFS= read -r f; do
    if has_cr "$f"; then hits="$hits"$'\n'"$f"; fi
  done < <(find "$OVERLAY_DIR" -type f -not -path '*/.build/*' -not -name 'profile.env')
  [ -z "$hits" ] || fail "CRLF в файлах:$hits"
}

test_repo_launcher_and_readme_exist() {
  assert_file "$OVERLAY_DIR/harness.ps1"
  assert_file "$OVERLAY_DIR/README.md"
  assert_contains "$OVERLAY_DIR/harness.ps1" 'Git\bin\bash.exe'
  assert_contains "$OVERLAY_DIR/README.md" 'harness.sh plan'
}

test_repo_upstream_files_untouched() {
  # База сравнения - точка расхождения с апстримом; пока remote upstream не
  # добавлен - коммит форка 63c6f6b. После git pull upstream база сдвигается
  # сама, и чужие обновления не считаются нашими правками.
  local base changed
  base="$(git -C "$REPO_DIR" merge-base HEAD upstream/main 2>/dev/null || echo 63c6f6b)"
  changed="$(git -C "$REPO_DIR" diff --name-only "$base" | grep -v '^overlay/' || true)"
  [ -z "$changed" ] || fail "изменены файлы апстрима:"$'\n'"$changed"
}
