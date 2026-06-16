#!/bin/bash
# SessionStart hook for Claude Code on the web.
# Installs the GDScript linter + GUT test framework and pre-imports the Godot
# project so linting, headless runs, and the unit-test suite work out of the box.
set -euo pipefail

# Only run in the remote (Claude Code on the web) environment.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Pinned to a GUT release matching the project's Godot 4.6 setup. Keep in sync
# with .github/workflows/godot-ci.yml and test/README.md.
GUT_VERSION="v9.6.0"

# Pin gdtoolkit to a version validated against this project's Godot 4.6 GDScript
# so a future breaking release can't silently break all web sessions.
echo "[session-start] Installing gdtoolkit (gdlint/gdformat)..."
python3 -m pip install --quiet --disable-pip-version-check "gdtoolkit==4.5.0"

# Fail with a clear message if the Godot binary isn't available.
command -v godot >/dev/null 2>&1 || { echo "[session-start] ERROR: godot not found in PATH"; exit 1; }

# Vendor GUT (Godot Unit Test) the same way CI does — it isn't committed to the
# repo. Test files extend GutTest, so GUT must be present before the import
# below or script resolution fails. Skip the clone if it's already vendored.
if [ ! -d "$CLAUDE_PROJECT_DIR/addons/gut" ]; then
  echo "[session-start] Vendoring GUT $GUT_VERSION..."
  rm -rf /tmp/gut
  git clone --depth 1 --branch "$GUT_VERSION" https://github.com/bitwes/Gut.git /tmp/gut
  mkdir -p "$CLAUDE_PROJECT_DIR/addons"
  cp -r /tmp/gut/addons/gut "$CLAUDE_PROJECT_DIR/addons/gut"
  rm -rf /tmp/gut
fi

# Pre-import the project: builds the .godot cache and imports assets so the
# project can be run/checked/tested headlessly without opening the editor first.
# `godot --import` exits 0 even on GDScript compile failures, so mirror CI and
# fail the hook if the import log reports script errors.
echo "[session-start] Importing Godot project..."
import_log="$(mktemp)"
trap 'rm -f "$import_log"' EXIT
godot --headless --import --verbose --path "$CLAUDE_PROJECT_DIR" 2>&1 | tee "$import_log"
if grep -E "SCRIPT ERROR|Failed to load script|Parse Error|Compile Error" "$import_log"; then
  echo "[session-start] ERROR: import reported script errors (see above)"
  exit 1
fi

echo "[session-start] Done."
