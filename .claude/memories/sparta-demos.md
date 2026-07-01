---
name: sparta-demos
description: "Authoring, recording, and machine-verifying Sparta PR demo clips — the scripted-input recorder is the standard path"
metadata:
  type: feedback
---

# Sparta — demo authoring & verification

The scripted-input recorder is the **standard** demo path as of #318/#321. The
older hand-authored/recorded `replay` path (documented in the main `sparta.md`
"Authoring & verifying demo scenarios" section) still works and is fine for a
quick reuse of `demos/showcase.json`, but prefer scripted input for anything that
shows a specific player gesture.

## Author a scripted-input demo (the standard path)

Sparta PR demos **can** show player-gesture features (multi-unit form-up, orders,
etc.) — don't reflexively `skip` them.

1. Write `demos/inputs/<name>.json`:
   `{ "seed":"12345", "camera":[{tick,x,y,zoom}], "steps":[...] }`. Steps are
   stamped with a physics tick (60/s) and use world coords: `click [x,y]`,
   `shift_click`, `rmb_click`, `box {from,to}`, `rmb_drag {from,to,shift?}`,
   `key "Y"`.
2. Point a **per-PR** manifest `demos/demo.<issue-or-PR#>.json` at it (NOT the
   bare `demos/demo.json` — that single shared file caused constant merge
   conflicts; #416/#417 switched CI to prefer a `demos/demo.*.json` file *added*
   in the PR diff, falling back to `demo.json` then `showcase.json`). Shape:
   `{ "input":"demos/inputs/<name>.json", "caption":…, "fixed_fps":30,
   "max_frames":150, "fps":15, "width":720 }`. For a static/illegible-in-motion
   change, `{ "skip":true, "reason":… }` and rely on stills in the PR body.
3. CI's Demo video workflow detects `input` and runs
   `tools/demo/DemoInputRecorder.tscn`, which drives a LIVE battle by injecting
   the steps through the real `SelectionManager`, so the clip exercises the actual
   controls.

**Standard 5v5 (`seed "12345"`):** player uids 0-4 =
Spearmen(140)/Infantry(120)/Archers(90)/Cavalry(80)/Cavalry(80) at
x=500/650/800/950/1100, y=300; enemies 5-9 at y=700. Spawn positions are
seed-independent, so clicks land regardless. For a form-up facing the enemy
(+y/down), drag **right→left** (start point on the right). Box-select a horizontal
row with e.g. `{from:[450,270], to:[850,330]}` (grabs uids 0/1/2). Pick infantry
(pointer marks) for facing-maneuver demos — they read cleanly under rotation.
Demo click coords are **world** coords (cursor override), not screen.

## Verify locally without ffmpeg (PNG-frame capture)

Movie Maker writes a PNG sequence for a `.png` path:

```sh
SPARTA_DEMO_INPUT="res://demos/inputs/<name>.json" "$GODOT_BIN" \
  --rendering-driver opengl3 --write-movie <scratch>/f.png \
  --fixed-fps 30 --quit-after 130 res://tools/demo/DemoInputRecorder.tscn
```

then `Read` a frame PNG. (The live `_draw()` renders the form-up preview during
the drag, so the gesture shows.) Drop `--headless` on Windows — it crashes Movie
Maker. Run `--headless --import` first in a fresh worktree. See the
"Local testing" section of `sparta.md` for the binary.

**Throwaway tool-scene screenshots** — for a state a recorded battle can't easily
reach, write a one-off `tools/demo/_shot_<n>.gd` + `.tscn` (a `Node` that loads
`Battle.tscn`, drives it, then
`get_viewport().get_texture().get_image().save_png("user://…")` and
`get_tree().quit()`), run it `--rendering-driver opengl3` (NOT headless — the
dummy renderer gives a null texture), then `Read` the PNG and **delete the
throwaway files**. Forcing states: hold-Space order overlay →
`Replay.mode = Replay.Mode.PLAYBACK; Replay.show_demo_orders = true`; mark LOD →
set `cam.zoom < 1.30` (below `LOD_ZOOM_OUT`). Annotate untyped
`load(...).instantiate()` with `: Node` or it's a parse error.

**Upscale crops to verify few-pixel render detail.** Mark-LOD glyphs are ~2 px; a
full-size screenshot looked fine but *hid* a regression (a "fixed" mark was
actually striping the other way). Crop and upscale with PIL NEAREST:
`Image.open(p).crop(box).resize((w*7,h*7), Image.NEAREST).save(out)`. Render
principle this caught: a directional mark glyph must be **compact along the facing
axis** (front-reach ≤ the infantry pointer's span); elongating it just trades
horizontal stripes for vertical ones when a packed rank rotates. Distinguish unit
types by *silhouette* (dart/kite/pointer), keeping team colour pure — a per-type
colour tint muddies the block's team-colour `modulate`.

## Verify a demo by exact game-state values (state dump)

As of PR #501 (#500) a demo can be verified by **reading exact game-state
values**, not just interpreting a rendered frame. It's the machine-readable
companion to `SPARTA_DEMO_FRAMES` PNG capture (#492), on the same recorder.

**Dump command (Windows / Git Bash):**
```sh
GODOT_BIN="…/Godot_v4.7-stable_win64_console.exe" \
  tools/demo/dump-state.sh demos/inputs/rout-rally.json 8,60,140 /tmp/state
```
Then `Read` each `state_<tick>.json` and assert on the values. Unlike frame
capture, the dump reads sim state (not the drawn frame), so it runs
**`--headless`** — no `--rendering-driver opengl3`, no window, faster.

**Plumbing (mirrors the frames path):**
- Env `SPARTA_DEMO_STATE` = comma-separated tick list; `SPARTA_DEMO_STATE_DIR` =
  out dir (default temp); `SPARTA_DEMO_STATE_FULL=1` also dumps raw per-soldier
  arrays.
- An input script can carry a `"state": [ticks]` array; env + script merge via the
  same `DemoFrames.merge_ticks` used by `frames`.
- Env-gated: unset = off; normal recording and the frames path are unchanged.

**Per-unit JSON fields** (readable enum NAMES, not ints): `uid`, `name`, `team`,
`position` [x,y], `facing` [x,y], `morale`, `state`
(IDLE/MOVING/FIGHTING/ROUTING/DEAD), `formation`
(NORMAL/TIGHT/LOOSE/SQUARE/SHIELD_WALL/TESTUDO), `soldiers`, `current_speed`,
`order_mode` (from `Battle.ORDER_MODE_NAMES`), `target_enemy_uid`, `engaged`, and
a `soldier_summary` {count, centroid, bbox, prone_count}.

**Pure-vs-node split:** the enum-name maps + `soldier_summary` are pure static
funcs in `tools/demo/DemoState.gd` (a `class_name`, unit-tested in
`test/unit/test_demo_state.gd` like `DemoFrames`); the node-side dump (walking the
"units" group, JSON write) lives on `DemoInputRecorder.gd`. New `class_name` → run
`godot --headless --import` and commit the `.gd.uid`.

**Gotchas baked into the dump:**
- `_sim_soldier_pos` is WORLD-space; the summary centroid/bbox use it directly.
- "prone" is per-soldier (`_sim_prone[i] > 0` = down); "engaged" is per-UNIT
  (`is_engaged()`) — so the summary carries `prone_count` per-soldier but
  `engaged` is a unit bool.
- A unit routs only at `morale <= 0` (`UnitCombat.gd`). Don't claim a ROUTING
  state a scenario doesn't actually produce (the `rout-rally.json` staged unit is
  annihilated before morale hits 0, so it never reaches ROUTING within reachable
  ticks).
- Enum-name maps use an explicit table with an "UNKNOWN(<n>)" fallback, so a new
  enum member surfaces as a greppable token. A merge that adds enum members (e.g.
  main adding SHIELD_WALL/TESTUDO) leaves the map STALE even when conflict-free —
  update the map + its test + the README field row.

## A unified "all artifacts done" quit-check must guard on armed

When two (or more) optional per-tick artifact paths (frame capture, state dump)
share ONE "are we done?" check that gates `get_tree().quit()`, the check must
require at least one path to be armed. Otherwise the empty case
(`0 == 0 and 0 == 0`) is trivially true and the run quits after the first tick.

This bit PR #501: a state-dump path (`_state_ticks`) was added next to the
frame-capture path (`_frame_ticks`) in `tools/demo/DemoInputRecorder.gd`, unifying
the two done-checks into one `_all_artifacts_done()` called unconditionally each
physics frame. In a normal CI movie recording neither env var is set, so both tick
lists are empty and the naive check returned `true` on tick 1 — quitting every
recording after one frame.

Fix (the guard is load-bearing — keep it FIRST so it short-circuits):

```gdscript
func _all_artifacts_done() -> bool:
	return (_frame_ticks.size() + _state_ticks.size()) > 0 \
		and _captured.size() == _frame_ticks.size() \
		and _state_dumped.size() == _state_ticks.size()
```

Root cause was moving the quit call out of the old `if _frame_ticks.has(tick)`
guard into an unconditional call. When you refactor a guarded side effect into a
shared helper, the guard that was implicit in the enclosing `if` must be made
explicit inside the helper. Also update sibling checks (e.g. a timeout handler) to
use the same unified predicate.

## CI re-record trigger & shared-checkout hazard

CI re-records only when the push diff touches
`scenes/`/`scripts/`/`assets/`/`project.godot`/`demos/*.json`/`demos/scenarios/**`/`demos/inputs/**`
— a demos-only push now DOES re-trigger (fixed in #317). A `main`-merge that drags
scripts into the diff also re-triggers.

**Shared-checkout hazard:** this repo often has concurrent AI sessions on the local
checkout. Always do PR work in an isolated `git worktree` off `origin/<branch>`,
never on the shared checkout. `main` moves fast (physics slices), so expect
repeated `demos/demo.json` merge conflicts — resolve by keeping your branch's
manifest, and check for a `demos/demo.<PR#>.json` first: CI prefers a
`demos/demo.*.json` file *added in the PR diff* over the bare `demo.json`, so the
correct clip records even if the merge left `demo.json` holding another PR's
content. Still fix `demo.json` when it's stale — a `git merge origin/main`
silently takes main's `demo.json` (theirs).
