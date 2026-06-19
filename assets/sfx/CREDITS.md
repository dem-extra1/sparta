# Sound-effect credits & licensing

All bundled sound effects are **CC0 1.0 (public domain)** — free to use, modify,
and redistribute in personal, educational, and commercial projects, with no
attribution required. They were created and distributed by **Kenney**
(<https://kenney.nl>). We credit Kenney here anyway (encouraged, not mandatory).

CC0 1.0: <https://creativecommons.org/publicdomain/zero/1.0/>

Each clip is the unmodified original file from a Kenney pack, renamed to the
event name that `scripts/Sfx.gd` looks up (see `README.md`).

| Event (file)   | Source pack                | Original file in pack                | Duration | Licence |
| -------------- | -------------------------- | ------------------------------------ | -------- | ------- |
| `hit.ogg`      | Kenney Impact Sounds (1.0) | `Audio/impactMetal_light_002.ogg`    | 0.24 s   | CC0 1.0 |
| `shoot.ogg`    | Kenney RPG Audio           | `Audio/knifeSlice.ogg`               | 0.60 s   | CC0 1.0 |
| `rout.ogg`     | Kenney Interface Sounds (1.0) | `Audio/back_003.ogg`              | 0.09 s   | CC0 1.0 |
| `death.ogg`    | Kenney Impact Sounds (1.0) | `Audio/impactSoft_heavy_001.ogg`     | 0.57 s   | CC0 1.0 |
| `select.ogg`   | Kenney Interface Sounds (1.0) | `Audio/select_001.ogg`            | 0.04 s   | CC0 1.0 |
| `order.ogg`    | Kenney Interface Sounds (1.0) | `Audio/confirmation_001.ogg`      | 0.29 s   | CC0 1.0 |
| `victory.ogg`  | Kenney Music Jingles       | `Audio/Steel jingles/jingles_STEEL00.ogg` | 0.93 s | CC0 1.0 |
| `defeat.ogg`   | Kenney Music Jingles       | `Audio/Hit jingles/jingles_HIT00.ogg` | 0.28 s | CC0 1.0 |

## Source packs

- **Interface Sounds** (1.0) — <https://kenney.nl/assets/interface-sounds>
- **Impact Sounds** (1.0) — <https://kenney.nl/assets/impact-sounds>
- **RPG Audio** — <https://kenney.nl/assets/rpg-audio>
- **Music Jingles** — <https://kenney.nl/assets/music-jingles>

Each downloaded pack ships its own `License.txt` confirming CC0; the relevant
line is *"License: (Creative Commons Zero, CC0)"*.

## Choosing / swapping clips

The mappings above are best-effort matches picked by description (the combat and
UI cues map cleanly; `rout`, `victory`, and `defeat` are more a matter of taste).
To swap any of them, drop a replacement `assets/sfx/<event>.{ogg,wav}` and re-run
the Godot import — no code change needed. Record the new source + licence here.

Only commit audio you can legally redistribute — prefer CC0. Do **not** copy
mixed-licence collections wholesale (e.g. R's `beepr` bundles Nintendo and
Wilhelm-scream sounds we can't ship).
