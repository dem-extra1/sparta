#!/usr/bin/env bash
# Record Sparta gameplay demo clips (mp4 + poster jpg) for the documentation site.
#
# Plays each named replay back headlessly via Godot's Movie Maker, then encodes the
# result to a browser-friendly MP4 (with sound) and a poster frame. This reuses the
# same pipeline as .github/workflows/demo-video.yml — the project's deterministic
# replays reproduce on the same build, so each clip reflects the current code.
#
# Usage:
#   website/tools/record-demos.sh [OUTPUT_DIR]
#
# Environment:
#   GODOT_BIN     Godot 4.7 binary (default: godot). On macOS, e.g.
#                 /Applications/Godot.app/Contents/MacOS/Godot
#   PROJECT_ROOT  Repo root (default: inferred from this script's location)
#
# Requirements: a Godot 4.7 binary, ffmpeg, and (on a headless Linux host) xvfb —
# the script auto-wraps Godot in `xvfb-run` when no DISPLAY is set and it's available.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
OUT_DIR="${1:-$PROJECT_ROOT/website/media}"
GODOT_BIN="${GODOT_BIN:-godot}"

# Each demo: name | source (res://-relative) | fixed_fps | max_frames | width(px) | type.
# type is "replay" (default, DemoRunner.tscn) or "input" (DemoInputRecorder.tscn).
# Replays may be seed-only auto-battles or scripted scenarios with hand-authored orders.
DEMOS=(
  "showcase|demos/showcase.json|30|360|800|replay"
  "clash|demos/clash.json|30|240|640|replay"
  "charge|demos/charge_demo.json|30|240|640|replay"
  "support|demos/support_demo.json|30|240|640|replay"
  "group_attack|demos/inputs/group-attack-distributed.json|30|240|640|input"
  "pace_modes|demos/inputs/pace-modes.json|30|420|640|input"
  "sidestep|demos/inputs/sidestep.json|30|150|640|input"
  "about_face|demos/inputs/about-face.json|30|180|640|input"
  "wheel|demos/inputs/wheel.json|30|300|640|input"
  "square|demos/inputs/anti-cav-square.json|30|300|640|input"
  "order_distance|demos/inputs/order-distance.json|30|120|640|input"
  "file_doubling|demos/inputs/file-doubling.json|30|300|640|input"
  "cycle_charge|demos/inputs/cycle-charge.json|30|600|640|input"
  "testudo_under_fire|demos/inputs/testudo-under-fire.json|30|300|640|input"
)

# Wrap Godot in a virtual framebuffer on a headless host (CI). Movie Maker needs a
# render context; software GL under Xvfb is fine (no GPU required).
GODOT_RUN=("$GODOT_BIN")
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
  GODOT_RUN=(xvfb-run -a "$GODOT_BIN")
fi

command -v ffmpeg >/dev/null 2>&1 || { echo "error: ffmpeg not found on PATH" >&2; exit 1; }

cd "$PROJECT_ROOT"
mkdir -p "$OUT_DIR"

# Scratch dir for the intermediate AVIs, removed on exit. mktemp -d is portable
# (BSD + GNU); naming the AVI inside it avoids the leak of `$(mktemp).avi`, where
# the suffix-less placeholder mktemp creates is never the file we later remove.
WORK_DIR="$(mktemp -d -t sparta-demo-XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Import once so scripts/scenes resolve. Movie Maker would import on first run
# anyway, but a clean import surfaces script errors up front.
"$GODOT_BIN" --headless --import || true

for spec in "${DEMOS[@]}"; do
  IFS='|' read -r NAME SOURCE FIXED_FPS MAX_FRAMES WIDTH TYPE <<<"$spec"
  TYPE="${TYPE:-replay}"
  if [ "$TYPE" = "input" ]; then
    SCENE=res://tools/demo/DemoInputRecorder.tscn
    ENV_KEY=SPARTA_DEMO_INPUT
  else
    SCENE=res://tools/demo/DemoRunner.tscn
    ENV_KEY=SPARTA_DEMO_REPLAY
  fi
  echo "== Recording '$NAME' ($TYPE: res://$SOURCE, $MAX_FRAMES frames @ ${FIXED_FPS}fps, ${WIDTH}px) =="

  AVI="$WORK_DIR/$NAME.avi"
  env "${ENV_KEY}=res://${SOURCE}" "${GODOT_RUN[@]}" \
    --rendering-driver opengl3 \
    --write-movie "$AVI" --fixed-fps "$FIXED_FPS" \
    --quit-after "$MAX_FRAMES" "$SCENE"
  [ -s "$AVI" ] || { echo "::error::Movie Maker produced no output for '$NAME'"; exit 1; }

  # MP4 with sound: H.264 + AAC in yuv420p with +faststart is the most widely
  # browser-playable combination (Safari included). scale uses -2 so the height
  # stays even (a libx264 requirement). The demo runner force-enables SFX
  # (tools/demo/DemoRunner.gd), so the AVI carries any battle sound that fires
  # (still silent if a replay happens to trigger no sound events).
  ffmpeg -y -i "$AVI" \
    -vf "scale=$WIDTH:-2:flags=lanczos" \
    -c:v libx264 -pix_fmt yuv420p -profile:v high -movflags +faststart \
    -c:a aac -b:a 128k \
    "$OUT_DIR/$NAME.mp4"

  # Poster frame (~1s in) used as the <video poster=…> placeholder.
  ffmpeg -y -ss 1 -i "$OUT_DIR/$NAME.mp4" -frames:v 1 -q:v 3 "$OUT_DIR/$NAME.jpg"

  rm -f "$AVI"
  echo "  -> $OUT_DIR/$NAME.mp4  +  $OUT_DIR/$NAME.jpg"
done

echo "Done — wrote ${#DEMOS[@]} demo clip(s) to $OUT_DIR"
