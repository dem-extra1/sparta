#!/usr/bin/env bash
# tools/demo/dump-state.sh — dump machine-readable JSON game-state from a scripted-input demo at
# chosen ticks, so a demo can be verified by ASSERTING ON EXACT VALUES (a unit's state, morale,
# position) instead of interpreting a rendered frame. See demos/README.md, "Verifying a demo by
# state (AI verification)". It's the machine-readable companion to capture-frames.sh.
#
# It drives the live battle through DemoInputRecorder (the same recorder CI uses), and at each
# listed physics tick writes state_<tick>.json to the output dir. Unlike frame capture this reads
# SIM state (not the drawn frame), so it runs under --headless — no real renderer needed.
#
# Usage:
#   tools/demo/dump-state.sh <input-script> <ticks> [out-dir]
#
#   <input-script>  Repo-relative or res:// path to a demos/inputs/*.json script.
#   <ticks>         Comma-separated physics ticks, e.g. 8,60,140.
#   [out-dir]       Output dir for the JSON (default: a temp dir; the path is printed).
#
# Environment:
#   GODOT_BIN               Godot 4.7 binary (default: godot). On Windows, e.g.
#                           C:\Users\you\apps\Godot_v4.7-stable_win64_console.exe
#   SPARTA_DEMO_STATE_FULL  Set to 1 to also dump the raw per-soldier arrays (deep debugging).
#
# Example (Windows, from the repo root):
#   GODOT_BIN="C:\Users\you\apps\Godot_v4.7-stable_win64_console.exe" \
#     tools/demo/dump-state.sh demos/inputs/rout-rally.json 8,60,140 /tmp/state
#   # then Read /tmp/state/state_00140.json and assert on the values.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
GODOT_BIN="${GODOT_BIN:-godot}"

if [ "$#" -lt 2 ]; then
  sed -n '2,33p' "$0"   # print the usage header
  exit 2
fi

INPUT="$1"
TICKS="$2"
OUT_DIR="${3:-}"

# Normalize the input path to res:// so the recorder (running inside the project) can open it.
case "$INPUT" in
  res://*) INPUT_RES="$INPUT" ;;
  /*)      INPUT_RES="res://${INPUT#"$PROJECT_ROOT"/}" ;;   # absolute inside the repo
  *)       INPUT_RES="res://$INPUT" ;;                      # repo-relative
esac

# Import once so autoloads / class_name globals (DemoFrames, DemoState) are registered.
"$GODOT_BIN" --headless --import --path "$PROJECT_ROOT" >/dev/null 2>&1 || true

export SPARTA_DEMO_INPUT="$INPUT_RES"
export SPARTA_DEMO_STATE="$TICKS"
if [ -n "$OUT_DIR" ]; then
  export SPARTA_DEMO_STATE_DIR="$OUT_DIR"
fi

echo "Dumping $INPUT_RES state at ticks $TICKS…"
# --headless is fine: the dump reads sim state, not the drawn frame. The recorder quits itself
# once the last armed snapshot is written, so no --quit-after tick count is needed.
"$GODOT_BIN" --headless --path "$PROJECT_ROOT" \
  res://tools/demo/DemoInputRecorder.tscn

if [ -n "$OUT_DIR" ]; then
  echo "Done. State JSON in: $OUT_DIR"
else
  echo "Done. State JSON written to the temp dir the recorder printed above" \
       "(the '-> …' path on the 'state dump armed' line); pass a third arg to choose the dir."
fi
