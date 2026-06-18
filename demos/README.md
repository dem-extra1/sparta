# Gameplay demos in PRs

When a Claude session makes a **user-visible change** (anything affecting how the
game looks or plays), a short clip is posted in the PR so reviewers can *see* the
change, not just read the diff.
[`.github/workflows/demo-video.yml`](../.github/workflows/demo-video.yml) plays a
replay back headlessly (Godot Movie Maker → ffmpeg → GIF) and posts it as an
inline, autoplaying GIF in the PR conversation.

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

`demo.example.json` is a copy-paste starting point.

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

## Where the GIF lives

The GIF is pushed to a long-lived **`demo-media`** branch and embedded by raw URL.
This deliberately avoids committing to your PR's own branch: it never disturbs the
PR's required status checks, and the clip keeps working after the PR branch is
deleted on merge. The comment is updated in place on each push (no spam), and the
filename carries the commit SHA so GitHub never shows a stale cached frame.

> Inline autoplaying previews in comments are GIFs by necessity — true `<video>`
> players require GitHub's browser-only attachment upload, which CI can't reach.

## Trying the launcher locally

```sh
godot --headless --import        # once, to import the project
SPARTA_DEMO_REPLAY="res://demos/showcase.json" \
  xvfb-run -a godot --rendering-driver opengl3 \
  --write-movie /tmp/demo.avi --fixed-fps 30 --quit-after 300 \
  res://tools/demo/DemoRunner.tscn
ffmpeg -i /tmp/demo.avi -vf "fps=12,scale=640:-1:flags=lanczos" /tmp/demo.gif
```

[`../tools/demo/DemoRunner.gd`](../tools/demo/DemoRunner.gd) is the headless entry
point: it arms replay playback from `SPARTA_DEMO_REPLAY`, then switches to the
battle scene while Movie Maker records. It's tooling only — it changes no
simulation code.
