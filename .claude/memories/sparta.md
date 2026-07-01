---
name: sparta-gotchas
description: "Operational gotchas and reviewer conventions for Lacaedemon/sparta (Godot tactical battle game)"
metadata:
  type: feedback
---

# Sparta — working notes

## Pending: migrate to gha quarto-publish `@v2` (branch deploy)

Sparta is the registered `quarto-publish` consumer in gha's `REVDEPS.md`, and
gha cut a **breaking v2** (gha#118): `quarto-publish` moved from the Pages
`actions/deploy-pages` artifact to a `gh-pages` **branch** deploy. `@v1` was
rolled back to the last compatible commit, so sparta is safe on `@v1` for now.
To move to `@v2`: (1) Settings → Pages → Source = "Deploy from a branch",
`gh-pages` / `(root)`; (2) change the `quarto-publish.yml` caller's job
permissions from `pages: write` + `id-token: write` to `contents: write`;
(3) bump the pin to `@v2`. Migration steps live in the gha CHANGELOG.

## Website docs scope in stacked PRs

Sparta requires user-facing PRs to update the `website/` docs (the website-update
policy in the repo's `CLAUDE.md`). That requirement makes it easy to over-document:
on a stacked PR, write docs only for features whose code is on the *current branch's*
ancestry, not for a sibling branch's feature.

This is the sparta instance of the general rule in `preferences.md` ("only document
features present on the current branch's ancestry — grep first").

**Concrete case:** in the terrain-speed PR (#185), website docs were written for the
order-response delay feature (from `feat/order-response-delay`, a separate branch also
targeting `main`). That code was never in `feat/terrain-speed`'s ancestry, so the
reviewer correctly flagged it as a "hallucinated feature." Before documenting a feature,
`grep` for its symbol/constant (e.g. `order_response_delay`) on the current branch; if
it's absent, move the docs to the branch where the code lives.

## Demo scenario design — team 0 is stationary by default

Only team 1 (enemy AI, `_run_enemy_ai()`) auto-advances. Team 0 (player units) stays
**stationary** until given an explicit order, so any hand-authored
`demos/scenarios/*.json` replay that needs team 0 engaged must issue a move (or attack)
order early — at tick 0 or close to it. This bit the line-relief scenario (PR #200): the
relief order fired before any engagement because the player unit never advanced.

After writing a scenario, work out the engagement timing on paper before relying on the
CI clip to confirm it — a mistimed scenario wastes a CI run and may silently record an
unrelated moment.

The reference tables a scenario author needs — spawn positions and UIDs, effective unit
speeds, and the order `target`-field semantics — live with the code in sparta's
`demos/README.md` and `REPLAY.md`, not here. A memory copy of constants like
`SPEED_SCALE` and the spawn layout would rot silently when the game changes them.

## Demo camera path — record it like a human operator

When recording the camera presentation track for a demo (the track played back by
`tools/demo/DemoRunner.gd`), move the camera the way a person would, not a robot.
Repeated reviewer feedback on PR #232:

- **Don't chase the unit centroid recomputed every frame** — it drifts both ways as
  units shuffle and die, so the pan constantly *reverses direction* and reads as
  jerky even when smoothed. Sample a fixed focus point **once**, or don't anchor to
  the centroid at all.
- **Hold, then move once in one direction, then hold** — script holds plus single
  eased (smoothstep) moves; aim for ~1 direction-reversal per axis over the whole
  clip.
- **End on a multi-second stable hold** — finish all camera motion well before the
  recording ends (set `max_frames` to cover the motion *plus* the hold) so the clip
  doesn't cut off mid-move.
- **Raise the framerate for a moving camera** — `fixed_fps` 30 / GIF `fps` 12 suit a
  static-camera battle, but a panning/zooming camera looks choppy at 12 fps. Use
  `"fixed_fps": 60, "fps": 30` and bump `max_frames` to keep the duration.

Playback also low-passes the track (`Battle.CAMERA_SMOOTHING`), but that smooths
magnitude, not direction — fix the *path*, not just the filter. Verify by logging
the played-back camera and counting velocity sign-changes and per-tick jerk, not by
eyeballing one frame. The committed `demos/camera-showcase.json` is baked keyframes
(no centroid logic); author the recorder as a throwaway off-screen scene.

## Demo media in PRs — inline play-once GIF + link to the MP4

The demo workflow posts the PR clip as an **inline GIF that plays once** (ffmpeg
`-loop -1`, freezes on the final frame) plus a **link to the MP4 with sound**
(#236). The MP4 rides the `demo-media` branch and is linked, not embedded.

**Why a GIF and not a poster→MP4 player (the road not taken):** a committed `.mp4`
does render a pausable/scrubbable player at its `/blob/<branch>/x.mp4` page (the
`/raw/` form serves `application/octet-stream` and just downloads), so a
poster-image-linked-to-blob *looks* like a CI-automatable click-to-play. It shipped
briefly (#237) but **GitHub's blob-view video player doesn't work on the mobile site
or app**, so the poster led nowhere on mobile. Reverted to the inline GIF, which
renders everywhere including mobile. An inline `<video>` player only renders for
files on GitHub's browser-only attachment CDN, which CI can't reach. Full contract
lives in `demos/README.md`. See also [[reference-github-media-embedding]].

## Authoring & verifying demo scenarios (hard-won gotchas)

When hand-authoring a `demos/scenarios/*.json` replay (a `seed` + `orders` +
optional `camera` track) and verifying it locally:

- **The replay loader requires `version: 1` and `physics_tps: 60`.** Without both,
  `Replay.start_playback` returns false *silently* and `DemoRunner` falls back to a
  fresh random battle — so the clip records the wrong thing (units at spawn, no
  orders, default camera) with no error. Always include them (see `showcase.json`).
- **A HOLD order does NOT keep an enemy unit stationary.** The enemy AI
  (`Battle._run_enemy_ai`) sets `target_enemy` directly every `AI_PERIOD`, and
  `Unit._think`'s chase branch (`elif target_enemy != null`) fires regardless of
  `order_mode == HOLD` (HOLD only suppresses chasing a *detected* foe, not an
  explicitly-set target). So you can't stage a "held line" the player charges into;
  units meet in the middle. Design demos around the natural clash instead.
- **Camera playback steps between keyframes, then EMA-smooths** (`Battle.CAMERA_SMOOTHING`).
  For a smooth pan/zoom, emit *dense* eased keyframes (e.g. every ~3 ticks with a
  smoothstep), not sparse ones.
- **Record locally on macOS** with `GODOT_BIN` (`/Applications/Godot.app/Contents/MacOS/Godot`):
  `SPARTA_DEMO_REPLAY="res://demos/scenarios/X.json" $GODOT_BIN --rendering-driver opengl3
  --write-movie /tmp/d.avi --fixed-fps 60 --quit-after N res://tools/demo/DemoRunner.tscn`.
  Movie Maker works headless (no Xvfb needed on macOS).
- **Extract frames without ffmpeg:** the AVI is MJPEG in `00db` chunks. Walk the
  `movi` LIST sequentially (tag `00db` = JPEG frame, `01wb` = audio), reading each
  chunk's little-endian size; decode the JPEGs with PIL. A naive `FFD8..FFD9` scan
  over-counts (internal markers), so parse the chunks. Frame index == physics tick
  at `--fixed-fps 60`. This lets you verify a demo frame-by-frame before pushing.

Verify timing on paper first (unit speeds in `demos/README.md`), then confirm by
recording + extracting a few frames — don't trust a CI run to catch a mistimed
scenario.

## Release workflow — tag-gated publish, and the NSIS installer path

The `Release builds` workflow (`.github/workflows/release.yml`) builds on
`push: tags: v*` **and** on manual `workflow_dispatch`. A dispatch run builds
every artifact — including the NSIS installer step — and only the final
*publish to the GitHub Release* is tag-gated. So you can validate the installer
build without cutting a release; just don't expect a dispatch run to publish one.
A bug in the tag-only publish path, though, only surfaces when you actually tag.

- **The relative `OutFile` in `tools/installer/sparta.nsi` landed in the `.nsi`'s
  own directory (`tools/installer/`), not the workflow's working dir.** makensis
  ran from the repo root with the script path, yet the built installer wasn't in
  the repo root — a `mv "sparta-…setup.exe" build/` from there failed with
  *cannot stat*. (NSIS docs are muddy on whether a relative `OutFile` is cwd- or
  script-relative, and it varies — don't rely on either.) This was the first tag
  to run the installer step (added after v0.1.0). Fix pattern: make the path an
  overridable define (`!ifndef OUTFILE` / `!define OUTFILE …` / `!endif`) and pass
  an absolute `-DOUTFILE="$(pwd)/build/…"` from the workflow, matching how
  `EXE_PATH` is already absolute — then makensis writes straight into `build/`
  regardless.
- **The release workflow runs from the *tagged* tree.** Fixing `main` is not
  enough: re-point the tag at the fixed commit (`git tag -f -a v0.2.0 <sha>` +
  `git push origin v0.2.0 --force`) to re-trigger. Reusing a tag is fine when no
  release ever published under it.
- **A backgrounded `gh run watch … ; echo EXIT $?` exits 0 even when the run
  failed** — the wrapper's exit code is the `echo`'s, not the run's. Read the run
  `conclusion` explicitly afterward; don't trust the task's exit code.

## Local testing — repo targets Godot 4.7 (no more 4.6 dance)

As of PR #420 ("Upgrade engine target from Godot 4.6.x to Godot 4.7", merged
2026-06-30), Sparta **targets Godot 4.7** — `project.godot`'s `config/features`
is committed as `"4.7"` on `main`. Local machines run 4.7 too, so target and
binary match.

- **No more 4.6↔4.7 bump/restore.** The old workflow (bump `config/features`
  4.6→4.7 before a local run, then `git checkout project.godot` to restore 4.6)
  is **obsolete and now actively wrong** — restoring to 4.6 regresses the
  committed target. Run the suite directly; leave `project.godot` alone.
- **Getting the binary:** point `GODOT_BIN` at a 4.7 binary (the `_console`
  variant gives terminal output on Windows), e.g.
  `GODOT_BIN=<path> bash tools/check.sh validate test chars`, or run GUT
  straight: `<binary> --headless -s addons/gut/gut_cmdln.gd -gdir=res://test
  -ginclude_subdirs -gexit`.
- **The `test_settings.gd` doubler quirk** is the same GUT-on-4.7 issue
  described just below — if a lone `test_settings.gd` doubler parse error
  appears it's that known quirk, not a regression. Since the #420 upgrade the
  full suite has been observed passing every test, so don't assume that failure
  is still present, and don't pin an exact test total; the suite grows.

## GUT's doubler breaks on void-returning methods under Godot 4.7

`partial_double()`/`double()` can fail to parse under Godot 4.7 + GUT v9.7.0:
some generated wrapper methods still emit an invalid `return` for void-returning
or default-parameter methods, which 4.7's stricter return-type checking now
rejects ("A void function cannot return a value"). This is bitwes/Gut#816 — GUT
9.7.0's fix for the underlying Godot change doesn't cover every method shape.
Hit while migrating to 4.7 (#420): `test_settings.gd`'s one `partial_double()`
use on `Settings.gd` (which has several void methods and default-valued params)
failed this way. Fix: skip the doubler for the affected script — write a small
hand-rolled subclass that overrides just the method you need to spy on (GDScript
dispatches it virtually from the base class's own calls), e.g. a counter in an
overridden `_save()` instead of `assert_not_called`. Check before reaching for
GUT's doubler on any script with void or default-valued-param methods.

## Verify maneuvers/soldier bodies tick by tick, not by eyeballing GIFs

For maneuver/soldier-body work, **verify by stepping the simulation tick by tick
— in the real Battle scene — and asserting on actual body positions**, not by
watching demo GIFs/frames.

**Why:** during the quarter-turn (#371) work, demo GIFs at 50px blocks were
ambiguous and misleading. A headless GUT test that instantiates
`scenes/Battle.tscn` (set `Replay.forced_seed`), awaits `get_tree().physics_frame`
one tick at a time, and logs/asserts each unit's `_sim_soldier_pos` bbox +
per-tick max body step caught what frames couldn't: it proved the sim correct
(bbox constant, step ≤0.02px) and isolated the real problems to the **render**
(figure-LOD didn't show facing #399; spear/archer marks striped under rotation
#400) and a deferred **engage** behavior (#402). An isolated single-unit test
misses bugs that only appear under the full per-tick orchestration (steering +
couple + combat).

**How to apply:**
- Write a live-battle tick-by-tick test (see
  `test/unit/test_quarter_turn_battle.gd`) asserting no per-tick surge / no
  footprint drift / no reposition. Make it permanent — it's the regression guard.
- Treat demo GIFs as a *presentation* check only, never the correctness signal.
  A clean tick-by-tick test + a bad-looking GIF means the bug is in rendering,
  not the sim.

## Settings.gd setters persist to the REAL user://settings.cfg in tests

`Settings.gd`'s setter methods (`set_order_binding`, and the property setters
like `edge_scroll =`, `walk_advance =`, `form_up_dist_default =`) all call
`_save()` internally, which writes the **real** `user://settings.cfg` on whatever
machine runs the test — GUT tests are not sandboxed. A test that calls a setter
to trigger `Settings.changed` (e.g. to verify a UI element repaints on a live
rebind) persists that change to the developer's actual config, contaminating real
gameplay and every later test run until manually fixed.

**Why this matters:** caught on `test_shortcuts_overlay.gd` — a test called
`Settings.set_order_binding("skirmish", KEY_J)` to verify the overlay repaints;
this silently rewrote the `skirmish=` binding from the default (KEY_K) to KEY_J.
The editor and later playtests then loaded skirmish bound to J. Required manually
editing `settings.cfg` to restore.

**How to apply:**
- To trigger `Settings.changed` **without** the disk write, mutate the backing
  dict/property directly and emit by hand:
  `Settings.order_bindings["slug"] = KEY_X; Settings.changed.emit()` — NOT
  `Settings.set_order_binding(...)`. Mirrors the safe pattern in
  `test_selection_manager.gd` (`Settings.order_bindings["hold"] = KEY_Z`).
- After writing/reviewing a GUT test that touches `Settings`, grep the diff for
  any setter-method call (`Settings.set_*(`, or a property assignment like
  `Settings.walk_advance = ...`) and replace with direct mutation + manual
  `changed.emit()` when the test only needs the signal, not persistence.
- If contamination is suspected, check
  `C:\Users\<user>\AppData\Roaming\Godot\app_userdata\Sparta\settings.cfg`
  (Windows) for stale values and restore.

## MultiMesh instance transforms don't read back in headless tests

`MultiMesh.set_instance_transform_2d(i, t)` followed immediately by
`get_instance_transform_2d(i)` in a headless GUT test returns identity, not the
value just set — even for `Unit._mm_body`, whose write path is proven correct in
production. `instance_count` reads back fine; only the per-instance transform
buffer doesn't sync back to the CPU-side getter without a render/RenderingServer
sync point headless tests never reach.

**Why:** hit while adding a per-soldier facing-pip MultiMesh layer (#399). A
sanity check against the already-shipped `_mm_body` also read back identity,
confirming a general Godot/headless limitation, not a new-code bug. No existing
test asserts on `get_instance_transform_2d()`; they check `instance_count` and
`mesh` identity only.

**How to apply:** don't test by setting a MultiMesh instance transform and
reading it back. Extract the transform computation into a small pure `static
func` (plain values in, `Transform2D` out) and unit-test *that* — e.g.
`Unit._facing_pip_transform(prone, sf, pos) -> Transform2D`. This is also
better-factored code, so the fix pays for itself.

## Battle.gd merge: order-sentinel and same-name-local collisions

Two feature PRs that each extend `Battle.gd`'s order pipeline often introduce
**colliding additions** git merges without a textual conflict, but that are
semantically or syntactically broken. Watch for two specific collisions when
resolving a `Battle.gd` merge:

- **Order-sentinel constant collision.** Order types are encoded as negative
  sentinels in the `target` field (`ORDER_APPEND_WAYPOINT -2`,
  `ORDER_FORMATION_ONLY -3`, `ORDER_FRONTAGE_ONLY -4`, …). Two branches each grab
  the *next* free value independently — e.g. #469 added `ORDER_NUDGE := -5` and
  main's #474 added `ORDER_WHEEL := -5`. If both keep `-5`, the two
  `if target_uid == …` dispatch arms alias each other and one order silently runs
  the other's handler. **Fix:** keep main's value, renumber the incoming PR's
  sentinel to the next free slot (`ORDER_NUDGE := -6`), leave a matching comment.
  Run `grep -n "ORDER_" scripts/Battle.gd` after resolving to confirm every
  sentinel is unique.
- **Same-named local in one function.** Both dispatch arms landed in
  `_apply_order_cmd` and both declared `var dir`. GDScript scopes a `var` to the
  whole **function**, not the `if` block, so two `var dir` in one function is a
  redeclaration parse error even in separate `if`s. The textual merge stacks them
  with no conflict; validate catches it only at import. **Fix:** rename one
  (e.g. main's wheel arm to `var wheel_dir`).

**Verify the resolve with `tools/check.sh validate`** (Godot import) before
trusting the merge — a redeclaration or shadow surfaces only at parse time.
Learned resyncing #469 (arrow-key nudge) after main merged #474 (wheel).

## Routing units early-return in `_physics_process` — merge-isolated

In `scripts/Unit.gd`, `_physics_process` takes an **early return** for a routing
unit:

```gdscript
if state == State.ROUTING:
    _process_rout(delta)
    if state != State.DEAD:   # timer expired: rallied (IDLE) or shattered
        _separate()           # routers still shoulder past anyone in their path
    return
```

Routers run only `_process_rout` + `_separate` and skip the entire normal path:
`_think`, `_tick_intermixing`, morale/fatigue/cohesion ticks, and all the
movement/re-facing/formation logic below the return.

**Merge implication.** When resyncing the routing/rally branch (#460, #434)
against a `main` that landed new movement features — engage/attack re-facing
(#402/#476), file doubling (#373), anti-cav square (#487), shielded close order
(#485) — git auto-merged `Unit.gd`/`Battle.gd` cleanly, and the auto-merge was
**also semantically correct**: those features all live in the `_think`/movement
path routers never reach, so they can't interact with rout/rally state.

General rule: a state that early-returns from `_physics_process` (ROUTING, DEAD)
is isolated from any feature added to the normal think/movement path, so a clean
git auto-merge of the two branches is usually clean semantically too. Still run
the full suite (`tools/check.sh test`) to confirm — that's the real signal.

## `_check_victory` counts routers in play (last-unit rally)

`scripts/Battle.gd`'s victory check no longer counts only fightable units.
PR #495 (closes #493) replaced the `_team_units(0).size()` /
`_team_units(1).size()` counts in `_check_victory()` with a boolean helper:

```gdscript
func _team_in_play(team: int) -> bool:
    for group in ["units", "routers"]:
        for node in get_tree().get_nodes_in_group(group):
            var u = node as UnitRef
            if u != null and u.team == team:
                return true
    return false
```

`_check_victory()` ends the battle only when `not _team_in_play(0)` /
`not _team_in_play(1)`. A **routing** unit has left the `"units"` group for
`"routers"` (`Unit._rout()` → `add_to_group("routers")`) but is still on the
field and may rally, so it keeps its team **in play**. Before #495, losing the
last fightable unit ended the battle instantly and froze the router mid-rout.

- **The rally window is bounded**, so waiting on routers can't stall the outcome:
  each rout resolves (rally→IDLE or shatter→removed) within `ROUT_TIME`.
- **No AI change was needed.** The enemy AI advances on `_team_units(0)` (the
  `"units"` group only), so it already halts when the last player unit routs —
  don't add a separate "halt" hook.
- **Known gap, tracked in #504:** `_report_campaign_result()` still counts
  survivors with `_team_units(0).size()`, which EXCLUDES still-routing units.
  Pre-existing. If you touch campaign accuracy, reuse `_team_in_play` /
  union `"units"`+`"routers"` there too.

## Render-only cosmetic overlay pattern

When a PR is purely **"show an existing sim state on screen"** (e.g. #486: draw
shields for the SHIELD_WALL / TESTUDO `formation_mode` stances — the defensive
effects already existed, only the visual was missing), build it as a
**render-only overlay** so it never touches sim/combat/formation code and stays
conflict-free with the many in-flight PRs that DO touch that code.

**The pattern (mirrors `UnitSprites` / the emblem/flag chrome):**

1. **Pure geometry helper** in its own `class_name` script
   (`scripts/UnitShields.gd`). Static funcs taking plain shape inputs
   (frontage/ranks/spacing/mark_r) returning local-frame polygons — a function of
   block shape ONLY, nothing reads or writes the sim. Directly unit-testable and
   replay-safe. Keep block geometry consistent with the formation grid:
   half-width `= (files-1)/2 * spacing`, half-depth `= (ranks-1)/2 * spacing`,
   front rank toward **-Y** (local forward), files span X — same frame
   `UnitFormation.slots` / the emblem use.
2. **A `draw(u, body, dark, lite)` dispatcher** that switches on the state
   (`u.formation_mode`) and is a **no-op** for every other value.
3. **`Unit._draw` calls it** inside a `draw_set_transform(Vector2.ZERO,
   facing.angle() + PI*0.5, Vector2.ONE)` … reset sandwich, so the overlay
   **rotates with facing and scales with the block** for free. Size off the live
   formation shape (`UnitFormation.frontage` / `ranks_for`), not the bare
   `RADIUS`. Use the team-tinted `body_c/dark_c/lite_c` already computed in
   `_draw`.

**LOD decision — differs from the emblem.** The centre emblem hides at figure LOD
(`if not _detailed_lod`) because the per-soldier silhouettes carry the type. A
shield overlay does the OPPOSITE: draw it at BOTH mark and figure LOD, because
the raised/overhead shields are exactly what the individual figures don't show.
Put the overlay OUTSIDE the `if not _detailed_lod` guard and note why.

**Coverage gotcha.** The pure geometry helpers get covered by GUT tests, but the
draw-only `draw()` / `_draw_*` funcs don't — `codecov/patch` fails on them.
Calling `unit._draw()` directly from a test errors ("Drawing is only allowed
inside this node's `_draw()`"). Instead drive it the way the engine does: add the
unit to the tree, set the stance, `queue_redraw()`, and
`await get_tree().process_frame` twice — that runs `_draw` under the real draw
notification and covers the dispatch.

## `record-demos.sh` DEMOS conflicts are ADDITIVE — keep both rows

`website/tools/record-demos.sh` holds a `DEMOS=( ... )` bash array, one row per
demo clip. Every feature PR that adds a website demo appends a new row at the end.
When two such PRs land, git conflicts on the adjacent lines:

```
<<<<<<< HEAD
  "rout_rally|demos/inputs/rout-rally-recover.json|30|300|640|input"
=======
  "testudo_under_fire|demos/inputs/testudo-under-fire.json|30|300|640|input"
>>>>>>> origin/main
```

This is an **additive** conflict, not a genuine either/or. Resolve by keeping
**both** rows — each PR's demo should survive. Don't pick a side.

Distinct from the `demos/demo.json` conflict (below / CLAUDE.md), where you keep
only YOUR PR's version because that file names the single clip CI posts for the
PR in hand. `record-demos.sh` is the persistent website catalog, so both entries
stay.

## `website/tactics.qmd` same-mechanic conflicts are a DEDUP, not additive

`website/tactics.qmd` (and `how-to-play.qmd`) conflicts differ from the
`record-demos.sh` additive case above. When two PRs document the **same mechanic**
from different angles, git shows a big block conflict, but the right resolution is
a **semantic dedup**, not "keep both sides".

Concrete case (PR #495 last-unit-rally vs main's #460 rout-rally): both rewrote
the "Morale & routing" section and each added rally prose + a demo video.
Resolution that worked:

- **Intro paragraph** — keep the richer of the two, drop the thinner one.
- **Bullets** — keep the general-mechanic bullets ("A routing unit can rally" /
  "shatters instead"), DROP your own now-redundant duplicate of that same
  explanation, and KEEP only your PR's *unique* angle (the last-unit case: "the
  battle isn't over while a side is only routing").
- **Demo videos** — this IS additive: keep BOTH `<figure>` blocks (general
  mechanic first, then the specific case), each in its own ` ```{=html} ` fence.

Rule of thumb: two docs describing the same feature → merge into one coherent
narrative (general mechanic once, then each PR's distinct implication); two *media
embeds* → keep both. Read the merged section end-to-end afterward to confirm it
doesn't say the same thing twice. `&mdash;` in figcaptions is an HTML entity, so
it passes `tools/check.sh chars` (only literal curly quotes / en-em dashes fail).

## This repo runs sessions in `.claude/worktrees/` — edit the worktree path

A Sparta session's working dir is often a git **worktree**
(`…\sparta\.claude\worktrees\<name>`), separate from the main checkout
(`…\sparta`). A feature branch created in the worktree is checked out **there**,
while the main checkout stays on `main`.

**Hazard (easy to hit twice):** Read/Edit/Write using the *main-checkout*
absolute path (`…\sparta\scripts\…`) edits files on the `main` branch, NOT the
worktree's feature branch. Then tests run from the worktree silently see none of
the changes (a new test file isn't discovered; `git status` in the worktree is
clean while the main checkout shows the edits).

**How to apply:**
- Do **all** file operations on the **worktree path**
  (`…\.claude\worktrees\<name>\…`), matching where the branch is checked out.
  Bash cwd already resets to the worktree — keep tool paths consistent with it.
- If edits don't seem to take effect, run `git status --short` in **both** the
  worktree and the main checkout to find where they landed.
- To move stray edits from the main checkout onto the worktree branch:
  `git stash push -u` in the main checkout, then `git stash pop` in the worktree
  (the stash is shared via the common `.git`). `-u` includes untracked files.
- **`gh` commands are cwd-sensitive the same way.** Running `gh pr create` from
  the main checkout (on `main`) fails with `must be on a branch named differently
  than "main"`, even though the feature branch is pushed — `gh` reads the current
  directory's checked-out branch. Run `gh pr create` (and branch-scoped
  `git push`) from the **worktree** dir.

## GII / multi-session scope — unclaimed issues, own worktree only

GII (grab issues iteratively) means picking up **unclaimed** open issues — no
existing PR, no in-progress branch. Do NOT continue another session's in-progress
PRs as part of the GII loop; those belong to their own sessions.

- Before grabbing an issue, verify no open PR covers it (`gh pr list` and check
  `headRefName` / body for "Closes #N").
- If all remaining unclaimed issues are blocked or too large, surface that to the
  user rather than hijacking in-progress PRs.
- **Never use another session's worktree** (one you did not create in this
  session). Each session owns its worktrees. If a branch is already checked out in
  a different worktree, create a fresh worktree from the remote branch in a new
  location or ask the user. Editing files in another session's worktree or its
  main-repo checkout is off-limits.

(The concrete rules here are Sparta-multi-session-specific; the general
"check for a prior claim before starting" rule lives in ai-config.)

When the next AI session reviewing a PR cites a "CLAUDE.md rule" to justify a
requested change, check that the rule's exact wording actually appears in
*this repo's* `CLAUDE.md` — not just in the harness's own baseline style
defaults, which read similarly but aren't written into this file. PR #420's
reviewer cited "one short line max — never write multi-line comment blocks" as
a CLAUDE.md rule; it isn't in sparta's `CLAUDE.md`, and the codebase's own
convention (e.g. `Settings.gd`) wraps explanatory comments across 2-3 lines.
Rebutting with that distinction is fine — verify the citation, don't just comply.
