#!/usr/bin/env bash
# Личный харнес поверх KISA Stack.
# Использование: overlay/harness.sh [plan|apply]   (по умолчанию plan)
set -euo pipefail

OVERLAY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$OVERLAY_DIR")"
UPSTREAM_DIR="${HARNESS_UPSTREAM_DIR:-$REPO_DIR}"
OVERLAY_SKILLS_DIR="${HARNESS_OVERLAY_SKILLS:-$OVERLAY_DIR/skills}"
OVERLAY_RULES_DIR="${HARNESS_OVERLAY_RULES:-$OVERLAY_DIR/rules}"
BUILD_DIR="${HARNESS_BUILD_DIR:-$OVERLAY_DIR/.build}"
RENDER_DIR="$BUILD_DIR/render"
BUILD_DIR_AT_START="$BUILD_DIR"

for _lib in "$OVERLAY_DIR"/lib/*.sh; do
  # shellcheck disable=SC1090
  source "$_lib"
done

usage() { printf 'Usage: %s [plan|apply]\n' "$0" >&2; }

reset_build_dir() {
  [ "$BUILD_DIR" = "$BUILD_DIR_AT_START" ] ||
    die "E_PROFILE профиль не должен переопределять BUILD_DIR: '$BUILD_DIR'"
  case "$BUILD_DIR" in
    ""|"/"|"$HOME") die "E_INTERNAL опасный BUILD_DIR: '$BUILD_DIR'" ;;
  esac
  rm -rf "$BUILD_DIR"
  RENDER_DIR="$BUILD_DIR/render"
  mkdir -p "$RENDER_DIR"
}

main() {
  local mode="${1:-plan}" rt
  case "$mode" in
    plan|apply) ;;
    *) usage; exit 2 ;;
  esac
  trap print_notes EXIT
  check_prereqs
  load_profile
  validate_profile
  detect_runtimes
  reset_build_dir
  info "режим: $mode"

  for rt in "${ACTIVE_RUNTIMES[@]}"; do
    plan_skills "$rt"
    plan_rules "$rt"
  done
  if has_runtime claude && [ "$WIKI_ENABLED" = 1 ]; then
    plan_hooks
  fi
  plan_mcp

  show_pending
  if [ "$mode" = apply ]; then
    commit_pending
    for rt in "${ACTIVE_RUNTIMES[@]}"; do
      apply_skills "$rt"
    done
    apply_mcp
  else
    info "это был plan: ничего не записано. Применить: overlay/harness.sh apply"
  fi
}

main "$@"
