#!/bin/bash
# SessionStart hook for Claude Code on the web.
# Installs the GDScript linter and pre-imports the Godot project so tests,
# linting, and headless runs work out of the box.
set -euo pipefail

# Only run in the remote (Claude Code on the web) environment.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

echo "[session-start] Installing gdtoolkit (gdlint/gdformat)..."
pip install --quiet --disable-pip-version-check gdtoolkit

# Pre-import the project: builds the .godot cache and imports assets so the
# project can be run/checked headlessly without opening the editor first.
echo "[session-start] Importing Godot project..."
godot --headless --import --path "$CLAUDE_PROJECT_DIR"

echo "[session-start] Done."
