# Design note: unified orders queue

Status: **design — green-lit, not yet implemented.** This note consolidates the
design from #516 (and its refinement comments) into one spec, and lays out the
phased implementation plan tracked by the phase issues linked below.

The goal: model **every player-issued command as one polymorphic `Order`**, held
in a single **orders queue** on `Unit`. `current_order` (the head of the queue)
is what the unit is doing now; it drives execution and subsumes the scattered
maneuver flags that hold that state today.

## Motivation

A unit's "what is it doing / what will it do next" is currently smeared across
many ad-hoc fields:

- move target plus a separate waypoint/append list,
- `_pending_march_target`,
- the maneuver in-progress flags (`_wheel_target`, `_engage_turn_target`, the
  conversio / quarter-turn in-progress state),
- `order_mode`, `formation_mode` transitions, and more.

Three problems follow from that spread.

**No single source of truth.** Inference logic drifts from what the code
actually does. The conversio-vs-centre-pivot ambiguity that made #465 hard to
verify is a direct symptom: an about-face and a 180° centre-pivot both read as
`state: MOVING`.

**The transcript can't see the maneuver.** The machine-readable state transcript
(#500 / #501 / #507) records `state`, `formation`, `order_mode`, position,
facing, morale, and the per-soldier summary — but *not* which maneuver a unit is
executing (#515), because no field authoritatively holds it. So a correct
conversio and the exact bug it was meant to replace look identical in the dump.

**A whole class of double-apply bugs.** `Battle.gd` applies every order twice —
once immediately for zero-latency feedback, and again when the next physics tick
drains `_pending_orders` (#518). Any non-idempotent order path is corrupted by
the second apply reading state the first apply just armed. This has already
produced the move-to-rear about-face aborting mid-turn and centre-pivoting
(#517), and the arrow-nudge travelling a few pixels instead of the full
`NUDGE_DISTANCE` (#521). Wheel, file-double, and formation/spacing transitions
are all exposed to the same hazard.

Adding a new command today means threading new flags through several code paths.

## The model

### Order + orders queue + current_order

`Unit` holds an `orders` queue of `Order` values. `current_order` is the head:
the order the unit executes this tick. Completed orders leave the queue; the
next order becomes current. This replaces the move-only waypoint list and every
in-progress maneuver flag with one structure.

Queue operations preserve the gestures that exist today:

- **append** (shift-click waypoint) — add to the tail,
- **replace-current** (plain order) — clear and set head,
- **insert-next** — splice ahead of the tail,
- **clear**.

Some orders are instantaneous; some occupy the unit for N ticks. Some are
interruptible, some not. Each subtype encodes its own duration and
interruptibility.

### Verbs vs modes

The design splits cleanly into two layers.

**Orders are verbs.** They are queue entries that execute and complete: move,
wheel, attack, "form testudo".

**Modes are durable nouns.** They are persistent `Unit` state that a completed
order writes: `formation_mode`, `spacing`, `active_weapon`, `stance`. A
transition order (form testudo / change spacing / switch weapon) executes like
any other order — possibly over a transition time — and on completion writes its
mode. The mode then stays as queryable `Unit` state until a later order changes
it.

This split is what keeps the transcript honest for free: it already serializes
`state` / `formation` / `order_mode`, so it records **both** the live
order/queue **and** the resulting modes with no special-case dump code.

### Taxonomy

One queue, many subtypes. GDScript is single-inheritance `class_name`, so the
hierarchy stays shallow — a tagged-record / enum-plus-data approach may beat a
deep class tree in places (evaluate during phase 1, per the avoid-nesting
default).

| Order (verb) | Kind | Writes mode | Notes |
|---|---|---|---|
| `MoveOrder` | movement | — | carries an **execution style** (direct march / about-face-conversio / sidestep) chosen by geometry — an about-face is the execution style of a rear move, not a separate order |
| `WheelOrder` | movement | — | pivot the line about an end |
| `QuarterTurnOrder` | movement | — | 90° facing change in place |
| `FileDoubleOrder` | movement | — | deepen / widen the formation (duplicatio / explicatio) |
| `NudgeOrder` | movement | — | short sidestep / backstep, holds facing |
| `AttackOrder` | targeting | — | terminates when the target dies |
| `FormationOrder` | transition | `formation_mode` | tight / loose / square / shield-wall / testudo |
| `SpacingOrder` | transition | `spacing` | open / close order |
| `StanceOrder` | transition | `stance` | hold / cycle-charge (and the intra-unit rank-relief mode toggle — see below) |
| `SwitchWeaponOrder` | transition | `active_weapon` | future: pike↔sword, javelin↔sword |
| `RelieveUnitOrder` | targeted action | — | **inter-unit** relief: a fresh unit passes through / replaces a tired front-line ally; the order names the ally to relieve, and the response-delay + ward become the order's own execution state |

**Waypoints are absorbed, not preserved alongside.** The current waypoint/append
list *is* a proto-orders-queue for moves — a waypoint already is a queued move.
Unifying just replaces the bespoke move-only list with the general queue; the
append gesture is identical to the player. The codebase already half-built this
pattern (a move waypoint queue, then maneuvers and relief bolted on separately
as flags); the unified queue finishes it. Net: fewer moving parts after the
refactor, not more.

**Relief is two distinct behaviors — keep them separate.** Today relief runs
through `_relief_partner` links on `Unit`, managed by `UnitRelief.gd` — a single
mechanism that conflates two things we want to model differently. The order/mode
split cleaves them cleanly:

- **Inter-unit relief is an order.** One unit relieving another — a fresh unit
  passes through or replaces a tired front-line ally — is a targeted queue action
  (`RelieveUnitOrder`) that names the ally to relieve. Its response-delay and ward
  become the order's own execution state. This is definitely an order, not a mode.
- **Intra-unit rank-relief is a mode.** Individuals within a unit relieving their
  *own* unit's front line — rear ranks rotating forward to the fighting line — is
  a durable intra-unit behavior, so it belongs in the mode layer (a reactive /
  ROE-style mode toggled by a `StanceOrder`), not a queue entry. It is the same
  rank-cycle recovery that makes routs nearly unreachable in #529 — so whether
  the mode is on, and how strong its recovery is, is the knob that issue turns.

Modeling these two separately (an order for one, a mode for the other) is the
right resolution of the current single-mechanism `_relief_partner` / `UnitRelief`
relief.

**Support-ward is the one real judgement call.** "Guard unit Y until told
otherwise" may fit better as a durable *assignment mode* (like formation/stance)
than as a queue entry, or as a standing `SupportOrder`. Decide case-by-case
during phase 3.

## Composability

Orders compose at three carefully-separated levels. The first two are in; the
third is out by default.

### 1. Intra-order phasing (the core)

An `Order` carries its own choreography as internal phases — a small
deterministic state machine — not as separate queue entries. The canonical case
is the move-to-rear: **phase 1 conversio (turn in place) → phase 2 march**.

This is both the clean model and the fix for the #517 / #518 bug class. Today the
about-face and the march are dispatched as separate state mutations that race
through the immediate-plus-drain double-apply, and the second apply cancels the
conversio mid-turn. Modeled as one phased order, the phases advance once per tick
deterministically; there is no second dispatch to lose. **Composition inside a
single queue entry is both the model and the bug fix.**

### 2. Macro expansion (a thin layer)

A higher-level command expands into a *sequence of primitive orders appended to
the flat queue* — e.g. a flank maneuver → wheel, advance, attack — tagged with a
group id so cancelling the macro clears its not-yet-executed children. This gives
reuse and compound player commands **without** a persistent tree: the executed
structure stays flat, so `current_order` is always a single legible primitive in
the transcript.

### 3. No deep order-tree / behavior-tree

Avoid by default. It is more machinery than the domain needs, harder to serialize
deterministically (it undercuts the "what is it doing now" legibility that
motivates the whole design), and it cuts against the avoid-nesting default. Adopt
it only if genuinely hierarchical reactive behavior becomes a real need.

### Parallel composition is the order/mode split, not nesting

"March while in testudo" = a `MoveOrder` executing while `formation_mode =
TESTUDO`, a durable mode set by an earlier order. Concurrency lives in the mode
layer. That is precisely what keeps a nested tree from being needed.

## Conditional logic

Orders support conditional logic in three tiers, deliberately constrained so the
queue stays deterministic and transcript-legible. Arbitrary if/else is the
"deep tree" trap in another costume, and is out of the core.

### 1. Terminal conditions (explicit)

Every order already ends on a condition: move → reached target; attack → target
dead; hold → timer. Make the terminal condition a **first-class field** of the
order, not special-cased logic. This enables "advance UNTIL contact, then
attack" as `MoveOrder{terminal: contact}` → `AttackOrder`. Condition-driven queue
advancement is just the self-terminating form of the phased / macro composition
above.

### 2. Guards from a bounded, enumerated vocabulary

An order or queue slot may carry a guard — "advance to the next order WHEN
\<condition\>" — drawn from a small closed deterministic set:

`enemy-in-range`, `contact-made`, `morale-below-X`, `ally-exhausted`,
`ticks-elapsed`, `flanked`, …

This covers "hold UNTIL in range THEN fire" without free-form code. The closed
vocabulary is the guardrail: composable, not Turing-complete.

### 3. Standing conditional behavior = the mode layer

Most "conditional orders" are really rules-of-engagement / stance: HOLD ("don't
chase unless attacked"), cycle-charge / caracole (#472), "fire at will in range".
These are durable **reactive modes** that modify how orders execute — the same
layer as `formation_mode`, per the order/mode split. The existing `order_mode`
enum (`HOLD` / `CYCLE_CHARGE` / `SUPPORT` / …) is already a crude version. Do NOT
encode these as if/else inside every order.

### Out of the core: arbitrary reactive branching

"If flanked form square else advance" is a reactive AI layer *above* the queue
that reissues and reorders commands — it edits the plan; it is not an `if`
embedded in each order. Reactivity mutates a still-flat, still-deterministic
queue.

## Two invariants

Conditionals — indeed the whole design — rest on two hard constraints. Break
either and the rest falls apart.

**Determinism.** Every condition and every order is a pure function of
*serialized* sim state, evaluated in the sim step. No wall-clock, no unseeded RNG
(cf. the #497 flake). Same inputs → same branch on replay. Orders are set and
advanced deterministically in the sim step, identical on replay.

**Transcript legibility.** The dump records the active order AND its active phase
AND its pending / unmet condition — e.g. `MoveToRear: conversio` vs `MoveToRear:
march`, or `Hold: until enemy_in_range`. A phased or conditional order is
verifiable by a direct read, not by inferring intent from motion. This is
strictly better than the flat maneuver label #515 asked for, because the phase
boundary itself is visible — conversio-vs-pivot verification becomes a one-field
read.

## How the transcript records it

Because `current_order` is a real field and modes are real `Unit` state, the
transcript records the unit's plan with no special-case dump code:

- `current_order` — the head primitive (e.g. `MoveOrder`, `WheelOrder`),
- its **active phase** when phased (e.g. `MoveToRear: march`),
- its **pending terminal condition / guard** when conditional (e.g. `Hold:
  until enemy_in_range`),
- the durable **modes** (`formation_mode`, `spacing`, `active_weapon`, `stance`),
  set by completed orders and already serialized today,
- optionally the queue tail (the pending orders) for full plan legibility.

This resolves #515 as a side effect: the explicit-maneuver field it asks for is
just `current_order` plus its phase, so #515 becomes phase 1 of this work rather
than a separate bolt-on.

## Phased implementation plan

Do this phased, not big-bang. Each phase drops the flags it subsumes as it
migrates them, so the flag spread shrinks monotonically. Land after #497 (the
spring purge) so the refactor is not fighting in-flight `Unit.gd` changes.

Every phase must hold both invariants (determinism on replay; the transcript
stays legible) and must preserve every existing behavior it touches
(append/waypoint, relief, HOLD, formation transitions).

### Phase 1 — `Order` + orders queue + `current_order` (apply-once)

**Scope.** Introduce the `Order` value type, the `orders` queue on `Unit`, and
`current_order` with phase support. Make each order **apply exactly once** in the
sim step — the queue advances deterministically per tick, retiring the immediate
+ tick-drain double-apply. Wire `current_order` (+ its phase) into the
transcript.

**Subsumes.** The move-only waypoint/append list becomes the queue; #515's
explicit-maneuver field becomes `current_order` + phase.

**Resolves.** The #518 double-apply class at its root — apply-once is the whole
point. Phase 1 **coordinates with the in-flight #518 fix**: that short-term fix
is effectively this phase's apply-once slice landing first, and the queue then
formalizes it (single source of truth, one apply site). Do not duplicate the fix;
build the queue on top of it.

**Determinism / replay risks.** The apply-once cutover changes *when* an order's
effect first lands (tick boundary instead of immediately-plus-next-tick), so
existing replays and demo transcripts must be re-verified tick-by-tick, not just
by final position.

**Done-check.** Orders route through one apply site; `current_order` + phase
appear in the transcript; a scripted-input replay of an existing maneuver
produces the same body positions tick-by-tick as before (minus the spurious
second apply); the double-apply reproduction from #518 no longer fires.

### Phase 2 — migrate movement maneuvers onto the queue

**Scope.** Move `MoveOrder` (with geometry-chosen execution style),
`WheelOrder`, `QuarterTurnOrder`, `FileDoubleOrder`, and `NudgeOrder` onto the
queue. Model the move-to-rear as a phased order (conversio → march).

**Subsumes.** `_wheel_target`, `_engage_turn_target`, the conversio /
quarter-turn in-progress state, `_pending_march_target`, and the nudge state —
all dropped as each migrates.

**Resolves / verifies.** The phased move-to-rear fixes the #517 centre-pivot; the
apply-once queue plus phasing fixes the #521 nudge under-travel. Both become
tick-by-tick transcript checks.

**Determinism / replay risks.** Execution-style selection must be a pure function
of geometry and serialized state (no frame-timing dependence). Re-verify every
migrated maneuver against its recorded transcript.

**Done-check.** Each movement maneuver runs off `current_order`; the subsumed
flags are deleted; the #517 conversio holds bodies frozen through the full turn
and the #521 nudge translates the centroid by the full `NUDGE_DISTANCE`, both
confirmed in the transcript.

### Phase 3 — migrate transition orders + split relief + absorb waypoints

**Scope.** Move `FormationOrder`, `SpacingOrder`, `StanceOrder`, and
`SwitchWeaponOrder` onto the queue, each writing its durable mode on completion.
Split the current `_relief_partner` / `UnitRelief` mechanism into its two real
behaviors: **inter-unit relief** becomes a `RelieveUnitOrder` queue entry (names the ally;
response-delay + ward become the order's execution state), and **intra-unit
rank-relief** becomes a durable mode toggled by a `StanceOrder` (cross-links
#529, whose rank-cycle recovery is exactly this mode). Finish absorbing the
waypoint list. Decide support-ward: durable assignment mode vs standing
`SupportOrder`.

**Subsumes.** The `_relief_partner` / `UnitRelief` relief mechanism (split into
the order + the mode) and the ad-hoc formation/spacing/stance transition flags.

**Determinism / replay risks.** Transition timing (a formation change over N
ticks) must advance deterministically; a mode must be written exactly on
completion, not mid-transition, or replays diverge.

**Done-check.** Every transition order writes its mode on completion and appears
in the transcript as an in-flight order until then; inter-unit relief runs as a
`RelieveUnitOrder` queue entry while intra-unit rank-relief is a queryable mode;
the support-ward decision is recorded here.

### Phase 4 — terminal conditions + trigger vocabulary + ROE modes

**Scope.** Add the first-class terminal-condition field, the bounded enumerated
guard vocabulary, and the reactive ROE modes (HOLD / fire-at-will / cycle-charge)
in the mode layer. Enable "advance UNTIL contact THEN attack" and "hold UNTIL in
range THEN fire".

**Subsumes.** The crude `order_mode` HOLD behavior, promoted into a real ROE
mode.

**Determinism / replay risks.** This is the highest-risk phase for determinism:
every condition must read only serialized sim state and evaluate in the sim step.
No wall-clock, no unseeded RNG. Guard evaluation order must be fixed.

**Done-check.** Each guard in the closed vocabulary is a pure function of
serialized state; a conditional order's pending condition shows in the transcript;
a replay with conditions produces identical branch choices on re-run.

### Phase 5 — transcript records order + phase + condition (verification payoff)

**Scope.** Finish the transcript surface: `current_order`, active phase, pending
terminal condition / guard, the durable modes, and optionally the queue tail.
This is largely delivered incrementally by phases 1–4; phase 5 closes any gaps
and locks the format.

**Determinism / replay risks.** Low — read-only serialization. Guard against
non-deterministic ordering when dumping the queue.

**Done-check.** A single transcript read distinguishes conversio from centre-pivot
(the #517 verification), shows a held-until condition, and shows every durable
mode — no motion-inference needed.

## Relationship to existing issues

- **#515** (explicit current-maneuver state) — absorbed as phase 1; it becomes
  `current_order` + phase. Close it into this once phase 1 lands, or keep it as
  the phase-1 tracking issue.
- **#518** (orders applied twice) — the bug class phase 1 kills at the root. The
  in-flight #518 fix is phase 1's apply-once slice landing first.
- **#517** (move-to-rear centre-pivot) — fixed by the phased move-to-rear in
  phase 2 and verified in phase 5.
- **#521** (nudge under-travel) — fixed by apply-once + the queue in phases 1–2.
- **#529** (routs nearly unreachable — in-fight morale recovery) — the intra-unit
  rank-relief *mode* introduced in phase 3 is the same rank-cycle recovery that
  issue tracks; whether that mode is on, and how strong its recovery is, is the
  knob #529 tunes.
