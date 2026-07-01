#!/usr/bin/env bash
# tools/demo/capture-frames.sh — render a scripted-input demo to PNG frames at chosen ticks,
# so a demo can be visually verified (the frame actually shows the intended behaviour), not
# just confirmed to run. See demos/README.md, "Verifying a demo visually".
#
# It drives the live battle through DemoInputRecorder (the same recorder CI uses), and at each
# listed physics tick saves the drawn viewport to a PNG. Capture needs a REAL renderer, so it
# runs WITHOUT --headless using --rendering-driver opengl3 (a window may open locally; that's
# fine). --headless uses the dummy renderer and produces blank/null textures.
#
# Usage:
#   tools/demo/capture-frames.sh <input-script> <ticks> [out-dir]
#
#   <input-script>  Repo-relative or res:// path to a demos/inputs/*.json script.
#   <ticks>         Comma-separated physics ticks, e.g. 10,60,120.
#   [out-dir]       Output dir for the PNGs (default: a temp dir; the path is printed).
#
# Environment:
#   GODOT_BIN   Godot 4.7 binary (default: godot). On Windows, e.g.
#               C:\Users\you\apps\Godot_v4.7-stable_win64_console.exe
#
# Example (Windows, from the repo root):
#   GODOT_BIN="C:\Users\you\apps\Godot_v4.7-stable_win64_console.exe" \
#     tools/demo/capture-frames.sh demos/inputs/rout-rally.json 20,90,160 /tmp/frames
#   # then Read /tmp/frames/frame_00020.png … and confirm the units/behaviour are on-screen.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
GODOT_BIN="${GODOT_BIN:-godot}"

if [ "$#" -lt 2 ]; then
  sed -n '2,30p' "$0"   # print the usage header
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

# Import once so autoloads / class_name globals (DemoFrames) are registered.
"$GODOT_BIN" --headless --import --path "$PROJECT_ROOT" >/dev/null 2>&1 || true

export SPARTA_DEMO_INPUT="$INPUT_RES"
export SPARTA_DEMO_FRAMES="$TICKS"
if [ -n "$OUT_DIR" ]; then
  export SPARTA_DEMO_FRAME_DIR="$OUT_DIR"
fi

echo "Rendering $INPUT_RES frames at ticks $TICKS…"
# Real renderer (opengl3), NOT --headless — capture needs a drawn frame. The recorder quits
# itself once the last armed frame is saved, so no --quit-after frame count is needed (and a
# frame count is unreliable: an unfocused window throttles rendering, quitting before the run
# reaches the later ticks).
"$GODOT_BIN" --rendering-driver opengl3 --path "$PROJECT_ROOT" \
  res://tools/demo/DemoInputRecorder.tscn

if [ -n "$OUT_DIR" ]; then
  echo "Done. Frames in: $OUT_DIR"
else
  echo "Done. Frames written to the temp dir the recorder printed above" \
       "(the '-> …' path on the 'frame capture armed' line); pass a third arg to choose the dir."
fi
