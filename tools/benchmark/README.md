# Performance benchmark

Sparta's standing performance target ([#549](https://github.com/Lacaedemon/sparta/issues/549)):
**60fps at a representative large-battle scale, on the reference hardware** — a 2022 MacBook
Air (Apple M2, 24GB) and the developer's usual PC. See `PLAN.md` for the target statement.

GitHub Actions runners are **not** that hardware, so a green CI check here never means "60fps
on the Mac/PC" — it only means "this PR didn't measurably slow the sim down on the CI
runner." Two complementary pieces cover the gap:

1. **This directory** — a benchmark you run **locally, by hand, on the actual reference
   hardware** to check the real 60fps target. This is the ground-truth check.
2. **`.github/workflows/benchmark.yml`** — a CI-only **relative regression check** against a
   CI-runner-specific baseline (`baseline.json`). It catches "did this PR make things slower,"
   not "is this PR fast enough" — see that file's own comments for what it does and doesn't
   guarantee.

## What's here

- `BenchmarkRunner.gd` / `.tscn` — headless entry point. Loads a
  `benchmarks/scenarios/*.json` scenario, drives a live `Battle` through it (same mechanism
  `demos/inputs/*.json`'s `scenario` field uses — see `demos/README.md`), lets combat spin up
  for a warmup window, then times N physics ticks with `Time.get_ticks_usec()` and writes a
  JSON report. Mirrors the shape of `tools/demo/DemoRunner.gd`, but measures timing instead of
  recording video.
- `BenchmarkStats.gd` — pure aggregation (mean/p95/min/max, soldier-count scaling). Unit-tested
  in `test/unit/test_benchmark_stats.gd`; the live battle-driving part of the runner isn't
  unit-testable (same reason `DemoInputRecorder.gd`'s scene-driving isn't — it needs a real
  battle instance), so it's verified by actually running the benchmark (below).
- `run-benchmark.sh` — wrapper, mirrors `tools/demo/dump-state.sh`'s shape (`GODOT_BIN` env var,
  headless invocation, human-readable summary printed at the end).
- `baseline.json` — the CI-runner baseline `benchmark.yml` compares against. **Not** the Mac/PC
  target — see its header comment.
- `../../benchmarks/scenarios/large-battle.json` — the reference scenario (see below for why it
  lives outside `demos/`).

## Why `benchmarks/` and not `demos/inputs/`

The scenario file uses the same `scenario` unit-list format `demos/inputs/*.json` supports, but
it deliberately lives in a new top-level `benchmarks/` directory (per #549's suggestion) rather
than `demos/inputs/`:

- It's loaded directly by `BenchmarkRunner.gd` via `Battle.scenario`, not by
  `DemoInputRecorder.gd` — it has no `steps`/`camera`/`frames`/`state` input track, so it isn't
  a valid *demo* input script.
- `demos/inputs/**` is in `demo-video.yml`'s path filter (a PR touching it gets a gameplay-clip
  CI run). A benchmark scenario isn't a gameplay demo (see `demos/demo.json` skip note below),
  so keeping it out of `demos/` avoids implying it's demo content and avoids an unrelated CI
  trigger.

## Running it locally

```sh
GODOT_BIN="C:\Users\you\Documents\apps\Godot_v4.7-stable_win64_console.exe" \
  tools/benchmark/run-benchmark.sh
```

On Linux/macOS, drop `GODOT_BIN` if `godot` is on `PATH`. No `xvfb-run` needed — this is a
plain `--headless` run (no renderer, no Movie Maker); see "What this does and doesn't measure"
below for why headless is the right mode for this benchmark, not a limitation of it.

Or invoke Godot directly (no wrapper):

```sh
SPARTA_BENCHMARK_SCENARIO="res://benchmarks/scenarios/large-battle.json" \
  SPARTA_BENCHMARK_OUT="/tmp/benchmark.json" \
  "$GODOT_BIN" --headless --path . res://tools/benchmark/BenchmarkRunner.tscn
```

The wrapper prints a summary like:

```
Benchmarking res://benchmarks/scenarios/large-battle.json at scale 1x...
...
Report: /tmp/sparta_benchmark_XXXXXX.json
  scenario:          res://benchmarks/scenarios/large-battle.json
  soldiers simulated: 1720 (scale 1x)
  ticks sampled:      600 / 600
  mean tick time:     X.XXX ms  (implied XXX.X fps)
  p95 tick time:      X.XXX ms
  worst tick time:    X.XXX ms
  60fps budget:       16.667 ms/tick -- WITHIN budget on mean, within budget on p95
```

**Run this by hand periodically on the actual reference hardware** (the MacBook Air, the dev
PC) as per-entity realism grows (more per-soldier state, weapon/shield objects, individual
orders — the bottom-up-emergence direction in `PLAN.md`) to confirm the real 60fps target still
holds. CI's regression check (below) is the early warning between these manual runs, not a
replacement for them.

### Finding the soldier-count ceiling

`run-benchmark.sh` takes an optional soldier-count multiplier so you can sweep scale without
authoring new scenario files:

```sh
for s in 1 2 4; do
  tools/benchmark/run-benchmark.sh benchmarks/scenarios/large-battle.json "$s"
done
```

Comparing mean/p95 tick time across the sweep gives a rough sense of how tick cost scales with
soldier count on your machine, and roughly where it crosses the 60fps budget (16.67ms/tick) —
useful context for how far below Cannae-scale (tens of thousands of combatants) the current
per-soldier-array architecture can individually simulate. This is a rough local sweep, not a
precise binary search for the exact crossover soldier count.

## What this does and doesn't measure

**Physics-step time only, not full frame/render time.** `BenchmarkRunner` runs plain
`--headless` (no `--rendering-driver`, no window) and free-runs physics as fast as the CPU
allows (`Engine.max_fps = 0`, no `--fixed-fps` lockstep), timing the wall-clock gap between
consecutive `physics_frame` signals. This is a deliberate tradeoff:

- **Why physics-step time:** it's what scales with soldier count and combat load — the actual
  sim-hot-path (`Unit.gd`, `SoldierBodies.gd`, combat/formation scripts) this benchmark exists
  to catch regressions in. It's also stable and reproducible: no GPU driver, no compositor, no
  windowing-system variance, which matters a lot for the CI regression check (a noisy GPU
  signal on a shared runner would be a bad regression-detection input).
- **What it misses:** actual draw/render cost — sprite compositing, soldier-mesh instancing,
  UI/HUD drawing — which is a real contributor to the ACTUAL 60fps target on the reference
  hardware. A build could pass this benchmark comfortably and still miss 60fps once render cost
  is added on top.
- **Follow-up (not built here):** a local-only windowed variant (real `--rendering-driver`,
  measuring full frame time via `RenderingServer.frame_post_draw`, similar to
  `tools/demo/capture-frames.sh`'s renderer requirement) would close this gap for the *local*
  Mac/PC protocol specifically. Headless CI can't meaningfully measure GPU render cost anyway
  (software/dummy rendering, no real GPU on most runners), so this wouldn't help the CI
  regression check — only the local ground-truth check. Not scoped into this PR; file a
  follow-up if the physics-only signal turns out to hide a real render-side regression.

## CI regression check

See `.github/workflows/benchmark.yml`'s header comment for the full contract: when it runs,
what it compares against, and why a regression is flagged as a PR comment rather than a hard
merge block.
