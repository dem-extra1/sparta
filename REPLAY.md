# Reproducible Battle Replays

Sparta records every battle so it can be re-watched and — more importantly —
re-run for debugging. This is the same technique **many strategy games** use, and the
reason such replay files stay tiny.

## How it works

There are two common ways to build replays:

1. **State-snapshot recording** — save every unit's position/health each frame
   and play it back like a video. Simple, but the logs are large and it's "dumb"
   playback: you can't re-run the real logic to investigate a bug.
2. **Deterministic simulation + input log** *(what Sparta does)* — record only
   the RNG **seed** and the player's **orders** (each stamped with the physics
   tick it took effect). Replaying re-seeds the RNG and re-injects those orders
   on the same ticks, so the **real simulation** re-runs and unfolds identically.

Godot has no built-in system for either; both are something you build. Sparta
uses approach #2 because it gives tiny logs *and* reproduces bugs in the live
sim, which is exactly what makes it useful for debugging.

### Why it's reproducible

The simulation is deterministic by construction:

- **One RNG stream.** All gameplay randomness goes through `Replay.rng`, a single
  seeded `RandomNumberGenerator`, drawn in a stable order (today: the lone
  `randf_range` in `Unit._strike`, once per striking unit, in tree order).
- **Fixed timestep.** The sim advances on the 60 Hz physics tick, never on a
  variable-framerate / wall-clock timer. The enemy AI re-evaluates on a fixed
  tick cadence (`Battle.AI_PERIOD`) for the same reason.
- **Orders drive the sim; presentation rides alongside.** Only right-click orders
  change the outcome, and each references units by a stable per-battle `uid` so it
  survives a scene reload. Camera pan and zoom are also recorded, but as a separate
  **presentation track** that's purely cosmetic — it reproduces how the battle was
  framed without ever feeding the sim. Selection isn't recorded.
- Orders are queued and applied on the **next** physics tick, so live play and
  playback take the exact same code path (`Battle._apply_order_cmd`).

> Note: results are reproducible on the **same build and platform**. Bit-exact
> cross-platform floating-point replay is out of scope.

## Using it

- Every live battle is **recorded automatically** (a `● REC` indicator shows
  top-center). When the battle ends it's saved to `user://replays/`.
- On the end screen, **Watch Replay** re-runs the battle you just played (the
  indicator changes to `▶ REPLAY`). During playback you can still pan the camera
  and click units to inspect them, but you can't issue orders. (The recorded
  camera track only drives the view when the **demo recorder** replays it for a CI
  clip; in-app you keep free pan/zoom.)
- **Load Replay** (a persistent top-right button, also on the end screen) opens
  a file picker on the replays folder so you can watch *any* saved battle, not
  just the most recent one.
- **Fight Again** starts a fresh, newly-recorded battle.

Replay files are small JSON:

```json
{
  "version": 1,
  "seed": "2582915400366924141",
  "physics_tps": 60,
  "created": 1781512075.7,
  "result": "Defeat",
  "duration_ticks": 1013,
  "orders": [
    { "tick": 84, "units": [0, 1], "x": 740.0, "y": 560.0, "target": -1 },
    { "tick": 132, "units": [3], "x": 0.0, "y": 0.0, "target": 7 }
  ],
  "camera": [
    { "tick": 0, "x": 800.0, "y": 500.0, "zoom": 0.62 },
    { "tick": 90, "x": 812.0, "y": 470.0, "zoom": 1.70 }
  ]
}
```

The optional `camera` array is the **presentation track**: camera keyframes (`x`,
`y`, `zoom`) stamped with the physics tick they were captured on. Consecutive
identical samples are dropped, so a still camera costs one keyframe. On playback the
camera holds the latest keyframe at or before the current tick. The field is additive
— replays without it (every pre-camera recording) play with the default static
camera — so no `version` bump is needed.

Each order's `target` overloads one int to encode the order kind, so the JSON
schema stays fixed as order types are added (`Battle._apply_order_cmd` dispatches
on it):

- `-1` — plain **move** to `x,y`.
- `-2` — **append** `x,y` to the units' waypoint queue instead of replacing the route.
- `-3` — **formation change only**: no movement, the `formation` field carries the mode.
- a `uid` on the **enemy** team — **attack** that unit (`x,y` ignored).
- a `uid` on the **same** team — **relief**, **merge**, or **support**, depending on
  whether the target is one of the ordered `units` and on the order `mode`.

The seed is stored as a **string** on purpose: JSON
numbers are float64 and would silently lose precision on a full 64-bit seed,
desyncing the replay.

Hand-authored **scenarios** (under `demos/scenarios/`) are just replay files
written by hand; see [`demos/README.md`](demos/README.md) for the spawn layout,
unit speeds, and timing you need to stage one.

## Where it lives

| File | Role |
| --- | --- |
| `scripts/Replay.gd` | Autoload singleton: seeded RNG, record/playback, save/load |
| `scripts/Battle.gd` | Tick clock, order queue/apply, AI cadence, saves on battle end |
| `scripts/Unit.gd` | Draws combat randomness from `Replay.rng`; carries a `uid` |
| `scripts/SelectionManager.gd` | Routes right-click orders to `Battle.enqueue_order` |
| `scripts/HUD.gd` | `● REC` / `▶ REPLAY` indicator and the Watch Replay button |

## Keeping it deterministic as the game grows

When you add new systems, preserve replayability by:

- Drawing **all** randomness from `Replay.rng` (never `randf()`/`randi()` or a
  fresh `RandomNumberGenerator`), in a deterministic order.
- Running gameplay logic on the physics tick, not on `_process`/wall-clock time.
- Recording any new player input that affects the simulation as an order (extend
  the command schema and bump `Replay.FORMAT_VERSION`).
