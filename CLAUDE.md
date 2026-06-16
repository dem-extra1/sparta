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

In some sessions (especially those where the `claude-code-remote` MCP server is
not configured), the `send_later` tool is **not available**, so you cannot
schedule a delayed self check-in to re-poll a PR's CI/merge state. This is a
session/MCP-config condition, not specific to any one client. When you hit it,
do not just report it as a dead end — use whichever of these is available:

1. **`subscribe_pr_activity`** (if available) — it wakes the session on PR
   comments, CI completions, and reviews (the exact set depends on the
   deployment), which covers most babysitting needs.
   Two things a PR-activity subscription won't reliably hand you, so check them
   actively rather than waiting on a webhook. First, a CI run that goes green
   *and* needs you to act on it (e.g. auto-merge). Second, a **merge conflict
   appearing** — poll the PR's `mergeable_state` (via the GitHub API) to catch
   it. (A push does emit a `synchronize` webhook, but the subscription may not
   surface it, so don't rely on it.)

2. **`/loop` skill** (if available) — runs a prompt or slash command on an
   interval (e.g. `/loop 1h check PR #N CI and mergeability`). This is the
   practical replacement for `send_later`'s self-scheduling: periodic re-checks
   without the MCP tool.

3. **On-demand** — while the session is alive, the user can ping at any time and
   you re-check the PR state.

4. **Enable the MCP server** — `send_later` lives in the `claude-code-remote` MCP
   server. If you truly need it, it must be configured for the environment; that's
   a settings/MCP-config change, not something to flip on mid-session.

When both are available, **#1 + #2 together** replicate what `send_later` was for.
Never use Bash `sleep` to wait for external events.
