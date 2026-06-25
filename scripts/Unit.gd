extends Node2D
class_name Unit
## A regiment: one selectable token with a soldier count and morale.
## Renders itself via _draw() with per-type sprite shapes: infantry kite
## shield, spearmen hoplon + spear, cavalry horse + rider.

enum State { IDLE, MOVING, FIGHTING, ROUTING, DEAD }

# Stable per-battle id (assigned by Battle.gd at spawn). Replays reference units
# by this so recorded orders survive scene reloads.
var uid: int = -1

# --- Tunable stats (set by Battle.gd when spawning) ---
@export var unit_name: String = "Spearmen"
@export var team: int = 0
@export var max_soldiers: int = 120
@export var attack: int = 12
@export var defense: int = 6
@export var move_speed: float = 90.0
@export var attack_range: float = 26.0
@export var is_cavalry: bool = false
@export var anti_cavalry: bool = false   # spearmen: blunt cavalry charges
@export var is_ranged: bool = false   # archers: loose volleys from a distance
# Seconds before the unit starts executing a new order. Models the real-world
# lag between a signal and the regiment actually stepping off. Default 0.5 s;
# faster units (cavalry) can be given a lower value at spawn time.
@export var order_response_delay: float = 0.5
# Discipline and experience level (0.0 raw recruits → 1.0 veteran legionaries).
# Well-trained melee units cycle their ranks in combat: fresh files rotate to the
# front, which reduces fatigue buildup and sustains morale through prolonged fights.
@export var training: float = 0.0:
	set(v):
		training = clampf(v, 0.0, 1.0)
		_rank_cycle_timer = RANK_CYCLE_INTERVAL if training <= 0.0 \
				else RANK_CYCLE_INTERVAL / training

# --- Runtime state ---
var soldiers: int
var morale: float = 100.0
var fatigue: float = 0.0   # 0 fresh .. 100 exhausted; rotated out by relief
var cohesion: float = 1.0   # 1.0 gelled; drops on a merge, then ramps back
var state: int = State.IDLE
var facing: Vector2 = Vector2.DOWN
var move_target: Vector2 = Vector2.ZERO
var has_move_target: bool = false
# Queued destinations after move_target: the unit marches the route in order,
# popping the next point each time it reaches the current one. Filled by
# Shift+right-click; a plain move order clears it.
var waypoints: Array[Vector2] = []
var target_enemy: Unit = null
var selected: bool = false
# Order stance, set by Battle._apply_order_cmd from the order's mode.
# Int rather than Battle.OrderMode to keep Unit decoupled; 0 == OrderMode.NORMAL.
# The smart-order behaviours read this; NORMAL is current behaviour.
var order_mode: int = 0
var formation_mode: int = FORMATION_NORMAL
# Stance values from Battle.OrderMode that Unit's own behaviour reacts to, mirrored
# as plain ints to avoid a Unit<->Battle preload cycle (kept in sync with the enum;
# Battle._ready asserts they match). NORMAL is 0 (Unit's default order_mode).
const ORDER_HOLD := 1
const ORDER_ATTACK_FLANK := 2
const ORDER_ATTACK_REAR := 3
const ORDER_SKIRMISH := 4
const ORDER_SUPPORT := 5

# Formation modes: how tightly the regiment is packed.
# TIGHT: soldiers close ranks — better missile defense (shields raised) and
#        better charge resistance, at the cost of a smaller footprint.
# NORMAL: default spacing.
# LOOSE: soldiers spread out — wider area coverage.
const FORMATION_NORMAL := 0
const FORMATION_TIGHT := 1
const FORMATION_LOOSE := 2
# In tight formation, shields reduce incoming missile damage by this fraction.
const TIGHT_MISSILE_DEFENSE: float = 0.25
# In tight formation, this fraction of a cavalry charge bonus is absorbed
# (braced soldiers brace against the impact — not a full reversal like anti-cav).
const TIGHT_CHARGE_ABSORPTION: float = 0.55
# Separation-radius scale factors per formation mode.
const TIGHT_SEPARATION_SCALE: float = 0.75
const LOOSE_SEPARATION_SCALE: float = 1.35
# Melee intermixing: how fast enemy separation dissolves when two non-hold units are
# locked in mutual combat. Rise rate is fraction per second; max is the dissolution
# ceiling (so a floor of 1-MAX always remains — spears still feel solid). Decay is 4×
# faster than rise so a unit that breaks contact re-solidifies in roughly 3 s at max
# instead of 12 s, matching the "disengages promptly" expectation.
const MELEE_INTERMIX_RATE: float = 0.07
const MELEE_INTERMIX_DECAY_RATE: float = 0.28
const MELEE_INTERMIX_MAX: float = 0.85
# Skirmish: a kiting ranged unit backs off when a threat closes inside this
# distance, instead of standing to fire. Above melee contact (~62) and below
# RANGED_RANGE (160) so there's room to fire before being caught.
const SKIRMISH_KITE_DISTANCE: float = 100.0
# Support: a unit ordered to guard a friendly "ward" engages any enemy that
# closes within SUPPORT_GUARD_RADIUS of the ward, otherwise shadows the ward,
# holding station SUPPORT_FOLLOW_DISTANCE off so it doesn't pile onto it. The guard
# radius is near DETECTION_RANGE (190) so it meets threats about as far as it would
# normally spot them; the follow distance sits just past two footprints (~36).
const SUPPORT_GUARD_RADIUS: float = 180.0
const SUPPORT_FOLLOW_DISTANCE: float = 80.0
# The friendly unit a SUPPORT order tells this one to guard (set by Battle from the
# order's target). Cleared when it dies/routs, reverting this unit to NORMAL.
var support_target: Unit = null
# Field rectangle the unit keeps inside when kiting (set by Battle on spawn). The
# default is effectively unbounded so direct Unit tests don't need to set it.
var field_bounds: Rect2 = Rect2(-100000, -100000, 200000, 200000)

const RADIUS: float = 18.0
const DETECTION_RANGE: float = 190.0
const ATTACK_INTERVAL: float = 0.6
const ROUT_TIME: float = 6.0
# Radius over which a rout shakes friendly morale. Shared by the morale-spread
# loop and the cosmetic shockwave so the visual matches the actual area of effect.
const ROUT_SHOCK_RADIUS: float = 140.0
# Rout recovery: when a unit's rout timer runs out it RALLIES — recovers to your
# control — if it has broken contact (no living enemy within RALLY_CONTACT_RADIUS) and
# still fields enough men (>= SHATTER_STRENGTH_FRAC of its max). Otherwise it SHATTERS:
# run down or gutted past reforming, it leaves play for good. A rallied unit comes back
# at RALLY_MORALE, kept low so it stays fragile and can break again.
const RALLY_CONTACT_RADIUS: float = 160.0   # = RANGED_RANGE: in archer reach = not broken contact
const RALLY_MORALE: float = 30.0
const SHATTER_STRENGTH_FRAC: float = 0.15

# Ranged combat. A ranged unit looses volleys at any enemy within
# RANGED_RANGE that isn't already in melee contact — far outreaching melee's
# ~62px contact, so archers skirmish from safety. RANGED_RANGE stays below
# DETECTION_RANGE so an auto-acquired target is always in detection too. Volleys
# fire on their own (slower) cadence and hit a touch softer per shot than melee.
const RANGED_RANGE: float = 160.0
const RANGED_INTERVAL: float = 1.0
const RANGED_DAMAGE_FACTOR: float = 0.7

# Fatigue builds while FIGHTING and recovers while resting; it bites into attack
# so rotating tired regiments out via line relief is a real tactical lever.
const FATIGUE_PER_SEC: float = 8.0
const FATIGUE_RECOVER_PER_SEC: float = 5.0
const FATIGUE_MAX_ATTACK_PENALTY: float = 0.4
# Rank cycling: well-trained melee units rotate fresh files to the front, reducing
# effective fatigue buildup. At training=1.0, buildup is halved. Ranged units don't
# cycle ranks (they fire from static lines), so the reduction only applies to melee.
const RANK_CYCLE_FATIGUE_REDUCTION: float = 0.5
# A well-trained unit also sustains its morale while fighting — the visible discipline
# of rotation keeps the formation steady. Threshold is the minimum training for any
# morale recovery to kick in; at threshold it's minimal, scaling up to full at 1.0.
const RANK_CYCLE_MORALE_THRESHOLD: float = 0.5
const RANK_CYCLE_MORALE_PER_SEC: float = 1.2

# Morale recovers slowly when a unit is not engaged in combat, rewarding
# players who pull battered regiments back from the line to rest.
const MORALE_RECOVER_PER_SEC: float = 2.0

# Merging two regiments starts the result with a "strangers" cohesion debuff
# (scales attack) that ramps back to full as the merged unit gels.
const MERGE_COHESION_FLOOR: float = 0.6
const COHESION_RECOVER_PER_SEC: float = 0.1

# Per-type collision footprint: the center-to-center separation floor used in
# _separate(). RADIUS stays the visual/contact size; this is purely the body
# width for crowding, assigned per type in _ready(). Each stays below attack
# reach (attack_range + RADIUS) so units still press into melee contact instead
# of bouncing apart. Cavalry are bulkier; spearmen a touch wider than infantry.
const SEPARATION_RADIUS_INFANTRY: float = 18.0
const SEPARATION_RADIUS_SPEARMEN: float = 20.0
const SEPARATION_RADIUS_CAVALRY: float = 24.0
# Hard ceiling on a footprint (merging widens it). Two maxed units have a
# floor of 2*28 = 56, still under melee reach (attack_range 26 + RADIUS 18 +
# RADIUS 18 = 62), so even merged mega-units keep pressing into contact.
const SEPARATION_RADIUS_MAX: float = 28.0

# Cavalry charge: a physics-based bonus, not a one-shot token. The damage
# multiplier scales with the rider's IMPACT VELOCITY at the moment of contact — the
# component of its approach velocity aimed straight at the target — so both closing
# speed and angle matter. Calibrated so a full-speed head-on gallop (~a cavalry's
# move_speed) lands roughly the old flat +0.8 (x1.8 damage); a shallow angle or a
# near-stationary unit (e.g. a shadowing supporter) earns proportionally less,
# down to nothing. Deterministic (positions + move_speed only) so replays stay exact.
const CHARGE_BONUS_AT_REF_SPEED: float = 0.8
# Reference closing speed at which a head-on charge yields the full bonus above. An
# independent balance knob, NOT a hard link to Battle: it's set near a typical cavalry
# gallop (~96 = base 160 * Battle.SPEED_SCALE 0.6) so a full charge ~matches the prior
# flat x1.8, but it's a plain literal on purpose — deriving it from Battle.SPEED_SCALE
# would reintroduce the Unit<->Battle preload cycle this file avoids elsewhere. Changing
# cavalry speed just rescales the charge (faster hits harder, by design); nothing breaks.
# The bonus always scales with the unit's own gallop (speed_toward <= move_speed): a
# cavalry at the reference speed peaks at the reference x1.8, and a faster one exceeds it
# on purpose — that's intended scaling, not a cap to enforce (so no assert pins it).
const CHARGE_REFERENCE_SPEED: float = 96.0
# Anti-cavalry spearmen brace and turn the charge against the rider: the momentum
# becomes a speed-scaled PENALTY (impaling yourself at a gallop hurts) instead of a
# bonus, floored so even a full charge into spears never drops below the old x0.6.
const ANTI_CAV_CHARGE_BACKFIRE: float = 0.5
const ANTI_CAV_CHARGE_FLOOR: float = 0.6

var _attack_cd: float = 0.0
var _rout_timer: float = 0.0
# Counts down after a new order is received; the unit holds its current action
# until this reaches zero. A fighting unit ticks it down but is not gated by it
# (it keeps executing _think() — retargets, disengages, and support orders all
# take effect immediately regardless of the timer).
var _order_response_timer: float = 0.0
var _moved_last_frame: bool = false
# Velocity the unit carried into its last move; the cavalry charge bonus reads it
# at contact. Spent by _strike (so only the contact strike charges, not the grinding
# strikes after) and cleared when the unit goes idle/holds (a stationary unit carries no
# momentum); kept while FIGHTING so a strike delayed by attack cooldown still lands it.
var _approach_velocity: Vector2 = Vector2.ZERO
var _relief_partner: Unit = null   # unit we're swapping with mid-relief
var team_color: Color = Color.WHITE
# Collision footprint for _separate(); assigned per type in _ready().
var separation_radius: float = SEPARATION_RADIUS_INFANTRY
# The merge-aware "base" footprint at Normal formation — updated on spawn and
# whenever absorb() widens separation_radius. set_formation(NORMAL) restores to
# this rather than to the raw type constant, so a merged unit doesn't silently
# lose its widened body on a formation cycle.
var _base_separation_radius: float = SEPARATION_RADIUS_INFANTRY
# Rises while this unit is locked in mutual melee (both FIGHTING, neither HOLD).
# Scales down the separation push vs. matched enemies so units gradually intermix.
var _combat_intermixing: float = 0.0

# --- Cosmetic soldier flocking state (Stage B) -------------------------
# Per-mark render positions/velocities in the unit's (unrotated) local frame. Cosmetic
# only — never read by the sim. _soldier_pos[i] is where mark i is drawn; it chases its
# rotated, jittered formation slot via _flock_step().
var _soldier_pos: PackedVector2Array = PackedVector2Array()
var _soldier_vel: PackedVector2Array = PackedVector2Array()
var _flock_settled: bool = false        # true once every mark is on its slot and at rest
var _combat_clock: float = 0.0          # render-time clock driving the melee churn (Stage C)
var _rank_cycle_timer: float = 0.0      # counts down to the next rank-cycle signal (Stage D)
var _rank_cycle_slot_offset: int = 0    # accumulated slot rotation; mark i targets slot (i+offset)%n
var _rank_cycle_anim: float = 1.0       # 0.0 = signal just fired, rises to 1.0 as animation settles
var _flock_last_pos: Vector2 = Vector2.ZERO     # unit position last flock frame (for trail shove)
var _flock_last_facing: Vector2 = Vector2.DOWN  # unit facing last flock frame (for wheel detection)
var _flock_color: Color = Color(0, 0, 0, 0)     # last body modulate applied to the marks
var _block_extent: float = RADIUS       # block half-size; sizes the ring/halo/bars/shadow
var _mm_body: MultiMesh = null
var _mm_outline: MultiMesh = null
var _mmi_body: MultiMeshInstance2D = null
var _mmi_outline: MultiMeshInstance2D = null
var _shadow: Polygon2D = null
# Meshes are shared across all units (foot/cav marks come in two sizes each —
# a body mesh and a slightly larger outline mesh), built once on demand.
static var _mesh_cache: Dictionary = {}


func _ready() -> void:
	soldiers = max_soldiers
	team_color = Color("4a7fd6") if team == 0 else Color("d65a4a")
	separation_radius = _type_separation_radius()
	_base_separation_radius = separation_radius
	add_to_group("units")
	# Layer budget: field=0, then this unit's cosmetic stack sits 1..3 — shadow (eff 1),
	# marks (eff 2), chrome (this _draw, eff 3) — all below the z=4 rout shockwave / z=5
	# volley trails / z=100 selection box. The marks/shadow are child nodes (MultiMeshes /
	# Polygon2D) layered just under this node via their relative z_index (Stage B).
	z_index = 3
	_setup_flock_renderer()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	if state == State.ROUTING:
		_process_rout(delta)
		if state != State.DEAD:   # timer expired: rallied (IDLE) or shattered (DEAD -> freed)
			_separate()   # routers still shoulder past anyone in their path
		return

	_attack_cd = max(0.0, _attack_cd - delta)
	_moved_last_frame = false

	_think(delta)
	_tick_intermixing(delta)

	# Units are solid: resolve any overlap so an advancing regiment can't
	# walk straight through (or over) the one in front of it.
	_separate()

	tick_fatigue(delta)
	tick_cohesion(delta)
	tick_morale(delta)
	_update_relief()

	# A stationary, non-fighting unit carries no momentum: drop any leftover approach
	# velocity so a later standing strike can't charge off it. While FIGHTING we
	# keep it — a strike held back by attack cooldown on the contact frame still charges
	# on the next — and _strike spends it, so grinding strikes after the first don't.
	if not _moved_last_frame and state != State.FIGHTING:
		_approach_velocity = Vector2.ZERO

	# Phase 1 (flag-gated, off by default): keep the parallel soldier-body layer
	# seeded from the regiment's settled position this tick. No gameplay effect —
	# nothing reads _sim_soldier_pos yet. See docs/individual-collision-design.md.
	if INDIVIDUAL_COLLISION:
		seed_sim_soldiers()

	queue_redraw()


## Decide what to do this frame: fight if in contact, otherwise move.
func _think(delta: float) -> void:
	# Order-response delay: tick down on every frame. Non-fighting units are frozen
	# until the timer expires; fighting units are not gated — they keep executing
	# _think() normally, so a disengage or retarget order issued mid-combat takes
	# effect on the same frame, not after the delay. When the timer hits 0 this
	# tick, fall through so motion starts immediately rather than waiting an
	# extra frame.
	if _order_response_timer > 0.0:
		_order_response_timer = maxf(0.0, _order_response_timer - delta)
		if _order_response_timer > 0.0 and state != State.FIGHTING:
			return

	# Support stance: guard a friendly ward — engage threats near it, else
	# shadow it. Handled up front so it overrides the normal target/move logic. If
	# the ward is gone (dead, routed, or cleared) the order is spent, so drop it and
	# fall through to NORMAL auto-behaviour.
	if order_mode == ORDER_SUPPORT:
		if _support_valid():
			_support_tick(delta)
			return
		support_target = null
		order_mode = 0   # ward gone: revert to NORMAL

	var enemy: Unit = _current_target()
	if enemy != null:
		var dist: float = position.distance_to(enemy.position)
		var in_contact: bool = dist <= attack_range + RADIUS + enemy.RADIUS
		# Skirmish: a ranged unit kites — if a threat is inside the kite
		# distance it backs off (away from the threat, clamped to the field) rather
		# than standing to fire or being caught in melee; beyond it, it falls through
		# to the normal ranged fire below. Gated by the same "not disengaging" rule
		# as firing, so a plain move order still marches it off instead of kiting.
		if is_ranged and order_mode == ORDER_SKIRMISH and dist < SKIRMISH_KITE_DISTANCE \
				and (target_enemy != null or not has_move_target):
			var away: Vector2 = position - enemy.position
			if away.length() < 0.001:
				away = Vector2.UP if team == 0 else Vector2.DOWN   # degenerate: own back edge
			_move_to(_clamp_to_field(position + away.normalized() * SKIRMISH_KITE_DISTANCE), delta)
			# Only commit to the retreat if it actually moved. If the unit is cornered
			# against the field edge (clamp snapped the target onto its position),
			# fall through to the fire/melee branches so it still shoots instead of
			# standing idle.
			if _moved_last_frame:
				return
		# Ranged units stand and loose volleys at any enemy inside RANGED_RANGE
		# that hasn't closed to melee — they skirmish at distance instead of charging.
		# Gated by the same "not disengaging" rule as melee: a plain move order with
		# no explicit attack target marches them off rather than rooting them to fire.
		if is_ranged and not in_contact and dist <= RANGED_RANGE \
				and (target_enemy != null or not has_move_target):
			state = State.FIGHTING
			_face(enemy.position)
			if _attack_cd <= 0.0:
				_attack_cd = RANGED_INTERVAL
				_shoot(enemy)
			return
		# Fight when in contact, UNLESS the player gave a plain move order with no
		# explicit attack target — that's a disengage command, so march off and let
		# the unit break contact. (Pulling out exposes the rear; the enemy chasing
		# it strikes for the ×2 flank bonus, which is the cost of disengaging.)
		if in_contact and (target_enemy != null or not has_move_target):
			state = State.FIGHTING
			_face(enemy.position)
			if _attack_cd <= 0.0:
				_attack_cd = ATTACK_INTERVAL
				_strike(enemy)
			return
		elif target_enemy != null:
			# Explicit attack order, not yet in contact: chase past any move target.
			# A flank/rear stance closes on the enemy's side or back instead of
			# head-on, so the strike on arrival lands with the flank/rear bonus.
			var goal: Vector2 = enemy.position
			if order_mode == ORDER_ATTACK_FLANK or order_mode == ORDER_ATTACK_REAR:
				goal = _attack_approach_point(enemy)
			_move_to(goal, delta)
			return

	# Obey a move order (disengaging if needed), else auto-advance on a near enemy.
	if has_move_target:
		if position.distance_to(move_target) > 5.0:
			_move_to(move_target, delta)
		elif not waypoints.is_empty():
			move_target = waypoints.pop_front()   # advance along the queued route
		else:
			has_move_target = false
			state = State.IDLE
	elif enemy != null and order_mode != ORDER_HOLD:
		_move_to(enemy.position, delta)
	else:
		# Idle: no enemy, or a HOLD stance that won't chase — the paths above
		# still fight/fire whatever reaches a held unit.
		state = State.IDLE


# --- Targeting -------------------------------------------------------------

func _current_target() -> Unit:
	if target_enemy != null and is_instance_valid(target_enemy) and target_enemy.state != State.DEAD and target_enemy.state != State.ROUTING:
		return target_enemy
	target_enemy = null
	return _nearest_enemy()


func _nearest_enemy() -> Unit:
	return _nearest_enemy_to(position, DETECTION_RANGE)


## Nearest living, non-routing enemy within `radius` of `center`. Backs both normal
## auto-acquisition (centred on this unit, DETECTION_RANGE) and the support stance,
## which scans around the WARD's position so a supporter meets threats
## closing on its charge rather than only ones near itself.
func _nearest_enemy_to(center: Vector2, radius: float) -> Unit:
	var best: Unit = null
	var best_d: float = radius
	for u in get_tree().get_nodes_in_group("units"):
		var other: Unit = u as Unit
		if other == null or other.team == team:
			continue
		if other.state == State.DEAD or other.state == State.ROUTING:
			continue
		var d: float = center.distance_to(other.position)
		if d < best_d:
			best_d = d
			best = other
	return best


## Whether this unit's SUPPORT order still has a valid ward to guard: a
## living, non-routing friendly that isn't this unit itself.
func _support_valid() -> bool:
	return support_target != null and is_instance_valid(support_target) \
		and support_target != self \
		and support_target.state != State.DEAD \
		and support_target.state != State.ROUTING


## Support stance: guard the ward. If an enemy has closed within
## SUPPORT_GUARD_RADIUS of the ward, peel off and engage it (firing at standoff if
## ranged, melee in contact, else closing on it); otherwise shadow the ward,
## holding a short standoff so the supporter doesn't pile onto the unit it guards.
## Targeting keys off the WARD's position, so the supporter returns to its charge
## once a threat is dealt with. Deterministic (no RNG / wall-clock), matching the
## normal fire/melee cadence so live and replayed battles stay in lockstep.
func _support_tick(delta: float) -> void:
	var ward: Unit = support_target
	var threat: Unit = _nearest_enemy_to(ward.position, SUPPORT_GUARD_RADIUS)
	if threat != null:
		var dist: float = position.distance_to(threat.position)
		var in_contact: bool = dist <= attack_range + RADIUS + threat.RADIUS
		if is_ranged and not in_contact and dist <= RANGED_RANGE:
			state = State.FIGHTING
			_face(threat.position)
			if _attack_cd <= 0.0:
				_attack_cd = RANGED_INTERVAL
				_shoot(threat)
		elif in_contact:
			state = State.FIGHTING
			_face(threat.position)
			if _attack_cd <= 0.0:
				_attack_cd = ATTACK_INTERVAL
				_strike(threat)
		else:
			_move_to(threat.position, delta)
		return
	# No threat near the ward: shadow it, holding station a short distance off so
	# the supporter doesn't crowd the unit it's guarding.
	if position.distance_to(ward.position) > SUPPORT_FOLLOW_DISTANCE:
		_move_to(ward.position, delta)
	else:
		state = State.IDLE


## Approach point for a flank/rear attack: a spot at melee-contact distance
## on the enemy's flank or rear, relative to its facing, so closing on it brings
## this unit alongside/behind the target and its strike lands with the flank/rear
## bonus. Recomputed each tick from sim state, so it tracks a turning or moving
## target and stays deterministic (no RNG / wall-clock). Flank picks whichever
## side this unit is already nearer, so it doesn't wrap around unnecessarily.
func _attack_approach_point(enemy: Unit) -> Vector2:
	var contact: float = attack_range + RADIUS + enemy.RADIUS
	if order_mode == ORDER_ATTACK_REAR:
		return enemy.position - enemy.facing * contact
	var perp := Vector2(-enemy.facing.y, enemy.facing.x)
	# Tie-break: an attacker exactly on the enemy's fore/aft axis (dot == 0) goes to
	# the enemy's perp side (its left), deterministically rather than NaN/oscillating.
	var side: float = 1.0 if (position - enemy.position).dot(perp) >= 0.0 else -1.0
	return enemy.position + perp * (side * contact)


## Keep a point inside the playable field (used when a skirmisher kites), so
## a retreating unit doesn't back off the map edge.
func _clamp_to_field(p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x, field_bounds.position.x, field_bounds.end.x),
		clampf(p.y, field_bounds.position.y, field_bounds.end.y))


# --- Movement --------------------------------------------------------------

func _move_to(point: Vector2, delta: float) -> void:
	# Route around terrain via the pathfinding layer when one is active; with no
	# obstacles registered the next step is the target itself (straight line).
	var step: Vector2 = point
	var terrain_speed: float = 1.0
	if PathField.active != null:
		step = PathField.active.next_step(position, point)
		terrain_speed = PathField.active.speed_at(position)
	var to: Vector2 = step - position
	if to.length() < 1.0:
		return
	var dir: Vector2 = to.normalized()
	var effective_speed: float = move_speed * terrain_speed
	_face_dir(dir)
	position += dir * effective_speed * delta
	state = State.MOVING
	_moved_last_frame = true
	# Charge velocity; terrain-scaled so forest reduces the charge bonus (intentional — can't sprint in trees).
	_approach_velocity = dir * effective_speed


func _face(point: Vector2) -> void:
	_face_dir(point - position)


func _face_dir(dir: Vector2) -> void:
	if dir.length() > 0.01:
		facing = dir.normalized()


## Collision footprint by unit type. Cavalry get the widest body, spearmen a bit
## wider than infantry; all stay below attack reach so melee still presses.
func _type_separation_radius() -> float:
	if is_cavalry:
		return SEPARATION_RADIUS_CAVALRY
	if anti_cavalry:
		return SEPARATION_RADIUS_SPEARMEN
	return SEPARATION_RADIUS_INFANTRY


## Change the regiment's formation and recalculate its separation footprint.
## Uses _base_separation_radius (which absorb() keeps updated) so a formation
## cycle on a merged unit doesn't discard the merge-widened body.
func set_formation(mode: int) -> void:
	formation_mode = mode
	var base := _base_separation_radius
	if mode == FORMATION_TIGHT:
		separation_radius = base * TIGHT_SEPARATION_SCALE
	elif mode == FORMATION_LOOSE:
		separation_radius = minf(SEPARATION_RADIUS_MAX, base * LOOSE_SEPARATION_SCALE)
	else:
		separation_radius = base


## Multiplier applied to incoming ranged damage. Tight formation: shields raised,
## reducing missile casualties. Normal/loose: no modifier.
func missile_defense_factor() -> float:
	return 1.0 - TIGHT_MISSILE_DEFENSE if formation_mode == FORMATION_TIGHT else 1.0


## Push out of any overlapping unit so regiments form a solid line instead of
## passing through each other. Each pair shares the correction half each by
## default; an anti-cavalry spearman yields nothing to enemy cavalry (a hard
## block — see _push_share). Since units move sequentially (each only moves
## itself), one frame reduces an overlap by ~75%; it converges within a few frames.
func _separate() -> void:
	if state == State.DEAD:
		return
	# Consider living units and routers alike: nobody gets walked through.
	for o in _separation_candidates():
		var other: Unit = o as Unit
		# DEAD: queue_free'd but not yet removed from its group this frame.
		if other == null or other == self or other.state == State.DEAD:
			continue
		# A moving unit and an idle friendly pass cleanly through each other.
		if _separation_exempt(other):
			continue
		var min_dist: float = separation_radius + other.separation_radius
		if _is_melee_intermixing_with(other):
			var dissolve := minf(_combat_intermixing, other._combat_intermixing)
			min_dist *= (1.0 - dissolve)
		var offset: Vector2 = position - other.position
		var d: float = offset.length()
		if d >= min_dist:
			continue
		# Share of the correction this unit takes: 0.5 soft (the pair splits it),
		# but a spear line holds firm against enemy cavalry — 0 for the spearman,
		# 1 for the horse — so cavalry can't ride through a screen (hard block).
		var share: float = _push_share(other)
		var push: Vector2
		if d > 0.01:
			push = offset / d * ((min_dist - d) * share)
		else:
			# Exactly co-located: both units of the pair derive the SAME angle
			# (from the lower stable uid, for determinism) and push in OPPOSITE
			# directions, so they reliably fan apart instead of drifting
			# together. Using each unit's own id here would push near-adjacent
			# ids in almost the same direction and never separate them.
			#
			# Key off uid, NOT get_instance_id(): instance ids are assigned per
			# launch and differ between a live run and its replay, which would
			# desync co-located pushes. uid is the stable per-battle id. posmod
			# buckets the unspawned default (-1) into a valid 0..99 angle slot.
			# The push SIGN also comes from uid, except when both share a uid
			# (e.g. two unspawned test units, both -1): there's no stable order to
			# break the tie, so fall back to instance id for the sign alone — it's
			# always distinct, so the pair still fans apart instead of stacking.
			var lo: int = mini(uid, other.uid)
			var angle: float = float(posmod(lo, 100)) / 100.0 * TAU
			var dir: float
			if uid != other.uid:
				dir = 1.0 if uid > other.uid else -1.0
			else:
				dir = 1.0 if get_instance_id() > other.get_instance_id() else -1.0
			push = Vector2.RIGHT.rotated(angle) * dir * (min_dist * share)
		position += push


## Advance or decay this unit's intermixing meter. Rises while a non-ranged unit is
## actively fighting without a hold order; decays at 4x speed when not fighting.
func _tick_intermixing(delta: float) -> void:
	if state == State.FIGHTING and order_mode != ORDER_HOLD and not is_ranged:
		_combat_intermixing = minf(MELEE_INTERMIX_MAX,
				_combat_intermixing + MELEE_INTERMIX_RATE * delta)
	else:
		_combat_intermixing = maxf(0.0,
				_combat_intermixing - MELEE_INTERMIX_DECAY_RATE * delta)


## True when mutual melee intermixing should soften the separation push between
## this unit and `other`. Both must be actively fighting without a hold order.
func _is_melee_intermixing_with(other: Unit) -> bool:
	if other.team == team:
		return false
	return state == State.FIGHTING \
			and other.state == State.FIGHTING \
			and order_mode != ORDER_HOLD \
			and other.order_mode != ORDER_HOLD


# --- Individual-soldier simulation (phase 1: flag-gated scaffold) ----------
# Promotes soldiers from the cosmetic flock (render-only, local-space
# `_soldier_pos`) toward deterministic, world-space SIMULATED bodies, seeded
# from the regiment's formation slots. Phase 1 builds the layer and its stable
# ids in PARALLEL with the authoritative regiment circle and changes no
# gameplay: nothing in combat, movement, morale, or `_separate()` reads
# `_sim_soldier_pos`, and the per-tick seeding only runs when the feature flag
# is on (off by default), so the simulation is unchanged. The full migration
# plan is in docs/individual-collision-design.md.

# Off until the soldier layer becomes authoritative in a later phase. While off,
# the parallel seeding in _physics_process is skipped and the sim is unchanged.
const INDIVIDUAL_COLLISION: bool = false

# A soldier's global id is `uid * SOLDIER_ID_STRIDE + index`: a unique,
# replay-stable key per soldier for ordering and tie-breaks, stable even as a
# regiment loses soldiers. The stride exceeds any plausible max_soldiers
# (default 120), so two regiments' id ranges never overlap.
const SOLDIER_ID_STRIDE: int = 1024

# World-space positions of this regiment's simulated soldiers, index-aligned
# with their ids. Distinct from the cosmetic, local-space `_soldier_pos`.
var _sim_soldier_pos: PackedVector2Array = PackedVector2Array()


## Stable, globally-unique id for soldier `index` in this regiment. Pure — a
## function of the regiment uid and the index — so it survives across ticks and
## reproduces exactly on replay. Keys off `uid`, not `get_instance_id()`, for the
## same reason `_separate()` does: instance ids differ between a run and its replay.
func soldier_id(index: int) -> int:
	return uid * SOLDIER_ID_STRIDE + index


## World-space formation slots for `count` soldiers: the local formation grid
## (front rank toward the unit's facing) rotated by the facing and offset to the
## regiment position. Pure of RNG and frame timing — a deterministic function of
## (count, position, facing) — so it reproduces exactly on replay and is
## unit-testable. Reuses the render's slot grid and facing convention, minus the
## cosmetic jitter, so the sim layer stays exactly reproducible.
func soldier_world_slots(count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var slots := _formation_slots(count)
	var ang: float = facing.angle() + PI * 0.5
	for i in range(slots.size()):
		out.push_back(position + slots[i].rotated(ang))
	return out


## Half-extent of the seeded soldier block around the regiment center: the
## containment radius the parallel layer must stay within while the regiment
## circle is authoritative. Reuses the render's block-extent math.
func soldier_block_extent() -> float:
	return _compute_extent(_formation_slots(soldiers))


## Seed the parallel soldier-body layer from the current formation. Deterministic
## and side-effect-free beyond `_sim_soldier_pos`. Phase 1 only — not yet read by
## the simulation.
func seed_sim_soldiers() -> void:
	_sim_soldier_pos = soldier_world_slots(soldiers)


# --- Order summary (for the HUD / selection overlay) -----------------------

## Human-readable description of this unit's current order — what the player
## told it to do (attack a target, move to a point) or, failing an explicit
## order, what it's doing on its own. Shown in the HUD's selected-unit panel.
func order_summary() -> String:
	if state == State.ROUTING:
		return "Routing!"
	# A SUPPORT order is reported by its ward, ahead of the target/move lookups
	# below — a supporter holds no target_enemy/move_target of its own.
	if order_mode == ORDER_SUPPORT and _support_valid():
		return "Supporting %s" % support_target.unit_name
	# A just-killed unit lingers one frame before queue_free() prunes it, and may
	# still hold a stale target_enemy. Skip the order lookups for it (and for an
	# idle unit) and fall through to the neutral "holding" text below.
	if state != State.DEAD:
		var has_target: bool = target_enemy != null and is_instance_valid(target_enemy) \
				and target_enemy.state != State.DEAD and target_enemy.state != State.ROUTING
		if has_target:
			return "Attacking %s" % target_enemy.unit_name
		if has_move_target:
			var dest: String = "Moving to (%d, %d)" % [int(round(move_target.x)), int(round(move_target.y))]
			if not waypoints.is_empty():
				dest += " (+%d waypoint%s)" % [waypoints.size(), "" if waypoints.size() == 1 else "s"]
			return dest
		if state == State.FIGHTING:
			return "Engaged"
		if state == State.MOVING:
			return "Advancing on enemy"
	return "Holding position"


## Human-readable formation name for the HUD.
func formation_summary() -> String:
	match formation_mode:
		FORMATION_TIGHT:
			return "Tight"
		FORMATION_LOOSE:
			return "Loose"
		_:
			return "Normal"


## Shared "collision-exemption" primitive: a moving unit may pass cleanly through
## an IDLE friendly (and vice versa), so the pair interpenetrates instead of
## shoving. Re-enables on its own once the mover stops (both IDLE) or the friendly
## moves off. Enemies are never exempt; two non-idle friendlies are not exempt;
## routers (a separate state/group) are never exempt and still get shouldered.
## Line relief and merging build on this same exemption.
func _separation_exempt(other: Unit) -> bool:
	if other == _relief_partner:
		return true   # the swapping pair interpenetrates during a relief
	if other.team != team:
		return false
	# FIGHTING and ROUTING are implicitly non-exempt (neither is IDLE/MOVING), so
	# only a moving unit and a stationary idle friendly pass through each other.
	return (state == State.MOVING and other.state == State.IDLE) \
		or (state == State.IDLE and other.state == State.MOVING)


## This unit's share of a separation correction. Normally a pair splits it 50/50
## (soft separation). But an anti-cavalry spearman HOLDS THE LINE against enemy
## cavalry: the spearman yields nothing (0) and the charging horse is shoved fully
## clear (1), so cavalry can't ride through a spear screen. The total correction
## still sums to 1.0, so separation speed is unchanged — only who yields differs.
## Friendly pairs and every other enemy matchup stay soft (0.5).
func _push_share(other: Unit) -> float:
	if other.team == team:
		return 0.5
	if anti_cavalry and not is_cavalry and other.is_cavalry:
		return 0.0   # spearman holds firm against the charging cavalry
	if is_cavalry and other.anti_cavalry and not other.is_cavalry:
		return 1.0   # cavalry is shoved fully clear of the spear line
	return 0.5


## Neighbours to test for overlap. Uses the per-frame spatial hash that Battle
## rebuilds at the start of each tick (a local 3x3-block lookup, O(k) in the
## neighbourhood rather than O(n) over all units); falls back to a full
## units+routers group scan when no grid is current for this frame — e.g. a unit
## test that calls _separate() directly with no Battle running.
func _separation_candidates() -> Array:
	if SpatialHash.is_current(Engine.get_physics_frames()):
		return SpatialHash.query(position)
	var all: Array = get_tree().get_nodes_in_group("units")
	all.append_array(get_tree().get_nodes_in_group("routers"))
	return all


# --- Combat ----------------------------------------------------------------

## Physics-based cavalry charge multiplier: the bonus is the rider's IMPACT
## MOMENTUM, not a one-shot token. It scales with the component of the unit's approach
## velocity aimed straight at the target — so a fast, head-on gallop lands the full
## bonus, a shallow/glancing approach lands less, and a near-stationary unit (a unit
## grinding in melee, or a shadowing supporter) lands none. Cavalry only, and not
## against other cavalry. Anti-cavalry spearmen brace and turn it into a speed-scaled
## penalty (charging onto set spears backfires) — so a cavalry unit that ISN'T moving
## carries no momentum and fights spearmen at x1.0, neither charging nor impaling itself
## (intended; the old model applied a flat first-strike x0.6 even when stationary).
## Deterministic — derived from positions and move_speed, which live play and replay
## reach identically — so replays stay exact.
func charge_multiplier(enemy: Unit) -> float:
	if not is_cavalry or enemy.is_cavalry:
		return 1.0
	var to_target: Vector2 = enemy.position - position
	if to_target.length() < 0.001:
		return 1.0
	# Speed directed at the target (combines closing speed and angle, relative to it).
	var speed_toward: float = maxf(0.0, _approach_velocity.dot(to_target.normalized()))
	var charge: float = CHARGE_BONUS_AT_REF_SPEED * (speed_toward / CHARGE_REFERENCE_SPEED)
	if enemy.anti_cavalry:
		# A braced spear line reverses the charge into a penalty that grows with the
		# closing speed, floored so it never drops below the old flat x0.6.
		return maxf(ANTI_CAV_CHARGE_FLOOR, 1.0 - charge * ANTI_CAV_CHARGE_BACKFIRE)
	# Tight formation: soldiers brace for impact, absorbing a fraction of the
	# charge bonus (but not reversing it — that's the spearmen's specialty).
	if enemy.formation_mode == FORMATION_TIGHT:
		return 1.0 + charge * (1.0 - TIGHT_CHARGE_ABSORPTION)
	return 1.0 + charge


func _strike(enemy: Unit) -> void:
	# Tired troops hit softer; a freshly-merged unit hits softer still until it
	# gels. Both scale effective attack before defence.
	var eff_attack: float = float(attack) * fatigue_attack_factor() * cohesion
	var base: float = maxf(1.0, eff_attack - float(enemy.defense))
	# Draw from the seeded replay RNG (one stream, stable order) so battles are
	# reproducible. This is the simulation's only source of randomness.
	var dmg: float = base * Replay.rng.randf_range(0.6, 1.4)

	# Cavalry charge: a momentum-scaled bonus (or a backfire onto braced spears),
	# computed from the rider's impact velocity at this contact. Spend it so the
	# charge lands only on this first, contact-making strike — not the grinding strikes
	# that follow in the same melee.
	dmg *= charge_multiplier(enemy)
	_approach_velocity = Vector2.ZERO

	Sfx.play(&"hit")   # presentation only; throttled in Sfx so a line doesn't roar
	enemy.take_casualties(int(round(dmg)), self)


## A ranged volley: like a melee strike without the cavalry charge, scaled
## by RANGED_DAMAGE_FACTOR — archers trade per-hit punch for striking from beyond
## melee reach. Draws from the same seeded RNG stream so battles stay reproducible.
## Damage flows through take_casualties, so volleys inherit the same flank/rear
## multiplier as melee (relative to the TARGET's facing): fire into a flank or
## rear deals the full 1.5x / 2.0x bonus, so archers in a pincer hit notably
## harder than head-on.
func _shoot(enemy: Unit) -> void:
	# RNG consumed first so the seeded stream stays deterministic regardless of
	# which unit is ultimately hit.
	var rng_roll: float = Replay.rng.randf_range(0.6, 1.4)
	var interceptor: Unit = _friendly_interceptor(enemy)
	var target: Unit = enemy if interceptor == null else interceptor
	var eff_attack: float = float(attack) * fatigue_attack_factor() * cohesion
	var base: float = maxf(1.0, eff_attack - float(target.defense))
	var dmg: float = base * RANGED_DAMAGE_FACTOR * rng_roll * target.missile_defense_factor()
	Sfx.play(&"shoot")
	# Cosmetic volley trail: arrows streak toward whoever was actually hit, so the
	# player can see why a friendly is taking damage. Spawned on the (deterministic)
	# sim tick but animated/faded on render time — no effect on replays.
	if is_inside_tree():
		VolleyTrail.spawn(get_parent(), global_position, target.global_position, team_color)
	target.take_casualties(int(round(dmg)), self)


## Return the nearest living friendly unit that lies in the straight-line flight
## path from this unit toward `target`, or null if the path is clear. A friendly
## blocks a shot when their centre is within their own separation_radius of the
## flight line AND the closest point on that line is strictly between shooter and
## target (projection in [0.05, 0.95]).
func _friendly_interceptor(target: Unit) -> Unit:
	var seg: Vector2 = target.position - position
	var seg_len_sq: float = seg.length_squared()
	if seg_len_sq < 0.001:
		return null
	var closest: Unit = null
	var closest_proj: float = INF
	for u_node in get_tree().get_nodes_in_group("units"):
		var u: Unit = u_node as Unit
		if u == null or u == self or u.team != team or u.state == State.DEAD:
			continue
		var proj: float = (u.position - position).dot(seg) / seg_len_sq
		if proj < 0.05 or proj > 0.95:
			continue
		var foot: Vector2 = position + seg * proj
		if (u.position - foot).length() < u.separation_radius and proj < closest_proj:
			closest = u
			closest_proj = proj
	return closest


## Called by an attacker. Applies flanking from THIS unit's facing.
func take_casualties(amount: int, attacker: Unit) -> void:
	if state == State.DEAD or state == State.ROUTING:
		return

	var flank: float = _flank_multiplier(attacker)
	var total: int = max(1, int(round(amount * flank)))
	soldiers -= total

	# Morale erodes from losses, worse when hit in the flank/rear.
	morale -= float(total) * 0.12 * flank
	var ratio: float = float(soldiers) / float(max_soldiers)
	if ratio < 0.4:
		morale -= (0.4 - ratio) * 6.0   # crumble as a regiment thins out

	if soldiers <= 0:
		soldiers = 0
		_die()
		Sfx.play(&"death")
	elif morale <= 0.0:
		_rout()
		Sfx.play(&"rout")

	# Cosmetic "men fall" markers (Stage C): drop a small fading heap of bodies on the
	# contact edge where this strike's casualties fell, leaning toward where the blow came
	# from. Spawned on the deterministic sim tick but render-only — no sim group, no
	# Replay.rng — so it has no simulation/replay/determinism impact (same contract as the
	# volley trail and rout shockwave). Guarded by is_inside_tree() like those.
	if is_inside_tree():
		var edge: Vector2 = global_position
		if is_instance_valid(attacker):
			# World-space throughout: edge is global_position, so the direction to the
			# attacker must be a global delta too. Mixing in local `position` would skew
			# the offset if the units' parent ever had a non-identity transform.
			var toward: Vector2 = attacker.global_position - global_position
			if toward.length() > 0.001:
				edge += toward.normalized() * _block_extent
		# Cavalry leave bigger bodies (matching their larger live marks); foot soldiers the default.
		var body_r: float = CAV_MARK_RADIUS if is_cavalry else MARK_RADIUS
		Fallen.spawn(get_parent(), edge, team_color, total, body_r)

	queue_redraw()


## 1.0 = frontal, 1.5 = flank, 2.0 = rear (relative to our facing).
func _flank_multiplier(attacker: Unit) -> float:
	var to_attacker: Vector2 = (attacker.position - position).normalized()
	var d: float = facing.dot(to_attacker)
	if d >= 0.35:
		return 1.0
	elif d >= -0.5:
		return 1.5
	else:
		return 2.0


# --- Fatigue & line relief --------------------------------------------

## Fatigue builds while fighting and recovers while resting. Well-trained melee
## units cycle their ranks, reducing effective buildup by up to RANK_CYCLE_FATIGUE_REDUCTION.
func tick_fatigue(delta: float) -> void:
	if state == State.FIGHTING:
		var cycle_reduction := 0.0 if is_ranged else training * RANK_CYCLE_FATIGUE_REDUCTION
		fatigue = minf(100.0, fatigue + FATIGUE_PER_SEC * (1.0 - cycle_reduction) * delta)
	else:
		fatigue = maxf(0.0, fatigue - FATIGUE_RECOVER_PER_SEC * delta)


## Attack multiplier from fatigue: 1.0 fresh, down to (1 - max penalty) spent.
func fatigue_attack_factor() -> float:
	return 1.0 - FATIGUE_MAX_ATTACK_PENALTY * (fatigue / 100.0)


## The "strangers" cohesion debuff from a merge ramps back to full over time.
func tick_cohesion(delta: float) -> void:
	if cohesion < 1.0:
		cohesion = minf(1.0, cohesion + COHESION_RECOVER_PER_SEC * delta)


## Morale recovers when resting; well-trained melee units also sustain it while
## fighting via visible rank rotation keeping the formation steady.
func tick_morale(delta: float) -> void:
	if state != State.FIGHTING and morale < 100.0:
		morale = minf(100.0, morale + MORALE_RECOVER_PER_SEC * delta)
	elif state == State.FIGHTING and not is_ranged \
			and training >= RANK_CYCLE_MORALE_THRESHOLD and morale < 100.0:
		var recovery := RANK_CYCLE_MORALE_PER_SEC \
				* ((training - RANK_CYCLE_MORALE_THRESHOLD) / (1.0 - RANK_CYCLE_MORALE_THRESHOLD)) \
				* delta
		morale = minf(100.0, morale + recovery)


## Start the order-response countdown. Called by Battle after stamping new
## motion fields onto the unit. The unit holds its current action for
## order_response_delay seconds before executing the new order.
func start_order_response() -> void:
	_order_response_timer = order_response_delay


## Fold another friendly regiment into this one: pool soldiers, blend the
## combat stats weighted by strength, and start with a cohesion debuff that
## decays. The absorbed unit is removed. Caller guarantees same team.
func absorb(other: Unit) -> void:
	var a: float = float(soldiers)
	var b: float = float(other.soldiers)
	var total: float = a + b
	if total <= 0.0:
		return
	max_soldiers += other.max_soldiers
	# Strength-weighted blend so the bigger regiment dominates the result.
	attack = int(round((attack * a + other.attack * b) / total))
	defense = int(round((defense * a + other.defense * b) / total))
	morale = (morale * a + other.morale * b) / total
	fatigue = (fatigue * a + other.fatigue * b) / total
	soldiers += other.soldiers
	# Strangers debuff and a wider body for the combined regiment — capped so the
	# footprint never grows past melee reach (which would deadlock contact).
	cohesion = MERGE_COHESION_FLOOR
	separation_radius = minf(maxf(separation_radius, other.separation_radius) + 2.0,
		SEPARATION_RADIUS_MAX)
	_base_separation_radius = separation_radius
	set_formation(formation_mode)
	other._merged_away()
	queue_redraw()


## Remove a unit that has been absorbed by a merge (not a battle death).
func _merged_away() -> void:
	_relief_partner = null
	_remove_from_play()


## Begin relieving an engaged friendly: this (fresh) unit takes over its fight
## and advances, the tired unit peels back to the rear. The pair is mutually
## exempt from separation (see _separation_exempt) so they pass through each
## other during the swap; the exemption clears once they're apart (_update_relief).
func begin_relief(tired: Unit) -> void:
	if tired == self:
		return   # a unit can't relieve itself (a self-link would never clear)
	# If either unit was already mid-relief with someone else, close those old
	# back-links first so a previous partner doesn't keep a dangling exemption.
	var old_self: Unit = _relief_partner
	if is_instance_valid(old_self) and old_self != tired:
		old_self._relief_partner = null
	var old_tired: Unit = tired._relief_partner
	if is_instance_valid(old_tired) and old_tired != self:
		old_tired._relief_partner = null
	_relief_partner = tired
	tired._relief_partner = self
	# Take over the tired unit's fight so the front isn't left open. A unit can be
	# FIGHTING an auto-acquired foe with target_enemy still null, so fall back to
	# its nearest enemy rather than just walking onto an empty slot.
	var foe: Unit = tired.target_enemy
	if foe == null:
		foe = tired._nearest_enemy()
	target_enemy = foe
	if foe != null:
		has_move_target = false
	else:
		move_target = tired.position   # truly no foe: advance onto its slot
		has_move_target = true
	# Tired unit disengages and falls back toward its own back edge.
	tired.target_enemy = null
	tired.move_target = tired._rear_point()
	tired.has_move_target = true


## A point toward this unit's own back edge — where a relieved unit retreats to.
func _rear_point() -> Vector2:
	var back: Vector2 = Vector2.UP if team == 0 else Vector2.DOWN
	return position + back * 160.0


## End the relief exemption once the partner has left the line (gone, dead, or
## routing) or the swapping pair has moved clear of each other.
func _update_relief() -> void:
	if _relief_partner == null:
		return
	# Drop the exemption if the partner is gone or has left the line (dead or
	# routing), or once the swapping pair has moved clear of each other.
	var gone: bool = not is_instance_valid(_relief_partner) \
		or _relief_partner.state == State.DEAD \
		or _relief_partner.state == State.ROUTING
	var apart: bool = is_instance_valid(_relief_partner) \
		and position.distance_to(_relief_partner.position) \
			> separation_radius + _relief_partner.separation_radius + 24.0
	if gone or apart:
		var partner: Unit = _relief_partner
		_relief_partner = null
		if is_instance_valid(partner) and partner._relief_partner == self:
			partner._relief_partner = null


# --- Death & routing -------------------------------------------------------

func _die() -> void:
	_remove_from_play()


## Shared teardown for leaving the battle (a death or a merge): mark dead,
## deselect, leave the units group, and free.
func _remove_from_play() -> void:
	state = State.DEAD
	selected = false
	remove_from_group("units")
	remove_from_group("routers")   # no-op unless removing a routing unit
	queue_free()


func _rout() -> void:
	if state == State.ROUTING:
		return
	state = State.ROUTING
	selected = false
	target_enemy = null
	has_move_target = false
	_rout_timer = ROUT_TIME
	_combat_intermixing = 0.0
	remove_from_group("units")   # no longer counts as a fighting unit
	add_to_group("routers")
	# Routing is contagious: shake nearby friends.
	for u in get_tree().get_nodes_in_group("units"):
		var friend: Unit = u as Unit
		if friend != null and friend.team == team:
			if position.distance_to(friend.position) < ROUT_SHOCK_RADIUS:
				friend.morale -= 12.0
	# Cosmetic morale-shock ripple marking the area allies were shaken. Spawned on
	# the deterministic sim tick but animated/faded on render time, in no sim group, so
	# it has no simulation/replay/determinism impact. Guarded like the volley trail.
	if is_inside_tree():
		RoutShockwave.spawn(get_parent(), global_position, ROUT_SHOCK_RADIUS, team_color)
	queue_redraw()


func _process_rout(delta: float) -> void:
	# Flee toward own back edge (team 0 started at top, team 1 at bottom).
	var flee: Vector2 = Vector2.UP if team == 0 else Vector2.DOWN
	facing = flee
	position += flee * (move_speed * 1.3) * delta
	_rout_timer -= delta
	if _rout_timer > 0.0:
		queue_redraw()
		return
	# Rout over: a unit that broke contact and kept enough men RALLIES back into
	# the fight; one still in contact, or gutted past reforming, SHATTERS for good.
	if _can_rally():
		_rally()
	else:
		_shatter()


## Whether a routed unit recovers rather than shatters when its rout times out:
## it must have broken contact — no living enemy within RALLY_CONTACT_RADIUS — and still
## field enough men to reform (>= SHATTER_STRENGTH_FRAC of its max). Positions + counts
## only, so it's deterministic and replay-safe.
func _can_rally() -> bool:
	if soldiers < int(round(max_soldiers * SHATTER_STRENGTH_FRAC)):
		return false
	return _nearest_enemy_to(position, RALLY_CONTACT_RADIUS) == null


## Recover from a rout: the unit reforms under the player's control at low,
## fragile morale and rejoins the fightable units — the inverse of the state/group
## changes _rout() made. It can be re-ordered, and can break again, from here.
func _rally() -> void:
	state = State.IDLE
	morale = RALLY_MORALE
	_rout_timer = 0.0
	# has_move_target was cleared on rout, so a stale waypoint queue is never consulted;
	# clear it anyway so a unit that was mid-march before routing reforms with no orders.
	waypoints.clear()
	remove_from_group("routers")
	add_to_group("units")
	queue_redraw()


## Shatter: a routed unit that couldn't escape, or was gutted past recovery, is
## destroyed for good — the terminal counterpart to a rally. Reuses the synchronous
## group teardown so it never lingers in a spatial-hash / separation scan after
## leaving play (queue_free() alone defers to end of frame).
func _shatter() -> void:
	_remove_from_play()


# --- Visuals ------------------------------------------------------------------

# Individual-soldier rendering (Stage A). The regiment is drawn as a formation
# block of one small mark per living soldier (cosmetic only — never fed back into the
# sim), packed roughly within the unit's footprint so the on-field size still matches
# the collision RADIUS. Wider-than-deep, like a real formation.
const FORMATION_SPACING: float = 3.4    # px between soldier marks
const FORMATION_ASPECT: float = 1.7     # files-to-ranks ratio (> 1 = wider than deep)
const MARK_RADIUS: float = 1.7          # foot soldier mark
const CAV_MARK_RADIUS: float = 2.6      # cavalry marks are larger (horses)
const MARK_JITTER: float = 1.3          # stable per-mark wobble so it's not a rigid grid
const EMBLEM_SCALE: float = 0.5         # the per-type sprite, shrunk to a centre emblem
const FLAG_POLE_HEIGHT: float = 18.0    # pole from above-bar to flag attachment point
const FLAG_WIDTH: float = 12.0          # horizontal extent of the flag rectangle
const FLAG_HEIGHT: float = 8.0          # vertical extent of the flag rectangle

# Soldier flocking (Stage B). The marks no longer snap to their formation slot:
# each soldier eases toward its slot (an arrival spring) while pushing off its
# neighbours (separation), so the block visibly deforms and trails when the regiment
# advances or wheels, then reforms when it halts. Purely COSMETIC — these positions are
# never read by the simulation (combat, morale, movement and collisions all use the
# unit's single point), so determinism and replays are untouched. The marks render
# through two MultiMeshes (body + outline), giving 2 draw calls per unit regardless of
# soldier count — replacing Stage A's draw_circle pair per soldier (240/unit at full
# strength). Integration runs in _process (render time), decoupled from the fixed-step
# sim, and sleeps entirely once the block has settled.
const FLOCK_STIFFNESS: float = 90.0     # arrival spring pulling a soldier to its slot
const FLOCK_DAMPING: float = 19.0       # ~critical (2*sqrt(stiffness)): settles without ringing
const FLOCK_SEPARATION: float = 140.0   # push accel keeping marks from piling up
const FLOCK_MAX_SPEED: float = 320.0    # cap on a mark's catch-up speed (bounds integration)
# A mark never trails its slot by more than this, keeping the block tight at speed.
const FLOCK_MAX_LAG: float = 26.0
const FLOCK_SETTLE_POS: float = 0.30    # within this of its slot and...
const FLOCK_SETTLE_VEL: float = 1.5     # ...slower than this -> the block sleeps
const FLOCK_DT_MAX: float = 1.0 / 30.0  # clamp render dt so a hitch can't blow up integration

# Melee churn (Stage C). While a regiment is FIGHTING, its front-rank soldier marks
# press into and recoil from the contact line and jitter sideways, so the engaged edge of
# the block visibly fights instead of two blocks merely touching. The churn fades to
# nothing a couple of ranks back (COMBAT_REACH), so only the fighting edge moves while the
# body of the block holds formation. Purely cosmetic — these offsets are layered onto the
# render-only mark targets and never read by the sim, so determinism and replays are
# untouched (the clock is render time, not the fixed sim tick).
const COMBAT_LUNGE: float = 3.2         # max forward press toward the enemy (px)
const COMBAT_LATERAL: float = 1.5       # sideways churn amplitude (px)
const COMBAT_REACH: float = 8.0         # depth behind front rank over which churn fades to 0 (px)
const COMBAT_FREQ: float = 9.0          # churn oscillation rate (rad/s)

# Rank cycling (Stage D). A periodic signal (whistle) causes well-trained
# melee units to rotate their ranks: front-rank marks slide backward while
# rear-rank marks advance to the front. At the signal, the back ranks briefly
# widen laterally to open a corridor for the retiring front rank to pass through,
# then close back up. Purely cosmetic -- never read by the sim -- render-only.
const RANK_CYCLE_INTERVAL: float = 12.0   # seconds between signals at training=1.0
const RANK_CYCLE_ANIM_DURATION: float = 0.7  # seconds for the widen-and-close animation
const RANK_CYCLE_WIDEN: float = 3.5       # max lateral spread for rear marks (px)

# Relief corridor (Stage E). When a unit has a relief partner swapping through it,
# marks spread laterally away from the approach axis by this factor (applied to each
# mark's perpendicular distance from that axis) when the partner is fully overlapping.
const RELIEF_SPREAD_MAX: float = 0.45


## Local-space slot offsets for `n` soldier marks: a centred, wider-than-deep
## grid (front rank toward -Y, the rotated "forward"). Pure and deterministic — a
## function of n only — so it's unit-testable; _slot_target() adds stable jitter.
func _formation_slots(n: int) -> PackedVector2Array:
	var slots := PackedVector2Array()
	if n <= 0:
		return slots
	var files: int = maxi(1, int(ceil(sqrt(float(n) * FORMATION_ASPECT))))
	var ranks: int = int(ceil(float(n) / float(files)))
	var y0: float = -(ranks - 1) * 0.5 * FORMATION_SPACING
	for i in range(n):
		var file: int = i % files
		var rank: int = i / files
		# Centre each rank on its own count, so a partial last rank doesn't pull the
		# block's centroid off the unit (most visible on small / heavily-depleted units).
		var rank_count: int = mini(files, n - rank * files)
		var rx0: float = -(rank_count - 1) * 0.5 * FORMATION_SPACING
		slots.push_back(Vector2(rx0 + file * FORMATION_SPACING, y0 + rank * FORMATION_SPACING))
	return slots


## Deterministic pseudo-random float in [0, 1) from an int, for stable (non-flickering)
## per-mark jitter in the formation render. Cosmetic only — never used by the simulation.
func _hash01(i: int) -> float:
	var x: float = sin(float(i) * 12.9898) * 43758.5453
	return x - floor(x)


# --- Soldier flocking (Stage B) ------------------------------------------
# Render-time only: the cosmetic mark layer eases toward the formation and trails the
# unit's motion. None of this writes back into the simulation.

## Disc mesh at the given radius, shared across all units. Built once and cached.
static func _disc_mesh(radius: float) -> ArrayMesh:
	var key: float = snappedf(radius, 0.01)
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var segments: int = 10
	var verts := PackedVector2Array()
	verts.push_back(Vector2.ZERO)   # fan centre
	for i in range(segments + 1):
		var a: float = TAU * float(i) / float(segments)
		verts.push_back(Vector2(cos(a), sin(a)) * radius)
	var idx := PackedInt32Array()
	for i in range(segments):
		idx.append(0)
		idx.append(1 + i)
		idx.append(2 + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_cache[key] = mesh
	return mesh


static func _rect_mesh(w: float, h: float) -> ArrayMesh:
	var key: String = "r%.2f_%.2f" % [w, h]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var hw := w * 0.5
	var hh := h * 0.5
	var verts := PackedVector2Array([
		Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh),
	])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_cache[key] = mesh
	return mesh


static func _diamond_mesh(radius: float) -> ArrayMesh:
	var key: String = "d%.2f" % [radius]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var verts := PackedVector2Array([
		Vector2(0.0, -radius), Vector2(radius, 0.0),
		Vector2(0.0, radius),  Vector2(-radius, 0.0),
	])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_cache[key] = mesh
	return mesh


## Build the cosmetic render layer: a ground shadow (Polygon2D) and two MultiMeshes
## (outline behind, body in front) for the soldier marks. z_index is RELATIVE to this
## node (z=3), so the children sit at: shadow eff 1, outline/body eff 2 — under this
## node's chrome (_draw at eff 3) but above the field (z=0). The body is added after the
## outline so it draws in front of it at the same effective z. One-time setup in _ready().
func _setup_flock_renderer() -> void:
	var mark_r: float = CAV_MARK_RADIUS if is_cavalry else MARK_RADIUS
	# Per-type mesh shapes so soldiers read differently at a glance:
	# spearmen = tall thin rectangle (shaft), archers = diamond (arrow), cavalry/infantry = disc.
	var body_mesh: ArrayMesh
	var outline_mesh: ArrayMesh
	if anti_cavalry:
		body_mesh    = _rect_mesh(mark_r * 0.65, mark_r * 1.7)
		outline_mesh = _rect_mesh(mark_r * 0.65 + 1.2, mark_r * 1.7 + 1.2)
	elif is_ranged:
		body_mesh    = _diamond_mesh(mark_r * 1.15)
		outline_mesh = _diamond_mesh(mark_r * 1.15 + 0.6)
	else:
		body_mesh    = _disc_mesh(mark_r)
		outline_mesh = _disc_mesh(mark_r + 0.6)

	_shadow = Polygon2D.new()
	_shadow.polygon = _ellipse_polygon()
	_shadow.color = Color(0, 0, 0, 0.22)
	_shadow.z_index = -2   # eff 1: above the field, below the marks
	add_child(_shadow)

	_mm_outline = MultiMesh.new()
	_mm_outline.transform_format = MultiMesh.TRANSFORM_2D
	_mm_outline.mesh = outline_mesh
	_mmi_outline = MultiMeshInstance2D.new()
	_mmi_outline.multimesh = _mm_outline
	_mmi_outline.z_index = -1   # eff 2
	add_child(_mmi_outline)

	_mm_body = MultiMesh.new()
	_mm_body.transform_format = MultiMesh.TRANSFORM_2D
	_mm_body.mesh = body_mesh
	_mmi_body = MultiMeshInstance2D.new()
	_mmi_body.multimesh = _mm_body
	_mmi_body.z_index = -1   # eff 2, added after the outline -> drawn in front of it
	add_child(_mmi_body)

	_flock_last_pos = position   # local-to-parent frame; see _update_flock
	_flock_last_facing = facing
	_seed_soldiers()


## Unit-radius ellipse outline (pre-squished) for the ground shadow; scaled in _update_shadow().
func _ellipse_polygon(segments: int = 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a: float = TAU * float(i) / float(segments)
		pts.push_back(Vector2(cos(a) * 1.1, sin(a) * 0.36))
	return pts


## Start the marks already formed up on their slots (the regiment spawns in formation,
## not scrambling in from the centre).
func _seed_soldiers() -> void:
	var n: int = soldiers
	_soldier_pos.resize(n)
	_soldier_vel.resize(n)
	var slots := _formation_slots(n)
	var ang: float = facing.angle() + PI * 0.5
	for i in range(n):
		_soldier_pos[i] = _slot_target(slots, i, ang)
		_soldier_vel[i] = Vector2.ZERO
	_block_extent = _compute_extent(slots)
	_update_shadow()
	_refresh_flock_render()
	_flock_settled = true


## Local-frame target for mark at slot_i: the formation slot plus stable per-mark
## jitter (so a settled block reads as a crowd, not a rigid grid), rotated into the
## unit's facing. jitter_i seeds the wobble independently from the slot so a mark
## moving to a new slot during rank cycling keeps its own stable personality.
func _slot_target(slots: PackedVector2Array, slot_i: int, ang: float, jitter_i: int = -1) -> Vector2:
	var ji: int = jitter_i if jitter_i >= 0 else slot_i
	var jx: float = (_hash01(ji * 2) - 0.5) * MARK_JITTER
	var jy: float = (_hash01(ji * 2 + 1) - 0.5) * MARK_JITTER
	return (slots[slot_i] + Vector2(jx, jy)).rotated(ang)


## Block half-size: the farthest slot plus a mark radius, floored at the collision RADIUS.
## Sizes the state ring, selection halo, stat bars (in _draw) and the ground shadow.
func _compute_extent(slots: PackedVector2Array) -> float:
	var mark_r: float = CAV_MARK_RADIUS if is_cavalry else MARK_RADIUS
	var extent: float = RADIUS
	for s in slots:
		extent = maxf(extent, s.length())
	return extent + mark_r + 2.0


func _process(delta: float) -> void:
	_update_flock(delta)


## Advance the cosmetic mark layer one render frame. Cheap fast-path when the block is
## settled and the unit hasn't moved/turned (no allocation, no integration).
func _update_flock(delta: float) -> void:
	if _mm_body == null:
		return
	if state == State.DEAD:
		if _mm_body.instance_count != 0:
			_mm_body.instance_count = 0
			_mm_outline.instance_count = 0
		return

	var n: int = soldiers
	if _soldier_pos.size() != n:   # casualties (shrink) or a merge (grow)
		_resize_soldiers(n)
		_flock_settled = false

	# `position` (local-to-parent), not global_position: the marks live in this node's local
	# frame, so the trail shove must be in that same frame. They coincide today (units sit
	# under an identity parent) but tracking `position` stays correct if that ever changes.
	var displacement: Vector2 = position - _flock_last_pos
	var turned: bool = not facing.is_equal_approx(_flock_last_facing)
	# Relief corridor (Stage E): compute lateral-spread parameters once for all marks so
	# each mark's individual offset is a cheap dot-product, and so the effect can also
	# gate the early-exit check below (a settling block must not sleep while a partner
	# is still swapping through it).
	var relief_perp: Vector2 = Vector2.ZERO
	var relief_spread: float = 0.0
	if _relief_partner != null and is_instance_valid(_relief_partner):
		var approach_raw: Vector2 = _relief_partner.position - position
		# Guard against exact co-location: normalized() returns zero on a zero-length
		# vector. Fall back to a stable axis so the spread is maximum (as intended)
		# rather than absent precisely when overlap is highest.
		var approach: Vector2 = approach_raw.normalized() if approach_raw.length() > 0.5 \
				else Vector2.RIGHT
		relief_perp = approach.rotated(PI * 0.5)
		var dist: float = position.distance_to(_relief_partner.position)
		var max_dist: float = separation_radius + _relief_partner.separation_radius + 30.0
		relief_spread = RELIEF_SPREAD_MAX * clampf(1.0 - dist / max_dist, 0.0, 1.0)

	# A FIGHTING block never rests: its front rank churns against the contact line each
	# frame (Stage C), so it skips the at-rest fast-path even when the unit is standing
	# still and not turning.  A unit in a relief swap likewise stays active until the
	# partner moves clear (Stage E).
	var fighting: bool = state == State.FIGHTING
	if _flock_settled and displacement.is_zero_approx() and not turned and not fighting \
			and relief_spread <= 0.0:
		return   # at rest — nothing to do

	_flock_last_pos = position
	_flock_last_facing = facing

	var slots := _formation_slots(n)
	var ang: float = facing.angle() + PI * 0.5

	var new_extent: float = _compute_extent(slots)
	if not is_equal_approx(new_extent, _block_extent):
		_block_extent = new_extent
		_update_shadow()
		queue_redraw()   # chrome (ring / halo / bars) is sized to the block

	# Trail: shove every mark back by the unit's displacement so the block lags behind the
	# advancing/wheeling regiment; the arrival spring then reels them back onto formation.
	if not displacement.is_zero_approx():
		for i in range(n):
			_soldier_pos[i] -= displacement

	var sep_dist: float = FORMATION_SPACING * 0.9
	var grid := _build_soldier_grid(sep_dist)
	var dt: float = minf(delta, FLOCK_DT_MAX)
	# Front rank depth datum (slot 0 is the front-centre rank, see _formation_slots): a
	# mark's depth behind it scales how hard it churns while fighting (Stage C).
	var front_y: float = slots[0].y if n > 0 else 0.0
	if fighting:
		_combat_clock += dt

	# Rank cycling (Stage D): a periodic signal rotates slot assignments so front-rank
	# marks slide toward the rear and rear-rank marks advance to the front. Active only
	# for trained melee units (ranged units fire from static lines). Render-only.
	var cycling: bool = fighting and not is_ranged and training > 0.0 and n > 1
	# Drain the widen animation unconditionally so it always finishes even when
	# the unit breaks contact mid-animation (cycling would be false, but the anim
	# should not freeze or re-fire incorrectly on re-engagement).
	if _rank_cycle_anim < 1.0:
		_rank_cycle_anim = minf(1.0, _rank_cycle_anim + dt / RANK_CYCLE_ANIM_DURATION)
	if cycling:
		_rank_cycle_timer -= dt
		if _rank_cycle_timer <= 0.0:
			var files: int = maxi(1, int(ceil(sqrt(float(n) * FORMATION_ASPECT))))
			_rank_cycle_slot_offset = (_rank_cycle_slot_offset + files) % n
			_rank_cycle_timer = RANK_CYCLE_INTERVAL / training
			_rank_cycle_anim = 0.0
			if is_inside_tree():
				Sfx.play(&"whistle")

	var still: bool = true
	for i in range(n):
		var slot_i: int = (i + _rank_cycle_slot_offset) % n if cycling else i
		var target: Vector2 = _slot_target(slots, slot_i, ang, i)
		if fighting:
			# Front-rank marks press into and recoil from the contact line; rotate the
			# (forward = -Y) lunge onto the unit's facing alongside the slot it modifies.
			var lunge := _combat_lunge_offset(slots[slot_i].y - front_y, float(i) * 1.3, _combat_clock)
			target += lunge.rotated(ang)
		# Rear-rank widen (Stage D): during the rank-cycle animation, rear ranks spread
		# laterally to open a corridor for the front rank to fall back through. The spread
		# peaks at the midpoint (sin peaks at PI/2) then closes as the animation settles.
		if cycling and _rank_cycle_anim < 1.0:
			var depth: float = slots[slot_i].y - front_y   # 0 = front rank, + = deeper rear
			if depth > FORMATION_SPACING * 0.5:
				var spread_phase: float = sin(_rank_cycle_anim * PI)
				var norm_depth: float = minf(depth / (FORMATION_SPACING * 2.0), 1.0)
				var lateral_sign: float = signf(slots[slot_i].x) if abs(slots[slot_i].x) > 0.5 \
						else (1.0 if slot_i % 2 == 0 else -1.0)
				var widen: float = lateral_sign * RANK_CYCLE_WIDEN * spread_phase * norm_depth
				target += Vector2(widen, 0.0).rotated(ang)
		# Relief corridor (Stage E): spread marks laterally to open a lane for the incoming
		# partner. Each mark is pushed away from the approach axis in proportion to how far
		# it already sits from that axis, so the center clears and the flanks fan out.
		if relief_spread > 0.0:
			target += _relief_spread_offset(_soldier_pos[i], relief_perp, relief_spread)
		var neighbors := _neighbors_of(grid, i, sep_dist)
		var res := _flock_step(_soldier_pos[i], _soldier_vel[i], target, neighbors, sep_dist, dt)
		_soldier_pos[i] = res[0]
		_soldier_vel[i] = res[1]
		if res[1].length() > FLOCK_SETTLE_VEL or res[0].distance_to(target) > FLOCK_SETTLE_POS:
			still = false

	# A fighting block keeps churning, so it never sleeps even if a frame reads as "still".
	# A block in a relief spread likewise stays active: settling onto plain slot positions
	# would immediately snap marks back out (the spread-modified targets fire again next
	# frame), producing a repeating snap-then-spring flicker.
	if still and not fighting and relief_spread <= 0.0:
		# Snap exactly onto formation and sleep until the unit next moves or loses men.
		# Use the same slot-rotation condition as the main loop (minus fighting, which
		# is already false here) so the settled mark positions stay consistent.
		var settled_cycling: bool = not is_ranged and training > 0.0 and n > 1
		for i in range(n):
			var slot_i: int = (i + _rank_cycle_slot_offset) % n if settled_cycling else i
			_soldier_pos[i] = _slot_target(slots, slot_i, ang, i)
			_soldier_vel[i] = Vector2.ZERO
		_flock_settled = true
	else:
		_flock_settled = false

	_refresh_flock_render()


## Step one mark: a damped arrival spring toward its slot plus separation from neighbours,
## with a speed cap and a max-lag clamp for stability. Pure and deterministic (a function
## of its arguments only) so it is unit-testable. Returns [new_pos, new_vel].
static func _flock_step(pos: Vector2, vel: Vector2, target: Vector2,
		neighbors: PackedVector2Array, sep_dist: float, dt: float) -> Array:
	var accel: Vector2 = (target - pos) * FLOCK_STIFFNESS - vel * FLOCK_DAMPING
	for nb in neighbors:
		var away: Vector2 = pos - nb
		var d: float = away.length()
		if d > 0.0001:
			if d < sep_dist:
				accel += (away / d) * (FLOCK_SEPARATION * (1.0 - d / sep_dist))
		else:
			# Exactly coincident — avoided in practice (marks spawn fanned out, see
			# _resize_soldiers), so this is just a guard nudge to break the symmetry.
			accel += Vector2(FLOCK_SEPARATION, 0.0)
	var nvel: Vector2 = vel + accel * dt
	var sp: float = nvel.length()
	if sp > FLOCK_MAX_SPEED:
		nvel *= FLOCK_MAX_SPEED / sp
	var npos: Vector2 = pos + nvel * dt
	var lag: Vector2 = npos - target
	var lag_len: float = lag.length()
	if lag_len > FLOCK_MAX_LAG:
		npos = target + lag * (FLOCK_MAX_LAG / lag_len)
		# Re-derive velocity from the clamped move so a clamped mark doesn't carry an
		# inflated velocity that pops once it re-enters the lag boundary, then re-bound it
		# (the move is huge only in the degenerate far-spawn case, never in normal play).
		nvel = (npos - pos) / dt
		var clamped_sp: float = nvel.length()
		if clamped_sp > FLOCK_MAX_SPEED:
			nvel *= FLOCK_MAX_SPEED / clamped_sp
	return [npos, nvel]


## Melee churn offset for one front-rank mark (Stage C). Returns an offset in the
## unit's UNROTATED local frame (forward / toward-enemy is -Y, matching _formation_slots),
## which the caller rotates onto the unit's facing. `depth` is how far behind the front
## rank the mark sits (0 = front rank): the churn fades linearly to zero by COMBAT_REACH,
## so only the fighting edge moves. The forward press rides a raised sine (always into the
## enemy, surging and recoiling rather than pulling back past the line); a separate, faster
## out-of-phase term jitters it sideways. Pure and deterministic (a function of its
## arguments) so it's unit-testable; render-only, never read by the sim.
static func _combat_lunge_offset(depth: float, phase: float, t: float) -> Vector2:
	var falloff: float = clampf(1.0 - depth / COMBAT_REACH, 0.0, 1.0)
	if falloff <= 0.0:
		return Vector2.ZERO
	var press: float = COMBAT_LUNGE * falloff * (0.55 + 0.45 * sin(t * COMBAT_FREQ + phase))
	var churn: float = COMBAT_LATERAL * falloff * sin(t * COMBAT_FREQ * 1.7 + phase * 2.0)
	return Vector2(churn, -press)


## Relief corridor offset for one mark (Stage E). Returns a lateral offset pushing the
## mark away from the approach axis, opening a lane for the incoming relief partner.
## `mark_pos` is the mark's current local position; `relief_perp` is the unit vector
## perpendicular to the approach direction; `spread` is the fractional scale (0–1).
## Pure and deterministic so it is unit-testable. Render-only; never read by the sim.
static func _relief_spread_offset(mark_pos: Vector2, relief_perp: Vector2, spread: float) -> Vector2:
	return relief_perp * mark_pos.dot(relief_perp) * spread


## Bucket marks into a uniform grid (cell = sep_dist) so separation is a local 3x3 lookup
## rather than O(n^2). Keyed by integer cell coords -> indices into _soldier_pos.
func _build_soldier_grid(cell: float) -> Dictionary:
	var grid := {}
	for i in range(_soldier_pos.size()):
		var p: Vector2 = _soldier_pos[i]
		var k := Vector2i(int(floor(p.x / cell)), int(floor(p.y / cell)))
		if not grid.has(k):
			grid[k] = PackedInt32Array()
		grid[k].append(i)
	return grid


## Positions of marks within one cell of mark i (its separation neighbourhood).
func _neighbors_of(grid: Dictionary, i: int, cell: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var p: Vector2 = _soldier_pos[i]
	var cx: int = int(floor(p.x / cell))
	var cy: int = int(floor(p.y / cell))
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			var k := Vector2i(cx + ox, cy + oy)
			if grid.has(k):
				for j in grid[k]:
					if j != i:
						out.append(_soldier_pos[j])
	return out


## Resize the mark arrays to match the live soldier count. Casualties just truncate; a
## merge grows the array, and the new marks are fanned onto a small deterministic spiral
## near the centre (a sunflower phyllotaxis) rather than stacked on the exact origin — so
## they're never coincident, the separation step can tell them apart, and they spread out
## to formation cleanly instead of drifting as one blob.
func _resize_soldiers(n: int) -> void:
	var old: int = _soldier_pos.size()
	_soldier_pos.resize(n)
	_soldier_vel.resize(n)
	for i in range(old, n):
		var k: int = i - old
		var a: float = float(k) * 2.39996323   # golden angle (rad): even, non-repeating
		_soldier_pos[i] = Vector2.from_angle(a) * (0.4 * sqrt(float(k) + 0.5))
		_soldier_vel[i] = Vector2.ZERO


## Push the current mark positions/colours into the two MultiMeshes (1 instance per mark).
func _refresh_flock_render() -> void:
	var n: int = _soldier_pos.size()
	if _mm_body.instance_count != n:
		_mm_body.instance_count = n
		_mm_outline.instance_count = n
	for i in range(n):
		var t := Transform2D(0.0, _soldier_pos[i])
		_mm_body.set_instance_transform_2d(i, t)
		_mm_outline.set_instance_transform_2d(i, t)
	_apply_flock_color()


## Tint the marks via the MultiMeshInstance modulate (one colour for the whole block, so
## no per-instance colour buffer): team colour for the body, a darkened shade for the
## outline, faded while routing. Only re-applied when the colour actually changes.
func _apply_flock_color() -> void:
	var alpha: float = 0.45 if state == State.ROUTING else 1.0
	var body_c := Color(team_color.r, team_color.g, team_color.b, alpha)
	if body_c == _flock_color:
		return
	_flock_color = body_c
	_mmi_body.modulate = body_c
	_mmi_outline.modulate = Color(body_c.r * 0.35, body_c.g * 0.35, body_c.b * 0.35, alpha)


## Size/position the ground shadow ellipse to the current block extent.
func _update_shadow() -> void:
	if _shadow == null:
		return
	var r: float = _block_extent * 0.95
	_shadow.position = Vector2(0, _block_extent * 0.45)
	_shadow.scale = Vector2(r, r)


func _draw() -> void:
	var alpha: float = 0.45 if state == State.ROUTING else 1.0
	var body_c := Color(team_color.r, team_color.g, team_color.b, alpha)
	var dark_c := Color(body_c.r * 0.35, body_c.g * 0.35, body_c.b * 0.35, alpha)
	var lite_c := Color(minf(body_c.r + 0.30, 1.0), minf(body_c.g + 0.30, 1.0),
			minf(body_c.b + 0.30, 1.0), alpha)

	# The soldier marks (Stage B) are rendered by the flocking MultiMeshes and the
	# ground shadow by a Polygon2D — both child nodes layered under this chrome via
	# z_index. _draw() handles only the screen-relative chrome: state ring, type emblem,
	# selection halo and stat bars. `_block_extent` (maintained by _update_flock) sizes
	# them to the live block rather than the bare collision radius.
	var extent: float = _block_extent

	# State ring around the block: red = engaged, orange = routing.
	match state:
		State.FIGHTING:
			draw_arc(Vector2.ZERO, extent + 2.0, 0, TAU, 36,
					Color(0.90, 0.15, 0.15, alpha), 3.0)
		State.ROUTING:
			# alpha=1.0 intentional: ring stays fully visible on the faded routing block.
			draw_arc(Vector2.ZERO, extent + 2.0, 0, TAU, 36,
					Color(0.95, 0.50, 0.05, 1.0), 3.5)

	# A small per-type emblem (kept for at-a-glance type) at the block centre, like a
	# standard, drawn in the facing-rotated local frame (forward = up).
	draw_set_transform(Vector2.ZERO, facing.angle() + PI * 0.5,
			Vector2(EMBLEM_SCALE, EMBLEM_SCALE))
	if is_cavalry:
		_draw_cavalry_sprite(body_c, dark_c, lite_c)
	elif anti_cavalry:
		_draw_spear_sprite(body_c, dark_c, lite_c)
	elif is_ranged:
		_draw_archer_sprite(body_c, dark_c, lite_c)
	else:
		_draw_infantry_sprite(body_c, dark_c, lite_c)

	# Reset to screen-space for HUD overlays.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if selected:
		draw_arc(Vector2.ZERO, extent + 4.0, 0, TAU, 36, Color(0.95, 0.95, 0.3), 2.5)

	# Strength bar + morale bar stacked above the block.
	var bw: float = 38.0
	var by: float = -extent - 16.0
	var frac: float = clampf(float(soldiers) / float(max_soldiers), 0.0, 1.0)
	var morale_frac: float = clampf(morale / 100.0, 0.0, 1.0)
	var morale_color: Color
	if morale_frac > 0.60:
		morale_color = Color(0.30, 0.80, 0.30, alpha)
	elif morale_frac > 0.30:
		morale_color = Color(0.85, 0.75, 0.10, alpha)
	else:
		morale_color = Color(0.85, 0.20, 0.10, alpha)

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-bw * 0.5, by - 3.0), str(soldiers),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, alpha))
	# Strength (green).
	draw_rect(Rect2(-bw * 0.5, by, bw, 5.0), Color(0.15, 0.15, 0.15, alpha))
	draw_rect(Rect2(-bw * 0.5, by, bw * frac, 5.0), Color(0.30, 0.80, 0.30, alpha))
	# Morale (green → yellow → red as it degrades).
	draw_rect(Rect2(-bw * 0.5, by + 7.0, bw, 4.0), Color(0.15, 0.15, 0.15, alpha))
	draw_rect(Rect2(-bw * 0.5, by + 7.0, bw * morale_frac, 4.0), morale_color)

	_draw_unit_flag(body_c, alpha, extent)


## Infantry: kite (heater) shield with a cross motif and sword pommel.
func _draw_infantry_sprite(body: Color, dark: Color, lite: Color) -> void:
	var R := RADIUS
	var metal := Color(0.78, 0.80, 0.85, body.a)
	var pts := PackedVector2Array([
		Vector2(0,          -R),
		Vector2( R * 0.82, -R * 0.30),
		Vector2( R * 0.90,  R * 0.42),
		Vector2(0,           R),
		Vector2(-R * 0.90,  R * 0.42),
		Vector2(-R * 0.82, -R * 0.30),
	])
	draw_colored_polygon(pts, body)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3],
			pts[4], pts[5], pts[0]]), dark, 2.0)
	# Cross on shield face.
	draw_line(Vector2(0,  -R + 5.0), Vector2(0,  R * 0.90), lite, 2.0)
	draw_line(Vector2(-R * 0.72, R * 0.05), Vector2(R * 0.72, R * 0.05), lite, 2.0)
	# Sword pommel / crossguard at the top of the shield.
	draw_line(Vector2(-5.0, -R + 8.0), Vector2(5.0, -R + 8.0), metal, 2.5)
	draw_line(Vector2(0, -R + 2.0), Vector2(0, -R + 9.0), metal, 2.0)


## Archers: a light skirmisher body with a drawn bow + nocked arrow forward.
func _draw_archer_sprite(body: Color, dark: Color, lite: Color) -> void:
	var R := RADIUS
	var metal := Color(0.78, 0.80, 0.85, body.a)
	var wood := Color(0.62, 0.48, 0.30, body.a)
	# Light round body — archers are unarmoured, so a smaller token than a shield.
	draw_circle(Vector2.ZERO, R * 0.60, body)
	draw_arc(Vector2.ZERO, R * 0.60, 0, TAU, 20, dark, 1.5)
	# Bow: an arc bulging forward (up = forward in this rotated local space), with
	# a bowstring across its tips.
	var bow_r: float = R * 1.05
	var a0: float = -PI * 0.5 - 0.7
	var a1: float = -PI * 0.5 + 0.7
	draw_arc(Vector2.ZERO, bow_r, a0, a1, 16, wood, 2.5)
	var tip0: Vector2 = Vector2.from_angle(a0) * bow_r
	var tip1: Vector2 = Vector2.from_angle(a1) * bow_r
	draw_line(tip0, tip1, lite, 1.0)
	# Nocked arrow at the string's midpoint, pointing forward with a metal head.
	var nock: Vector2 = (tip0 + tip1) * 0.5
	draw_line(nock, Vector2(0, -(bow_r + 9.0)), metal, 1.5)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -(bow_r + 13.0)),
		Vector2(3.0, -(bow_r + 5.0)),
		Vector2(-3.0, -(bow_r + 5.0)),
	]), metal)


## Spearmen: round hoplon shield with a forward-pointing spear.
func _draw_spear_sprite(body: Color, dark: Color, lite: Color) -> void:
	var R := RADIUS
	var metal := Color(0.78, 0.80, 0.85, body.a)
	var wood := Color(0.62, 0.48, 0.30, body.a)
	# Spear shaft (forward = up in rotated local space).
	var shaft_y: float = -(R + 15.0)
	draw_line(Vector2(0, -R * 0.05), Vector2(0, shaft_y), wood, 3.0)
	# Spear blade.
	var blade := PackedVector2Array([
		Vector2(0,    shaft_y - 9.0),
		Vector2( 3.5, shaft_y),
		Vector2(-3.5, shaft_y),
	])
	draw_colored_polygon(blade, metal)
	draw_polyline(PackedVector2Array([blade[0], blade[1], blade[2], blade[0]]), dark, 1.0)
	# Hoplon (round shield).
	draw_circle(Vector2.ZERO, R * 0.88, body)
	draw_arc(Vector2.ZERO, R * 0.88, 0, TAU, 24, dark, 2.0)
	# Shield boss.
	draw_circle(Vector2.ZERO, R * 0.26, lite)
	draw_arc(Vector2.ZERO, R * 0.26, 0, TAU, 12, dark, 1.5)
	# Inner ring detail.
	draw_arc(Vector2.ZERO, R * 0.60, 0, TAU, 20,
			Color(dark.r, dark.g, dark.b, dark.a * 0.6), 1.0)


## Cavalry: horse body (two overlapping ovals) with rider and lance.
func _draw_cavalry_sprite(body: Color, dark: Color, lite: Color) -> void:
	var R := RADIUS
	var metal := Color(0.78, 0.80, 0.85, body.a)
	# Horse body: forequarters + hindquarters bridged by a quad.
	draw_circle(Vector2(0, -R * 0.30), R * 0.62, body)
	draw_circle(Vector2(0,  R * 0.28), R * 0.68, body)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-R * 0.60, -R * 0.30),
		Vector2(-R * 0.66,  R * 0.28),
		Vector2( R * 0.66,  R * 0.28),
		Vector2( R * 0.60, -R * 0.30),
	]), body)
	draw_arc(Vector2(0, -R * 0.30), R * 0.62, 0, TAU, 16, dark, 1.5)
	draw_arc(Vector2(0,  R * 0.28), R * 0.68, 0, TAU, 16, dark, 1.5)
	# Horse head / neck offset forward-right.
	var head := Vector2(R * 0.20, -R * 0.88)
	draw_circle(head, R * 0.28, lite)
	draw_arc(head, R * 0.28, 0, TAU, 12, dark, 1.5)
	# Four legs trailing behind.
	draw_line(Vector2(-R * 0.35, R * 0.60), Vector2(-R * 0.48, R + 4.0), dark, 2.5)
	draw_line(Vector2(-R * 0.12, R * 0.60), Vector2(-R * 0.18, R + 5.0), dark, 2.5)
	draw_line(Vector2( R * 0.12, R * 0.60), Vector2( R * 0.18, R + 5.0), dark, 2.5)
	draw_line(Vector2( R * 0.35, R * 0.60), Vector2( R * 0.48, R + 4.0), dark, 2.5)
	# Rider torso.
	draw_circle(Vector2(0, -R * 0.18), R * 0.42, lite)
	draw_arc(Vector2(0, -R * 0.18), R * 0.42, 0, TAU, 14, dark, 1.5)
	# Lance pointing forward-right with a triangular blade tip.
	var lance_tip := Vector2(R * 0.65, -R * 0.78)
	draw_line(Vector2(R * 0.15, -R * 0.18), lance_tip, metal, 2.5)
	var lance_dir := Vector2(0.50, -0.60).normalized()
	var lance_perp := Vector2(-lance_dir.y, lance_dir.x)
	var tip_blade := PackedVector2Array([
		lance_tip + lance_dir * 7.0,
		lance_tip + lance_perp * 3.0,
		lance_tip - lance_perp * 3.0,
	])
	draw_colored_polygon(tip_blade, metal)
	draw_polyline(PackedVector2Array([tip_blade[0], tip_blade[1], tip_blade[2], tip_blade[0]]),
			dark, 1.0)


## A regimental standard: a pole rising above the stat bars with a coloured flag bearing a
## per-type emblem. Drawn in screen space (called after draw_set_transform reset) so it
## always stands upright regardless of the unit's facing direction. Dead units skip it.
func _draw_unit_flag(body_c: Color, alpha: float, extent: float) -> void:
	if state == State.DEAD:
		return
	# Pole rises from just above the soldier-count text (which sits ~14 px above bar top).
	var pole_base := Vector2(0.0, -extent - 34.0)
	var pole_top  := Vector2(0.0, pole_base.y - FLAG_POLE_HEIGHT)
	draw_line(pole_base, pole_top, Color(0.85, 0.85, 0.85, alpha), 1.5)
	# Flag rectangle hangs below the pole tip (positive-Y in screen space = downward).
	var fx: float = pole_top.x
	var fy: float = pole_top.y
	draw_rect(Rect2(fx, fy, FLAG_WIDTH, FLAG_HEIGHT), body_c)
	draw_rect(Rect2(fx, fy, FLAG_WIDTH, FLAG_HEIGHT),
			Color(1.0, 1.0, 1.0, alpha * 0.5), false, 1.0)
	# Type emblem centred on the flag: spear = vertical, bow = arc, lance = diagonal, cross = infantry.
	var fc := Vector2(fx + FLAG_WIDTH * 0.5, fy + FLAG_HEIGHT * 0.5)
	var sym_c := Color(1.0, 1.0, 1.0, alpha)
	if is_cavalry:
		draw_line(fc + Vector2(-3.0, 2.5), fc + Vector2(3.0, -2.5), sym_c, 1.5)
	elif anti_cavalry:
		draw_line(fc + Vector2(0.0, 3.0), fc + Vector2(0.0, -3.0), sym_c, 1.5)
	elif is_ranged:
		draw_arc(fc, 2.5, -PI * 0.55, PI * 0.55, 6, sym_c, 1.5)
	else:
		draw_line(fc + Vector2(-2.5, 0.0), fc + Vector2(2.5, 0.0), sym_c, 1.5)
		draw_line(fc + Vector2(0.0, -2.5), fc + Vector2(0.0, 2.5), sym_c, 1.5)
