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
you **declare what to show**: commit a small **manifest** (`demos/demo.json`)
pointing at a **replay** that exercises it. If you don't, CI still posts a demo —
the default `showcase.json` battle, labelled as a generic build demo — but a
tailored one is far more useful, so prefer to add a manifest.

## The contract

Add a `demos/demo.json` on your PR branch:

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
| `replay` | yes | Repo-relative path to a replay JSON to play back — **no `res://` prefix** (the workflow adds it). See below. |
| `caption` | recommended | Explains the change; shown above the GIF. |
| `fixed_fps` | no (30) | Sim/record framerate Movie Maker runs at. |
| `max_frames` | no (300) | Recording length in frames (`300 / fixed_fps` ≈ seconds). |
| `fps` | no (12) | Output GIF framerate. |
| `width` | no (640) | Output GIF width in px (height auto). |
| `skip` | no (false) | Set `true` when the change **can't** be shown by a recorded battle (a paused-overlay interaction, an editor-only tool, a non-visual refactor). CI then records nothing and posts a short note instead of an unrelated clip. See [No clip applies](#no-clip-applies). |
| `reason` | no | Used only with `skip` — the explanation shown in the note (falls back to `caption`). |

`demo.example.json` is a copy-paste starting point. Any **other** keys are
ignored by the workflow (its `jq` only reads the fields above), so a leading
`"_comment"` note — as used in `demo.example.json` itself — is safe to include.

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
cost of a larger file). `demos/demo.json` here uses those values.

### Order markers (what was commanded)

During a demo recording the clip also draws the **player's orders** over the
field, so a viewer sees *what was commanded*, not only the resulting moves: a
green dashed path with a destination ring (plus dots for shift-waypoints) for a
move, and a red line with a crosshair for an attack. It's driven from the orders
already in the replay, so any scenario with player orders shows them
automatically — no manifest field to set. The overlay is recording-only: in-app
**Watch Replay** keeps orders on the hold-Space survey, unchanged. (Capturing the
live cursor and selection box is a tracked follow-up.)

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
field, so they start **400 px** apart vertically. Each unit's speed is stated in the
loadout in **metres/second**; effective px/s is `speed_mps × WORLD_UNITS_PER_METER`
(`20`) `× SPEED_SCALE` (`1.0`):

| Unit | speed (m/s) | effective px/s |
| --- | --- | --- |
| Spearmen | 2.2 | 44 |
| Infantry | 2.6 | 52 |
| Archers | 3.0 | 60 |
| Cavalry | 8.5 | 170 |

**Only team 1 advances on its own.** The enemy AI (`Battle.gd` →
`_run_enemy_ai()`) walks each idle enemy toward the nearest player unit. Team 0
units stay put until you order them, so a scenario that needs the player line to
engage **must** issue a move (or attack) order early — for example the tick-12
order in `demos/scenarios/line-relief.json` and `charge_demo.json`. Forget it and
the clip records the player line standing still while only the enemy closes.

With both sides closing over the 400 px gap, a head-on meet takes roughly
`400 / (sum of the two effective speeds)` seconds: about 4.5 s for
spearmen-vs-spearmen (`44 + 44`), about 1.2 s for cavalry-vs-cavalry (`170 + 170`).
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
- **A demo is always posted on those PRs.** With a `demos/demo.json`, it records the
  replay you named (tailored to your change). Without one, it falls back to the
  default `demos/showcase.json` battle, posted with an honest "generic build demo"
  caption that nudges you to add a manifest. So the manifest is how you make the
  demo *demonstrate your change* — skipping it gives a generic clip, not nothing.
- **Unless you opt out.** A `demos/demo.json` with `"skip": true` posts a short note
  instead of a clip — see below.

## No clip applies

Some user-visible changes genuinely can't be shown by the recorded-battle pipeline:
a **paused-overlay** interaction (e.g. previewing a queued waypoint while the sim is
paused), an **editor-only** tool, or a change that's visible only through input the
replay format doesn't capture. In those cases a generic showcase clip is worse than
nothing — it shows an unrelated battle and implies it's a demo of your change (see
issue #75).

To say so, commit a `demos/demo.json` that opts out:

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
are off by default in-game, so the recorder turns them on for the recording (see
[`../tools/demo/DemoRunner.gd`](../tools/demo/DemoRunner.gd)) — that's how the MP4
ends up with the battle's sound.

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
