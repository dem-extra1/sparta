# Sound effects

The game's sound effects are **procedural placeholders** synthesised at runtime
by the `Sfx` autoload (`scripts/Sfx.gd`) — no audio files are bundled, because
the CI/dev sandbox can't fetch external assets.

## Dropping in real (open-access) audio

`Sfx` prefers a real file over its synthesised placeholder. To upgrade a sound,
drop an audio file in this directory named after the event:

```
assets/sfx/<event>.wav      # or .ogg
```

Recognised events: `hit`, `shoot`, `rout`, `death`, `select`, `order`,
`victory`, `defeat`.

If `assets/sfx/hit.wav` exists, it is used instead of the synth — no code change
needed. Keep clips short (well under a second for combat/UI sounds).

## Licensing

Only commit audio you can legally redistribute — prefer **CC0** (public domain)
sources such as [freesound.org](https://freesound.org) (CC0 filter),
[OpenGameArt](https://opengameart.org) (CC0), or [Kenney](https://kenney.nl).
Do **not** copy mixed-licence collections wholesale (e.g. R's `beepr` bundles
Nintendo and Wilhelm-scream sounds that we can't ship). Note the source + licence
of each file when you add it.

Tracked in the "improve sound effects" follow-up issue.
