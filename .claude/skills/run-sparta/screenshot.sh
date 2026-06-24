#!/usr/bin/env bash
# screenshot.sh — Launch Sparta in a virtual framebuffer and capture a PNG.
#
# Usage (run from repo root):
#   .claude/skills/run-sparta/screenshot.sh [output.png]
#
# Output defaults to /tmp/sparta_screenshot.png.
# Requires: xvfb-run, scrot, godot on PATH (or GODOT_BIN set).
# The game renders via llvmpipe (no real GPU needed).

set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
OUT="${1:-/tmp/sparta_screenshot.png}"
DISPLAY_NUM=":98"  # use :98 to avoid collision with other xvfb sessions

# Launch Godot in a virtual framebuffer. After 4 seconds the battle is loaded
# and the first frame has been drawn. We screenshot then kill.
xvfb-run -n 98 -s "-screen 0 1280x720x24" bash -c "
  '$GODOT_BIN' --rendering-driver opengl3 --display-driver x11 \
    --scene res://scenes/Battle.tscn 2>/dev/null &
  GODOT_PID=\$!
  sleep 4
  DISPLAY=:98 scrot '$OUT'
  kill \$GODOT_PID 2>/dev/null
  wait \$GODOT_PID 2>/dev/null
"

echo "Screenshot saved to: $OUT"
ls -lh "$OUT"
