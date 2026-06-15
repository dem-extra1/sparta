# Claude / AI Agent Instructions

Project notes and reminders for AI agents working in this repository.

## Handling missing `send_later` (PR check-in scheduling)

In some sessions (especially Claude Code on the web), the `send_later` tool from
the `claude-code-remote` MCP server is **not available**, so you cannot schedule
a delayed self check-in to re-poll a PR's CI/merge state. When you hit this, do
not just report it as a dead end — use one of these instead:

1. **`subscribe_pr_activity`** — available in these sessions. It wakes the session
   on PR comments, CI completions, and reviews. This covers most babysitting needs.
   The only gap is transitions webhooks never deliver (a green CI run needing no
   action, a new push, or a merge-conflict appearing).

2. **`/loop` skill** — runs a prompt or slash command on an interval
   (e.g. `/loop 1h check PR #N CI and mergeability`). This is the practical
   replacement for `send_later`'s self-scheduling: it gives periodic re-checks
   without the MCP tool.

3. **On-demand** — while the session is alive, the user can ping at any time and
   you re-check the PR state.

4. **Enable the MCP server** — `send_later` lives in the `claude-code-remote` MCP
   server. If you truly need it, it must be configured for the environment; that's
   a settings/MCP-config change, not something to flip on mid-session.

For most PR-babysitting, **#1 + #2 together** replicate what `send_later` was for.
Never use Bash `sleep` to wait for external events.
