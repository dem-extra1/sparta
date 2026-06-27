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

## Demo media in PRs — poster still linked to the MP4 *blob* URL

The demo workflow posts the PR clip as a **static poster frame linked to the MP4**,
not an autoplaying GIF (#236 / #237). The link target matters: GitHub serves a
committed `.mp4` differently by URL form —

- **`/blob/<branch>/x.mp4`** renders GitHub's React media viewer — a pausable,
  scrubbable `<video>` player (with sound). This is the click target.
- **`/raw/<branch>/x.mp4`** serves `Content-Type: application/octet-stream` with
  `nosniff`, so the browser **downloads** it instead of playing — a dead click
  target. (The raw form is still right for *embedding the poster image*, which is a
  PNG.)

An inline `<video>` player only renders for files on GitHub's browser-only
attachment CDN, which CI can't reach — so poster-image-links-to-blob is the
CI-automatable click-to-play. A silent autoplaying GIF remains the fallback when the
MP4 encode fails. Full contract lives in `demos/README.md`.
