test_skills_clean_install() {
  run_ok apply
  local root
  for root in "$HOME/.claude" "$CODEX_HOME" "$HERMES_HOME"; do
    assert_file "$root/skills/researcher/SKILL.md"
    assert_file "$root/skills/suno-music/generate.py"
    assert_file "$root/skills/css-graphics/scripts/render.js"
  done
}

test_skills_plan_installs_nothing() {
  run_ok plan
  assert_no_path "$HOME/.claude/skills"
  assert_contains "$SB/out.log" 'SKILL   claude/researcher: new'
}

test_skills_second_run_is_noop() {
  run_ok apply
  export HARNESS_TS="20260101-000001"
  run_ok apply
  assert_contains "$SB/out.log" 'SKILL   claude/researcher: same'
  assert_no_path "$HOME/.kisa-harness/backups/20260101-000001"
  assert_eq "$(find "$HOME/.claude/skills" -maxdepth 1 -name '*.backup-*' | wc -l | tr -d ' ')" 0
}

test_skills_overlay_wins() {
  mkdir -p "$HARNESS_OVERLAY_SKILLS/researcher"
  printf -- '---\nname: researcher\ndescription: overlay version\n---\nOVERLAY-MARK\n' \
    > "$HARNESS_OVERLAY_SKILLS/researcher/SKILL.md"
  run_ok apply
  assert_contains "$HOME/.claude/skills/researcher/SKILL.md" 'OVERLAY-MARK'
  assert_contains "$SB/out.log" 'SKILL   claude/researcher: new (overlay)'
}

test_skills_overlay_only_skill_installed() {
  mkdir -p "$HARNESS_OVERLAY_SKILLS/my-own"
  printf -- '---\nname: my-own\ndescription: mine\n---\nbody\n' > "$HARNESS_OVERLAY_SKILLS/my-own/SKILL.md"
  run_ok apply
  assert_file "$CODEX_HOME/skills/my-own/SKILL.md"
}

test_skills_extra_file_is_not_a_change() {
  run_ok apply
  printf 'KEY=secret\n' > "$HOME/.claude/skills/suno-music/.env"
  export HARNESS_TS="20260101-000001"
  run_ok apply
  assert_contains "$SB/out.log" 'SKILL   claude/suno-music: same'
  assert_contains "$HOME/.claude/skills/suno-music/.env" 'KEY=secret'
}

test_skills_update_sweeps_backup_and_keeps_env() {
  run_ok apply
  printf 'KEY=secret\n' > "$HOME/.claude/skills/suno-music/.env"
  printf 'local edit\n' >> "$HOME/.claude/skills/suno-music/SKILL.md"
  export HARNESS_TS="20260101-000002"
  run_ok apply
  assert_contains "$SB/out.log" 'SKILL   claude/suno-music: changed'
  assert_not_contains "$HOME/.claude/skills/suno-music/SKILL.md" 'local edit'
  assert_contains "$HOME/.claude/skills/suno-music/.env" 'KEY=secret'
  assert_eq "$(find "$HOME/.claude/skills" -maxdepth 1 -name '*.backup-*' | wc -l | tr -d ' ')" 0
  local kept
  kept="$(find "$HOME/.kisa-harness/backups/20260101-000002/skills/claude" -path '*suno-music.backup-*' -name SKILL.md)"
  [ -n "$kept" ] || fail "прежняя версия скилла не перенесена в бэкапы"
  assert_contains "$kept" 'local edit'
}

test_skills_foreign_backup_dir_untouched() {
  mkdir -p "$HOME/.claude/skills/old.backup-20250101-000000"
  printf 'x\n' > "$HOME/.claude/skills/old.backup-20250101-000000/SKILL.md"
  run_ok apply
  assert_file "$HOME/.claude/skills/old.backup-20250101-000000/SKILL.md"
}

test_skills_runtime_without_home_skipped() {
  rm -rf "$HERMES_HOME"
  run_ok apply
  assert_no_path "$HERMES_HOME"
  assert_file "$HOME/.claude/skills/researcher/SKILL.md"
}
