# Sound effects

The game ships **curated open-access (CC0) audio** for every event, sourced from
[OpenGameArt](https://opengameart.org) — see [`CREDITS.md`](CREDITS.md) for the
per-file source and licence. The `Sfx` autoload (`scripts/Sfx.gd`) loads these files at
startup. The procedural synthesiser in `Sfx` remains as an automatic **fallback**:
if an event ever has no bundled file, its placeholder is synthesised at runtime
instead, so the game is never silent.

## Dropping in / swapping audio

`Sfx` prefers a real file over its synthesised placeholder. To add or replace a
sound, drop an audio file in this directory named after the event:

```
assets/sfx/<event>.wav      # or .ogg
```

Recognised events: `hit`, `shoot`, `rout`, `death`, `select`, `order`,
`victory`, `defeat`.

If `assets/sfx/hit.ogg` (or `.wav`) exists, it is used instead of the synth — no
code change needed. Keep clips short (well under a second for combat/UI sounds).

Godot imports audio on first load, generating a committed `<file>.import` sidecar
(see `hit.wav.import`). After dropping a new file, run the editor — or
`godot --headless --import` — so the sidecar is created; CI imports automatically.

## Licensing

Only commit audio you can legally redistribute — prefer **CC0** (public domain)
sources such as [freesound.org](https://freesound.org) (CC0 filter),
[OpenGameArt](https://opengameart.org) (CC0), or [Kenney](https://kenney.nl).
Do **not** copy mixed-licence collections wholesale (e.g. R's `beepr` bundles
Nintendo and Wilhelm-scream sounds that we can't ship). Record the source +
licence of each file in [`CREDITS.md`](CREDITS.md) when you add it.
