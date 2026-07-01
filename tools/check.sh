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
#   coverage  GUT suite instrumented for line coverage; writes coverage/lcov.info.
#             Mirrors .github/workflows/test-coverage.yml. Slower than `test` and
#             non-gating, so not in the default set (run it explicitly or via "all").
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
#   GODOT_BIN    Godot 4.7 binary (default: godot). On macOS, e.g.
#                /Applications/Godot.app/Contents/MacOS/Godot
#   GUT_VERSION  GUT release vendored into addons/gut when it's missing
#                (default: v9.7.0). Keep in sync with godot-ci.yml and
#                test/README.md.
#
# Exit status is non-zero if any selected check fails, so it drops straight into
# a pre-push hook or a `&&` chain.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
GODOT_BIN="${GODOT_BIN:-godot}"
# Keep in sync with .github/workflows/godot-ci.yml and test/README.md.
GUT_VERSION="${GUT_VERSION:-v9.7.0}"

DEFAULT_CHECKS=(validate test chars)
ALL_CHECKS=(validate test chars coverage links)

# --- pretty output ---------------------------------------------------------
# Colour only when stdout is a terminal and NO_COLOR isn't set. Per the NO_COLOR
# spec, any value (including empty) disables colour, so test for presence, not
# emptiness.
if [ -t 1 ] && [ -z "${NO_COLOR+x}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

section() { printf '\n%s== %s ==%s\n' "$C_BOLD$C_BLUE" "$1" "$C_RESET"; }
info()    { printf '%s\n' "$1"; }
warn()    { printf '%s%s%s\n' "$C_YELLOW" "$1" "$C_RESET"; }
err()     { printf '%s%s%s\n' "$C_RED" "$1" "$C_RESET" >&2; }

# Per-check results, kept in parallel indexed arrays (not an associative array,
# so this stays compatible with the Bash 3.2 that ships on macOS).
RESULT_NAMES=()
RESULT_STATUSES=()

# set_result <name> <status> — record/overwrite a check's status.
set_result() {
  local name="$1" status="$2" i
  if [ ${#RESULT_NAMES[@]} -gt 0 ]; then
    for i in "${!RESULT_NAMES[@]}"; do
      if [ "${RESULT_NAMES[$i]}" = "$name" ]; then
        RESULT_STATUSES[$i]="$status"
        return
      fi
    done
  fi
  RESULT_NAMES+=("$name")
  RESULT_STATUSES+=("$status")
}

# get_result <name> — print a check's status (empty string if unset).
get_result() {
  local name="$1" i
  if [ ${#RESULT_NAMES[@]} -gt 0 ]; then
    for i in "${!RESULT_NAMES[@]}"; do
      if [ "${RESULT_NAMES[$i]}" = "$name" ]; then
        printf '%s' "${RESULT_STATUSES[$i]}"
        return
      fi
    done
  fi
}

# --- helpers ---------------------------------------------------------------

usage() { sed -n '2,/^set /{/^set /d;s/^# \{0,1\}//;p}' "$0"; }

list_checks() {
  info "Available checks:"
  info "  validate   Godot import / script-validation (godot-ci.yml)"
  info "  test       GUT unit suite (godot-ci.yml)"
  info "  chars      non-standard characters in docs (check-non-standard-chars.yml)"
  info "  coverage   instrumented GUT suite -> coverage/lcov.info (test-coverage.yml)"
  info "  links      Markdown link-check via lychee (check-links.yml)"
  info ""
  info "Default (no args): ${DEFAULT_CHECKS[*]}"
  info "all              : ${ALL_CHECKS[*]}"
}

have() { command -v "$1" >/dev/null 2>&1; }

require_godot() {
  if ! have "$GODOT_BIN"; then
    err "Godot binary '$GODOT_BIN' not found. Install Godot 4.7 (Standard) or set GODOT_BIN."
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
  # A private temp dir (not a fixed path) so two overlapping runs — e.g. a manual
  # run while an editor task does the same — don't clobber each other's clone.
  local gut_tmp; gut_tmp="$(mktemp -d)"
  if ! git clone --depth 1 --branch "$GUT_VERSION" \
      https://github.com/bitwes/Gut.git "$gut_tmp" >/dev/null 2>&1; then
    err "Failed to clone GUT $GUT_VERSION."
    rm -rf "$gut_tmp"
    return 1
  fi
  # Install atomically: copy into a staging dir on the same filesystem, then
  # rename it into place. A crash mid-copy then leaves only the staging dir, not a
  # half-populated addons/gut that the early-return check above would treat as a
  # valid install on the next run.
  mkdir -p "$PROJECT_ROOT/addons"
  local staging="$PROJECT_ROOT/addons/.gut-staging.$$"
  rm -rf "$staging"
  if ! cp -r "$gut_tmp/addons/gut" "$staging"; then
    err "Failed to install GUT into addons/gut."
    rm -rf "$gut_tmp" "$staging"
    return 1
  fi
  rm -rf "$gut_tmp"
  # A concurrent run may have installed GUT between the early-return check above
  # and now; if so, use theirs and drop our staging copy. This also sidesteps
  # POSIX `mv`'s "move into an existing directory" behaviour, which would
  # otherwise deposit the staging dir *inside* a valid addons/gut.
  if [ -d "$PROJECT_ROOT/addons/gut" ]; then
    rm -rf "$staging"
    return 0
  fi
  if ! mv "$staging" "$PROJECT_ROOT/addons/gut"; then
    err "Failed to move GUT into addons/gut."
    rm -rf "$staging"
    return 1
  fi
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
  # Send the matched error lines to stderr so all of this check's error output
  # (these plus the err() message below) stays on one stream.
  if grep -E "SCRIPT ERROR|Failed to load script|Parse Error|Compile Error" "$log" >&2; then
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

check_coverage() {
  require_godot || return 1
  ensure_gut || return 1
  # Same run as `test`, plus the GUT pre/post hooks that instrument res://scripts
  # and write an lcov report. Mirrors .github/workflows/test-coverage.yml. Not in
  # the default set — instrumentation is slower and coverage never gates. The
  # report lands at coverage/lcov.info (git-ignored); see test/README.md.
  ( cd "$PROJECT_ROOT" && COVERAGE_LCOV_FILE=res://coverage/lcov.info \
      "$GODOT_BIN" --headless -s addons/gut/gut_cmdln.gd \
      -gdir=res://test -ginclude_subdirs -gexit \
      -gpre_run_script=res://test/pre_run_hook.gd \
      -gpost_run_script=res://test/post_run_hook.gd ) || return 1
  # The post-run hook reports a failed lcov write with push_error(), which does
  # not make Godot exit non-zero, so a clean exit above doesn't prove the report
  # was written. Confirm the file exists before claiming success.
  if [ ! -s "$PROJECT_ROOT/coverage/lcov.info" ]; then
    err "coverage/lcov.info was not written — see the post_run_hook output above."
    return 1
  fi
  info "Coverage report written to coverage/lcov.info"
}

check_chars() {
  # Flag curly quotes and en/em dashes in the Quarto docs, which are kept
  # plain-ASCII so pandoc's smart typography renders them. The flagged characters
  # are U+2018/2019 (' '), U+201C/201D (" "), U+2013/2014 (en/em dash).
  #
  # Matching is done with `grep -F` over the literal UTF-8 byte sequences (built
  # via printf's octal escapes) rather than `grep -P '\x{...}'`: -P is a GNU
  # extension absent from the BSD grep that ships on macOS, whereas fixed-string
  # byte matching is portable and needs no special locale.
  local lsq rsq ldq rdq endash emdash
  lsq="$(printf '\342\200\230')"; rsq="$(printf '\342\200\231')"
  ldq="$(printf '\342\200\234')"; rdq="$(printf '\342\200\235')"
  endash="$(printf '\342\200\223')"; emdash="$(printf '\342\200\224')"

  # Collect the tracked docs null-delimited (handles spaces/newlines) and skip
  # cleanly when there are none — avoids relying on GNU xargs' -r and stops grep
  # from blocking on stdin if the file list is empty.
  local files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(cd "$PROJECT_ROOT" && git ls-files -z '*.qmd' '*.R')
  if [ ${#files[@]} -eq 0 ]; then
    info "No docs to check."
    return 0
  fi

  local out
  out="$(cd "$PROJECT_ROOT" && grep -nF \
      -e "$lsq" -e "$rsq" -e "$ldq" -e "$rdq" -e "$endash" -e "$emdash" \
      "${files[@]}" 2>/dev/null)"
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
    set_result links skip
    return 0
  fi
  # Null-delimited so filenames with spaces survive into lychee's argv. Note this
  # is a bare lychee run; the CI workflow delegates to d-morrison/gha's reusable
  # check-links.yml, which may carry its own ignore-list/timeout config, so a
  # local pass here doesn't guarantee an identical CI result.
  local files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(cd "$PROJECT_ROOT" && git ls-files -z '*.md')
  if [ ${#files[@]} -eq 0 ]; then
    info "No Markdown files to check."
    return 0
  fi
  ( cd "$PROJECT_ROOT" && lychee --no-progress "${files[@]}" )
}

# --- driver ----------------------------------------------------------------

run_check() {
  local name="$1"
  section "$name"
  local fn="check_${name}"
  if ! declare -F "$fn" >/dev/null; then
    err "Unknown check: $name (try --list)"
    set_result "$name" fail
    return 1
  fi
  if "$fn"; then
    # A check may have set its own result (e.g. 'skip'); default to pass.
    if [ -z "$(get_result "$name")" ]; then
      set_result "$name" pass
    fi
  else
    set_result "$name" fail
  fi
}

main() {
  local checks=()
  for arg in "$@"; do
    case "$arg" in
      -h|--help) usage; exit 0 ;;
      -l|--list) list_checks; exit 0 ;;
      all)       checks+=("${ALL_CHECKS[@]}") ;;
      validate|test|chars|coverage|links) checks+=("$arg") ;;
      *) err "Unknown argument: $arg"; usage; exit 2 ;;
    esac
  done
  if [ ${#checks[@]} -eq 0 ]; then
    checks=("${DEFAULT_CHECKS[@]}")
  fi

  # De-duplicate (order-preserving) so e.g. `all validate` or repeated names run
  # each check once and print one summary line apiece.
  local deduped=() c seen name
  for c in "${checks[@]}"; do
    seen=""
    if [ ${#deduped[@]} -gt 0 ]; then
      for name in "${deduped[@]}"; do
        if [ "$name" = "$c" ]; then seen=1; break; fi
      done
    fi
    [ -z "$seen" ] && deduped+=("$c")
  done
  checks=("${deduped[@]}")

  for name in "${checks[@]}"; do
    run_check "$name" || true
  done

  # Summary.
  section "summary"
  local failed=0
  for name in "${checks[@]}"; do
    case "$(get_result "$name")" in
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
