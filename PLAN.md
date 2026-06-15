# Sparta — Project Plan & Handoff

> Self-contained record so any new session (cloud or local) can continue without prior chat context.
> Last updated: 2026-06-14.

## Vision
A game fusing **Crusader Kings 3** grand-strategy campaign mechanics with **Total War**-style
real-time tactical battles. Built solo by a developer **new to gamedev**, so the strategy is a
**vertical slice**: build the hardest/most-differentiating piece (a battle) first, get it playable,
then grow outward.

## Locked decisions
- **Engine:** Godot **4.6.x Standard build** (GDScript, *not* the C#/.NET build).
- **Battles:** 2D top-down sprite tokens (not 3D).
- **Art:** **CC0 only** — Kenney, OpenGameArt (Toen's Medieval Strategy pack). See `ASSETS.md`.
  - ⚠️ **Not** Total War mod assets — they are copyrighted, not public domain.
- **First milestone:** one self-contained tactical battle. No campaign map yet.

## Current status — Milestone 1: SCAFFOLDED, not yet run in Godot
All code written and committed to the repo. Runs with **zero downloaded art** (units are
self-drawn colored tokens). **Not yet opened in the Godot editor**, so no live playtest has
happened — first run is the immediate next step (see Verification).

### What exists
```
project.godot          Config; main scene = scenes/Battle.tscn
scenes/Battle.tscn     Wires Camera2D + Units container + SelectionManager + HUD
scripts/
  Battle.gd            Spawns two 5-unit armies, enemy AI, win/lose check
  Unit.gd              Regiment: stats, movement, melee w/ flanking, morale, routing, _draw visuals
  SelectionManager.gd  LMB click + drag-box select; RMB move/attack orders
  CameraController.gd  WASD/arrow/edge pan, mouse-wheel zoom
  HUD.gd               Hint bar, selected-unit info panel, victory/defeat overlay (built in code)
assets/sprites, assets/ui   Empty (.gitkeep) — CC0 art drops here later
README.md, ASSETS.md   Run instructions + CC0 asset sourcing
```

### Implemented systems (all 10 from the original plan)
1. Project bootstrap (config, main scene). 2. Unit scene/stats + state machine
(IDLE→MOVING→FIGHTING→ROUTING/DEAD). 3. Straight-line movement. 4. Click + drag-box selection,
order issuing. 5. Melee combat with **flanking** (×1.5 side / ×2 rear). 6. **Morale & routing**
(contagious to nearby allies). 7. Win condition (a team with no fighting units loses).
8. HUD (info panel + end overlay). 9. Camera pan/zoom. 10. Polish: unit types
(infantry / anti-cavalry spearmen / cavalry with charge bonus = rock-paper-scissors) + grass field.

**Deliberate deviation from original plan:** UI is built in code in `HUD.gd` instead of separate
`.tscn` files, and Units are instantiated in code (`Unit.new()` in `Battle.gd`) instead of a
`Unit.tscn`. Simpler, fewer scene files to corrupt. Functionally equivalent.

## Verification (do this FIRST in the new session)
Godot was **not installed** in the authoring environment, so only static checks passed
(consistent tab indentation, references resolve, Godot 4.6 API reviewed). Live run still needed.

1. Install Godot 4.6.x Standard: <https://godotengine.org/download/windows/>
   (or headless check: `godot --headless --path . --quit` to catch parse/load errors).
2. Open the folder in Godot → **F5**. Expect two armies (blue top, red bottom) on a green field.
3. Left-click a unit → info panel fills. Drag a box → multi-select friendlies.
4. Right-click an enemy → selected units advance and fight; strength bars drop.
5. Flank/rear-attack an enemy → it takes extra damage and routs faster.
6. Eliminate one side → Victory/Defeat overlay + "Fight Again" restart.
7. Camera: WASD/edge pans, wheel zooms.

If any script error appears on first run, fix it before building further — this is expected for
hand-authored GDScript that hasn't been engine-checked.

## Next milestones (not started)
- **M1 polish (optional, after first run is fun):**
  - Swap token `_draw()` for real CC0 `Sprite2D` art (see README "Swapping placeholder art").
  - Stretch: render each regiment as an N×M block of soldier sprites that thins with casualties
    (the true Total War look); unit facing arrows; pre-battle deployment phase.
- **M2 — CK3-style campaign map:** clickable provinces, characters/realms, turn-based
  diplomacy & war. Battles **auto-resolved** at first (no tactical layer yet).
- **M3 — Integration:** an army battle on the campaign map launches into the M1 battle scene
  and returns a result (winner, casualties) to the campaign. This is where the two genres meet;
  the battle scene was kept self-contained specifically to make this hand-off clean.

## Pointers
- Tune unit stats in `Battle.gd` → `_spawn_line()` `loadout` array.
- Combat math in `Unit.gd` → `_strike()` / `take_casualties()` / `_flank_multiplier()`.
- Enemy AI in `Battle.gd` → `_run_enemy_ai()` (currently: advance on nearest player unit).
