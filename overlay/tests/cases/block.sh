_BEG='<!-- kisa-harness:begin -->'
_END='<!-- kisa-harness:end -->'

test_block_new_file() {
  load_libs
  printf 'line A\n' > "$SB/c.md"
  ( upsert_block "$SB/absent.md" "$SB/c.md" "$SB/o.md" "$_BEG" "$_END" ) || fail "upsert упал"
  assert_eq "$(cat "$SB/o.md")" "$_BEG"$'\n''line A'$'\n'"$_END"
}

test_block_append_preserves_bytes() {
  load_libs
  printf 'line A\n' > "$SB/c.md"
  printf '# gstack\nmine' > "$SB/t.md"          # без перевода строки в конце
  ( upsert_block "$SB/t.md" "$SB/c.md" "$SB/o.md" "$_BEG" "$_END" ) || fail "upsert упал"
  head -c "$(wc -c < "$SB/t.md")" "$SB/o.md" | cmp -s - "$SB/t.md" || fail "чужие байты изменены"
  assert_contains "$SB/o.md" "$_BEG"
  assert_contains "$SB/o.md" 'line A'
}

test_block_idempotent() {
  load_libs
  printf 'line A\n' > "$SB/c.md"
  printf '# gstack\n' > "$SB/t.md"
  ( upsert_block "$SB/t.md" "$SB/c.md" "$SB/o1.md" "$_BEG" "$_END" ) || fail "первый upsert упал"
  ( upsert_block "$SB/o1.md" "$SB/c.md" "$SB/o2.md" "$_BEG" "$_END" ) || fail "второй upsert упал"
  cmp -s "$SB/o1.md" "$SB/o2.md" || fail "повторный upsert изменил файл"
}

test_block_replace_keeps_outside() {
  load_libs
  printf 'OLD\n' > "$SB/c1.md"
  printf 'NEW\n' > "$SB/c2.md"
  printf 'before\n' > "$SB/t.md"
  ( upsert_block "$SB/t.md" "$SB/c1.md" "$SB/o1.md" "$_BEG" "$_END" ) || fail "upsert упал"
  printf 'after\n' >> "$SB/o1.md"
  ( upsert_block "$SB/o1.md" "$SB/c2.md" "$SB/o2.md" "$_BEG" "$_END" ) || fail "замена упала"
  assert_contains "$SB/o2.md" 'before'
  assert_contains "$SB/o2.md" 'after'
  assert_contains "$SB/o2.md" 'NEW'
  assert_not_contains "$SB/o2.md" 'OLD'
}

test_block_crlf_markers() {
  load_libs
  printf 'X\n' > "$SB/c.md"
  printf 'top\n' > "$SB/t.md"
  ( upsert_block "$SB/t.md" "$SB/c.md" "$SB/o1.md" "$_BEG" "$_END" ) || fail "upsert упал"
  sed 's/$/\r/' "$SB/o1.md" > "$SB/crlf.md"     # редактор перевел файл в CRLF
  ( upsert_block "$SB/crlf.md" "$SB/c.md" "$SB/o2.md" "$_BEG" "$_END" ) || fail "upsert на CRLF упал"
  assert_eq "$(grep -c 'kisa-harness:begin' "$SB/o2.md")" 1
}

test_block_unpaired_marker() {
  load_libs
  printf 'X\n' > "$SB/c.md"
  printf '%s\nsomething\n' "$_BEG" > "$SB/t.md"
  ( upsert_block "$SB/t.md" "$SB/c.md" "$SB/o.md" "$_BEG" "$_END" ) > "$SB/out.log" 2>&1 \
    && fail "непарный маркер должен давать ошибку"
  assert_contains "$SB/out.log" E_MARKER
}

test_block_outside_block() {
  load_libs
  printf 'a\n# >>> kisa-harness >>>\n[mcp_servers.deploychan]\n# <<< kisa-harness <<<\nb\n' > "$SB/t.toml"
  assert_eq "$(outside_block "$SB/t.toml" '# >>> kisa-harness >>>' '# <<< kisa-harness <<<')" 'a'$'\n''b'
}
