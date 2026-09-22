#!/usr/bin/env bash
# Тесты харнеса. Запуск: bash overlay/tests/run.sh [часть-имени-теста]
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="$(dirname "$TESTS_DIR")"
REPO_DIR="$(dirname "$OVERLAY_DIR")"
HARNESS="$OVERLAY_DIR/harness.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_file()         { [ -f "$1" ] || fail "нет файла: $1"; }
assert_no_path()      { [ ! -e "$1" ] || fail "путь не должен существовать: $1"; }
assert_contains()     { grep -qF -- "$2" "$1" || fail "в $1 нет строки: $2"; }
assert_not_contains() { ! grep -qF -- "$2" "$1" || fail "в $1 есть лишняя строка: $2"; }
assert_eq()           { [ "$1" = "$2" ] || fail "ожидалось '$2', получено '$1'"; }

tree_hash() {
  ( cd "$1" && { find . | sort; find . -type f -exec cksum {} + | sort; } | cksum )
}

jqt() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq "$@" | tr -d '\r'; }

# Есть ли в файле \r. Сравнение по числу байт: grep $'\r' в Git Bash ненадежен.
has_cr() {
  [ "$(tr -d '\r' < "$1" | wc -c | tr -d ' ')" != "$(wc -c < "$1" | tr -d ' ')" ]
}

write_profile() {
  {
    printf 'WIKI_DIR="%s"\n' "$SB/wiki"
    local line
    for line in "$@"; do printf '%s\n' "$line"; done
  } > "$HARNESS_PROFILE"
}

new_sandbox() {
  SB="$(mktemp -d)"
  trap 'rm -rf "$SB"' EXIT
  export HOME="$SB/home"
  export CODEX_HOME="$HOME/.codex"
  export HERMES_HOME="$HOME/.hermes"
  export HARNESS_PROFILE="$SB/profile.env"
  export HARNESS_BUILD_DIR="$SB/build"
  export HARNESS_CLAUDE_BIN="$SB/no-such-claude"
  export HARNESS_OVERLAY_SKILLS="$SB/overlay-skills"
  export HARNESS_OVERLAY_RULES="$SB/overlay-rules"
  export HARNESS_TS="20260101-000000"
  export HARNESS_SYNC_CONF="$SB/sync.conf"
  export HARNESS_MCP_FIXTURE="$REPO_DIR/overlay/tests/fixtures/catalog.json"
  mkdir -p "$HOME/.claude" "$CODEX_HOME" "$HERMES_HOME" "$SB/wiki" \
           "$HARNESS_OVERLAY_SKILLS" "$HARNESS_OVERLAY_RULES"
  write_profile
}

run_harness() { bash "$HARNESS" "$@" > "$SB/out.log" 2>&1; }
run_ok() { run_harness "$@" || fail "harness $* упал:"$'\n'"$(cat "$SB/out.log")"; }
run_fail() {
  local code="$1"; shift
  if run_harness "$@"; then fail "harness $* должен был упасть с $code"; fi
  grep -qF -- "$code" "$SB/out.log" || fail "в выводе нет $code:"$'\n'"$(cat "$SB/out.log")"
}

load_libs() {
  local lib
  for lib in "$OVERLAY_DIR"/lib/*.sh; do
    # shellcheck disable=SC1090
    source "$lib"
  done
}

for case_file in "$TESTS_DIR"/cases/*.sh; do
  # shellcheck disable=SC1090
  source "$case_file"
done

pattern="${1:-}"
passed=0
failed=()
for t in $(declare -F | awk '{ print $3 }' | grep '^test_' | sort); do
  if [ -n "$pattern" ] && [[ "$t" != *"$pattern"* ]]; then continue; fi
  printf '%s ... ' "$t"
  out="$( ( new_sandbox; "$t" ) 2>&1 )"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    passed=$((passed + 1)); echo ok
  else
    failed+=("$t"); echo FAIL
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
done

printf '\npassed: %d, failed: %d\n' "$passed" "${#failed[@]}"
[ "${#failed[@]}" -eq 0 ]
