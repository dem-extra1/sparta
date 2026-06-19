# Art assets

The game runs **without any downloaded art** — units draw as placeholder tokens in
`Unit.gd`. When you want real medieval art, use genuinely free **CC0** sources below.

> 📓 For the broader **running catalog** of audio + graphics sources (including
> reference-only libraries we can't bundle), see
> [`docs/asset-sources.md`](docs/asset-sources.md).

> ⚠️ **Do not use Total War mod assets.** They are *not* public domain — modders retain
> copyright and many derive from copyrighted base-game art. Shipping them is legally risky.
> The sources below are CC0 (public-domain equivalent): free for any use, no attribution
> required (crediting is still polite — see the table).

## Recommended CC0 packs

| Pack | Use for | License | Link |
| --- | --- | --- | --- |
| Toen's Medieval Strategy Sprite Pack (16×16) | Soldiers, cavalry, siege, banners | CC0 | https://opengameart.org/content/toens-medieval-strategy-sprite-pack-v10-16x16 |
| Kenney — game assets | UI buttons, panels, fonts, tiles | CC0 | https://kenney.nl/assets |
| OpenGameArt — CC0 collection | Terrain, grass/dirt tiles, props | CC0 | https://opengameart.org/art-search-advanced?keys=&field_art_licenses_tid%5B%5D=4 |

## How to add them
1. Download a pack and unzip it.
2. Drop the PNGs into `assets/sprites/` (units) or `assets/ui/` (interface).
3. Godot auto-imports them when the editor regains focus.
4. Wire a `Sprite2D` into `Unit.gd._ready()` (see README "Swapping placeholder art").

## Credits
CC0 requires no attribution, but list anything you use here as good practice:

- _(none yet — placeholder primitives only)_
