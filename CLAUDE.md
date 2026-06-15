# CLAUDE.md — AI working instructions for Sparta

Orientation and standing policies for any AI session working in this repo.
Sparta is a **Godot 4.6** (GDScript, Standard build — not .NET/C#) prototype
fusing CK3-style grand strategy with Total War-style tactical battles. See
`README.md` for layout and `PLAN.md` for project vision, roadmap, architecture,
and verification steps — read `PLAN.md` first.

## Project at a glance
- Godot **4.6.x Standard** (GDScript, not C#/.NET). 2D top-down tactical battle.
- Main scene: `scenes/Battle.tscn`. Core scripts live in `scripts/`.
- Issues are tracked on this repo with `P0`–`P3` labels; `PLAN.md` mirrors the roadmap.

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
