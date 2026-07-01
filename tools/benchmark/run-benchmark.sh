#!/usr/bin/env bash
# tools/benchmark/run-benchmark.sh -- run the reference large-battle performance benchmark
# and print a human-readable summary. See tools/benchmark/README.md for the full protocol
# (including how to use this LOCALLY on real reference hardware to check the actual 60fps
# target -- CI runners are not that hardware; see there for why).
#
# Drives tools/benchmark/BenchmarkRunner.tscn headlessly: loads a demos/README.md-style
# "scenario" (default: benchmarks/scenarios/large-battle.json), lets combat spin up for a
# warmup window, then times N physics ticks and reports mean/p95/max tick time and the
# implied fps (see BenchmarkRunner.gd's class doc for what "implied fps" does and doesn't
# capture -- physics-step time only, not render cost).
#
# Usage:
#   tools/benchmark/run-benchmark.sh [scenario] [scale]
#
#   [scenario]  Repo-relative or res:// path to a benchmarks/scenarios/*.json scenario
#               (default: benchmarks/scenarios/large-battle.json).
#   [scale]     Soldier-count multiplier applied to every unit in the scenario, e.g. 2 to
#               double headcount (default: 1). Useful for a local sweep to find the
#               soldier-count ceiling on your machine -- see the README.
#
# Environment:
#   GODOT_BIN                    Godot 4.7 binary (default: godot). On Windows, e.g.
#                                 C:\Users\you\Documents\apps\Godot_v4.7-stable_win64_console.exe
#   SPARTA_BENCHMARK_WARMUP_TICKS  Physics ticks to run before measuring (default 120 = 2s).
#   SPARTA_BENCHMARK_TICKS         Physics ticks to measure (default 600 = 10s).
#   SPARTA_BENCHMARK_OUT           Output JSON path (default: a temp file; printed below).
#
# Example (Windows, from the repo root):
#   GODOT_BIN="C:\Users\you\Documents\apps\Godot_v4.7-stable_win64_console.exe" \
#     tools/benchmark/run-benchmark.sh
#
#   # A local scaling sweep (see README, "Finding the soldier-count ceiling"):
#   for s in 1 2 4; do
#     tools/benchmark/run-benchmark.sh benchmarks/scenarios/large-battle.json "$s"
#   done
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
GODOT_BIN="${GODOT_BIN:-godot}"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,33p' "$0"   # print the usage header
  exit 0
fi

SCENARIO="${1:-benchmarks/scenarios/large-battle.json}"
SCALE="${2:-1}"

# Normalize the scenario path to res:// so the runner (running inside the project) can open
# it -- same normalization dump-state.sh applies to input scripts.
case "$SCENARIO" in
  res://*) SCENARIO_RES="$SCENARIO" ;;
  /*)      SCENARIO_RES="res://${SCENARIO#"$PROJECT_ROOT"/}" ;;   # absolute inside the repo
  *)       SCENARIO_RES="res://$SCENARIO" ;;                      # repo-relative
esac

OUT_PATH="${SPARTA_BENCHMARK_OUT:-$(mktemp -t sparta_benchmark_XXXXXX.json 2>/dev/null || echo "${TMPDIR:-/tmp}/sparta_benchmark_result.json")}"

# Import once so autoloads / class_name globals (BenchmarkStats) are registered.
"$GODOT_BIN" --headless --import --path "$PROJECT_ROOT" >/dev/null 2>&1 || true

export SPARTA_BENCHMARK_SCENARIO="$SCENARIO_RES"
export SPARTA_BENCHMARK_SCALE="$SCALE"
export SPARTA_BENCHMARK_OUT="$OUT_PATH"

echo "Benchmarking $SCENARIO_RES at scale ${SCALE}x..."
# Plain --headless, no --write-movie / --fixed-fps: the runner free-runs physics as fast as
# the CPU allows (Engine.max_fps = 0) and self-quits once its measurement window completes
# (or its own timeout/stall guard fires), so no --quit-after tick count is needed here.
"$GODOT_BIN" --headless --path "$PROJECT_ROOT" \
  res://tools/benchmark/BenchmarkRunner.tscn || true
# `|| true`: a headless Godot run's exit code is not a reliable success signal (push_error()
# does not set a nonzero exit -- see CLAUDE.md), so the OUTPUT FILE below is the authoritative
# check, not this command's exit status.

if [ ! -s "$OUT_PATH" ]; then
  echo "ERROR: no benchmark report was written to $OUT_PATH (run may have crashed or hung)." >&2
  exit 1
fi

echo
echo "Report: $OUT_PATH"
python3 - "$OUT_PATH" <<'PY' 2>/dev/null || cat "$OUT_PATH"
import json, sys
with open(sys.argv[1]) as f:
    r = json.load(f)
s = r["stats"]
budget_ms = 1000.0 / 60.0
print(f"  scenario:          {r['scenario']}")
print(f"  soldiers simulated: {r['soldier_count']} (scale {r['scale']}x)")
print(f"  ticks sampled:      {s['count']} / {r['requested_measure_ticks']}"
      f"{'  (EARLY STOP -- see warnings above)' if r['early_stop'] else ''}")
print(f"  mean tick time:     {s['mean_ms']:.3f} ms  (implied {s['implied_fps']:.1f} fps)")
print(f"  p95 tick time:      {s['p95_ms']:.3f} ms")
print(f"  worst tick time:    {s['max_ms']:.3f} ms")
print(f"  60fps budget:       {budget_ms:.3f} ms/tick -- "
      f"{'WITHIN budget on mean' if s['mean_ms'] <= budget_ms else 'OVER budget on mean'}"
      f", {'within budget on p95' if s['p95_ms'] <= budget_ms else 'over budget on p95'}")
PY
