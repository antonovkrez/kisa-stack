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
