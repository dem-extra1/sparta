# CLAUDE.md — AI working instructions for Sparta

Orientation and standing policies for any AI session working in this repo.
Sparta is a **Godot 4.6** (GDScript, Standard build — not .NET/C#) prototype
fusing dynastic grand strategy with real-time tactical battles. See
`README.md` for layout and `PLAN.md` for project vision, roadmap, architecture,
and verification steps — read `PLAN.md` first.

## Cross-repo AI configuration (`d-morrison/ai-config`)

This repo pulls in [`d-morrison/ai-config`](https://github.com/d-morrison/ai-config)
for portable skills and memories via the **Plugin Marketplace**.

`.claude/settings.json` registers the `d-morrison` marketplace and enables the
`ai-config` plugin, so Claude Code installs it at session start — skills are
available as `/ai-config:<name>` (e.g. `/ai-config:ardi`, `/ai-config:remember`).

**Local / after cloning:** the submodule is already registered in `.gitmodules`;
initialize it with:
```bash
git submodule update --init
```
Memories live in `.ai-config/memories/` (e.g. `@.ai-config/memories/preferences.md`).
Skills live in `.ai-config/skills/`.

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

- **Author demos as a scripted-input recording — not a hand-authored replay.** Write a
  deterministic input script (`demos/inputs/*.json`: a list of mouse clicks/drags and
  keystrokes stamped with the tick they fire on) and point `demos/demo.json` at it with
  the `input` field. The recorder drives a live battle through the *real* controls, so the
  clip exercises the actual code and the script stays editable as text. See the
  **Scripted-input demos** section of `demos/README.md`.
- The older `replay` field (play-and-save, or hand-authored scenario JSON) still works and
  is fine for a quick reuse of `demos/showcase.json`, but prefer `input` for anything that
  shows a specific interaction. Always write a `caption` describing what changed.
- See `demos/README.md` for the full contract and `demos/demo.example.json` for a
  template.
- If you skip this, CI still posts a *generic* build demo, but it won't show your
  specific change — so add a tailored manifest whenever the change is worth seeing.
- If your change genuinely **can't** be shown by a recorded battle (a paused-overlay
  interaction, an editor-only tool, a non-visual refactor), don't let CI post an
  unrelated generic clip: commit a `demos/demo.json` with `"skip": true` and a
  `"reason"`. CI then posts a short note explaining the absence instead
  (`demos/demo.skip.example.json` is a template).

### Static features: images in the PR description
For changes a still shows better than motion — new **interfaces/menus/HUD**, **new
or improved art**, layout/visual polish — also embed informative **image(s) in the
PR description itself** (in addition to the CI clip when motion matters). A labelled
screenshot in the body lets a reviewer judge the change at a glance without opening
media.

- Capture a PNG, commit it under `demos/shots/` on your PR branch, and embed it in
  the description by raw URL with a caption — referencing the **commit SHA** so the
  image keeps rendering after the branch is deleted on merge.
- See `demos/README.md` for how to produce the PNG (pull a frame from the demo
  recording, or screenshot a scene) and the full image contract.
- This is separate from the `demos/demo.json` video manifest: images go in the PR
  **body** (you post them), the gameplay clip still posts as a CI comment. For a
  static UI a recorded battle can't film, `skip` the clip (above) and rely on the
  image.

## Website updates in user-facing PRs

When a PR changes **how the game looks or plays** — mechanics, controls, UI,
balance, or any player-visible behaviour — include corresponding updates to the
`website/` docs site so the documentation stays in sync.

**When the rule applies:** any PR that touches `scenes/`, `scripts/`, `assets/`,
or `project.godot` in a way a player would notice. Pure refactors, internal
architecture, and CI changes are exempt.

**What to update:**

- `website/how-to-play.qmd` — step-by-step guide for new players. Add a step,
  update a control description, or note a new interaction.
- `website/tactics.qmd` — tactical guidance. Add a section when a new mechanic
  creates strategic decisions (terrain types, order delay, unit interactions, etc.).
- Other pages (`website/index.qmd`, `website/roadmap.qmd`) when the change is
  milestone-level.

**Where to look for site layout:** `website/README.md` describes the page
structure, build instructions, and how demo clips are recorded. Each `.qmd` page
links back to its source of truth in the repo root.

Keep website changes on the **same PR branch** as the code change — don't split
them into a follow-up PR, since reviewers need to see both together.

**Re-check website sync at each review round and at the end of every work
session — not just when first authoring the PR.** Before declaring a round done
or reporting a PR clean, audit the live `website/` content against the current
state of the game and confirm nothing has drifted, including:

- **Prose** — does any page describe behaviour the PR (or an earlier merged PR
  that never updated the site) has since changed?
- **Demo videos** — the `<video>` embeds (`website/media/*.mp4`) are recorded
  fresh at deploy time, so they track code automatically; the exception is
  anything that only shows at a non-default camera (zoom/pan), which the static
  demo camera can't capture (tracked in the demo-recording follow-up). When the
  change is camera-dependent, note that the clip won't show it.
- **Screenshots / images** — any committed image embedded in a page must still
  match what the game looks like now; a visual change can make an existing
  screenshot stale even when no prose changed. Recapture it on the PR branch.

This audit covers drift from **previously merged PRs** too, not only the one in
hand — if you spot a page that an earlier change left stale, fix it on the
current PR when it's in scope, or file a follow-up issue otherwise.

## Code conventions

### Comments: no issue-number references
Don't cite issue numbers (`#123`) in code comments. The explanation itself
should stand on its own; a reader shouldn't need to open a tracker to understand
the code, and the reference rots as issues close and renumber. Issue numbers
belong in commit messages, PR descriptions, and `TODO`/`FIXME` comments (where a
`TODO(#123):` link to outstanding work is useful) — not in ordinary explanatory
comments or docstrings.

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
