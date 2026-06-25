# Sparta documentation site

The source for Sparta's [Quarto](https://quarto.org/) website, published to GitHub
Pages at **<https://lacaedemon.github.io/sparta/>**.

It's pure-markdown Quarto — every page is a plain `.qmd`, so building it needs only
the Quarto CLI (no R, no Python). Templated on
[UCD-SERG/qwt](https://github.com/UCD-SERG/qwt), trimmed to the website essentials.

## Build & preview locally

```bash
cd website
quarto preview      # live-reloading local server
quarto render       # one-shot build into website/_site
```

The pages re-present content whose source of truth lives in the repo root
(`README.md`, `PLAN.md`, `REPLAY.md`, `ASSETS.md`, `docs/`). Each page links back to
its source — keep them in sync when the originals change.

## Demo clips

The `<video>` embeds point at `media/showcase.mp4` and `media/clash.mp4` (with
`.jpg` posters). These are **not committed** — they're recorded fresh at deploy time
by [`.github/workflows/publish-site.yml`](../.github/workflows/publish-site.yml),
which runs:

```bash
website/tools/record-demos.sh website/media
```

That plays deterministic replays back headlessly via Godot's Movie Maker and encodes
them with ffmpeg (the same pipeline as `demo-video.yml`). To record them locally you
need a Godot 4.6 binary and ffmpeg:

```bash
# macOS example:
GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot" \
  website/tools/record-demos.sh website/media
quarto preview      # now the clips show locally
```

If the clips are absent (e.g. a plain local render), the `<video>` elements simply
show their poster / fallback text — the site still builds fine.

To feature a **specific tactic** (a flank charge, a rout), play that battle in-game,
copy the saved replay from `user://replays/` into `demos/`, and add a row to the
`DEMOS` list in `website/tools/record-demos.sh`.

## Deployment

Pushing to `main` (touching `website/**` or game code) triggers `publish-site.yml`.
Its `demos` job records the clips and uploads them as an artifact; its `publish`
job calls the shared reusable workflow
[`d-morrison/gha/.github/workflows/quarto-publish.yml@v2`](https://github.com/d-morrison/gha),
which pulls that artifact into `website/media`, renders the Quarto project, and
deploys to the `gh-pages` branch. The render/deploy logic lives in `gha` (reused
across SERG Quarto repos), not hand-rolled here.

**One-time repo setup:** Settings → Pages → *Build and deployment* → Source =
**Deploy from a branch**, branch `gh-pages` / `(root)`.
