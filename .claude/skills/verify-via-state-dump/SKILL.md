---
name: verify-via-state-dump
description: Verify a claimed gameplay behavior (a maneuver, formation, speed/physics rule, or combat/morale rule) against the machine-readable per-tick state transcript instead of trusting a video/GIF. Use before merging a PR, or whenever a claim is visually ambiguous or seems to contradict a demo clip.
user-invocable: true
allowed-tools: Bash, Read, Grep, Glob, Write
---

# Verify via state dump

Prove a gameplay claim numerically, from the sim's own per-tick JSON state,
rather than by eyeballing a rendered frame or a GIF. This is the method that
ran across today's maneuver, formation, speed/physics, and combat/morale
verification sweeps (#474, #469, #466, #463, #485, #487, #452, #471, #442,
#449, #454, #497, #439, #431, #460, #495, #465/#517, #541) — it caught five
real bugs that a video-eyeballing pass missed.

## When to use this

- Verifying a PR's or issue's claimed gameplay behavior before merging.
- A demo clip looks plausible but the claim is subtle (mid-maneuver geometry,
  per-soldier identity, an exact speed/timing threshold, a morale/rout
  trigger tick).
- A claim in a PR description or review comment seems to contradict what a
  linked video/GIF shows, or the claim can't be confirmed by eye at all.

## Why not just watch the video

Aggregate/whole-clip visual checks — and even automated bbox/centroid
footprint checks — can miss real bugs, because they only prove the *summary*
stayed put, not that every individual soldier moved the way the claim says:

- **#517 (about-face centre-pivot).** The unit's final facing and position
  looked correct at the end of the turn. The bug was in the *middle* of the
  turn — the pivot briefly recentered on the unit's centroid instead of
  holding its anchor file — and only showed up sampling frames mid-maneuver,
  not at the clip's start/end.
- **#541 (soldier identity-swap).** The aggregate footprint — centroid,
  bounding box, soldier count — was **identical** before and after, because
  the formation's layout was symmetric: soldiers had swapped which body
  occupied which slot, but the slots themselves didn't move. A bbox/centroid
  check, or a human glancing at the clip, saw "nothing changed" and passed
  it. Only tracking **each soldier by index** (not by slot) caught the swap.

The lesson: aggregate metrics prove less than they seem to. Whenever a claim
is about *identity* or *mid-action* geometry, check per-soldier, per-tick —
not just the start/end aggregate.

## The method

1. **Stage a minimal scenario.** Write (or copy and edit) a scratch
   `demos/inputs/*.json` script — it doesn't need to be committed unless it's
   also going into the PR's demo manifest. Use:
   - `"seed"` — battle seed; `"12345"` is the documented standard layout
     (see `demos/README.md`, "Hand-authoring a scenario", for unit
     uid/position/speed tables).
   - `"drill": true` — solo rehearsal: only team 0 deploys, the sim never
     auto-ends, so a maneuver can be exercised with no combat. Good for
     wheeling/nudge/formation claims.
   - `"scenario": [...]` — stage a custom matchup instead of the default 5v5
     when the claim needs a specific pairing (a rout, a flank charge, a
     morale threshold). Each entry: `team` (0 player / 1 enemy), `type`
     (`Spearmen`/`Infantry`/`Archers`/`Cavalry`), `x`, `y`, optional `facing`
     `[x,y]`, `count`, `morale`, `formation` (0 Normal, 1 Tight, 2 Loose,
     3 Square, 4 Shield Wall, 5 Testudo).
   - `"camera"` — optional keyframes `{tick,x,y,zoom}`; irrelevant to the
     state dump itself (state is read from sim data, not the drawn frame),
     but keep it if you'll also render frames for a sanity look.

   Example (`demos/inputs/wheel.json`, real file in this repo):
   ```json
   {
     "seed": "12345",
     "drill": true,
     "camera": [{"tick": 0, "x": 650.0, "y": 300.0, "zoom": 1.1}],
     "steps": [
       {"tick": 10, "click": [650, 300]},
       {"tick": 30, "key": "C"},
       {"tick": 150, "key": "Z"}
     ]
   }
   ```

2. **Script the exact action the claim is about**, via `"steps"` — each
   stamped with a physics `tick` (60/s):
   - `{"tick": t, "click": [x, y]}` / `"shift_click"` / `"rmb_click"` — a
     press+release at a world-space point (select, or issue an order).
   - `{"tick": t, "box": {"from": [x,y], "to": [x,y]}}` — a drag box-select.
   - `{"tick": t, "rmb_drag": {"from": [x,y], "to": [x,y], "shift": false}}`
     — a right-drag move/form-up order.
   - `{"tick": t, "key": "Y"}` — a gameplay hotkey (formation cycle, stance,
     etc.).

3. **Dump per-tick state.** Either add a `"state": [t1, t2, ...]` array to
   the input script, or set the `SPARTA_DEMO_STATE` env var (the two merge).
   Use the wrapper:
   ```sh
   GODOT_BIN="C:\path\to\Godot_v4.7-stable_win64_console.exe" \
     tools/demo/dump-state.sh demos/inputs/<script>.json 8,60,140 /tmp/state
   ```
   This runs `--headless` (fast, no window) and writes one
   `state_<tick>.json` per tick to the output dir. Pick ticks the run
   actually reaches — a battle freezes its tick when it ends (rout resolves,
   one side wiped), so a tick armed past that never fires; for a `drill`
   scenario the sim never auto-ends, so any tick up to the script's length
   works.

   Set `SPARTA_DEMO_STATE_FULL=1` when the claim is about **individual
   soldiers** — identity, per-body position/facing — not just the unit as a
   whole. This adds `soldiers_full` per unit: index-aligned `pos`, `facing`,
   `hp`, `prone`, `stamina` arrays (world-space `[x,y]` pairs for pos/facing).
   Without it you only get `soldier_summary` (`count`, `centroid`, `bbox`,
   `prone_count`) — a compact digest that, per #541 above, cannot distinguish
   "nothing moved" from "everyone moved and swapped identities."

   Per-unit fields always present: `uid`, `name`, `team`, `position`,
   `facing`, `morale`, `state` (`IDLE`/`MOVING`/`FIGHTING`/`ROUTING`/`DEAD`),
   `formation` (`NORMAL`/`TIGHT`/`LOOSE`/`SQUARE`/`SHIELD_WALL`/`TESTUDO`),
   `soldiers` (living count), `current_speed`, `order_mode`,
   `target_enemy_uid`, `engaged`.

4. **Compute the right metric for the claim** — don't default to the
   aggregate:
   - **Footprint/spacing claims** ("the block stays in formation", "the unit
     doesn't spread out") — `soldier_summary.centroid` / `.bbox` / `.count`
     across ticks is enough.
   - **Identity/individual-body claims** ("soldier stays in its own file",
     "no soldier teleports/swaps") — use `soldiers_full`. Track **by array
     index**, not by nearest-neighbor position: soldier `i` at tick A should
     (or per the claim, should NOT) be near soldier `i`'s own tick-B slot.
     Compare index-to-index across ticks, not just "is some soldier near
     this spot."
   - **Timing claims** (first casualty, rally tick, rout-trigger tick,
     speed-cap-reached tick) — scan the per-tick `state`/`morale`/`soldiers`/
     `current_speed` sequence for the tick where the value crosses the
     claimed threshold; report that tick number.

5. **Compare against the claim numerically.** State the exact numbers (tick,
   position, morale, index) that confirm or refute the claim. Don't describe
   a frame — quote the JSON values.

6. **If the claim doesn't hold**, search for an existing issue first
   (`gh issue list --search ...`), then file one with the concrete
   before/after numbers as proof — a tick table (tick, field, expected,
   actual), not a prose description.

## Known pitfalls

- **GIF frame extraction needs PIL's `ImageSequence`, not ffmpeg**, when
  ffmpeg isn't available locally. Sample frames across the **whole** clip,
  not just the start/end — a footprint-preserving maneuver bug (#517) can
  live entirely in the middle of the motion and never show at the
  endpoints.
- **Verify a cited commit SHA actually matches the PR's current HEAD**
  before trusting a linked demo as representative of the code under review.
  A demo comment can go stale after a later push. Issue #542 tracks a CI
  freshness gate for this; until it lands, check manually
  (`gh pr view <N> --json headRefName,commits` or compare the SHA in the
  demo-media link against `git rev-parse HEAD` on the PR branch).
- **Aggregate metrics can't distinguish "nothing moved" from "everything
  moved and swapped identity-preservingly."** Any claim of position- or
  identity-invariance (a formation change that's supposed to preserve who
  stands where, a maneuver that's supposed to keep files intact) needs a
  per-soldier-index check, not just a bbox/centroid comparison — see #541.

## Reference

- `demos/README.md`, "Verifying a demo by state (AI verification)" — the
  full field reference and CI's automatic per-PR transcript.
- `tools/demo/DemoState.gd` — pure serialization (`soldier_summary`,
  enum-name tables).
- `tools/demo/DemoInputRecorder.gd` — the recorder; builds `soldiers_full`
  (`_soldier_arrays`) and the per-unit record.
- `tools/demo/dump-state.sh` — the CLI wrapper used above.
- `demos/inputs/*.json` — existing scripted-input scenarios to copy from
  (e.g. `wheel.json`, `rout-rally.json`, `about-face.json`,
  `file-doubling.json`).
