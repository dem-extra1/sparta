# Design note: individual-level collision

Status: **design draft — not yet implemented.** Open decisions for the maintainer
are collected at the end; implementation waits on those.

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
   against the fixed 60 Hz tick.
3. **Soft vs. hard semantics carry down.** The `_push_share` screen logic and the
   melee-intermixing softening are regiment-level today; the individual model has
   to reproduce "a spear line stops a charge" and "melee lines interpenetrate a
   little" out of soldier-level rules, not lose them.

## A phased plan

Each phase is independently shippable and testable (the GUT suite exercises the
sim logic headless — no rendering needed), so collision correctness can be
verified before the next phase builds on it.

1. **Promote marks to bodies, behind a flag.** Give each soldier a stable id and a
   simulated position seeded from the current formation slot. Keep the regiment
   circle authoritative; run the soldier layer in parallel and assert it stays
   inside the regiment footprint. No gameplay change yet — this is the migration
   scaffold and its test harness.
2. **Soldier-level separation.** Port `_separate()`'s penetration/`_push_share`
   math to soldier-vs-soldier within and across regiments, on a soldier-sized
   `SpatialHash`. Determinism tests: same seed + orders ⇒ identical soldier
   positions on replay.
3. **Formation as soldier slots.** The regiment assigns slots (block/line, tight
   vs. loose); soldiers arrive at slots while separating. Cohesion becomes an
   emergent result of slot assignment + separation rather than a single circle.
4. **Combat at the individual level.** Melee and missiles resolve against soldiers,
   so flanking and screening fall out of geometry. This is where the
   rock-paper-scissors design meets per-soldier collision.
5. **Retire the regiment circle.** Once soldiers are authoritative, `RADIUS`-based
   `_separate()` becomes derived/diagnostic. `#201`'s physics (mass, momentum,
   knock-back) then layers on the soldier bodies.

## Open decisions (need the maintainer's call)

These are genuine design/perf trade-offs, not implementation details — and they
gate the gameplay feel and the frame budget, so they're yours to set:

1. **Bodies: plain data or Godot nodes?** Thousands of `CharacterBody2D` nodes
   with `move_and_slide` (PLAN.md roadmap item 5 floats this) buys engine
   collision and pathing but is heavy at this count; plain position/velocity
   arrays in `Unit` (today's mark approach, extended) are lighter and keep
   determinism fully in our hands. Recommendation: **stay data-driven**, reuse the
   `SpatialHash`, and keep `move_and_slide` out of the deterministic path.
2. **How many soldiers actually simulate?** Full `max_soldiers` (120/unit) vs. a
   smaller simulated count up-scaled visually. This sets the whole perf budget.
3. **Target scale.** Max simultaneous soldiers we design the grid/budget around
   (relates to the smartphone target in
   [#131](https://github.com/Lacaedemon/sparta/issues/131): ≥30 fps on a Pixel 6).
4. **Cross-platform replay.** Soldier-level float order amplifies the existing
   "same build/platform only" caveat. Confirm that stays acceptable, or we need a
   fixed-point/integer position path.

Once these are decided, phase 1 can start as a flagged, test-backed PR.
