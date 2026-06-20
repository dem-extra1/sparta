# Gameplay demos in PRs

When a Claude session makes a **user-visible change** (anything affecting how the
game looks or plays), a short clip is posted in the PR so reviewers can *see* the
change, not just read the diff.
[`.github/workflows/demo-video.yml`](../.github/workflows/demo-video.yml) plays a
replay back headlessly (Godot Movie Maker → ffmpeg) and posts it as an inline,
autoplaying GIF in the PR conversation — plus a link to an **MP4 with sound**
(the GIF is silent; see [Sound](#sound) below).

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

## When it runs

- On PRs from `claude/*` branches that touch `scenes/`, `scripts/`, `assets/`, or
  `project.godot` (a "user-visible change"). Docs/CI/test-only PRs don't trigger it.
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

## Where the GIF lives

The GIF (and the MP4 — see [Sound](#sound)) is pushed to a long-lived
**`demo-media`** branch and embedded/linked by raw URL. This deliberately avoids
committing to your PR's own branch: it never disturbs the PR's required status
checks, and the clip keeps working after the PR branch is deleted on merge. The
comment is updated in place on each push (no spam), and the filename carries the
commit SHA so GitHub never shows a stale cached frame.

## Sound

The inline preview is a GIF, and **GIF can't carry audio** — so the clip you see
autoplaying in the comment is silent. The workflow also encodes an **MP4 with
sound** (Godot's Movie Maker captures the game's audio into the recording; the GIF
step just drops it) and links it under the GIF as *"watch with sound"*. Click it to
play the clip with audio. SFX are off by default in-game, so the recorder turns
them on for the recording (see [`../tools/demo/DemoRunner.gd`](../tools/demo/DemoRunner.gd))
— that's how the MP4 ends up with the battle's sound.

Why a link and not an inline player: GitHub renders an inline, playable `<video>`
**only** for files uploaded through its browser-only attachment CDN
(`user-attachments` / `user-images.githubusercontent.com`), which needs a logged-in
session and is unreachable from CI. A `<video>` tag or bare link pointing at our
`demo-media` raw URL renders as a dead/greyed player or a download, not an
autoplaying clip — so a click-to-play link is the honest best CI can post. The
recorder force-enables SFX, so the MP4 is silent only if no sound events happen to
fire during the recorded battle.

## Trying the launcher locally

```sh
godot --headless --import        # once, to import the project
SPARTA_DEMO_REPLAY="res://demos/showcase.json" \
  xvfb-run -a godot --rendering-driver opengl3 \
  --write-movie /tmp/demo.avi --fixed-fps 30 --quit-after 300 \
  res://tools/demo/DemoRunner.tscn
# Silent GIF (inline preview):
ffmpeg -i /tmp/demo.avi -vf "fps=12,scale=640:-1:flags=lanczos" /tmp/demo.gif
# MP4 with sound (the AVI already holds the audio track):
ffmpeg -i /tmp/demo.avi -vf "scale=640:-2:flags=lanczos" \
  -c:v libx264 -pix_fmt yuv420p -profile:v high -movflags +faststart -c:a aac -b:a 128k /tmp/demo.mp4
```

[`../tools/demo/DemoRunner.gd`](../tools/demo/DemoRunner.gd) is the headless entry
point: it arms replay playback from `SPARTA_DEMO_REPLAY`, then switches to the
battle scene while Movie Maker records. It's tooling only — it changes no
simulation code.
