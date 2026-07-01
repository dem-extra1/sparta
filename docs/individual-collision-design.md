# Design note: individual-level collision

Status: **phases 1-4 landed; engaged melee is now soldier-authoritative** (behind
`Unit.INDIVIDUAL_COLLISION`, ON). Soldiers are seeded as world-space bodies from their
formation slots, separated across regiments on a soldier-sized `SoldierSpatialHash`, and
the flock render follows those positions. Phase 4 wired the per-soldier combat model
(`combat-model.md`) into live melee: `UnitCombat.strike` routes engaged, non-ranged
combat to `SoldierMelee.resolve`, which resolves the opposed land contest and wound
against per-soldier health, reaps the dead, and drives `unit.soldiers` — so casualties,
morale, rout, and the HUD now read soldier deaths for the engaged-melee case. Knockback,
prone, depth bracing, and stamina are wired (#201 slices A-D); friendly soldier collision
is soldier-level (phase 5 slice 1).

**Still regiment-level (the remaining authority work):** ranged casualties (decrement
`soldiers` and trim arbitrary rear bodies, not arrow-targeted), morale (a regiment scalar,
not derived from soldier state), and **enemy** soldier-vs-soldier collision + retiring the
regiment circle — the last is deferred to **#201** (stopping a charge needs momentum/mass;
see the phase-5 note below and #296). Posture/graded bracing and the rearward domino
cascade are also deferred. The design decisions are settled (see "Decisions" below).

Tracks [#164](https://github.com/Lacaedemon/sparta/issues/164) (collision at the
individual level, not the unit level) and
[#192](https://github.com/Lacaedemon/sparta/issues/192) (individuals occupy space
and don't overlap). It's the groundwork for the physics model in
[#201](https://github.com/Lacaedemon/sparta/issues/201), which layers metric
units, mass, and knock-back *on top of* individual bodies — so individual
collision has to land first.

This is the project's **#1 design pillar** (see [`PLAN.md`](../PLAN.md)), and
changing it touches the determinism guarantees that make replays work. So it gets
a design pass before code.

## Where collision is today

The simulation collides **regiments, not soldiers**. Each `Unit` is one circular
body and `_separate()` (`scripts/Unit.gd`) resolves regiment-vs-regiment overlap:

- A unit is a circle of `RADIUS = 18`. The *separation floor* is per-type —
  `SEPARATION_RADIUS_INFANTRY = 18`, `SPEARMEN = 20`, `CAVALRY = 24`, capped at
  `SEPARATION_RADIUS_MAX = 28` — kept below melee reach so lines press into
  contact instead of bouncing apart.
- Each frame a unit pushes out of any overlapping unit by a `_push_share` of the
  penetration: `0.5` for a normal pair (each corrects half), but `0`/`1` for a
  spear screen vs. cavalry so horses can't ride through (the existing hard-block).
- Neighbours come from `SpatialHash` (`CELL_SIZE = 128`), rebuilt once per tick,
  replacing the old O(n²) scan. A co-located pair fans apart along a **uid-keyed**
  angle so the push is deterministic across a run and its replay.

Individual soldiers already exist, but **only as decoration**. `_soldier_pos` /
`_soldier_vel` (the "flock marks", `MARK_RADIUS = 1.7`, `CAV_MARK_RADIUS = 2.6`,
`FORMATION_SPACING = 3.4`) are a cosmetic layer — the file says plainly they are
"never read by the sim". PR #202 added per-mark separation *in the renderer*; it
has no gameplay effect. So "individuals don't overlap" is true on screen and false
in the model.

## What #164 changes

Promote soldiers from drawn marks to **simulated bodies**: the thing that occupies
space, blocks movement, and fights becomes the individual, and the regiment
becomes a controller that issues formation slots and orders to its soldiers rather
than a single colliding circle.

The hard constraints any design must keep:

1. **Determinism / replay.** [`Replay.gd`](../scripts/Replay.gd) re-runs the real
   simulation from a seed plus an order log; it records no per-frame state. Every
   new per-soldier interaction must be order-stable and seed-driven, exactly like
   the current uid-keyed push. That means each soldier needs a **stable id**
   (e.g. `unit.uid * MAX_SOLDIERS + index`) to key tie-breaks and iteration order,
   and any randomness must draw from `Replay.rng` in a fixed order.
2. **Scale.** `max_soldiers` defaults to **120**. A few dozen regiments is then
   **thousands** of bodies, not dozens — the separation pass goes from ~10²
   to ~10⁴ entities. The `SpatialHash` is the right tool but needs a soldier-sized
   cell and a per-soldier rebuild, and the per-frame cost has to be budgeted
   against the fixed 60 Hz tick. The engaged/unengaged level-of-detail below is
   what keeps the expensive pass bounded (~1,500 bodies, not ~5,000).
3. **Soft vs. hard semantics carry down.** The `_push_share` screen logic and the
   melee-intermixing softening are regiment-level today; the individual model has
   to reproduce "a spear line stops a charge" and "melee lines interpenetrate a
   little" out of soldier-level rules, not lose them.

## A phased plan

Each phase is independently shippable and testable (the GUT suite exercises the
sim logic headless — no rendering needed), so collision correctness can be
verified before the next phase builds on it.

1. **[DONE] Promote marks to bodies, behind a flag.** Each soldier has a stable id
   (`soldier_id` = `uid * SOLDIER_ID_STRIDE + index`) and a world-space simulated
   position (`_sim_soldier_pos`) seeded from its formation slot (`seed_sim_soldiers`).
   The regiment circle stays authoritative; the soldier layer runs in parallel and
   the containment invariant is pinned in `test_soldier_bodies.gd`.
2. **[DONE] Soldier-level separation, engaged tier, within AND across regiments.**
   `_separate()`'s penetration/`_push_share` math is carried down to soldiers via the
   shared `_soldier_pair_push` helper (so the spear-vs-cavalry hard block falls out
   for free) and run for *engaged* soldiers only (front `ENGAGED_RANKS`, with linger
   hysteresis). One global, deterministic pass (`Unit.separate_engaged_global`,
   orchestrated by `Battle` on `physics_frame`) gathers engaged soldiers across all
   regiments in soldier-id order, buckets them in the soldier-sized
   `SoldierSpatialHash`, and applies a Jacobi accumulate-then-apply step — so enemy
   front ranks press into each other. (A debug overlay made the layer visible at this
   stage; phase 3 replaced it with the real soldier render.)
   **Superseded (#270):** this position-correction separation pass has since been
   retired. Soldiers never teleport — friendly crowding is handled by a velocity-based
   avoidance pass (`SoldierSteering`, written into each body's feed-forward) and enemy
   contact by combat **knockback**, so spacing emerges from steering + press-vs-recoil
   rather than a per-tick position snap.
3. **[DONE] Render-as-reality.** The flock render (`_update_flock`) now follows
   `_sim_soldier_pos`: each mark's target gains the simulated body's collision push
   (~0 for the unengaged bulk, the real per-soldier separation for engaged front
   ranks), so the on-screen soldiers reflect the collision while keeping all the
   flock polish (formation, combat lunge, rank-cycling, relief corridor, colour). The
   debug overlay is retired. The visual is subtle until the soldiers gain persistent
   body dynamics / per-soldier combat (the next phase) — today the sim re-seeds from
   formation each tick, so the soldiers hold formation and deform at contact rather
   than wandering as free bodies.
4. **Persistent bodies + combat at the individual level.** Give soldiers persistent
   dynamics — they arrive at their slots while separating (bounded "arrive" steering
   instead of the current per-tick re-seed), so cohesion is emergent and soldiers can
   be displaced and hold the displacement. Then melee and missiles resolve against
   soldiers, so flanking and screening fall out of geometry. This is the first
   gameplay change (it **unblocks #240**, the sustained spear-vs-sword standoff) and
   where the rock-paper-scissors design meets per-soldier collision. The per-soldier
   combat resolution for this phase — the opposed attack/defence rolls, health and
   stamina, knockback, prone, and the bracing chain — is specified in
   [`combat-model.md`](combat-model.md). This phase ships in slices. **Phase 4a
   [DONE]** lands two non-authoritative foundations: (i) the combat math (per-type
   profile, charge term, facing gate, opposed land contest, and wound) as pure,
   unit-tested functions on `Unit`, and (ii) **persistent soldier-body dynamics** —
   the engaged front-rank bodies arrive at their slots under bounded force and integrate
   their own velocity (`step_sim_soldiers`), so a body knocked back in melee holds the
   displacement and returns instead of re-seeding onto formation each tick (the
   unengaged bulk feeds the unit's march velocity forward, tracking its slots at
   velocity with no teleport — #270). The regiment circle still resolves
   casualties, exactly as phase 1 added the soldier-body state before later phases
   read it. **Phase 4b** wires the contest and wound into the live melee against a
   per-soldier health pool that accumulates on these persistent bodies (the first
   gameplay change; unblocks #240). A later slice (#270) retired the separation pass
   and added **knockback** as the enemy collision response; remaining slices add
   stamina, posture, and the prone/domino chain.
5. **Retire the regiment circle (in progress, shipping in slices).** Make soldiers
   authoritative for occupying space, so `RADIUS`-based `_separate()` becomes
   derived/diagnostic, then `#201`'s physics (mass, momentum, knock-back) layers on the
   soldier bodies.
   - **Slice 1 [DONE] — friendly collision.** A soldier->regiment **coupling** slides each
     regiment's center toward its soldiers' centroid at a bounded velocity, never a snap
     (`SoldierBodies.couple` / `Unit.couple_all_sim_soldiers`, run as the last soldier
     sub-step in `Battle._on_soldier_tick`). Because the formation slots are centred, the
     drift is ~0 during a clean march, so the coupling is silent except when bodies are
     pushed off formation. `SoldierSteering` gained a **friendly-contact tier**
     (regiment-broadphase-gated) that steers overlapping friendlies apart even when neither
     is fighting, carrying the move-through-idle / relief exemptions and the engaged-anchor
     asymmetry down from `_separate`. `_separate()` now **skips friendly pairs** — the
     regiment circle separates ENEMIES only. So friendly regiments separate from the soldier
     layer up; the enemy front-rank closeup and the spear-vs-cavalry hard block are
     unchanged. Soldiers separate substantially (not yet to a perfect zero-overlap; the last
     residual is a later tuning refinement).
   - **Enemy collision — deferred to #201 (see #296).** The next slice (move the
     not-both-engaged enemy separation + the spear-vs-cavalry hard block to the soldier
     level) hit a wall: the regiment's `_move_to` advances the charge (~170 u/s)
     independently of the soldier layer, and a velocity-only soldier push + the bounded
     body->regiment coupling cannot counteract it — a charging cavalry rides clean through
     a spear line even at extreme tuning. Stopping a charge on a braced line is a
     **momentum/mass** problem, which is exactly what **#201** layers onto the soldier
     bodies. So enemy collision (and then retiring the regiment circle entirely, plus the
     `_push_share` / intermixing helpers it still uses) moves with #201, not as a
     kinematic slice. Until
     then the regiment circle keeps resolving enemy collision (the `_front_depth` closeup
     and the hard block), unchanged. Friendly collision stays soldier-level (slice 1).

## Decisions (resolved)

The four design/perf trade-offs are settled:

1. **Bodies: plain data, not Godot nodes.** Soldiers are position/velocity arrays
   on the `Unit` (today's mark approach, extended) — not thousands of
   `CharacterBody2D` nodes. This keeps determinism fully in our hands and reuses
   the existing `SpatialHash`; `move_and_slide` stays out of the deterministic
   simulation path.
2. **All 120 soldiers exist; only the engaged ones run the expensive sim.** Every
   soldier in `max_soldiers` is a real body, but the simulation runs at two levels
   of detail (see below) — engaged soldiers get full per-soldier collision and
   combat, while the unengaged bulk just follows its formation slot cheaply.
3. **Target scale: budget for ~5,000 soldiers on the field, ~1,500 engaged at
   once.** A default 5v5 battle is ~1,020 soldiers (one side = Spearmen 140 +
   Infantry 120 + Archers 90 + Cavalry 80 + Cavalry 80 = 510); a large campaign
   stack (~20v20, the composition cycling) reaches ~4,000+. So the grid and
   per-frame budget are sized for **~5,000 total** bodies doing the cheap
   formation update, of which a realistic peak of **~1,000–1,500** are engaged and
   run the full collision/combat pass. This is the number to keep the 60 Hz tick
   under, and it's the figure to validate against #131's Pixel-6 ≥30 fps goal.
4. **Cross-platform replay: accept the same-build/platform-only caveat.** Soldier-
   level float ordering amplifies it, but bit-exact cross-platform replay stays out
   of scope — no fixed-point position path. Determinism within a build/platform
   (the property replays and tests rely on) is still required.

## Simulation level-of-detail (engaged vs. unengaged)

The key consequence of decisions 2 and 3: the per-frame cost is dominated by how
many soldiers are *engaged*, not by the total on the field. So soldiers run at two
tiers, re-evaluated each tick:

- **Engaged** — a soldier at a regiment's contact face: in or near melee, being
  shot at, or pressed against an enemy/obstacle. Runs the full pass —
  soldier-vs-soldier separation on the soldier-sized `SpatialHash`, plus
  individual combat resolution. This is where flanking, screening, and chokepoints
  emerge from geometry.
- **Unengaged** — the bulk of a regiment not in contact. Follows its formation slot
  as a cheap rigid offset from the regiment center (essentially today's behaviour),
  with no per-soldier neighbour scan. Promoted to *engaged* the moment an enemy or
  obstacle comes within range.

The engaged/unengaged flag must itself be deterministic (derived from positions and
states already in the sim, not wall-clock or frame-rate), so replays stay exact.
The promotion/demotion boundary uses linger hysteresis (`ENGAGED_LINGER`) so soldiers
don't flap between tiers at the threshold — shipped in phase 2.

Phases 1-4 are live: the soldiers are simulated, separated across regiments, rendered at
their simulated positions, and **engaged melee resolves per-soldier and drives regiment
strength/morale** (the first gameplay change). The per-soldier reach model gives a longer
weapon the opening-strike advantage on the approach; the fully *sustained* asymmetric
standoff of #240 (a spear holding a swordsman at bay while locked) still needs enemy
soldier-level positioning, which rides with #201 (the regiment circle still collapses
enemy fronts to the separation floor once locked). The next authority slices are ranged
casualties (kill soldiers in the health pool) and morale-from-soldier-state; enemy
collision and retiring the regiment circle move with #201.
