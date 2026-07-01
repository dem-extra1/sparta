# Gameplay demos in PRs

When a PR makes a **user-visible change** (anything affecting how the game looks
or plays), a short clip is posted so reviewers can *see* the change, not just read
the diff.
[`.github/workflows/demo-video.yml`](../.github/workflows/demo-video.yml) plays a
replay back headlessly (Godot Movie Maker → ffmpeg) and posts it as an inline GIF
that **plays once** (it freezes on the final frame instead of looping) in the PR
conversation — plus a link to an **MP4 with sound** (the GIF is silent; see
[Sound](#sound) below). An inline GIF is used rather than a poster-linked MP4
because GitHub's blob-view video player doesn't work on the mobile site or app,
while a GIF renders inline everywhere.

CI can't infer what a diff changed, so to make the clip *demonstrate your change*
you **declare what to show**: commit a small **manifest** pointing at a **replay**
that exercises it. If you don't, CI still posts a demo — the default
`showcase.json` battle, labelled as a generic build demo — but a tailored one is
far more useful, so prefer to add a manifest.

## The contract

Add a manifest on your PR branch, named **`demos/demo.<slug>.json`** — `<slug>`
is your issue or PR number (e.g. `demos/demo.371.json`). Each PR's manifest gets
its own unique filename, so two PRs in flight never conflict editing the same
file (the older shared `demos/demo.json` pointer still works as a fallback, but
a uniquely-named manifest is preferred for exactly this reason — see
[Resolution order](#resolution-order)):

```json
{
  "replay": "demos/showcase.json",
  "caption": "What this PR changes and what to watch for in the clip.",
  "fixed_fps": 30,
  "max_frames": 300,
  "fps": 12,
  "width": 640
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `input` | preferred | Repo-relative path to a **scripted-input** demo (`demos/inputs/*.json`) — **no `res://` prefix**. Recorded live through the real controls. The standard way to author a demo; see [Scripted-input demos](#scripted-input-demos). Wins over `replay` when both are present. |
| `replay` | alt | Repo-relative path to a saved replay JSON to play back — **no `res://` prefix**. The older path; prefer `input`. See [Getting a replay](#getting-a-replay-that-shows-your-change). |
| `caption` | recommended | Explains the change; shown above the GIF. |
| `fixed_fps` | no (30) | Sim/record framerate Movie Maker runs at. |
| `max_frames` | no (300) | Recording length in frames (`300 / fixed_fps` ≈ seconds). |
| `fps` | no (12) | Output GIF framerate. |
| `width` | no (640) | Output GIF width in px (height auto). |
| `skip` | no (false) | Set `true` when the change **can't** be shown by a recorded battle (a paused-overlay interaction, an editor-only tool, a non-visual refactor). CI then records nothing and posts a short note instead of an unrelated clip. See [No clip applies](#no-clip-applies). |
| `reason` | no | Used only with `skip` — the explanation shown in the note (falls back to `caption`). |

`demo.example.json` is a copy-paste starting point — copy it to
`demos/demo.<slug>.json` rather than `demos/demo.json`. Any **other** keys are
ignored by the workflow (its `jq` only reads the fields above), so a leading
`"_comment"` note — as used in `demo.example.json` itself — is safe to include.

### Resolution order

CI's "Resolve demo source" step picks the most specific manifest available:

1. A **per-PR manifest** (`demos/demo.*.json`, e.g. `demos/demo.371.json`) that
   was **added** in your PR's diff against the base branch. Preferred — see above.
2. The legacy shared `demos/demo.json`, if present. Still works, but every PR
   that uses it is editing the same file, so two such PRs in flight will conflict
   on merge (`demos/demo.json` is a perennial source of merge conflicts for
   exactly this reason — prefer the per-PR filename to avoid it).
3. The default `showcase.json` battle (generic, honestly labelled).

If your PR adds more than one `demos/demo.*.json` file, CI warns and picks the
first alphabetically — stick to one manifest per PR.

## Scripted-input demos

**The standard way to author a demo.** Instead of a recorded or hand-authored
replay, write a deterministic **input script** — a list of mouse clicks/drags and
keystrokes stamped with the physics tick they fire on. The recorder
(`tools/demo/DemoInputRecorder.gd`) drives a live battle by injecting those as real
`InputEvent`s through the same `SelectionManager` code a player's mouse drives, while
Movie Maker records. So the clip is produced by the actual controls (a demo doubles
as an input smoke test), and the script is editable text you can tune without replaying
the game.

Point your `demos/demo.<slug>.json` at it with the `input` field, and put the
script under `demos/inputs/`:

```json
{
  "seed": "12345",
  "camera": [ { "tick": 0, "x": 510.0, "y": 380.0, "zoom": 1.9 } ],
  "steps": [
    { "tick": 8,  "click": [500, 300] },
    { "tick": 24, "rmb_drag": { "from": [620, 460], "to": [385, 460] } }
  ]
}
```

- `seed` — the battle seed (string). Use `"12345"` for the documented standard 5v5
  layout (the unit table below); spawn **positions** are seed-independent, so clicks
  land regardless — the seed only fixes combat RNG for reproducibility.
- `camera` (optional) — a list of keyframes `{tick,x,y,zoom}` (world coordinates), sorted
  by tick. The recorder interpolates position and zoom linearly between them, so the clip
  pans and zooms over time; outside the track's range it holds the first / last frame. A
  single keyframe just statically frames the whole clip. Omit for the default whole-field
  camera. (`demos/inputs/camera-zoom.json` shows a multi-keyframe pan-and-zoom.)
- `steps` — each stamped with a `tick` (physics ticks, 60/s). Coordinates are world-space:
  - `click [x,y]` / `shift_click [x,y]` / `rmb_click [x,y]` — a press+release at a point.
  - `box { "from": [x,y], "to": [x,y] }` — a left-drag box-select.
  - `rmb_drag { "from": [x,y], "to": [x,y], "shift": false }` — a right-drag (move / form-up;
    `shift` toggles the form-up ordering variant). Drags animate over a few ticks so the
    live preview renders.
  - `key "Y"` — a gameplay hotkey press (formation cycle, order stance, etc.).

The standard 5v5 (`seed "12345"`) unit positions are in [Hand-authoring a scenario](#hand-authoring-a-scenario)
below — clicks target those world coordinates.

## Getting a replay that shows your change

Replays are the project's deterministic seed-plus-orders logs (see
[`../REPLAY.md`](../REPLAY.md)). Two ways to produce one:

1. **Play it.** Run the game, play a battle that demonstrates your change, then
   grab the saved file from `user://replays/` (on Linux:
   `~/.local/share/godot/app_userdata/sparta/replays/`) and commit it under
   `demos/`. Point `replay` at it. This is how you show *specific tactics* (a
   flank charge, a rout, a new ability).
2. **Seed-only.** For changes visible in any battle (unit art, HUD, balance),
   `demos/showcase.json` is a ready-made deterministic auto-battle (seed `12345`,
   no orders). Copy it and change the seed if you want a different battle.

A replay only reproduces on the **same build**, which is exactly the point here —
CI replays it against *your PR's* build, so the clip reflects your change.

### Camera moves (presentation track)

A replay also records the **camera** — pan and zoom over time — as a presentation
track alongside the orders (see [`../REPLAY.md`](../REPLAY.md)). When CI records the
clip it drives the camera from that track, so a recorded session **pans and zooms
exactly as it was played**. This is how to show a change that only appears at a
non-default camera — e.g. the zoomed-in soldier figures: record a battle while you
zoom into the clash, and the clip zooms in too. `demos/camera-showcase.json` is a
ready-made example (an auto-battle that zooms into the melee and back out).

A demo can also **open already zoomed in or panned** — the clip starts on the
track's first keyframe (the recorder snaps to it before the first frame), so you
don't have to begin every demo on the wide default view.

The track is cosmetic and additive: a replay with no camera track (every older
recording, and hand-authored scenarios) plays with the default static camera, so
nothing here changes existing demos.

**Raise the framerate for a moving camera.** The defaults (`fixed_fps` 30, GIF
`fps` 12) are tuned for static-camera battle demos, where only the units move
slowly. A panning/zooming camera looks choppy at 12 fps, so for a camera-motion
demo bump the manifest — e.g. `"fixed_fps": 60, "max_frames": 600, "fps": 30` —
to record at the full physics-tick rate and output a smooth 30 fps GIF (at the
cost of a larger file). The manifest here uses those values.

### Order markers (what was commanded)

During a demo recording the clip also draws the **player's orders** over the
field, so a viewer sees *what was commanded*, not only the resulting moves: a
green dashed path with a destination ring (plus dots for shift-waypoints) for a
move, and a red line with a crosshair for an attack. It's driven from the orders
already in the replay, so any scenario with player orders shows them
automatically — no manifest field to set. The overlay is recording-only: in-app
**Watch Replay** keeps orders on the hold-Space survey, unchanged.

The clip also replays the player's **mouse**, captured into the replay's `pointer`
track (see `REPLAY.md`): the cursor reticle, yellow selection halos on the selected
regiments, the multi-select drag-box, a pulse ringing out where each order is issued,
and a label + tint on the cursor when a stance is armed. It's captured live while a
battle is recorded -- same as the orders and camera -- so playing and saving a replay
records your real mouse for free (`demos/scenarios/pointer-demo.json` is one such
recording). Replays without a pointer track simply show no cursor overlay.

The clip also flashes the **keyboard hotkeys** you pressed, captured into the replay's
`keys` track: each gameplay hotkey (stances, `T` formation, `[`/`]` line width, merge,
control groups) pops up as a labelled chip by the cursor and fades over ~0.7 s, so a
keyboard-driven change reads on screen rather than happening invisibly
(`demos/scenarios/resizable-widths.json` is one such recording). Like the pointer track
it's captured live and back-compatible -- replays without a keys track show no chips.

## Hand-authoring a scenario

You can also write a replay JSON by hand — a **scenario** — to stage a specific
clash deterministically, rather than recording one by playing. The files under
`demos/scenarios/` (and `charge_demo.json`, `support_demo.json`, `clash.json`)
are built this way. A scenario is an ordinary replay file (see
[`../REPLAY.md`](../REPLAY.md) for the schema): a `seed` plus a list of `orders`,
each stamped with the physics `tick` it fires on.

To get the timing right you need the default battle's layout. A standard 5v5
(seed `"12345"`, no campaign) spawns these units, by `uid`:

| Unit | Team 0 (player, top, `y=300`) | Team 1 (enemy, bottom, `y=700`) |
| --- | --- | --- |
| Spearmen | 0 | 5 |
| Infantry | 1 | 6 |
| Archers | 2 | 7 |
| Cavalry | 3 | 8 |
| Cavalry | 4 | 9 |

Both lines center on `start_x = 500` with `spacing = 150` px on the `1600 × 1000`
field, so they start **400 px** apart vertically. Each unit's sprint speed is stated
in the loadout in **metres/second** (`sprint_mps`); effective px/s is
`sprint_mps × WORLD_UNITS_PER_METER` (`20`) `× SPEED_SCALE` (`1.0`):

| Unit | sprint speed (m/s) | effective px/s |
| --- | --- | --- |
| Spearmen | 2.8 | 56 |
| Infantry | 4.0 | 80 |
| Archers | 4.5 | 90 |
| Cavalry | 8.5 | 170 |

**Only team 1 advances on its own.** The enemy AI (`Battle.gd` →
`_run_enemy_ai()`) walks each idle enemy toward the nearest player unit. Team 0
units stay put until you order them, so a scenario that needs the player line to
engage **must** issue a move (or attack) order early — for example the tick-12
order in `demos/scenarios/line-relief.json` and `charge_demo.json`. Forget it and
the clip records the player line standing still while only the enemy closes.

With both sides closing over the 400 px gap, a head-on meet takes roughly
`400 / (sum of the two effective speeds)` seconds: about 3.6 s for
spearmen-vs-spearmen (`56 + 56`), about 1.2 s for cavalry-vs-cavalry (`170 + 170`).
These are approximations — the enemy AI re-targets only every `AI_PERIOD` (1 s),
and cavalry carry a 0.3 s order-response delay — so work the timing out on paper
**before** spending a CI run on it; a mistimed scenario silently records the
wrong moment.

Note that `max_frames` counts **output video frames at `fixed_fps`**, not physics
ticks: at the default 30 fps, 480 frames ≈ 16 s and 600 ≈ 20 s.

## When it runs

- On any same-repo PR that touches `scenes/`, `scripts/`, `assets/`, or
  `project.godot` (a "user-visible change"). Docs/CI/test-only PRs don't trigger it.
  Fork PRs are excluded because CI needs write access to push the clip to the
  `demo-media` branch.
- **A demo is always posted on those PRs.** With a manifest (`demos/demo.<slug>.json`
  or the legacy `demos/demo.json`), it records the replay you named (tailored to
  your change). Without one, it falls back to the default `demos/showcase.json`
  battle, posted with an honest "generic build demo" caption that nudges you to
  add a manifest. So the manifest is how you make the demo *demonstrate your
  change* — skipping it gives a generic clip, not nothing.
- **Unless you opt out.** A manifest with `"skip": true` posts a short note
  instead of a clip — see below.

## No clip applies

Some user-visible changes genuinely can't be shown by the recorded-battle pipeline:
a **paused-overlay** interaction (e.g. previewing a queued waypoint while the sim is
paused), an **editor-only** tool, or a change that's visible only through input the
replay format doesn't capture. In those cases a generic showcase clip is worse than
nothing — it shows an unrelated battle and implies it's a demo of your change (see
issue #75).

To say so, commit a `demos/demo.<slug>.json` that opts out:

```json
{
  "skip": true,
  "reason": "Previews a queued waypoint in the paused Space overlay — a paused-overlay interaction the recorded-battle pipeline can't capture."
}
```

CI records nothing and upserts the demo comment with an honest note (`🚫 No gameplay
clip for this PR — <reason>`) rather than a misleading GIF. Only use this when the
change really can't be filmed — for anything visible in a normal battle, a tailored
replay (or `showcase.json`) is far better.

## Still images for static features

A recorded battle is the right tool for *motion* — a charge, a rout, an ability
firing. For **static** changes a single labelled frame is clearer: a new
**interface/menu/HUD**, **new or improved art**, a layout or visual-polish change.
For those, post informative **image(s) in the PR description** (the body), in
addition to a clip when motion also matters — a reviewer then judges the change at a
glance without opening media.

### Producing the PNG

- **Battle-visible art** (units, HUD, effects): record as usual with the launcher
  command from [Trying the launcher locally](#trying-the-launcher-locally), then pull
  a single frame out of the AVI:

  ```sh
  ffmpeg -ss 5 -i /tmp/demo.avi -frames:v 1 demos/shots/your-change.png
  ```

  `-ss 5` grabs the frame ~5s in; pick a moment that shows your change.

- **A new menu/HUD/screen** the replay-driven battle doesn't reach: run that scene
  under Xvfb and save a viewport screenshot from a short throwaway script — after the
  frame draws, call

  ```gdscript
  get_viewport().get_texture().get_image().save_png("res://demos/shots/your-change.png")
  ```

  Crop or scale with ffmpeg or an image tool afterwards if needed.

### Posting it

Commit the PNG under `demos/shots/` on your PR branch (create the dir if needed),
then embed it in the **PR description** by raw URL with a caption:

```md
![New roster panel](https://github.com/lacaedemon/sparta/raw/<commit-sha>/demos/shots/roster-panel.png)
```

Use the **commit SHA** (immutable) so the image keeps rendering after the branch is
deleted on merge — a branch-name URL works while the PR is open but breaks once the
branch is gone. The PNG is committed in-repo, so it's permanent in `main` after merge.

This is independent of the `demos/demo.json` manifest: the manifest drives the CI
gameplay **clip** (posted as a comment), while these images live in the PR **body**
and you add them yourself. For a static UI a battle can't film, combine them — opt
the clip out with `"skip": true` (see [No clip applies](#no-clip-applies)) and post a
still in the description instead.

## Where the GIF lives

The GIF (and the MP4 — see [Sound](#sound)) is pushed to a long-lived
**`demo-media`** branch and embedded/linked by raw URL. This deliberately avoids
committing to your PR's own branch: it never disturbs the PR's required status
checks, and the clip keeps working after the PR branch is deleted on merge. The
comment is updated in place on each push (no spam), and the filename carries the
commit SHA so GitHub never shows a stale cached frame.

## Sound

The inline preview is a GIF (it plays once and freezes on the final frame), and
**GIF can't carry audio** — so the clip you see in the comment is silent. The
workflow also encodes an **MP4 with sound** (Godot's Movie Maker captures the game's
audio into the recording; the GIF step just drops it) and links it under the GIF as
*"watch with sound"*. Click it to play the clip with audio, pause, and scrub. SFX
are off by default in-game, so whichever recorder runs turns them on for the recording
([`../tools/demo/DemoInputRecorder.gd`](../tools/demo/DemoInputRecorder.gd) for scripted
input, [`../tools/demo/DemoRunner.gd`](../tools/demo/DemoRunner.gd) for a replay) — that's
how the MP4 ends up with the battle's sound.

Why a GIF plus a link, and not an inline player: GitHub renders an inline, playable
`<video>` **only** for files uploaded through its browser-only attachment CDN
(`user-attachments` / `user-images.githubusercontent.com`), which needs a logged-in
session and is unreachable from CI. A `<video>` tag or bare link pointing at our
`demo-media` raw URL renders as a dead/greyed player or a download. Linking the
poster to the MP4's blob page (so a click opens GitHub's file-view player) works on
desktop but **not on mobile** — the blob-view video player doesn't play there — so
an inline GIF (which renders everywhere, including mobile) plus a click-to-play MP4
link is the honest best CI can post. The
recorder force-enables SFX, so the MP4 is silent only if no sound events happen to
fire during the recorded battle.

## Trying the launcher locally

```sh
godot --headless --import        # once, to import the project
SPARTA_DEMO_REPLAY="res://demos/showcase.json" \
  xvfb-run -a godot --rendering-driver opengl3 \
  --write-movie /tmp/demo.avi --fixed-fps 30 --quit-after 300 \
  res://tools/demo/DemoRunner.tscn
# Silent, play-once GIF (inline preview; -loop -1 = no infinite loop):
ffmpeg -i /tmp/demo.avi -vf "fps=12,scale=640:-1:flags=lanczos" -loop -1 /tmp/demo.gif
# MP4 with sound (the AVI already holds the audio track):
ffmpeg -i /tmp/demo.avi -vf "scale=640:-2:flags=lanczos" \
  -c:v libx264 -pix_fmt yuv420p -profile:v high -movflags +faststart -c:a aac -b:a 128k /tmp/demo.mp4
```

[`../tools/demo/DemoRunner.gd`](../tools/demo/DemoRunner.gd) is the headless entry
point: it arms replay playback from `SPARTA_DEMO_REPLAY`, then switches to the
battle scene while Movie Maker records. It's tooling only — it changes no
simulation code.
