#!/usr/bin/env bash
# smoke.sh — Sparta headless smoke test.
#
# Runs in the repo root. Exits 0 on pass, non-zero on failure.
# Three probes, each independently useful:
#   1. headless import: loads all scripts/scenes, fails on any parse error
#   2. unit tests: 314 GUT tests must all pass
#   3. replay runner: headlessly plays back showcase.json for 30 ticks then quits
#
# Usage:
#   .claude/skills/run-sparta/smoke.sh           # all three probes
#   .claude/skills/run-sparta/smoke.sh validate  # only import check
#   .claude/skills/run-sparta/smoke.sh test      # only GUT tests
#   .claude/skills/run-sparta/smoke.sh replay    # only replay smoke

set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
PROBE="${1:-all}"

pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; exit 1; }

# ------------------------------------------------------------------
# 1. VALIDATE — headless import (no display needed)
# ------------------------------------------------------------------
if [[ "$PROBE" == "all" || "$PROBE" == "validate" ]]; then
  echo "== validate =="
  out=$("$GODOT_BIN" --headless --import 2>&1)
  if echo "$out" | grep -q "^ERROR:"; then
    echo "$out" | grep "^ERROR:"
    fail validate
  fi
  pass validate
fi

# ------------------------------------------------------------------
# 2. TEST — GUT unit suite (no display needed)
# ------------------------------------------------------------------
if [[ "$PROBE" == "all" || "$PROBE" == "test" ]]; then
  echo "== test =="
  out=$("$GODOT_BIN" --headless -s addons/gut/gut_cmdln.gd \
    -gtest=res://test/ -gexit 2>&1)
  if echo "$out" | grep -q "All tests passed"; then
    # Extract the summary line for visibility
    echo "$out" | grep -E "Tests|Passing|Time" | head -3
    pass test
  else
    echo "$out" | tail -30
    fail test
  fi
fi

# ------------------------------------------------------------------
# 3. REPLAY — headless battle smoke (no display needed)
# ------------------------------------------------------------------
if [[ "$PROBE" == "all" || "$PROBE" == "replay" ]]; then
  echo "== replay =="
  # DemoRunner loads the replay, enters Battle.tscn, runs 30 sim ticks, quits.
  out=$(SPARTA_DEMO_REPLAY=demos/showcase.json \
    timeout 60 "$GODOT_BIN" --headless \
      --scene res://tools/demo/DemoRunner.tscn \
      --quit-after 120 2>&1)
  if echo "$out" | grep -q "\[demo\] Playing back replay"; then
    pass replay
  else
    echo "$out" | tail -20
    fail replay
  fi
fi

echo ""
echo "== summary =="
echo "  All selected probes passed."
