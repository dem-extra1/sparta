# Sound-effect credits & licensing

All bundled sound effects are **CC0 1.0 (public domain)** — free to use, modify,
and redistribute in personal, educational, and commercial projects, with no
attribution required. Every clip was sourced from **[OpenGameArt](https://opengameart.org)**.
We credit each author here anyway (encouraged, not mandatory).

CC0 1.0: <https://creativecommons.org/publicdomain/zero/1.0/>

Each clip is taken from the submission below, renamed to the event name that
`scripts/Sfx.gd` looks up (see `README.md`).

| Event (file)  | Source submission                         | Author                  | Original file       | Duration | Licence |
| ------------- | ----------------------------------------- | ----------------------- | ------------------- | -------- | ------- |
| `hit.wav`     | Thwack Sounds                             | AntumDeluge (J. Irwin)  | `thwack-02.wav`     | 0.21 s   | CC0 1.0 |
| `shoot.wav`   | Swishes Sound Pack                        | artisticdude            | `swish-1.wav`       | 0.13 s   | CC0 1.0 |
| `rout.wav`    | Swishes Sound Pack                        | artisticdude            | `swish-9.wav`       | 0.20 s   | CC0 1.0 |
| `death.ogg`   | 20 Sword Sound Effects (Attacks & Clashes)| StarNinjas              | `sword_clash.10.ogg`| 0.85 s   | CC0 1.0 |
| `select.wav`  | 7 Assorted Sound Effects (Menu, Level Up) | Joth                    | `Menu Move.mp3`     | 0.62 s   | CC0 1.0 |
| `order.wav`   | 7 Assorted Sound Effects (Menu, Level Up) | Joth                    | `Menu Confirm.mp3`  | 0.62 s   | CC0 1.0 |
| `victory.wav` | 8-bit sound FX                            | Dizzy Crow              | `VictorySmall.wav`  | 1.52 s   | CC0 1.0 |
| `defeat.ogg`  | Game Over Trumpet SFX                     | 0new4y                  | `losetrumpet.ogg`   | 1.11 s   | CC0 1.0 |

## Source submissions

Each OpenGameArt submission page confirms CC0 on its licence line:

- **Thwack Sounds** — <https://opengameart.org/content/thwack-sounds>
- **Swishes Sound Pack** — <https://opengameart.org/content/swishes-sound-pack>
- **20 Sword Sound Effects (Attacks and Clashes)** —
  <https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes>
- **7 Assorted Sound Effects (Menu, Level Up)** —
  <https://opengameart.org/content/7-assorted-sound-effects-menu-level-up>
- **8-bit sound FX** — <https://opengameart.org/content/8-bit-sound-fx>
- **Game Over Trumpet SFX** — <https://opengameart.org/content/game-over-trumpet-sfx>

## Modifications

CC0 imposes no obligation to note changes, but for clarity:

- `death.ogg` and `defeat.ogg` are the **unmodified** original files, only renamed
  to the event name.
- `hit`, `shoot`, `rout`, `select`, `order`, and `victory` were **downmixed to mono
  and resampled to 22 050 Hz / 16-bit PCM WAV** (matching the engine's `MIX_RATE`)
  with macOS `afconvert`. The two Joth UI sounds were additionally **transcoded
  from MP3 → WAV**, since `scripts/Sfx.gd` only loads `.wav`/`.ogg`.

## Choosing / swapping clips

The combat and UI cues map cleanly; `rout`, `victory`, and `defeat` are more a
matter of taste (`death` reuses a sword **clash** as a decisive killing blow;
`rout` reuses a heavier **swish** as a line-breaks-and-flees whoosh). To swap any
of them, drop a replacement `assets/sfx/<event>.{ogg,wav}` and re-run the Godot
import — no code change needed. Record the new source + licence here.

Only commit audio you can legally redistribute — prefer CC0. Do **not** copy
mixed-licence collections wholesale, and verify each submission's licence line
individually (OpenGameArt hosts CC0, CC-BY, GPL, and others side by side).
