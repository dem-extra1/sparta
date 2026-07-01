# Tests

Unit tests use [GUT](https://github.com/bitwes/Gut) (Godot Unit Test), pinned to
**v9.7.0** (the Godot 4.7 release).

GUT itself is **not committed** to this repo — CI vendors it at run time and you
install it locally the same way:

```sh
git clone --depth 1 --branch v9.7.0 https://github.com/bitwes/Gut.git /tmp/gut
mkdir -p addons && cp -r /tmp/gut/addons/gut addons/gut
```

## Running

Headless (what CI runs — see `.github/workflows/godot-ci.yml`):

```sh
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit
```

Or, in the editor, enable the GUT plugin (**Project → Project Settings →
Plugins**) and use the GUT bottom panel.

Or run [`tools/check.sh`](../tools/check.sh) (no args), which vendors GUT on
demand and runs the suite alongside the project's other CI checks — see
[`tools/README.md`](../tools/README.md).

## Layout

```
test/
  unit/        fast, isolated tests of game logic (test_*.gd, extends GutTest)
```

Test files must be named `test_*.gd` and extend `GutTest`.

## Coverage

Line coverage is measured with
[`jamie-pate/godot-code-coverage`](https://github.com/jamie-pate/godot-code-coverage)
(its `godot4` branch), committed under [`../addons/coverage/`](../addons/coverage/)
and pinned to commit `9c8d4a9`. Unlike GUT, the coverage addon **is** committed —
it is small, has no releases to pin a tag against, and reviewers can see the exact
instrumented code in the diff. The only change from upstream is one debug
constant (`DEBUG_SCRIPT_COVERAGE`) set to `0`, so instrumenting the tree doesn't
dump every script's source into the logs.

Two GUT hooks drive it:

- [`pre_run_hook.gd`](pre_run_hook.gd) instruments `res://scripts` before the suite runs.
- [`post_run_hook.gd`](post_run_hook.gd) writes an `lcov.info` report afterward.

Run coverage locally the same way CI does
(see [`.github/workflows/test-coverage.yml`](../.github/workflows/test-coverage.yml)),
or via `tools/check.sh coverage`:

```sh
COVERAGE_LCOV_FILE=res://coverage/lcov.info \
  godot --headless -s addons/gut/gut_cmdln.gd \
    -gdir=res://test -ginclude_subdirs -gexit \
    -gpre_run_script=res://test/pre_run_hook.gd \
    -gpost_run_script=res://test/post_run_hook.gd
```

The report lands at `coverage/lcov.info` (git-ignored). CI uploads it to Codecov
in a **separate, non-gating** job, so a coverage dip never blocks a PR; the fast
gate stays in `godot-ci.yml`.

Two known limitations, both inherent to the instrumenter:

- **Autoloads are excluded.** `Settings`, `Replay`, and `Sfx` are already
  instantiated before the pre-run hook fires, so reloading their scripts to
  instrument them is unreliable; `pre_run_hook.gd` skips them.
- Instrumentation reloads each script with injected line counters, so the
  coverage run is a little slower than the plain `test` job — another reason it
  runs separately.
