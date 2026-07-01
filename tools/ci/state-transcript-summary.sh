#!/usr/bin/env bash
# Build a compact, human+AI-readable game-state summary from a set of per-tick
# state_<tick>.json snapshots (written by tools/demo/DemoInputRecorder.gd) and a
# single merged JSON of all snapshots. The summary is inlined into the demo PR
# comment so a reviewer — human or the @claude review bot — reads exact per-tick
# unit state (State / formation / order mode / morale / soldiers / centroid)
# directly in the PR conversation, instead of eyeballing the GIF. The merged JSON
# is published alongside the GIF/MP4 for full detail.
#
# Usage:
#   tools/ci/state-transcript-summary.sh <state-dir> <merged-json-out> <summary-md-out>
#
#   <state-dir>        Dir holding state_<tick>.json files (from the dump run).
#   <merged-json-out>  Path to write the merged {"ticks":[{tick,units}, …]} JSON.
#   <summary-md-out>   Path to write the compact markdown summary block.
#
# Emits nothing to the media/comment when no snapshots were produced: exits non-zero
# so the caller treats it as a failed (best-effort) dump and posts no transcript.
# Requires jq.
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $(basename "$0") <state-dir> <merged-json-out> <summary-md-out>" >&2
  exit 2
fi

STATE_DIR="$1"
MERGED_OUT="$2"
SUMMARY_OUT="$3"

# Collect the per-tick snapshots in tick order. Zero-padded filenames sort correctly.
shopt -s nullglob
FILES=("$STATE_DIR"/state_*.json)
if [ "${#FILES[@]}" -eq 0 ]; then
  echo "No state_*.json snapshots found in $STATE_DIR" >&2
  exit 1
fi

# Merge every snapshot into one array, sorted by tick, as the full downloadable artifact.
# `-s` slurps the files into an array; each element is already a {tick,units} object.
jq -s 'sort_by(.tick) | {ticks: .}' "${FILES[@]}" > "$MERGED_OUT"

# Guard the artifact per the push_error/exit-code note in CLAUDE.md: verify the merged
# JSON exists and is non-empty (and actually holds ticks) rather than trusting exit code.
if [ ! -s "$MERGED_OUT" ] || [ "$(jq '.ticks | length' "$MERGED_OUT")" -eq 0 ]; then
  echo "Merged transcript JSON is empty or has no ticks" >&2
  exit 1
fi

# Build the compact markdown summary: one table per dumped tick, one row per unit,
# with the key fields a reviewer needs. Centroid is the soldier-body centre [x,y].
{
  echo '<details><summary>🔬 <b>Per-tick state transcript</b> — exact unit state for AI/spot verification</summary>'
  echo
  jq -r '
    .ticks[]
    | "\n**tick \(.tick)**\n",
      "| unit | team | state | formation | order | morale | soldiers | centroid |",
      "| --- | --- | --- | --- | --- | ---: | ---: | --- |",
      ( .units[]
        | "| \(.name) | \(.team) | \(.state) | \(.formation) | \(.order_mode) | \(.morale) | \(.soldiers) | [\(.soldier_summary.centroid[0]), \(.soldier_summary.centroid[1])] |"
      )
  ' "$MERGED_OUT"
  echo
  echo '</details>'
} > "$SUMMARY_OUT"

if [ ! -s "$SUMMARY_OUT" ]; then
  echo "Summary markdown is empty" >&2
  exit 1
fi

echo "Wrote merged transcript ($(jq '.ticks | length' "$MERGED_OUT") ticks) and summary."
