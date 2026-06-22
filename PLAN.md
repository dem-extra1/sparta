# Sparta — Project Plan & Handoff

> Self-contained record so any new session (cloud or local) can continue without prior chat context.
> Last updated: 2026-06-15.

## Vision
A game fusing **dynastic grand-strategy** campaign mechanics with **real-time
tactical battles**. Built solo by a developer **new to gamedev**, so the strategy is a
**vertical slice**: build the hardest/most-differentiating piece (a battle) first, get it playable,
then grow outward.

## Locked decisions
- **Engine:** Godot **4.6.x Standard build** (GDScript, *not* the C#/.NET build).
- **Battles:** 2D top-down sprite tokens (not 3D).
- **Art:** **CC0 only** — Kenney, OpenGameArt (Toen's Medieval Strategy pack). See `ASSETS.md`.
  - ⚠️ **Not** commercial-game mod assets — they are copyrighted, not public domain.
- **First milestone:** one self-contained tactical battle. No campaign map yet.

## Design pillars
1. **Collision is core — treat it as a first-class system, not polish.** In a large-scale tactical
   battle, where bodies are on the field *is* the game: units must physically occupy space,
   press against each other, hold formation, and be blocked by friend and foe. Flanking, screening
   spearmen, cavalry charges, and chokepoints are only meaningful if units cannot pass through or
   stack on one another. Every movement/combat feature is designed around this constraint, and
   collision correctness/perf takes priority over new feature breadth.
   - **Current state:** soft separation in `Unit.gd` → `_separate()` — each frame a unit pushes
     out of any overlapping unit (live or routing) by half the overlap (neighbor corrects the rest).
     Spacing is the center-to-center floor `RADIUS + other.RADIUS`. It is intentionally *soft* so
     regiments still press into melee contact (attack reach > separation floor) instead of bouncing apart.
   - **Roadmap (in priority order):**
     1. ✅ No-stack soft separation between live units.
     2. Per-type footprint (cavalry wider than infantry) so charges and screens read correctly.
     3. Formation cohesion: a regiment holds a block/line shape while moving, not a blob.
     4. Hard blocking interactions: spearmen screen and physically stop cavalry passage; lines
        form chokepoints. This is where collision and the rock-paper-scissors design meet.
     5. Scale: replace the O(n²) neighbor scan with a spatial grid (and/or move to Godot
        `CharacterBody2D`/`move_and_slide`) before unit counts grow past a few dozen.

## Prioritized roadmap (synced with GitHub issues)
Tracked as issues on `Lacaedemon/sparta` with `P0`–`P3` labels (a GitHub Project board groups them).
Order reflects dependencies — validate the foundation, then build the collision pillar, then the
features that depend on it, then independent polish.

- **P0 — Foundation (do first):**
  - #12 M1 first run & verification in Godot — nothing below is validated until this passes.
  - #13 Spacebar active pause — implemented in PR #2, pending live confirm.
- **P1 — Collision pillar (core, in dependency order):**
  - #6 Per-type footprint (`_separate()` currently uses the shared `RADIUS`; make it per-type).
  - #10 NavigationAgent2D pathfinding (decide path-vs-collision split here).
  - #9 Scale beyond O(n²) — pairs with #10.
  - #7 Formation cohesion (depends on #6).
  - #8 Hard blocking: spears stop cavalry (depends on solid collision + formations).
- **P2 — Features on the shared "collision-exemption" primitive (build it once in #5, reuse):**
  - #5 Friendly pass-through (simplest; establishes the primitive).
  - #4 Line relief (adds fatigue stat + handoff).
  - #3 Unit merging (stat blending + "strangers" debuff).
- **P3 — Independent polish:**
  - #11 Richer selection (double-click type-select, control groups).

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

## Added since scaffold
- **Reproducible replays** (`scripts/Replay.gd`): deterministic sim + order log
  (a genre-standard approach). Every battle auto-records to `user://replays/`; "Watch
  Replay" re-runs it. Made the sim deterministic (single seeded RNG via
  `Replay.rng`; AI + orders on the fixed physics tick). Verified end-to-end:
  a recorded battle replays bit-identically tick-for-tick. See `REPLAY.md`.

## Next milestones (not started)
- **M1 polish (optional, after first run is fun):**
  - Swap token `_draw()` for real CC0 `Sprite2D` art (see README "Swapping placeholder art").
  - Stretch: render each regiment as an N×M block of soldier sprites that thins with casualties
    (the true massed-formation look); unit facing arrows; pre-battle deployment phase.
- **M2 — dynastic campaign map:** clickable provinces, characters/realms, turn-based
  diplomacy & war. Battles **auto-resolved** at first (no tactical layer yet).
  - **Thin slice landed (#70):** a Gallic War map (`scenes/Campaign.tscn`) — Rome vs
    the Gallic tribes (plus the neutral Germanic tribes, see #123) over clickable
    polygon provinces. Turn-based: move/attack an army into an adjacent province,
    auto-resolved combat, a greedy enemy AI, and a conquest victory. Reached from a new
    `scenes/MainMenu.tscn` (now the main scene) that also launches the M1 battle. Logic
    lives in `scripts/campaign/` with the rules (`CampaignState.gd`) unit-tested
    headlessly.
  - **Maps are data-driven (#125):** campaigns load from JSON under `data/campaigns/`
    via `CampaignLoader.gd`; the menu lists them from `Campaigns.gd`. Adding a
    campaign is a JSON file + one registry row.
  - **Diplomacy (#123):** `CampaignState` tracks per-faction war/peace stances and
    gates province entry on being at war (you can only enter/attack a faction you're at
    war with). The Gallic War now ships a **neutral third faction** (the Germanic
    tribes, at peace with both belligerents — declared via the map's optional `peace`
    list) that the player can court (stay at peace, avoid a second front) or conquer
    (declare war). The HUD has a **diplomacy panel** to declare war / sue for peace per
    faction and surfaces current stances; the AI only attacks factions it's at war with.
    Total-conquest victory is unchanged, so finishing the war means eventually dealing
    with the neutral too. Remaining for #123: truce timers, AI-initiated diplomacy, and
    multi-sided wars beyond three factions (#138/#139/#140). Characters/dynasty (#124)
    and the saga layer (#126) also remain follow-ups.
- **M3 — Integration:** an army battle on the campaign map launches into the M1 battle scene
  and returns a result (winner, casualties) to the campaign. This is where the two genres meet;
  the battle scene was kept self-contained specifically to make this hand-off clean.
  - **Hand-off landed (#122):** a player attack on a **defended** enemy province now
    launches `scenes/Battle.tscn` instead of auto-resolving. Each side deploys units
    scaled to its campaign army strength (`CampaignBattle.units_for`), and on the battle's
    end the winner's surviving units scale back to campaign strength and are applied to the
    province via `CampaignState.resolve_attack` — the same state transition auto-resolve
    uses, so the two converge. The campaign state is snapshotted across the one-way scene
    swap (`CampaignState.snapshot`/`restore`, held in the `CampaignBattle` static) and the
    battle's end screen gains a **Return to Campaign** button. Auto-resolve stays available
    as a HUD **"quick resolve"** toggle, and **AI attacks always auto-resolve** (no nested
    scene changes during the enemy turn). Remaining: launching battles for AI-vs-AI or
    AI-vs-player clashes, and richer army composition from province/unit data.

## Feature backlog (design goals — captured early, not yet scheduled)
- **Unit merging — combine two units into one.** Player can merge two friendly units into a single
  regiment. Two intended uses:
  1. **Consolidation:** fold depleted units together after casualties so a thinned line becomes one
     viable regiment instead of several near-broken ones.
  2. **Formation locking:** deliberately bind units into a single wider, coordinated block that
     moves and fights as one (ties directly into the collision/formation pillar — a merged unit has
     a larger footprint and held shape).
  - **"Strangers" debuff:** merging forces soldiers from different regiments together, so the result
    starts with a penalty (e.g. reduced morale and/or attack/cohesion) representing unfamiliarity.
    Lean toward a *temporary* debuff that decays over time as the merged unit "gels," rather than a
    permanent tax — keeps merging worthwhile without making it free.
  - **Open design questions (decide when scheduled):**
    - Merged `max_soldiers` = sum, or capped at a regiment ceiling (excess lost/disbanded)?
    - Restrictions: same team only? same/compatible unit types only (can cavalry merge into
      infantry)? proximity required (must be adjacent)?
    - Reversible? Can a merged unit later split back into sub-units?
    - Stat blending: average attack/defense, weight by soldier count, or take the stronger?
    - Debuff shape: flat % for N seconds, or a "cohesion" stat that ramps from low to full.
  - **Code touch-points (current architecture):** `Unit.gd` (new merge method; `soldiers`/
    `max_soldiers`/`morale` blending; a cohesion/debuff timer alongside the existing state machine),
    `SelectionManager.gd` (a merge order/input), and the collision footprint (`RADIUS` in `_separate()`)
    for the wider merged body.

- **Line relief — cycle tired units out of combat.** A fresh unit can "relieve" an already-engaged
  friendly: the fresh unit moves into the front-line slot while the tired one peels back to the rear,
  letting the player rotate exhausted regiments out and rest them.
  - **Requires a new fatigue/stamina stat** (does not exist yet): accumulates while `FIGHTING`
    (faster when taking casualties), recovers while idle/out of contact. Fatigue should bite into
    combat performance (attack/defense/morale) so relief is a real tactical lever, not flavor.
  - **Smooth swap mechanism (the hard part):** choreograph the exchange so it reads well and isn't
    exploitable —
    - The relieving unit advances into the slot *as* the relieved unit withdraws; ideally the fresh
      unit arrives/screens before the tired one fully disengages so the enemy doesn't get a free
      gap to pour through.
    - The two units must **pass through each other** during the maneuver — directly exercises the
      collision pillar. Plan: temporarily exempt the swapping pair from mutual `_separate()` (and/or
      lane them past each other) until the swap completes, then re-enable.
    - Define the window: brief protected/"relieving" state vs. fully simulated handoff with risk.
  - **Open design questions:** relief only with adjacent/behind friendlies? same type only, or any?
    can a routing/near-broken unit be relieved (rescue) or only steady ones? does the incoming unit
    inherit the target enemy automatically? cooldown to prevent infinite fresh-unit churn?
  - **Code touch-points:** `Unit.gd` (fatigue stat + recovery; a `RELIEVING`/handoff sub-state in the
    state machine; per-pair collision exemption in `_separate()`), `SelectionManager.gd` (a relieve
    order targeting an engaged friendly), and AI in `Battle.gd` (so the enemy also rotates lines).

- **Move-through friendly units — coordinated pass-through.** Let one unit move *through* an idle
  friendly unit smoothly (ranks interleave / the idle unit parts and reforms) instead of colliding,
  shoving, or detouring around it. Ref: https://www.youtube.com/shorts/7VTVNe_C5No
  - Shares the **collision-exemption** mechanism with line relief: while a unit is passing through a
    designated friendly, suspend mutual `_separate()` between them (and/or lane them) so they
    interpenetrate cleanly, then re-enable once clear. The idle unit may shuffle aside and reform to
    sell the effect.
  - Distinct from line relief: here the mover keeps going (transit), it doesn't take over the
    friendly's slot. Relief, merging, and pass-through should likely share one underlying
    "soft-pass / collision-exemption" primitive.
  - **Open design questions:** automatic (any friendly in the path yields) vs. an explicit order?
    only through *idle* friendlies, or moving ones too? does an enemy nearby cancel the courtesy?
    how wide a corridor does the idle unit open?
  - **Code touch-points:** `Unit.gd` (`_separate()` per-pair exemption; a transit/pass-through
    flag), movement/path logic, and `SelectionManager.gd` if an explicit order is chosen.

## Pointers
- Tune unit stats / loadout in `Battle.gd` → `_spawn_line()` array.
- Collision spacing / soft-resolve logic in `Unit.gd` → `_separate()` (center-to-center floor =
  `RADIUS + other.RADIUS`). Tune spawn gaps via `spacing` in `Battle.gd` → `_spawn_line()`.
- Tune movement pace in `Battle.gd` → `SPEED_SCALE` constant (lower = slower).
- Combat math in `Unit.gd` → `_strike()` / `take_casualties()` / `_flank_multiplier()`.
- Active pause: `HUD.gd` → `_toggle_pause()` (Space); selection/camera stay live via `PROCESS_MODE_ALWAYS`.
- Enemy AI in `Battle.gd` → `_run_enemy_ai()` (currently: advance on nearest player unit).
