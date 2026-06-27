# Design note: individual-level collision

Status: **phases 1-2 implemented and active** (behind `Unit.INDIVIDUAL_COLLISION`,
now ON). Soldiers are seeded as world-space bodies from their formation slots, the
engaged front ranks are separated per-soldier **across regiments** on a soldier-sized
`SoldierSpatialHash`, and the result is drawn as a debug overlay. The layer is still
**non-authoritative** — combat, movement, and morale read the regiment circle, not
`_sim_soldier_pos` — so gameplay is unchanged. Next: phase 3 (make the soldiers the
rendered reality), phase 4 (combat per-soldier), phase 5 (retire the regiment circle).
The design decisions are settled (see "Decisions" below).

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
   front ranks press into each other. Determinism + order-independence + hard-block +
   a perf smoke test are in `test_soldier_separation.gd`. A debug overlay
   (`Unit._draw`, engaged = magenta, bulk = cyan) makes the layer visible.
3. **Formation as soldier slots.** The regiment assigns slots (block/line, tight
   vs. loose); soldiers arrive at slots while separating. Cohesion becomes an
   emergent result of slot assignment + separation rather than a single circle.
4. **Combat at the individual level.** Melee and missiles resolve against soldiers,
   so flanking and screening fall out of geometry. This is where the
   rock-paper-scissors design meets per-soldier collision.
5. **Retire the regiment circle.** Once soldiers are authoritative, `RADIUS`-based
   `_separate()` becomes derived/diagnostic. `#201`'s physics (mass, momentum,
   knock-back) then layers on the soldier bodies.

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

Phases 1-2 are live (flagged on, non-authoritative). The next PR is phase 3: drive
the on-screen soldiers from `_sim_soldier_pos` so the simulated bodies become the
rendered reality, retiring the debug overlay and the cosmetic flock.
