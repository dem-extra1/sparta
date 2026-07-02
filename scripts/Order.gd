class_name Order
extends RefCounted
## Phase 1 of the unified orders-queue design (docs/orders-queue-design.md, #516): the `Order`
## value type. A queue entry describing one thing a `Unit` is doing or will do -- a verb, in the
## design doc's terms. Durable "mode" state (formation_mode, order_mode, stance, ...) stays on
## `Unit` itself; an Order is what writes it, not where it lives.
##
## Phase 1 is additive and parallel to the existing legacy fields (move_target, waypoints,
## target_enemy, _wheel_target, and friends): `Battle._apply_order_cmd` -- already the single
## exactly-once apply site fixed by #519 -- constructs an Order alongside its existing legacy
## mutation, and `Unit._update_current_order` (called once per `_think()` tick, read-only besides
## the Order bookkeeping itself) retires it when the legacy state it mirrors says the order is
## done. No gameplay code reads Order fields yet, so this cannot change sim behaviour or
## replay/determinism -- it only makes `current_order` a legible, transcript-visible single
## source of truth. Migrating movement execution itself onto the queue is phase 2.

## The order kinds phase 1 covers -- every order type that already has a live caller today via
## Battle's recorded/replayed order-dispatch path. Standalone drill hotkeys that stay outside
## that path (the conversio/quarter-turn V/Q keys -- see SelectionManager.gd, which documents
## why they are deliberately NOT recorded) are left out of the queue for the same reason: folding
## a non-replayed, non-deterministic-risk drill gesture into the replay-relevant queue would be
## new scope, not a wash. That migration is deferred to a later phase, if ever.
enum Type {
	MOVE,       ## March to a destination (a waypoint leg or a plain move); carries an execution
	            ## style chosen by geometry at issue time (direct march, or an about-face phase
	            ## for a rear-sector move -- see Phase below).
	ATTACK,     ## Chase and fight a specific enemy unit until it dies or the order is superseded.
	RELIEF,     ## Inter-unit relief: a fresh unit passes through/replaces a tired ally in contact.
	SUPPORT,    ## Guard a friendly ward, engaging threats near it until the ward is gone.
	WHEEL,      ## Circumductio: swing the line 90 degrees about a fixed flank file.
	NUDGE,      ## A short fixed-distance drill step (side-step or back-step), holding facing.
	FORMATION,  ## Change formation_mode (tight/loose/square/shield-wall/testudo). Instantaneous.
	FRONTAGE,   ## Resize frontage to an absolute file count (manual resize or a file-double/
	            ## file-halve maneuver -- same execution, different caller-derived target width).
	            ## Instantaneous.
}

## An order's internal choreography, for the one phase-1 case that already exists: a move into a
## unit's rear sector runs an about-face (conversio) in place, THEN marches -- two phases of one
## queue entry, not two queue entries (docs/orders-queue-design.md, "Intra-order phasing"). Every
## other order type stays NONE; the mechanism exists so a later phase can add more phased orders
## without a new Order subtype.
enum Phase {
	NONE,   ## Not phased, or a phased order that hasn't started its first phase yet.
	TURN,   ## In-place about-face running before the march (move-to-rear only).
	MARCH,  ## Marching to the destination -- the phase every other MOVE order is in throughout.
}

const TYPE_NAMES := {
	Type.MOVE: "MOVE",
	Type.ATTACK: "ATTACK",
	Type.RELIEF: "RELIEF",
	Type.SUPPORT: "SUPPORT",
	Type.WHEEL: "WHEEL",
	Type.NUDGE: "NUDGE",
	Type.FORMATION: "FORMATION",
	Type.FRONTAGE: "FRONTAGE",
}

const PHASE_NAMES := {
	Phase.NONE: "NONE",
	Phase.TURN: "TURN",
	Phase.MARCH: "MARCH",
}

var type: int = Type.MOVE
var phase: int = Phase.NONE

## Movement destination (MOVE/NUDGE); ZERO when unused.
var target_pos: Vector2 = Vector2.ZERO
## Target unit uid (ATTACK/RELIEF/SUPPORT); -1 when unused.
var target_uid: int = -1
## FORMATION target (Unit.FORMATION_* constant); -1 when unused.
var formation: int = -1
## FRONTAGE target file count; -1 when unused.
var frontage: int = -1
## WHEEL/NUDGE direction (Battle.NudgeDir for NUDGE; +-1 for WHEEL); 0 when unused.
var dir: int = 0
## The order_mode (Battle.OrderMode) the issuing command carried, for MOVE/ATTACK/SUPPORT.
var order_mode: int = 0


static func type_name(value: int) -> String:
	return TYPE_NAMES.get(value, "TYPE(%d)" % value)


static func phase_name(value: int) -> String:
	return PHASE_NAMES.get(value, "PHASE(%d)" % value)


## Readable one-line description for logs/transcripts, e.g. "MOVE:TURN" or "ATTACK".
func describe() -> String:
	if phase == Phase.NONE:
		return type_name(type)
	return "%s:%s" % [type_name(type), phase_name(phase)]


static func new_move(dest: Vector2, mode: int = 0, phased: bool = false) -> Order:
	var o := Order.new()
	o.type = Type.MOVE
	o.target_pos = dest
	o.order_mode = mode
	o.phase = Phase.TURN if phased else Phase.NONE
	return o


static func new_attack(enemy_uid: int, mode: int = 0) -> Order:
	var o := Order.new()
	o.type = Type.ATTACK
	o.target_uid = enemy_uid
	o.order_mode = mode
	return o


static func new_relief(ally_uid: int) -> Order:
	var o := Order.new()
	o.type = Type.RELIEF
	o.target_uid = ally_uid
	return o


static func new_support(ward_uid: int) -> Order:
	var o := Order.new()
	o.type = Type.SUPPORT
	o.target_uid = ward_uid
	return o


static func new_wheel(wheel_dir: int) -> Order:
	var o := Order.new()
	o.type = Type.WHEEL
	o.dir = wheel_dir
	return o


static func new_nudge(nudge_dir: int) -> Order:
	var o := Order.new()
	o.type = Type.NUDGE
	o.dir = nudge_dir
	return o


static func new_formation(formation_mode: int) -> Order:
	var o := Order.new()
	o.type = Type.FORMATION
	o.formation = formation_mode
	return o


static func new_frontage(files: int) -> Order:
	var o := Order.new()
	o.type = Type.FRONTAGE
	o.frontage = files
	return o
