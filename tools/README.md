# tools/

Developer tooling for Sparta — small helpers that speed up the edit → verify
loop. None of it ships in the game build.

## `check.sh` — run CI's checks locally

A single entry point that reproduces the **gating** checks from
`.github/workflows/` on your machine, so you can get a CI-equivalent pass (or
failure) without pushing and waiting on the runners.

```sh
tools/check.sh                 # default set: validate, test, chars
tools/check.sh test chars      # only the named checks, in order
tools/check.sh all             # every check (adds links if lychee is installed)
tools/check.sh --list          # list the available checks
tools/check.sh --help          # full usage
```

| Check | What it does | Mirrors |
|---|---|---|
| `validate` | `godot --headless --import` loads the whole project (autoloads, `class_name` globals, cross-script refs) and fails on any script/parse error. | `godot-ci.yml` |
| `test` | Runs the GUT unit suite headlessly (`-gexit`). | `godot-ci.yml` |
| `chars` | Flags curly quotes and en/em dashes in the Quarto docs (`*.qmd`, `*.R`), which are kept plain-ASCII. | `check-non-standard-chars.yml` |
| `links` | Markdown link-check via [lychee](https://github.com/lycheeverse/lychee), if installed. Needs network, so it's **not** in the default set. | `check-links.yml` |

Exit status is non-zero if any selected check fails, so it drops straight into a
pre-push hook or a `&&` chain:

```sh
tools/check.sh && git push
```

### Requirements

- **Bash 3.2+** — works with the system Bash that ships on macOS (no Homebrew
  Bash needed); uses only POSIX/BSD-compatible tool flags.
- **Godot 4.6 (Standard build)** on `PATH`, or point `GODOT_BIN` at it
  (e.g. `/Applications/Godot.app/Contents/MacOS/Godot` on macOS). See the README's
  "Running Godot headlessly" snippet for a Linux download.
- **GUT** is vendored on demand into `addons/gut/` the first time `validate`/`test`
  runs (it isn't committed); no manual install needed.
- **lychee** only for the optional `links` check.

### Environment variables

| Var | Default | Purpose |
|---|---|---|
| `GODOT_BIN` | `godot` | Godot 4.6 binary to invoke. |
| `GUT_VERSION` | `v9.6.0` | GUT release to vendor when `addons/gut/` is missing. Keep in sync with `godot-ci.yml` and `test/README.md`. |
| `NO_COLOR` | _(unset)_ | Set to disable coloured output. |

## `demo/`

The headless demo recorder used by the demo-video pipeline — see
[`demos/README.md`](../demos/README.md).
