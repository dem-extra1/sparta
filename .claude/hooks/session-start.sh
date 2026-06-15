#!/bin/bash
# SessionStart hook for Claude Code on the web.
# Installs the GDScript linter and pre-imports the Godot project so tests,
# linting, and headless runs work out of the box.
set -euo pipefail

# Only run in the remote (Claude Code on the web) environment.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Pin gdtoolkit to a version validated against this project's Godot 4.6 GDScript
# so a future breaking release can't silently break all web sessions.
echo "[session-start] Installing gdtoolkit (gdlint/gdformat)..."
python3 -m pip install --quiet --disable-pip-version-check "gdtoolkit==4.5.0"

# Fail with a clear message if the Godot binary isn't available.
command -v godot >/dev/null 2>&1 || { echo "[session-start] ERROR: godot not found in PATH"; exit 1; }

# Pre-import the project: builds the .godot cache and imports assets so the
# project can be run/checked headlessly without opening the editor first.
echo "[session-start] Importing Godot project..."
godot --headless --import --path "$CLAUDE_PROJECT_DIR"

echo "[session-start] Done."
