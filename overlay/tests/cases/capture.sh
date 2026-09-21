# Помощник: создать скилл в каталоге рантайма.
# _mk_skill <корень> <имя> <описание>
_mk_skill() {
  mkdir -p "$1/$2"
  printf -- '---\nname: %s\ndescription: %s\n---\nbody\n' "$2" "$3" > "$1/$2/SKILL.md"
}

test_capture_mode_accepted() {
  run_ok capture
  assert_contains "$SB/out.log" 'режим: capture plan'
}

test_capture_apply_submode_accepted() {
  run_ok capture apply
  assert_contains "$SB/out.log" 'режим: capture apply'
}

test_capture_unknown_submode_fails() {
  if run_harness capture frobnicate; then fail "неизвестный подрежим должен падать"; fi
}

test_capture_bad_from_fails() {
  write_profile 'CAPTURE_FROM=nosuch'
  run_fail E_PROFILE capture
}

test_capture_denies_upstream() {
  _mk_skill "$HOME/.claude/skills" researcher 'что угодно'
  run_ok capture
  assert_contains "$SB/out.log" 'DENY    researcher: апстрим'
}

test_capture_denies_gstack_mark() {
  _mk_skill "$HOME/.claude/skills" my-browse 'Fast headless browser. (gstack)'
  run_ok capture
  assert_contains "$SB/out.log" 'DENY    my-browse: метка gstack'
}

test_capture_denies_already_in_overlay() {
  _mk_skill "$HOME/.claude/skills" mine 'личный скилл'
  _mk_skill "$HARNESS_OVERLAY_SKILLS" mine 'личный скилл'
  run_ok capture
  assert_contains "$SB/out.log" 'DENY    mine: уже в overlay'
}

test_capture_denies_by_profile() {
  _mk_skill "$HOME/.claude/skills" mine 'личный скилл'
  write_profile 'CAPTURE_DENY="mine other"'
  run_ok capture
  assert_contains "$SB/out.log" 'DENY    mine: профиль'
}

test_capture_skips_entry_without_skill_md() {
  mkdir -p "$HOME/.claude/skills/not-a-skill"
  printf 'x\n' > "$HOME/.claude/skills/not-a-skill/readme.txt"
  run_ok capture
  assert_contains "$SB/out.log" 'SKIP    not-a-skill: нет SKILL.md'
}

test_capture_plan_writes_nothing() {
  _mk_skill "$HOME/.claude/skills" mine 'личный скилл'
  local before; before="$(tree_hash "$HARNESS_OVERLAY_SKILLS")"
  run_ok capture
  assert_contains "$SB/out.log" 'CAPTURE mine'
  assert_eq "$(tree_hash "$HARNESS_OVERLAY_SKILLS")" "$before"
  assert_no_path "$HARNESS_OVERLAY_SKILLS/mine"
}

test_capture_denies_gstack_in_block_description() {
  mkdir -p "$HOME/.claude/skills/blocky"
  printf -- '---\nname: blocky\ndescription: |\n  Fast headless browser for QA testing. (gstack)\n---\nbody\n' \
    > "$HOME/.claude/skills/blocky/SKILL.md"
  run_ok capture
  assert_contains "$SB/out.log" 'DENY    blocky: метка gstack'
}
