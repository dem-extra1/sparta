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
