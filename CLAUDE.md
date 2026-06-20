# CLAUDE.md — AI working instructions for Sparta

Orientation and standing policies for any AI session working in this repo.
Sparta is a **Godot 4.6** (GDScript, Standard build — not .NET/C#) prototype
fusing dynastic grand strategy with real-time tactical battles. See
`README.md` for layout and `PLAN.md` for project vision, roadmap, architecture,
and verification steps — read `PLAN.md` first.

## Project at a glance
- Godot **4.6.x Standard** (GDScript, not C#/.NET). 2D top-down tactical battle.
- Main scene: `scenes/Battle.tscn`. Core scripts live in `scripts/`.
- Issues are tracked on this repo with `P0`–`P3` labels; `PLAN.md` mirrors the roadmap.

## Verify before you push
Run `tools/check.sh` to reproduce CI's gating checks locally (Godot import
validation + GUT unit suite + the docs char-check; `tools/check.sh all` adds the
lychee link-check). It vendors GUT on demand and needs only a Godot 4.6 binary on
`PATH` (or `GODOT_BIN`). See `tools/README.md`. Prefer it over invoking the
individual checks by hand so local and CI results stay in sync.

## Gameplay demos in PRs
When your change is **user-visible** — it affects how the game looks or plays
(`scenes/`, `scripts/`, `assets/`, `project.godot`) — help reviewers *see* it:
commit a **`demos/demo.json`** so CI records a short clip and posts it on the PR.

- Point `replay` at a replay that exercises your change. Record one by playing the
  game and copying the saved file from `user://replays/` into `demos/`, or — for
  changes visible in any battle (unit art, HUD, balance) — reuse the bundled
  `demos/showcase.json`. Write a `caption` describing what changed.
- See `demos/README.md` for the full contract and `demos/demo.example.json` for a
  template.
- If you skip this, CI still posts a *generic* build demo, but it won't show your
  specific change — so add a tailored manifest whenever the change is worth seeing.
- If your change genuinely **can't** be shown by a recorded battle (a paused-overlay
  interaction, an editor-only tool, a non-visual refactor), don't let CI post an
  unrelated generic clip: commit a `demos/demo.json` with `"skip": true` and a
  `"reason"`. CI then posts a short note explaining the absence instead
  (`demos/demo.skip.example.json` is a template).

## Code review handling policy
When addressing review feedback (human or automated) on a PR, triage each finding:

1. **In scope + confident + small** → fix it on the PR branch, commit, push.
2. **Ambiguous or architecturally significant** → ask the user before acting.
3. **Out of scope for the current PR** (forward-looking polish, speculative
   future-proofing, preventative robustness with no current bug) → do **not**
   expand the PR to absorb it. Instead:
   - Create a GitHub issue to track it (or, if an existing issue already covers
     it, reuse that issue), and
   - Reply to the review with a link to the tracking issue so the reviewer
     knows where the work landed.
4. **Duplicate / no action needed** → skip silently.

A PR's scope is defined by its title/description. Keep the diff focused on that;
push genuinely separate concerns to their own tracked issues rather than letting
review rounds grow the change set unboundedly.

### Findings that live in an upstream/external repo
When a review raises an issue that actually lives in an **upstream/external
repository** — a reusable workflow, a dependency, an action we call, etc. —
rather than only working around it here:

1. **File a follow-up issue in the upstream repo** describing the problem (link
   back to this repo's PR/review for context).
2. **Reply to the review comment with a link to that upstream issue**, so the
   reviewer can see it's tracked at the source.

Still apply any reasonable local mitigation, but do not let the upstream root
cause go unrecorded.

## Git / branch conventions
- Develop on the designated feature branch; never push to a different branch
  without explicit permission.
- Commit messages: clear and descriptive, present tense.

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
