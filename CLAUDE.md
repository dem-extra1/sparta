# Sparta — AI agent instructions

Sparta is a **Godot 4.6** (GDScript, Standard build — not .NET/C#) prototype
fusing CK3-style grand strategy with Total War-style tactical battles. See
`README.md` for layout and `PLAN.md` for the roadmap.

## Working rules

### Handling code-review feedback about upstream repos

When a review (human or automated, e.g. Copilot/Claude) raises an issue that
actually lives in an **upstream/external repository** — a reusable workflow, a
dependency, an action we call, etc. — rather than only working around it here:

1. **File a follow-up issue in the upstream repo** describing the problem (link
   back to this repo's PR/review for context).
2. **Reply to the review comment with a link to that upstream issue**, so the
   reviewer can see it's tracked at the source.

Still apply any reasonable local mitigation, but do not let the upstream root
cause go unrecorded.

### Handling missing `send_later` (PR check-in scheduling)

In some sessions (especially Claude Code on the web), the `send_later` tool from
the `claude-code-remote` MCP server is **not available**, so you cannot schedule
a delayed self check-in to re-poll a PR's CI/merge state. When you hit this, do
not just report it as a dead end — use one of these instead:

1. **`subscribe_pr_activity`** — available in these sessions. It wakes the session
   on PR comments, CI completions, and reviews. This covers most babysitting needs.
   The only gap is transitions webhooks never deliver (a green CI run needing no
   action, a new push, or a merge-conflict appearing) — so actively re-check
   `mergeable_state` rather than waiting for a webhook that won't come.

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
