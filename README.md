# Sparta

A prototype that fuses grand strategy with real-time tactical battles. 
Built in **Godot 4.6** with GDScript.

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

### Replays
Every battle is recorded automatically (`● REC`, top-center). When it ends, hit
**Watch Replay** to re-run it (`▶ REPLAY`), or **Load Replay** (top-right, also
on the end screen) to pick any earlier saved battle. Logs are tiny deterministic
seed-plus-orders files in `user://replays/` — the same approach Total War uses —
so they're handy for both re-watching battles and debugging. See
[REPLAY.md](REPLAY.md).

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
  Battle.gd            Spawns armies, enemy AI, win/lose check, tick clock + replay orders
  Replay.gd            Deterministic record/playback (autoload): seeded RNG + order log
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

## Cloud development (Claude Code on the web)

The repo works well with Claude Code's cloud environment for editing GDScript and managing Git, with a few things to know:

**No setup needed for code editing.** The environment requires no environment variables and no build step — just open a session and start editing.

**Running Godot headlessly is possible** but requires installing it in the setup script. Add this to your environment's setup script (use Godot 4.6.x, or whatever version matches the project):

```bash
wget -q https://github.com/godotengine/godot/releases/download/4.6-stable/Godot_v4.6-stable_linux.x86_64.zip -O /tmp/godot.zip
mkdir -p "$HOME/.local/bin/"
unzip -q /tmp/godot.zip -d "$HOME/.local/bin/"
mv "$HOME/.local/bin/Godot_v4.6-stable_linux.x86_64" "$HOME/.local/bin/godot"
chmod +x "$HOME/.local/bin/godot"
rm /tmp/godot.zip
export PATH="$HOME/.local/bin:$PATH"
```

Once installed, `godot --headless` can run exports or a GDScript test suite (e.g. [GUT](https://github.com/bitwes/Gut)). This project does not currently have a test suite configured.

> **Note:** The snippet above targets Godot 4.6 to match the project. If the engine version changes, update both the download URL and the binary filename.

**To actually play the game**, pull the branch locally and open it in the Godot 4.6 desktop editor — the cloud environment has no display.

## Roadmap
- **M1 (here):** one playable tactical battle. ✅ scaffolded
- **M2:** campaign map — provinces, characters, turn-based diplomacy; battles auto-resolved.
- **M3:** integration — armies on the map launch into this battle scene and return a result.

## License

The **code** is licensed under the [MIT License](LICENSE).

**Bundled assets are licensed separately.** MIT covers the source code, *not* the
third-party art and audio under `assets/`, which each keep their own licence
(CC0 or CC-BY). See [`assets/sfx/CREDITS.md`](assets/sfx/CREDITS.md) for audio and
[`ASSETS.md`](ASSETS.md) for graphics. The project bundles only assets that permit
redistribution — never `NC`/`ND` or no-redistribution stock content.
