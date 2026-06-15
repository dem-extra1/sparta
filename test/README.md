# Tests

Unit tests use [GUT](https://github.com/bitwes/Gut) (Godot Unit Test), pinned to
**v9.6.0** (the Godot 4.6 release).

GUT itself is **not committed** to this repo — CI vendors it at run time and you
install it locally the same way:

```sh
git clone --depth 1 --branch v9.6.0 https://github.com/bitwes/Gut.git /tmp/gut
mkdir -p addons && cp -r /tmp/gut/addons/gut addons/gut
```

## Running

Headless (what CI runs — see `.github/workflows/godot-ci.yml`):

```sh
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit
```

Or, in the editor, enable the GUT plugin (**Project → Project Settings →
Plugins**) and use the GUT bottom panel.

## Layout

```
test/
  unit/        fast, isolated tests of game logic (test_*.gd, extends GutTest)
```

Test files must be named `test_*.gd` and extend `GutTest`.

> Coverage upload to Codecov is tracked as a follow-up — Godot 4 GDScript→lcov
> tooling is still immature, so it's deliberately not wired into CI yet.
