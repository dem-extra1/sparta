# Sparta

A prototype that fuses **Crusader Kings 3**-style grand strategy with **Total War**-style
real-time tactical battles. Built in **Godot 4.6** with GDScript.

This repo currently contains **Milestone 1: a single, self-contained tactical battle** —
the hardest and most differentiating piece, built first as a vertical slice. The campaign
map and the integration between the two layers come in later milestones (see the project plan).

## Run it

1. Install **Godot 4.6.x — Standard build** (not the .NET/C# build) from
   <https://godotengine.org/download/windows/>.
2. Open Godot, click **Import**, and select this folder's `project.godot`.
3. Press **F5** (Play). The battle starts immediately — no art download required;
   units render as colored placeholder tokens.

## How to play

| Action | Control |
| --- | --- |
| Select a unit | Left-click |
| Select multiple | Left-click and drag a box |
| Move / attack | Right-click ground (move) or an enemy (attack) |
| Pan camera | `WASD` / arrow keys / screen edges |
| Zoom | Mouse wheel |

You command the **blue** army (top). Defeat the **red** army (bottom).

### Tactics that matter
- **Flanking:** hitting a unit from the side (×1.5) or rear (×2) deals far more damage
  and morale loss. Maneuver behind the enemy line.
- **Morale & routing:** units that lose enough soldiers or take flank hits will **rout**
  (flee, shown faded) and stop counting toward the battle. Routs spread to nearby allies.
- **Rock-paper-scissors:** **Cavalry** are fast and get a charge bonus, but **Spearmen**
  (with the spear marker) blunt that charge. Use cavalry to flank, spears to screen.
- **Disengaging:** right-click ground (a move order) to pull a unit *out* of melee —
  handy for retreating a battered regiment or redeploying cavalry to a new flank.
  It's risky: while marching away the unit shows its back, so the enemy it left gets
  free rear hits (×2) until it's clear. Stop the unit and it re-engages anything nearby.

## Project layout

```
project.godot          Godot project config (main scene = scenes/Battle.tscn)
scenes/Battle.tscn     Main scene: camera + units container + selection + HUD
scripts/
  Battle.gd            Spawns armies, enemy AI, win/lose check
  Unit.gd              Regiment: stats, movement, melee, flanking, morale, routing
  SelectionManager.gd  Click + drag-box selection, move/attack orders
  CameraController.gd  WASD / edge pan, wheel zoom
  HUD.gd               Hint bar, unit info panel, victory/defeat overlay
assets/                CC0 art goes here (see ASSETS.md) — not required to run
```

## Swapping placeholder art for real sprites
Units currently draw themselves in `Unit.gd`'s `_draw()`. To use real CC0 art, add a
`Sprite2D` child in `Unit.gd._ready()` pointing at a texture in `assets/sprites/`, and
remove the token-drawing lines from `_draw()` (keep the strength bar / selection ring).
See [ASSETS.md](ASSETS.md) for where to get CC0 medieval sprites.

## Roadmap
- **M1 (here):** one playable tactical battle. ✅ scaffolded
- **M2:** CK3-style campaign map — provinces, characters, turn-based diplomacy; battles auto-resolved.
- **M3:** integration — armies on the map launch into this battle scene and return a result.
