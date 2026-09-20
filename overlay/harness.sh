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

for _lib in "$OVERLAY_DIR"/lib/*.sh; do
  # shellcheck disable=SC1090
  source "$_lib"
done

usage() { printf 'Usage: %s [plan|apply]\n' "$0" >&2; }

reset_build_dir() {
  case "$BUILD_DIR" in
    ""|"/"|"$HOME") die "E_INTERNAL опасный BUILD_DIR: '$BUILD_DIR'" ;;
  esac
  rm -rf "$BUILD_DIR"
  mkdir -p "$RENDER_DIR"
}

main() {
  local mode="${1:-plan}"
  case "$mode" in
    plan|apply) ;;
    *) usage; exit 2 ;;
  esac
  check_prereqs
  load_profile
  validate_profile
  detect_runtimes
  reset_build_dir
  info "режим: $mode"
  print_notes
}

main "$@"
