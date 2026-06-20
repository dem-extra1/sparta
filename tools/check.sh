#!/usr/bin/env bash
# tools/check.sh — run Sparta's CI checks locally, before you push.
#
# This mirrors the gating checks in .github/workflows/ so you can reproduce a CI
# pass (or failure) on your own machine without waiting on the runners:
#
#   validate  Godot import — loads the whole project (autoloads, class_name
#             globals, cross-script references) and fails on any script/parse
#             error. Mirrors .github/workflows/godot-ci.yml.
#   test      GUT unit suite, run headlessly. Mirrors godot-ci.yml.
#   chars     Curly quotes and en/em dashes in the website docs (*.qmd, *.R) —
#             the Quarto source is kept plain-ASCII. Mirrors
#             .github/workflows/check-non-standard-chars.yml.
#   links     Markdown link-check with lychee, if it's installed. Mirrors
#             .github/workflows/check-links.yml. Needs network; not in the
#             default set (run it explicitly or via "all").
#
# Usage:
#   tools/check.sh                 # default set: validate, test, chars
#   tools/check.sh test chars      # only the named checks, in the given order
#   tools/check.sh all             # every check (links included if lychee is present)
#   tools/check.sh -l | --list     # list the available checks
#   tools/check.sh -h | --help     # this help
#
# Environment:
#   GODOT_BIN    Godot 4.6 binary (default: godot). On macOS, e.g.
#                /Applications/Godot.app/Contents/MacOS/Godot
#   GUT_VERSION  GUT release vendored into addons/gut when it's missing
#                (default: v9.6.0). Keep in sync with godot-ci.yml and
#                test/README.md.
#
# Exit status is non-zero if any selected check fails, so it drops straight into
# a pre-push hook or a `&&` chain.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
GODOT_BIN="${GODOT_BIN:-godot}"
# Keep in sync with .github/workflows/godot-ci.yml and test/README.md.
GUT_VERSION="${GUT_VERSION:-v9.6.0}"

DEFAULT_CHECKS=(validate test chars)
ALL_CHECKS=(validate test chars links)

# --- pretty output ---------------------------------------------------------
# Colour only when stdout is a terminal and NO_COLOR isn't set.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

section() { printf '\n%s== %s ==%s\n' "$C_BOLD$C_BLUE" "$1" "$C_RESET"; }
info()    { printf '%s\n' "$1"; }
warn()    { printf '%s%s%s\n' "$C_YELLOW" "$1" "$C_RESET"; }
err()     { printf '%s%s%s\n' "$C_RED" "$1" "$C_RESET" >&2; }

# Result accumulators, keyed by check name.
declare -A RESULT

# --- helpers ---------------------------------------------------------------

usage() { sed -n '2,/^set /{/^set /d;s/^# \{0,1\}//;p}' "$0"; }

list_checks() {
  info "Available checks:"
  info "  validate   Godot import / script-validation (godot-ci.yml)"
  info "  test       GUT unit suite (godot-ci.yml)"
  info "  chars      non-standard characters in docs (check-non-standard-chars.yml)"
  info "  links      Markdown link-check via lychee (check-links.yml)"
  info ""
  info "Default (no args): ${DEFAULT_CHECKS[*]}"
  info "all              : ${ALL_CHECKS[*]}"
}

have() { command -v "$1" >/dev/null 2>&1; }

require_godot() {
  if ! have "$GODOT_BIN"; then
    err "Godot binary '$GODOT_BIN' not found. Install Godot 4.6 (Standard) or set GODOT_BIN."
    err "See README.md ('Running Godot headlessly') for the download snippet."
    return 1
  fi
}

# Vendor GUT into addons/gut if it isn't already there — the same way CI and the
# session-start hook do it (GUT is intentionally not committed). The test files
# extend GutTest, so it must be present before 'validate' imports the project.
ensure_gut() {
  if [ -d "$PROJECT_ROOT/addons/gut" ]; then
    return 0
  fi
  info "Vendoring GUT $GUT_VERSION (not committed; cloned on demand)..."
  rm -rf /tmp/gut-check
  if ! git clone --depth 1 --branch "$GUT_VERSION" \
      https://github.com/bitwes/Gut.git /tmp/gut-check >/dev/null 2>&1; then
    err "Failed to clone GUT $GUT_VERSION."
    return 1
  fi
  mkdir -p "$PROJECT_ROOT/addons"
  cp -r /tmp/gut-check/addons/gut "$PROJECT_ROOT/addons/gut"
  rm -rf /tmp/gut-check
}

# --- checks ----------------------------------------------------------------
# Each returns 0 on pass, non-zero on fail.

check_validate() {
  require_godot || return 1
  ensure_gut || return 1
  local log; log="$(mktemp)"
  # `--import` loads the project in full and reports compile/import errors, but
  # Godot doesn't reliably exit non-zero on script errors — so, like CI, we fail
  # on any error marker in the log.
  ( cd "$PROJECT_ROOT" && "$GODOT_BIN" --headless --import --verbose ) >"$log" 2>&1 || true
  if grep -E "SCRIPT ERROR|Failed to load script|Parse Error|Compile Error" "$log"; then
    err "Godot reported script/resource errors during import (see above)."
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
  info "Project imported with no script/parse errors."
}

check_test() {
  require_godot || return 1
  ensure_gut || return 1
  # gut_cmdln runs the suite without enabling the editor plugin; -gexit makes it
  # exit non-zero if any test fails or errors.
  ( cd "$PROJECT_ROOT" && "$GODOT_BIN" --headless -s addons/gut/gut_cmdln.gd \
      -gdir=res://test -ginclude_subdirs -gexit )
}

check_chars() {
  # Flag curly quotes (' ' " ") and en/em dashes (– —) in the Quarto docs, which
  # are kept plain-ASCII so pandoc's smart typography renders them. UTF-8 locale
  # is required for grep -P's \x{...} codepoints.
  local out
  out="$(cd "$PROJECT_ROOT" && git ls-files -z '*.qmd' '*.R' '*.r' \
      | LC_ALL=C.UTF-8 xargs -0 -r grep -nP \
        '[\x{2018}\x{2019}\x{201C}\x{201D}\x{2013}\x{2014}]' 2>/dev/null)"
  if [ -n "$out" ]; then
    err "Non-standard characters found (use straight quotes and ASCII '-'):"
    printf '%s\n' "$out" >&2
    return 1
  fi
  info "Docs are free of curly quotes / en-em dashes."
}

check_links() {
  if ! have lychee; then
    warn "lychee not installed — skipping link check."
    warn "Install it from https://github.com/lycheeverse/lychee, then re-run."
    RESULT[links]="skip"
    return 0
  fi
  local files
  files="$(cd "$PROJECT_ROOT" && git ls-files '*.md')"
  if [ -z "$files" ]; then
    info "No Markdown files to check."
    return 0
  fi
  ( cd "$PROJECT_ROOT" && echo "$files" | xargs lychee --no-progress )
}

# --- driver ----------------------------------------------------------------

run_check() {
  local name="$1"
  section "$name"
  local fn="check_${name}"
  if ! declare -F "$fn" >/dev/null; then
    err "Unknown check: $name (try --list)"
    RESULT[$name]="fail"
    return 1
  fi
  if "$fn"; then
    # A check may have set its own result (e.g. 'skip'); default to pass.
    RESULT[$name]="${RESULT[$name]:-pass}"
  else
    RESULT[$name]="fail"
  fi
}

main() {
  local checks=()
  for arg in "$@"; do
    case "$arg" in
      -h|--help) usage; exit 0 ;;
      -l|--list) list_checks; exit 0 ;;
      all)       checks=("${ALL_CHECKS[@]}") ;;
      validate|test|chars|links) checks+=("$arg") ;;
      *) err "Unknown argument: $arg"; usage; exit 2 ;;
    esac
  done
  if [ ${#checks[@]} -eq 0 ]; then
    checks=("${DEFAULT_CHECKS[@]}")
  fi

  for name in "${checks[@]}"; do
    run_check "$name" || true
  done

  # Summary.
  section "summary"
  local failed=0
  for name in "${checks[@]}"; do
    case "${RESULT[$name]}" in
      pass) printf '  %sPASS%s  %s\n' "$C_GREEN" "$C_RESET" "$name" ;;
      skip) printf '  %sSKIP%s  %s\n' "$C_YELLOW" "$C_RESET" "$name" ;;
      *)    printf '  %sFAIL%s  %s\n' "$C_RED" "$C_RESET" "$name"; failed=1 ;;
    esac
  done
  if [ "$failed" -ne 0 ]; then
    printf '\n%sSome checks failed.%s\n' "$C_RED$C_BOLD" "$C_RESET"
    exit 1
  fi
  printf '\n%sAll checks passed.%s\n' "$C_GREEN$C_BOLD" "$C_RESET"
}

main "$@"
