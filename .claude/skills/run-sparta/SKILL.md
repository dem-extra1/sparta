---
name: run-sparta
description: Run, build, test, or screenshot the Sparta Godot game. Use this skill to start the game, take a screenshot, run headless validation, run unit tests, or run a replay smoke test.
---

Sparta is a Godot 4.6 GDScript tactical battle game. It has no build step — Godot imports assets on first launch. The agent-facing path is a set of headless scripts that require no display; the screenshot path needs `xvfb-run` and `scrot` for a virtual framebuffer.

**All paths below are relative to the repo root.**

## Prerequisites

Godot 4.6 Standard (not .NET) must be on `PATH` as `godot`, or set `GODOT_BIN`:

```bash
which godot          # should print /usr/local/bin/godot
godot --version      # 4.6.x.stable.official.*
```

For screenshots only (not needed for headless probes):

```bash
apt-get install -y xvfb scrot
```

GUT (unit test framework) is vendored on demand by `tools/check.sh`, but is not committed. If `addons/gut/` is missing:

```bash
GUT_VERSION=v9.6.0
wget -q "https://github.com/bitwes/Gut/archive/refs/tags/${GUT_VERSION}.tar.gz" -O /tmp/gut.tar.gz
tar -xzf /tmp/gut.tar.gz -C /tmp/
cp -r /tmp/Gut-9.6.0/addons/gut/* addons/gut/
```

Then re-run `godot --headless --import` once to register the new scripts.

## Smoke test (agent path — no display)

The primary agent interface is `.claude/skills/run-sparta/smoke.sh`, run from repo root:

```bash
bash .claude/skills/run-sparta/smoke.sh              # validate + test + replay
bash .claude/skills/run-sparta/smoke.sh validate     # headless import (parse check)
bash .claude/skills/run-sparta/smoke.sh test         # 314 GUT unit tests
bash .claude/skills/run-sparta/smoke.sh replay       # headless showcase replay
```

Exit 0 = all selected probes passed. Example output:

```
== validate ==
  PASS  validate
== test ==
Tests              314
Passing Tests      314
Time              0.744s
  PASS  test
== replay ==
  PASS  replay

== summary ==
  All selected probes passed.
```

## Screenshot (agent path — needs virtual display)

```bash
bash .claude/skills/run-sparta/screenshot.sh /tmp/sparta_ss.png
```

Launches `Battle.tscn` in a 1280×720 xvfb session via llvmpipe (software GL), waits 4 seconds for the first frame, captures with `scrot`, then kills Godot. Takes ~10 seconds. Output is a PNG of the running battle.

## Run (human path)

```bash
godot                        # opens the Godot editor; press F5 to run
# or from command line:
godot --scene res://scenes/Battle.tscn   # launches battle directly (opens a window)
```

Requires a real display (not headless). Audio fails silently in a container without ALSA/PulseAudio — gameplay is unaffected.

## Individual checks

```bash
# Headless import validation only
godot --headless --import

# GUT tests directly
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/ -gexit

# Headless replay smoke
SPARTA_DEMO_REPLAY=demos/showcase.json \
  godot --headless --scene res://tools/demo/DemoRunner.tscn --quit-after 120
```

## Gotchas

- **ALSA/PulseAudio errors on launch** — `libpulse.so.0: cannot open shared object file` + `Unknown PCM default`. Normal in containers. Godot falls back to a dummy audio driver. No action needed.
- **`addons/gut/gut/` double-nesting** — if GUT is extracted from the tarball into `addons/gut/`, the layout is `addons/gut/gut/gut_cmdln.gd` (one level too deep). Fix: `cp -r addons/gut/gut/* addons/gut/` then re-import.
- **`tools/check.sh` tries `git clone` for GUT** — fails in network-restricted containers. Use the `wget` tarball path in Prerequisites above instead.
- **`--quit-after N`** is in frames at the project's physics TPS (60), not seconds. `--quit-after 120` = 2 seconds of sim time.
- **Screenshot tool timeout** — the `screenshot.sh` script takes ~10 seconds (4s wait + launch overhead). Any calling tool with a sub-10s timeout will see a timeout exit code, but the PNG is still written if Godot launched.
- **V-Sync warning** — `Could not set V-Sync mode` on xvfb. Benign.
