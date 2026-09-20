_BEGIN_MARK='<!-- kisa-harness:begin -->'
_END_MARK='<!-- kisa-harness:end -->'

test_rules_created() {
  run_ok apply
  assert_contains "$HOME/.claude/CLAUDE.md" "$_BEGIN_MARK"
  assert_contains "$HOME/.claude/CLAUDE.md" '# Кто ты'
  assert_contains "$HOME/.claude/CLAUDE.md" "$SB/wiki/claude-code/"
  assert_contains "$CODEX_HOME/AGENTS.md" "$_END_MARK"
  assert_no_path "$HERMES_HOME/AGENTS.md"
  assert_no_path "$HERMES_HOME/CLAUDE.md"
}

test_rules_foreign_content_preserved() {
  printf '# gstack\n\nmy own block\n' > "$HOME/.claude/CLAUDE.md"
  cp "$HOME/.claude/CLAUDE.md" "$SB/orig.md"
  run_ok apply
  head -c "$(wc -c < "$SB/orig.md")" "$HOME/.claude/CLAUDE.md" | cmp -s - "$SB/orig.md" \
    || fail "чужое содержимое CLAUDE.md изменено"
  assert_contains "$HOME/.claude/CLAUDE.md" "$_BEGIN_MARK"
  assert_file "$HOME/.kisa-harness/backups/20260101-000000/.claude/CLAUDE.md"
  cmp -s "$HOME/.kisa-harness/backups/20260101-000000/.claude/CLAUDE.md" "$SB/orig.md" \
    || fail "бэкап не совпадает с оригиналом"
}

test_rules_plan_writes_nothing() {
  printf 'x\n' > "$HOME/.claude/CLAUDE.md"
  local home_before repo_before
  home_before="$(tree_hash "$HOME")"
  repo_before="$(git -C "$REPO_DIR" status --porcelain)"
  run_ok plan
  assert_eq "$(tree_hash "$HOME")" "$home_before"
  assert_eq "$(git -C "$REPO_DIR" status --porcelain)" "$repo_before"
  assert_contains "$SB/out.log" 'CHANGED'
}

test_rules_idempotent() {
  run_ok apply
  local before; before="$(tree_hash "$HOME")"
  export HARNESS_TS="20260101-000001"
  run_ok apply
  assert_eq "$(tree_hash "$HOME")" "$before"
  assert_no_path "$HOME/.kisa-harness/backups/20260101-000001"
}

test_rules_unpaired_marker_stops_before_any_write() {
  printf '%s\nbroken\n' "$_BEGIN_MARK" > "$HOME/.claude/CLAUDE.md"
  local before; before="$(tree_hash "$HOME")"
  run_fail E_MARKER apply
  assert_eq "$(tree_hash "$HOME")" "$before"
}

test_rules_wiki_off() {
  write_profile 'WIKI_ENABLED=0'
  run_ok apply
  assert_not_contains "$HOME/.claude/CLAUDE.md" '# LLM Wiki'
  assert_not_contains "$CODEX_HOME/AGENTS.md" '# Память и LLM Wiki'
}

test_rules_overlay_extra() {
  printf 'MY-OVERLAY-RULE\n' > "$HARNESS_OVERLAY_RULES/claude.md"
  run_ok apply
  assert_contains "$HOME/.claude/CLAUDE.md" 'MY-OVERLAY-RULE'
  assert_not_contains "$CODEX_HOME/AGENTS.md" 'MY-OVERLAY-RULE'
}

test_rules_block_updates_in_place() {
  run_ok apply
  printf 'tail added by user\n' >> "$HOME/.claude/CLAUDE.md"
  printf 'SECOND-VERSION\n' > "$HARNESS_OVERLAY_RULES/claude.md"
  export HARNESS_TS="20260101-000002"
  run_ok apply
  assert_contains "$HOME/.claude/CLAUDE.md" 'SECOND-VERSION'
  assert_contains "$HOME/.claude/CLAUDE.md" 'tail added by user'
  assert_eq "$(grep -c 'kisa-harness:begin' "$HOME/.claude/CLAUDE.md")" 1
}
