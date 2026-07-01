extends Node2D
class_name Unit
## A regiment: one selectable token with a soldier count and morale.
## Renders itself via _draw() with per-type sprite shapes: infantry kite
## shield, spearmen hoplon + spear, cavalry horse + rider.
## Its soldier marks are flat geometric shapes when zoomed out and swap to
## detailed figure silhouettes (a standing soldier, a mounted rider) when the
## camera zooms in past LOD_ZOOM_IN — see _update_lod / UnitMeshes.figure_mesh.

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
@export var move_speed: float = 90.0    # sprint pace (also the loadout's declared top speed)
# Walk/jog paces, in world units/s -- independent per-type values (Battle sets them
# from the loadout's walk_mps/jog_mps), not a fixed fraction of move_speed. Real gaits
# don't scale by a uniform ratio across unit types (a horse's walk/trot/gallop ratios
# look nothing like a human's walk/jog/sprint ratios), and load-carriage research shows
# a heavier panoply costs proportionally more at a run than at a walk. Defaults here
# match the old 0.5/0.75 fractions of the default move_speed, for bare test units that
# never get a loadout.
@export var walk_speed: float = 45.0
@export var jog_speed: float = 67.5
# Effective melee reach, in world units (Battle sets it per weapon from reach_m;
# the 26 default is the infantry/sword baseline). A unit counts as in melee
# contact when the gap to its target closes within attack_range + both RADII, so a
# longer-reach weapon (a spear) reaches contact — and strikes — sooner than a
# shorter one (a sword) as the lines close.
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
# Player-set frontage (number of files / columns); 0 means "auto", deriving the
# stable wider-than-deep grid from max_soldiers (UnitFormation.frontage). The
# player can widen or narrow the line via SelectionManager (keyboard + drag); the
# change rides the replay command stream so playback reproduces it. Honoured and
# clamped to [1, max_soldiers] in UnitFormation.frontage.
var frontage_override: int = 0
# Extra rotation (radians) applied to the formation slot grid, on top of the unit heading.
# A quarter-turn turns every soldier in place WITHOUT reorganising the grid: each man
# faces a new way but stands where he stood. unit.facing rotates 90°, and this offset cancels
# that rotation in soldier_world_slots so the slots stay put -- the men don't drift. 0 = the
# grid is square to the heading (the default). A fresh move order / rout reforms it to 0.
var _formation_angle: float = 0.0
# Facing to pivot to once a move order's destination is reached, set by a
# drag-to-form-up order so the unit deploys facing the dragged line rather than its
# march direction. Vector2.ZERO means "keep the march facing" (no deploy turn).
var deploy_facing: Vector2 = Vector2.ZERO
# A commanded heading held throughout a move order so the unit translates toward
# its target WITHOUT turning to face travel -- the side-step maneuver (a small
# lateral shift shuffles sideways instead of pivoting). The unit also moves at a
# measured walk while this is set, to keep its ranks orderly. Vector2.ZERO means
# "face the travel direction" (the default turn-and-march), set per order in
# Battle._apply_order_cmd via UnitManeuver.
var ordered_facing: Vector2 = Vector2.ZERO
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
# Open-order grid-spacing scale. FORMATION_SPACING already sits at the historically
# attested close-order / locked-shield floor (~0.45 m per man) -- there's no
# historically grounded room to pack soldiers tighter than that, so TIGHT reuses the
# same floor (spacing_scale stays 1.0; its bonuses come from
# TIGHT_MISSILE_DEFENSE/TIGHT_CHARGE_ABSORPTION and the smaller separation_radius
# above, not from squeezing marks closer than any real formation ever stood). Only
# LOOSE widens the grid, to ~0.9 m per man -- matching the researched "room to wield
# a weapon" open-order figure.
const LOOSE_SPACING_SCALE: float = 2.0
# Melee intermixing: a legacy softening of enemy separation for fighting non-hold
# units. Largely superseded by the engaged-enemy front-rank close-up in _separate
# (which lets lines meet at contact and the per-soldier collision set the spacing);
# kept as a fallback for the non-engaged path. Rise is fraction per second; decay is
# 4x faster so a unit that breaks contact re-solidifies promptly.
const MELEE_INTERMIX_RATE: float = 0.07
const MELEE_INTERMIX_DECAY_RATE: float = 0.28
const MELEE_INTERMIX_MAX: float = 0.85
# How hard a committed melee unit presses onto the enemy while fighting, as a fraction
# of move speed. The separation / engaged-enemy front-rank floor counters it, so the
# value only sets how fast the lines close to contact, not the final spacing.
# AUTO mode walks by default (walk_speed), jogs when a ranged enemy is within
# RANGED_RANGE (jog_speed, under fire), and sprints (move_speed) once within
# SPRINT_START_DISTANCE of the target. WALK mode holds walk pace throughout —
# mandatory for formed stances (shield wall, pike phalanx) that break on a jog.
const SPRINT_START_DISTANCE: float = 200.0   # px from target: start full-speed charge
# Orderly move orders pivot the block about its centre toward their travel direction at
# this angular rate (rad/s) rather than snapping, so the ranks turn in good order. A
# half-circle (180°) centre pivot takes ~PI / TURN_RATE seconds. Combat chases still snap
# (they pass orderly = false to _move_to).
const TURN_RATE: float = PI
# Conversio (drill about-face): every soldier turns in place to reverse, so unit.facing
# rotates toward the opposite heading at this rate (rad/s), taking ~0.5 s for a full 180°.
# This is NOT a pivot of the block — neither a centre pivot (move orders) nor a flank wheel
# (circumductio); each man simply turns where they stand. The spring restoring force in
# SoldierBodies.step is zeroed while the turn runs, so soldiers stay at their grid positions
# despite the facing change — they rotate without drifting.
const CONVERSIO_TURN_RATE: float = PI * 2.0

const MELEE_PRESS_FRACTION: float = 0.6
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
# Pace mode: when true the unit always walks (walk_speed), overriding the
# AUTO escalation to jog/sprint. Set from the walk_advance setting at order time.
var walk_advance: bool = false
# Set to true in _think when a ranged enemy is within RANGED_RANGE; drives the
# AUTO-pace jog escalation. Cleared each frame before the check.
var _under_fire: bool = false

var support_target: Unit = null
# Field rectangle the unit keeps inside when kiting (set by Battle on spawn). The
# default is effectively unbounded so direct Unit tests don't need to set it.
var field_bounds: Rect2 = Rect2(-100000, -100000, 200000, 200000)

const RADIUS: float = 18.0
const DETECTION_RANGE: float = 190.0
# How often a melee unit applies a damage tick. This is the regiment's *aggregate*
# cadence — one tick stands for the whole front rank trading blows over that span,
# not a single soldier's swing — so it's tuned for battle pace, not literal sword
# strikes per second. (Per-soldier strike timing would come with the individual-
# soldier layer; see docs/individual-collision-design.md.)
const ATTACK_INTERVAL: float = 0.6
const ROUT_TIME: float = 6.0
# How long a non-fighting unit holds position to reform its ranks after a fresh move
# order is issued with reform_before_move on. Runs concurrently with order_response_delay
# (both count from zero); the effective delay before the march is max(order_response_delay,
# REFORM_DURATION). Deterministic (a plain counter, no RNG), so replays stay exact.
const REFORM_DURATION: float = 0.8
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
# Rates are tuned to real time (move speeds are real m/s, SPEED_SCALE = 1.0):
# sustained melee wears a unit down over minutes, not seconds. At FATIGUE_PER_SEC
# an untrained unit reaches full exhaustion after ~2.4 min of unbroken fighting
# (a meaningful ~20% attack penalty after ~1.2 min), and recovers fully after
# ~3.3 min of rest -- so relief is worth committing to but not constant churn.
const FATIGUE_PER_SEC: float = 0.7
const FATIGUE_RECOVER_PER_SEC: float = 0.5
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
# width for crowding, assigned per type in _ready(). Each stays below that type's
# melee contact (its attack_range + both RADII) so units still press into contact
# instead of bouncing apart. Cavalry are bulkier; spearmen a touch wider than
# infantry. (Spears reach far past their footprint; the foot-sword baseline,
# floor 36 < contact 62, is the tightest melee case.)
const SEPARATION_RADIUS_INFANTRY: float = 18.0
const SEPARATION_RADIUS_SPEARMEN: float = 20.0
const SEPARATION_RADIUS_CAVALRY: float = 24.0
# Hard ceiling on a footprint (merging widens it). Two maxed units floor at
# 2*28 = 56, still under the melee reaches of the foot/horse types (sword
# contact 62, spear far more), so even merged mega-units keep pressing into
# contact. (Archers carry a short sidearm by design and fight at range, so the
# pathological case of two maxed archer blobs is not a melee concern.)
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
# gallop (~170 = the loadout's 8.5 m/s * Battle.WORLD_UNITS_PER_METER 20) so a full
# charge ~matches the intended x1.8, but it's a plain literal on purpose — deriving it
# from Battle's constants would reintroduce the Unit<->Battle preload cycle this file
# avoids elsewhere. Changing cavalry speed just rescales the charge (faster hits harder,
# by design); nothing breaks. The bonus always scales with the unit's own gallop
# (speed_toward <= move_speed): a cavalry at the reference speed peaks at the reference
# x1.8, and a faster one exceeds it on purpose — intended scaling, not a cap (no assert).
const CHARGE_REFERENCE_SPEED: float = 170.0
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
# Reform-before-move: when a fresh move order arrives with "reform":true, the
# destination is stored here and _reform_timer counts down. Until it expires the
# unit holds position (IDLE); on expiry _commit_pending_reform() sets has_move_target.
# A subsequent order clears the timer, cancelling the pending reform.
var _reform_target: Vector2 = Vector2.ZERO
var _reform_timer: float = 0.0
var _moved_last_frame: bool = false
# Velocity the unit carried into its last move; the cavalry charge bonus reads it
# at contact. Spent by _strike (so only the contact strike charges, not the grinding
# strikes after) and cleared when the unit goes idle/holds (a stationary unit carries no
# momentum); kept while FIGHTING so a strike delayed by attack cooldown still lands it.
var _approach_velocity: Vector2 = Vector2.ZERO
# Velocity the regiment center followed its soldiers' centroid at this tick (phase 5):
# the soldier->regiment coupling slides the center toward where its bodies actually are,
# so friendly collision (and later all collision) emerges from the soldier layer. Stored
# for diagnostics/tests; the move itself happens in SoldierBodies.couple, bounded so it
# never teleports.
var _body_follow_vel: Vector2 = Vector2.ZERO
var _relief_partner: Unit = null   # unit we're swapping with mid-relief
var team_color: Color = Color.WHITE
# Collision footprint for _separate(); assigned per type in _ready().
var separation_radius: float = SEPARATION_RADIUS_INFANTRY
# The merge-aware "base" footprint at Normal formation — updated on spawn and
# whenever absorb() widens separation_radius. set_formation(NORMAL) restores to
# this rather than to the raw type constant, so a merged unit doesn't silently
# lose its widened body on a formation cycle.
var _base_separation_radius: float = SEPARATION_RADIUS_INFANTRY
# Density scale for the formation grid itself: set_formation() sets this alongside
# separation_radius, so LOOSE (open marching order) actually spreads soldiers out --
# not just widens an abstract collision footprint. TIGHT stays at 1.0 (see
# LOOSE_SPACING_SCALE above for why there's no tighter-than-default grid spacing).
# UnitFormation.slots() and _front_depth() read it; the files/ranks count itself
# never changes, only the spacing between them.
var spacing_scale: float = 1.0
# Rises while this unit is locked in mutual melee (both FIGHTING, neither HOLD).
# Scales down the separation push vs. matched enemies so units gradually intermix.
var _combat_intermixing: float = 0.0

var _flock_color: Color = Color(0, 0, 0, 0)     # last body modulate applied to the marks
var _block_extent: float = RADIUS       # block half-size; sizes the ring/halo/bars/shadow
# Render fast-path bookkeeping. _render_dirty is raised by SoldierBodies.step whenever a
# body actually moves (and by seed / about-face relabel); _process consumes it so the
# MultiMeshes are only rewritten when something visible changed, not every idle frame.
# The extent inputs (soldier count, frontage) are cached so the shadow/chrome recompute —
# and its PackedVector2Array alloc — only runs when the formation footprint changes.
var _render_dirty: bool = true
var _render_last_facing: Vector2 = Vector2.DOWN
var _render_extent_n: int = -1
var _render_extent_frontage: int = -1
var _mm_body: MultiMesh = null
var _mm_outline: MultiMesh = null
var _mmi_body: MultiMeshInstance2D = null
var _mmi_outline: MultiMeshInstance2D = null
var _shadow: Polygon2D = null
# Both level-of-detail variants of the body/outline meshes, built once in
# _setup_flock_renderer and swapped on the MultiMeshes as the camera zooms.
var _mark_body_mesh: ArrayMesh = null       # flat geometric mark (zoomed out)
var _mark_outline_mesh: ArrayMesh = null
var _figure_body_mesh: ArrayMesh = null     # detailed figure silhouette, facing right (zoomed in)
var _figure_outline_mesh: ArrayMesh = null
var _figure_body_mesh_flip: ArrayMesh = null     # same figure mirrored to face left
var _figure_outline_mesh_flip: ArrayMesh = null
var _detailed_lod: bool = false             # true while the figure meshes are active
var _figure_faces_left: bool = false        # which mirror is on the MultiMeshes (figure LOD)
# The cosmetic mark/figure mesh geometry lives in UnitMeshes (built once, shared and
# cached across all units); this node just holds the per-unit mesh handles below.


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

	UnitMorale.tick_fatigue(self, delta)
	UnitMorale.tick_cohesion(self, delta)
	UnitMorale.tick_morale(self, delta)
	tick_engaged(delta)
	UnitRelief.update(self)

	# A stationary, non-fighting unit carries no momentum: drop any leftover approach
	# velocity so a later standing strike can't charge off it. While FIGHTING we
	# keep it — a strike held back by attack cooldown on the contact frame still charges
	# on the next — and _strike spends it, so grinding strikes after the first don't.
	if not _moved_last_frame and state != State.FIGHTING:
		_approach_velocity = Vector2.ZERO

	# The parallel soldier-body layer (seeding + the global engaged-soldier
	# separation) is orchestrated once per tick by Battle, AFTER every unit has
	# settled this frame — see Battle._on_soldier_tick. It's non-authoritative
	# (nothing in combat/movement/morale reads _sim_soldier_pos), so it changes no
	# gameplay; the debug overlay in _draw shows it. See docs/individual-collision-design.md.
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
		# Also drain the reform timer concurrently so both run in parallel; the
		# effective delay before the march is max(order_response_delay, REFORM_DURATION).
		# Guard on the order timer still being positive: if it expires this very frame
		# (just hit 0 above), fall through so the reform block below ticks it once —
		# not twice.
		if _reform_timer > 0.0 and _order_response_timer > 0.0:
			_reform_timer = maxf(0.0, _reform_timer - delta)
		if _order_response_timer > 0.0 and state != State.FIGHTING:
			return

	# Reform phase: unit holds position after the order-response delay expires until
	# reform timer runs out, then commits the pending move. A fighting unit skips the
	# hold and commits immediately so combat orders are never gated by a reform pause.
	if _reform_timer > 0.0:
		if state == State.FIGHTING:
			_commit_pending_reform()
		else:
			_reform_timer = maxf(0.0, _reform_timer - delta)
			if _reform_timer > 0.0:
				state = State.IDLE
				# Use the hold to centre-pivot in place toward the pending destination, so
				# the ranks are already coming onto their heading before the first step. A
				# side-step holds its facing (ordered_facing set), so it doesn't pivot.
				if ordered_facing == Vector2.ZERO:
					_rotate_facing_toward(_reform_target - position, delta)
				return
			_commit_pending_reform()

	# In-place drill turns: every soldier turns where they stand, the block does not advance
	# or pivot as a body. Cancelled by engaging in combat or receiving a move order (the
	# partial rotation is preserved). On arrival each path runs its own completion step so the
	# re-engaged spring sees ~zero error: the conversio reverses body ordering; the quarter-turn
	# absorbs the rotation into _formation_angle.
	#
	# Conversio (about-face, 180°): the grid keeps its shape; bodies just reverse.
	if _conversio_target != Vector2.ZERO:
		if state == State.FIGHTING or has_move_target:
			_conversio_target = Vector2.ZERO
		else:
			if _advance_turn(_conversio_target, delta):
				_conversio_target = Vector2.ZERO
				_reverse_soldier_bodies()
			state = State.IDLE
			return

	# Quarter-turn (90°): every soldier turns in place; the grid does NOT reorganize (the
	# men keep their exact positions). unit.facing rotates 90° while the spring is frozen, and
	# when it stops _formation_angle absorbs however far it turned so soldier_world_slots holds
	# the slots still — no surge, for any grid shape including a depleted partial one. Frontage
	# and depth swap relative to the field, but no man takes a step. An interrupt leaves the
	# offset matching the partial turn, so the bodies don't surge there either.
	if _quarter_target != Vector2.ZERO:
		if state == State.FIGHTING or has_move_target:
			_settle_formation_angle()   # cancel the partial turn so the bodies don't surge
			_quarter_target = Vector2.ZERO
		else:
			if _advance_turn(_quarter_target, delta):
				_settle_formation_angle()
				_quarter_target = Vector2.ZERO
			state = State.IDLE
			return

	# Under-fire detection for AUTO pace: true when any alive enemy ranged unit is
	# within RANGED_RANGE of this unit (i.e. could be shooting at us this frame).
	# Must run before the ORDER_SUPPORT early return so _support_tick's _move_to
	# calls see the correct value.
	_under_fire = false
	for u in get_tree().get_nodes_in_group("units"):
		if u is Unit and u.team != team and u.is_ranged and u.state != State.DEAD \
				and u.state != State.ROUTING \
				and position.distance_to(u.position) <= RANGED_RANGE:
			_under_fire = true
			break

	# Support stance: guard a friendly ward — engage threats near it, else
	# shadow it. Handled up front so it overrides the normal target/move logic. If
	# the ward is gone (dead, routed, or cleared) the order is spent, so drop it and
	# fall through to NORMAL auto-behaviour.
	if order_mode == ORDER_SUPPORT:
		if UnitTargeting.support_valid(self):
			_support_tick(delta)
			return
		support_target = null
		order_mode = 0   # ward gone: revert to NORMAL

	var enemy: Unit = UnitTargeting.current_target(self)
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
			_move_to(UnitTargeting.clamp_to_field(self, position + away.normalized() * SKIRMISH_KITE_DISTANCE), delta)
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
				UnitCombat.shoot(self, enemy)
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
				UnitCombat.strike(self, enemy)
			# Press into contact: a committed melee unit keeps advancing onto the enemy
			# while it fights, so the lines close to body contact (separation provides the
			# counterforce, settling them at the engaged-enemy front-rank floor) instead
			# of trading blows at arm's length. A HOLD stance holds its ground and doesn't
			# press; ranged units don't melee-press at all.
			if not is_ranged and order_mode != ORDER_HOLD:
				_press_into(enemy.position, delta)
			return
		elif target_enemy != null:
			# Explicit attack order, not yet in contact: chase past any move target.
			# A flank/rear stance closes on the enemy's side or back instead of
			# head-on, so the strike on arrival lands with the flank/rear bonus.
			var goal: Vector2 = enemy.position
			if order_mode == ORDER_ATTACK_FLANK or order_mode == ORDER_ATTACK_REAR:
				goal = UnitTargeting.attack_approach_point(self, enemy)
			_move_to(goal, delta)
			return

	# Obey a move order (disengaging if needed), else auto-advance on a near enemy.
	# A player move order marches orderly -- it centre-pivots gradually toward its heading
	# before advancing; combat chases above stay snappy (orderly = false).
	if has_move_target:
		if position.distance_to(move_target) > 5.0:
			_move_to(move_target, delta, true)
		elif not waypoints.is_empty():
			# Each queued leg marches on its own terms: drop any side-step hold from
			# the leg just finished so the next leg turns to face its own travel.
			ordered_facing = Vector2.ZERO
			move_target = waypoints.pop_front()   # advance along the queued route
		else:
			has_move_target = false
			state = State.IDLE
			# The side-step maneuver is spent on arrival; the held facing stays (it is
			# already the unit's facing), so just drop the maneuver flag.
			ordered_facing = Vector2.ZERO
			# A drag-to-form-up order parks a deploy facing here; pivot to it on
			# arrival (the soldier bodies then ease into the rotated formation).
			if deploy_facing != Vector2.ZERO:
				facing = deploy_facing
				deploy_facing = Vector2.ZERO
	elif enemy != null and order_mode != ORDER_HOLD:
		_move_to(enemy.position, delta)
	else:
		# Idle: no enemy, or a HOLD stance that won't chase — the paths above
		# still fight/fire whatever reaches a held unit.
		state = State.IDLE


# --- Targeting & support order ----------------------------------------------
# The target-acquisition QUERIES (current target, nearest threat, ward validity, approach
# point, field clamp) live in UnitTargeting; the order EXECUTION that consumes them stays
# here (the AI brain in _think, and _support_tick below).

## Support stance: guard the ward. If an enemy has closed within
## SUPPORT_GUARD_RADIUS of the ward, peel off and engage it (firing at standoff if
## ranged, melee in contact, else closing on it); otherwise shadow the ward,
## holding a short standoff so the supporter doesn't pile onto the unit it guards.
## Targeting keys off the WARD's position, so the supporter returns to its charge
## once a threat is dealt with. Deterministic (no RNG / wall-clock), matching the
## normal fire/melee cadence so live and replayed battles stay in lockstep.
func _support_tick(delta: float) -> void:
	var ward: Unit = support_target
	var threat: Unit = UnitTargeting.nearest_enemy_to(self, ward.position, SUPPORT_GUARD_RADIUS)
	if threat != null:
		var dist: float = position.distance_to(threat.position)
		var in_contact: bool = dist <= attack_range + RADIUS + threat.RADIUS
		if is_ranged and not in_contact and dist <= RANGED_RANGE:
			state = State.FIGHTING
			_face(threat.position)
			if _attack_cd <= 0.0:
				_attack_cd = RANGED_INTERVAL
				UnitCombat.shoot(self, threat)
		elif in_contact:
			state = State.FIGHTING
			_face(threat.position)
			if _attack_cd <= 0.0:
				_attack_cd = ATTACK_INTERVAL
				UnitCombat.strike(self, threat)
		else:
			_move_to(threat.position, delta)
		return
	# No threat near the ward: shadow it, holding station a short distance off so
	# the supporter doesn't crowd the unit it's guarding.
	if position.distance_to(ward.position) > SUPPORT_FOLLOW_DISTANCE:
		_move_to(ward.position, delta)
	else:
		state = State.IDLE


# --- Movement --------------------------------------------------------------

func _move_to(point: Vector2, delta: float, orderly: bool = false) -> void:
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
	# Facing. A side-step holds its commanded heading and shuffles sideways. An
	# orderly move order centre-pivots gradually toward its travel direction (the ranks
	# turn in good order). A combat chase faces travel instantly (it must stay responsive).
	var maneuvering: bool = ordered_facing != Vector2.ZERO
	if maneuvering:
		_face_dir(ordered_facing)
	elif orderly:
		_rotate_facing_toward(dir, delta)
	else:
		_face_dir(dir)
	# Pace: a maneuver or walk-advance holds walk speed throughout. AUTO otherwise
	# walks by default, jogs under missile fire, and sprints at full speed once
	# close to the target. Each pace is this unit's own gait speed, not a fraction
	# of another -- see walk_speed/jog_speed/move_speed above.
	var pace_speed: float
	if maneuvering or walk_advance:
		pace_speed = walk_speed
	elif position.distance_to(point) <= SPRINT_START_DISTANCE:
		pace_speed = move_speed  # sprint distance beats under-fire: charge through the kill zone at full speed
	elif _under_fire:
		pace_speed = jog_speed
	else:
		pace_speed = walk_speed
	var effective_speed: float = pace_speed * terrain_speed
	# Turn-before-march: while centre-pivoting an orderly move, scale the advance by how
	# far the unit has come onto its heading. A sharp turn (e.g. a 180° pivot to a rear
	# destination) nearly halts and pivots, then accelerates as it aligns -- so it
	# never slides backwards/sideways at speed. Full speed once within ~60 deg of the
	# heading; side-steps are exempt (they march at a fixed walk perpendicular).
	if orderly and not maneuvering:
		effective_speed *= clampf(facing.dot(dir) * 2.0, 0.0, 1.0)
	position += dir * effective_speed * delta
	state = State.MOVING
	_moved_last_frame = true
	# Charge velocity; terrain-scaled so forest reduces the charge bonus (intentional — can't sprint in trees).
	_approach_velocity = dir * effective_speed


## Lean into a melee: nudge the position toward `point` WITHOUT flipping to MOVING or
## carrying a charge velocity. Unlike _move_to, it leaves `state` (FIGHTING) and
## `_approach_velocity` untouched — a grinding melee mustn't re-charge every strike,
## and the cavalry's one-shot impact velocity must survive the cooldown wait. The
## separation / engaged-enemy front-rank floor counters the press, so the line settles
## at body contact instead of trading blows at arm's length.
func _press_into(point: Vector2, delta: float) -> void:
	var to: Vector2 = point - position
	if to.length() < 1.0:
		return
	position += to.normalized() * move_speed * MELEE_PRESS_FRACTION * delta


func _face(point: Vector2) -> void:
	_face_dir(point - position)


func _face_dir(dir: Vector2) -> void:
	if dir.length() > 0.01:
		facing = dir.normalized()


## Rotate `facing` toward `target_dir` by at most `rate` * delta this frame — the
## gradual turn primitive shared by the orderly move order's centre pivot and the
## conversio about-face, instead of snapping. Takes the shortest arc, so a 180°
## reversal turns through the nearer side.
func _rotate_facing_toward(target_dir: Vector2, delta: float, rate: float = TURN_RATE) -> void:
	if target_dir.length() < 0.01:
		return
	var cur: float = facing.angle()
	var diff: float = angle_difference(cur, target_dir.angle())
	var step: float = clampf(diff, -rate * delta, rate * delta)
	facing = Vector2.from_angle(cur + step)


## Collision footprint by unit type. Cavalry get the widest body, spearmen a bit
## wider than infantry; all stay below attack reach so melee still presses.
func _type_separation_radius() -> float:
	if is_cavalry:
		return SEPARATION_RADIUS_CAVALRY
	if anti_cavalry:
		return SEPARATION_RADIUS_SPEARMEN
	return SEPARATION_RADIUS_INFANTRY


## The block's depth from its centre to its FRONT rank, in world units: how far the
## leading rank sits ahead of the unit centre along its facing (the formation is
## rank-major, front rank at -Y locally). Two enemy blocks whose centres are this far
## apart, summed, meet front-to-front — so engaged enemies use it as their separation
## floor, closing the lines to contact instead of holding a fixed gap.
func _front_depth() -> float:
	var files: int = UnitFormation.frontage(self)
	var ranks: int = int(ceil(float(soldiers) / float(files)))
	var depth: float = float(ranks - 1) * 0.5 * FORMATION_SPACING * spacing_scale
	# Cap the depth used as the engaged-enemy separation floor. A very narrow,
	# deep player-set frontage would otherwise make the summed floor exceed melee
	# contact range, pushing fighting lines apart faster than they close and
	# stuttering the melee. Half the unit's own reach keeps the summed floor
	# (this + the foe's) safely inside contact distance for every unit type. Heavy
	# melee units at normal widths sit below their cap, so it only bites on
	# narrowed columns; short-reach archers can clip it even at auto width, but
	# that only allows fractionally more overlap and they kite rather than grind.
	return minf(depth, attack_range * 0.5)


## Change the regiment's formation and recalculate its separation footprint.
## Uses _base_separation_radius (which absorb() keeps updated) so a formation
## cycle on a merged unit doesn't discard the merge-widened body.
func set_formation(mode: int) -> void:
	formation_mode = mode
	var base := _base_separation_radius
	if mode == FORMATION_TIGHT:
		separation_radius = base * TIGHT_SEPARATION_SCALE
		spacing_scale = 1.0   # already at the historical close-order/locked-shield floor
	elif mode == FORMATION_LOOSE:
		separation_radius = minf(SEPARATION_RADIUS_MAX, base * LOOSE_SEPARATION_SCALE)
		spacing_scale = LOOSE_SPACING_SCALE
	else:
		separation_radius = base
		spacing_scale = 1.0


## Set the regiment's frontage (file count). Clamped to [1, max_soldiers]; the
## formation grid (UnitFormation.slots) picks it up on the next tick and the
## soldier bodies ease toward the reshaped slots at velocity (no teleport).
func set_frontage(files: int) -> void:
	frontage_override = clampi(files, 1, maxi(1, max_soldiers))


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
		# Phase 5 (slice 1): friendly regiments no longer collide as circles -- their
		# spacing is resolved at the soldier level (SoldierSteering's friendly tier feeds
		# the body->regiment coupling). The regiment circle now only separates ENEMIES; the
		# enemy front-rank closeup and the spear-vs-cavalry hard block below are unchanged.
		# (The move-through-idle / relief exemptions were friendly-only, so they re-home to
		# the steering pass too.)
		if other.team == team:
			continue
		# (The move-through-idle / relief exemptions were friendly-only, so once friendlies
		# are skipped there's nothing left to exempt here -- the checks re-home to the
		# steering pass. _separation_exempt is still used there.)
		var min_dist: float
		if other.team != team and is_engaged() and other.is_engaged():
			# Engaged enemy lines close until their FRONT RANKS meet (centres a block-
			# depth apart on each side), then the per-soldier collision pass holds the
			# contact and packs the soldiers — so the spacing emerges from the bodies,
			# not a fixed enemy gap. No type-specific standoff here: a spear's reach
			# standoff is meant to emerge from knockback, not a separation rule.
			min_dist = _front_depth() + other._front_depth()
		else:
			min_dist = separation_radius + other.separation_radius
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
## this unit and `other`, so their lines close into contact. Both must be actively
## fighting without a hold order.
func _is_melee_intermixing_with(other: Unit) -> bool:
	if other.team == team:
		return false
	return state == State.FIGHTING \
			and other.state == State.FIGHTING \
			and order_mode != ORDER_HOLD \
			and other.order_mode != ORDER_HOLD


# --- Individual-soldier simulation (simulated bodies, rendered + authoritative melee) ---
# The soldiers you SEE are the simulated bodies. Each tick Battle advances every
# regiment's persistent parent-local `_sim_soldier_pos` at velocity (SoldierBodies): a
# body springs toward its formation slot, feeds the friendly-avoidance steering velocity
# forward (SoldierSteering), and holds any knockback the melee dealt it (SoldierMelee) —
# no body teleports, and there is no position-correction separation pass. The render
# loop reads `_sim_soldier_pos` directly, so the cross-regiment per-soldier
# spacing is visible. The engaged positions are AUTHORITATIVE for per-soldier melee (who
# is in reach of whom), but movement, morale, and `_separate()` still read the regiment
# circle, so those OUTCOMES come from the circle. Full plan in
# docs/individual-collision-design.md.

# Master switch for the soldier layer. ON: the persistent soldier bodies advance one
# velocity step per tick (steering + knockback, no separation pass) and the soldier
# render follows them. Per-soldier melee reads the engaged bodies; regiment
# movement/morale still run off the circle.
const INDIVIDUAL_COLLISION: bool = true

# A soldier's global id is `uid * SOLDIER_ID_STRIDE + index`: a unique,
# replay-stable key per soldier for ordering and tie-breaks, stable even as a
# regiment loses soldiers. The stride exceeds any plausible max_soldiers
# (default 120), so two regiments' id ranges never overlap.
const SOLDIER_ID_STRIDE: int = 1024

# Parent-local positions (relative to the unit's transform, i.e. built from
# `unit.position` — compare against `.position`, not `.global_position`) of this
# regiment's simulated soldiers, index-aligned with their ids.
var _sim_soldier_pos: PackedVector2Array = PackedVector2Array()

# Persistent per-body velocity (parent-local, same frame as _sim_soldier_pos),
# index-aligned with _sim_soldier_pos.
# Phase 4 gives the bodies persistent dynamics: instead of re-seeding their positions
# from the formation every tick (phase 3), each engaged body springs toward its slot
# and integrates this velocity, so a soldier displaced by separation HOLDS the
# displacement and eases back rather than snapping to formation. The spring itself
# lives in SoldierBodies; this is the state it advances. Still non-authoritative.
var _sim_body_vel: PackedVector2Array = PackedVector2Array()

# Per-soldier friendly-avoidance steering velocity (parent-local, same frame as
# _sim_soldier_pos), index-aligned with _sim_soldier_pos. Recomputed each tick by
# SoldierSteering for the engaged subset (zero
# elsewhere); SoldierBodies feeds it forward so an engaged body drifts off a crowding
# friendly instead of overlapping it. Velocity-based — it never moves a body directly.
var _sim_steer: PackedVector2Array = PackedVector2Array()

# Per-soldier health pool (phase 4b), index-aligned with _sim_soldier_pos: each body
# accumulates wounds across ticks and dies (removed, re-packing the formation) when it
# reaches 0. Seeded to the per-type max health (see SoldierBodies.seed). A near-dead
# soldier also fights worse, via SoldierCombat.condition, so wounds compound.
var _sim_soldier_hp: PackedFloat32Array = PackedFloat32Array()

# Per-soldier prone timer (phase 4b), index-aligned with _sim_soldier_pos: seconds-to-rise
# remaining (0 = standing). A knockback impulse can fell a soldier (SoldierCombat.prone_chance);
# a prone soldier loses active defence and can't strike until the timer decays to 0
# (SoldierBodies.step decrements it). Seeded to 0 (everyone standing).
var _sim_prone: PackedFloat32Array = PackedFloat32Array()

# Per-soldier stamina pool (slice D), index-aligned with _sim_soldier_pos: current stamina
# in [0, max_stamina] where max_stamina is the per-type value from combat_profile(). Drained
# by every strike thrown (KAPPA_A), by every blow met (KAPPA_D*phi*(1+c)), and by rising from
# prone (KAPPA_P); restored at RHO_STAMINA per second in SoldierBodies.step. Low stamina
# reduces both offence and active defence through SoldierCombat.stamina_factor (g(sigma)).
var _sim_soldier_stamina: PackedFloat32Array = PackedFloat32Array()

# Per-soldier facing (the drill-maneuver foundation), index-aligned with
# _sim_soldier_pos. By default every body faces the unit heading (kept synced each
# tick in SoldierBodies.step). A per-soldier maneuver -- about-face (conversio),
# the quarter-turn -- takes ownership via set_all_soldier_facing/set_soldier_facing
# (which raise the _per_soldier_facing flag); the bodies then keep their own
# facings until release_soldier_facing() hands control back to the unit heading.
var _sim_soldier_facing: PackedVector2Array = PackedVector2Array()
# While true, _sim_soldier_facing is owned by a maneuver and NOT re-synced to the
# unit heading each tick. False = bodies track unit.facing (the default).
var _per_soldier_facing: bool = false
# Non-zero while a conversio (in-place about-face) is in progress: the target (reversed)
# facing direction. unit.facing rotates toward this each tick; SoldierBodies.step zeroes the
# spring restoring force while it turns so bodies don't drift to intermediate slot positions.
# Cleared on arrival or when interrupted by combat, a move order, or routing.
var _conversio_target: Vector2 = Vector2.ZERO
# Non-zero while a quarter-turn (90° in-place turn) is in progress: the target facing, 90°
# to the left or right of the start. Same spring-freeze as the conversio; the heading the
# turn started from is kept so _formation_angle can absorb exactly how far it turned when it
# stops (full turn or an interrupt), leaving the slots — and the men — exactly where they were.
var _quarter_target: Vector2 = Vector2.ZERO
var _quarter_start_facing: Vector2 = Vector2.ZERO

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
	var slots := UnitFormation.slots(self, count)
	# _formation_angle lets a quarter-turn rotate every soldier's facing without moving the
	# grid: it cancels the heading rotation here, so the slots (and the men) stay put.
	var ang: float = facing.angle() + PI * 0.5 + _formation_angle
	for i in range(slots.size()):
		out.push_back(position + slots[i].rotated(ang))
	return out


## --- Per-soldier facing (drill-maneuver foundation) -------------------------
## By default each body faces the unit heading; these let a maneuver orient bodies
## individually. _sim_soldier_facing is index-aligned with _sim_soldier_pos.

## Point every body at `dir` and take maneuver ownership (the per-tick re-sync to
## the unit heading stops until release_soldier_facing()). No-op for a zero dir.
func set_all_soldier_facing(dir: Vector2) -> void:
	# No bodies yet (pre-seed): take no ownership, so a later seed/step doesn't
	# leave the flag set with the bodies silently facing the unit heading.
	if dir.length() < 0.01 or _sim_soldier_facing.is_empty():
		return
	_per_soldier_facing = true
	var d: Vector2 = dir.normalized()
	for i in range(_sim_soldier_facing.size()):
		_sim_soldier_facing[i] = d


## Point a single body at `dir` and take maneuver ownership. Out-of-range index or
## a zero dir is a no-op.
func set_soldier_facing(index: int, dir: Vector2) -> void:
	if index < 0 or index >= _sim_soldier_facing.size() or dir.length() < 0.01:
		return
	_per_soldier_facing = true
	_sim_soldier_facing[index] = dir.normalized()


## Hand facing control back to the unit heading: clear the maneuver flag and
## re-sync every body to the current unit facing.
func release_soldier_facing() -> void:
	_per_soldier_facing = false
	if _sim_soldier_facing.size() > 0:
		_sim_soldier_facing.fill(facing)


## Conversio (about-face, Vegetius III): every soldier turns in place to reverse 180° at
## CONVERSIO_TURN_RATE rad/s (~0.5 s for a full reversal). The grid keeps its footprint —
## the block does not pivot, neither about its centre (a move order) nor on a flank
## (a wheel / circumductio); each man just turns where they stand.
## unit.facing tracks the turn each tick so the sim always knows the soldiers' current
## facing (shield side, etc.). SoldierBodies.step zeroes the spring restoring force while
## it turns, so bodies stay at their grid positions instead of drifting to intermediate
## slot targets. If interrupted by combat or a move order, unit.facing stays at its current
## angle — the partial rotation is preserved. Blocked while fighting, before seeding, or
## while another in-place turn (conversio or quarter-turn) is already running.
func conversio() -> void:
	if state == State.FIGHTING or _sim_soldier_facing.is_empty() \
			or _conversio_target != Vector2.ZERO or _quarter_target != Vector2.ZERO:
		return
	_conversio_target = Vector2(-facing.x, -facing.y)


## Quarter-turn (90° in-place turn, Aelian/Asclepiodotus): every soldier pivots a quarter
## turn to the left (`dir` = -1) or right (`dir` = +1); the unit's frontage and depth swap
## relative to the field, but the men do not march and the internal grid is NOT reorganized —
## each man just turns where they stand. facing rotates toward the target with the spring frozen so
## the bodies hold their ground; on arrival _formation_angle absorbs the rotation so
## soldier_world_slots reproduces the men's positions (no transpose, no relabel). Blocked while
## fighting, before seeding, or while another in-place turn (conversio or quarter-turn) runs —
## re-arming mid-turn would reset the start heading and corrupt the settled offset.
func quarter_turn(dir: int) -> void:
	if state == State.FIGHTING or _sim_soldier_facing.is_empty() or dir == 0 \
			or _quarter_target != Vector2.ZERO or _conversio_target != Vector2.ZERO:
		return
	_quarter_start_facing = facing
	_quarter_target = facing.rotated(signf(dir) * PI * 0.5)


## Fold the rotation the quarter-turn just applied (start heading -> current heading) into
## _formation_angle, so soldier_world_slots reproduces the men's pre-turn slot positions and
## the arrival spring sees ~zero error. Works for a full 90° turn or an interrupted partial.
func _settle_formation_angle() -> void:
	var turned: float = angle_difference(_quarter_start_facing.angle(), facing.angle())
	_formation_angle = wrapf(_formation_angle - turned, -PI, PI)
	_render_dirty = true


## Advance an in-place turn one tick: rotate `facing` toward `target` at the drill rate and
## report whether it arrived this tick (snapping exactly onto the target so the completion step
## runs on an exact heading — the conversio's body reverse, the quarter-turn's offset settle).
## Shared by the conversio and the quarter-turn.
func _advance_turn(target: Vector2, delta: float) -> bool:
	_rotate_facing_toward(target, delta, CONVERSIO_TURN_RATE)
	if facing.dot(target) > 1.0 - 0.0001:
		facing = target
		return true
	return false


## Relabel the bodies for a completed about-face. The men keep their world positions, but
## facing has flipped 180°, so every formation slot rotates to its point-reflected spot —
## front rank and rear rank swap sides. Reversing the index-aligned body arrays maps each
## body onto the slot it now physically occupies, so SoldierBodies.step's arrival spring
## sees ~zero error and the block doesn't surge across itself. A centrosymmetric grid
## cancels exactly; a partial rear rank leaves a small residual the spring eases. Pure
## index permutation — no positions change — so it's replay-deterministic.
func _reverse_soldier_bodies() -> void:
	_sim_soldier_pos.reverse()
	_sim_body_vel.reverse()
	_sim_soldier_hp.reverse()
	_sim_prone.reverse()
	_sim_soldier_stamina.reverse()
	_sim_soldier_facing.reverse()
	if _sim_steer.size() == _sim_soldier_pos.size():
		_sim_steer.reverse()
	_render_dirty = true   # positions were relabelled — redraw next frame


## The facing of body `index`; the unit heading for an out-of-range index (so
## callers never index past a mid-resize array).
func soldier_facing(index: int) -> Vector2:
	if index < 0 or index >= _sim_soldier_facing.size():
		return facing
	return _sim_soldier_facing[index]


## Half-extent of the seeded soldier block around the regiment center: the
## containment radius the parallel layer must stay within while the regiment
## circle is authoritative. Reuses the render's block-extent math.
func soldier_block_extent() -> float:
	return SoldierFlock.compute_extent(self, UnitFormation.slots(self, soldiers))


## The render block's current half-size: the cached extent _process maintains as
## the block forms and takes casualties (what _draw sizes the state ring / selection halo /
## bars to). Unlike soldier_block_extent(), this returns the maintained field rather than a
## fresh recompute, so the demo-pointer overlay's selection halo matches the drawn block.
func render_block_extent() -> float:
	return _block_extent


## Seed the parallel soldier-body layer from the current formation. Deterministic
## and side-effect-free beyond `_sim_soldier_pos`. Read by the global separation
## pass and the flock render (phase 3), but NOT by gameplay (the regiment circle
## stays authoritative), so it changes no combat/movement/morale outcome.
func seed_sim_soldiers() -> void:
	SoldierBodies.seed(self)


## Advance this regiment's persistent soldier bodies one fixed step. The dynamics
## live in SoldierBodies.step (the engaged front ranks spring toward their slots and
## hold displacement; the unengaged bulk snaps to formation).
func step_sim_soldiers(delta: float) -> void:
	SoldierBodies.step(self, delta)


# --- Individual-soldier simulation: engaged tier --------------------------
# The expensive per-soldier work (the friendly-avoidance steering pass and per-soldier
# melee) runs only for *engaged* soldiers — the front ranks of a regiment in (or just out
# of) melee — while the unengaged bulk keeps following its formation slot cheaply. This is
# the level-of-detail split from docs/individual-collision-design.md: it bounds the work
# to ~the contact faces rather than every soldier on the field. The steering pass is
# global across all regiments (see Battle's per-tick soldier orchestration and
# SoldierSteering), so friendly front ranks avoid each other across regiment lines.

# A regiment is "engaged" while FIGHTING and for ENGAGED_LINGER seconds after, so
# the tier boundary has hysteresis and soldiers don't flap between full-sim and
# formation-follow at the threshold. ENGAGED_RANKS front ranks run the full pass.
const ENGAGED_LINGER: float = 0.5
const ENGAGED_RANKS: int = 3

# Soldier->regiment coupling (phase 5): each tick the regiment center slides a fraction
# FOLLOW_RATE*delta of the way toward its soldiers' centroid (geometric decay, stable for
# FOLLOW_RATE*delta < 1; ~10%/tick at 60 Hz). The step is capped at MAX_FOLLOW_SPEED*delta
# so the center can never teleport -- it only ever moves at a bounded velocity, like the
# soldier bodies. During a clean march the bodies sit on their slots, so the drift is ~0
# and the coupling is silent; it activates only when bodies are pushed off formation.
const FOLLOW_RATE: float = 6.0
const MAX_FOLLOW_SPEED: float = 80.0

# > 0 while engaged; FIGHTING refreshes it, otherwise it decays on the fixed tick.
var _engaged_linger: float = 0.0


## Advance the engaged-tier latch. Deterministic — driven by combat state and the
## fixed-step delta, never wall-clock — so it reproduces on replay.
func tick_engaged(delta: float) -> void:
	if state == State.FIGHTING:
		_engaged_linger = ENGAGED_LINGER
	else:
		_engaged_linger = maxf(0.0, _engaged_linger - delta)


## True while this regiment is in the engaged tier (its front ranks run the full
## per-soldier pass). A function of the latch only.
func is_engaged() -> bool:
	return _engaged_linger > 0.0


## How braced (set to receive) this regiment's soldiers are, in [0, 1] (#201 bracing): a
## regiment engaged and not skirmishing is set and buttresses knockback/knockdown; a loose
## skirmish line, or one not engaged, is not. Binary for now -- graded postures (advancing /
## sprinting / braced) come with the posture slice. Front-facing is enforced at the call site.
const BRACE_SET: float = 1.0
func soldier_brace() -> float:
	return BRACE_SET if (is_engaged() and order_mode != ORDER_SKIRMISH) else 0.0


## Indices of the engaged soldiers: the front ENGAGED_RANKS ranks of an engaged
## regiment, or none when it isn't engaged. `UnitFormation.slots` is rank-major
## (rank = index / files, rank 0 = front), so the front ranks are exactly the
## first files*ENGAGED_RANKS indices. Pure and deterministic.
func engaged_soldier_indices(count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not is_engaged() or count <= 0:
		return out
	var cutoff: int = mini(count, UnitFormation.frontage(self) * ENGAGED_RANKS)
	for i in range(cutoff):
		out.push_back(i)
	return out


## A soldier body's radius for this regiment's type — the drawn mark radius, so
## cavalry (horses) take more room than foot. The center-to-center floor between
## two soldiers is the sum of their radii, mirroring the regiment circle's
## `separation_radius + other.separation_radius`.
func soldier_body_radius() -> float:
	return CAV_MARK_RADIUS if is_cavalry else MARK_RADIUS


## This regiment's per-soldier strike reach, in world units: the weapon reach
## (attack_range, set per type from #233 — e.g. spear 48 vs sword 26). A soldier can
## strike an enemy body within this center-to-center distance; a longer reach lets a
## soldier strike foes who cannot strike back — the spear-vs-sword standoff (#240).
func soldier_reach() -> float:
	return attack_range


## Step every regiment's persistent soldier bodies one fixed tick. Called by Battle each
## tick, after the steering pass has set the bodies' friendly-avoidance velocity bias.
## Order-free across regiments, so it stays replay-safe.
static func step_all_sim_soldiers(units: Array, delta: float) -> void:
	for o in units:
		var u: Unit = o as Unit
		if u != null and u.state != State.DEAD:
			u.step_sim_soldiers(delta)


## Slide every regiment's center toward its soldiers' centroid (phase 5), after the bodies
## have integrated this tick. Order-free across regiments (each reads only its own bodies
## and writes only its own position), so it stays replay-safe. Called by Battle each tick
## as the last soldier sub-step.
static func couple_all_sim_soldiers(units: Array, delta: float) -> void:
	for o in units:
		var u: Unit = o as Unit
		if u != null and u.state != State.DEAD:
			SoldierBodies.couple(u, delta)


# --- Individual-soldier combat profile -------------------------------------
# The per-soldier combat MATH lives in SoldierCombat.gd (the opposed land contest,
# the wound, the charge term, the facing gate, the per-type profile). Unit just
# exposes its own profile, reading its type flags and training.

## This regiment's per-soldier combat profile, from its own type flags and training.
## See SoldierCombat.profile_for / docs/combat-model.md "Soldier attributes".
func combat_profile() -> Dictionary:
	return SoldierCombat.profile_for(is_cavalry, anti_cavalry, is_ranged, training)


# --- Order summary (for the HUD / selection overlay) -----------------------

## Human-readable description of this unit's current order — what the player
## told it to do (attack a target, move to a point) or, failing an explicit
## order, what it's doing on its own. Shown in the HUD's selected-unit panel.
func order_summary() -> String:
	if state == State.ROUTING:
		return "Routing!"
	# A SUPPORT order is reported by its ward, ahead of the target/move lookups
	# below — a supporter holds no target_enemy/move_target of its own.
	if order_mode == ORDER_SUPPORT and UnitTargeting.support_valid(self):
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
		# A unit locked in melee is ANCHORED against arriving friendlies: the newcomer
		# yields and flows around it, instead of shoving the fighting unit out of
		# position (which made it rotate to re-face the enemy). Both engaged, or
		# neither, split the correction evenly as before.
		if is_engaged() == other.is_engaged():
			return 0.5
		if is_engaged():
			return 0.0   # I'm fighting — hold the line; the newcomer gives way
		return 1.0       # the other is fighting — I give way fully and flow around it
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


# --- Combat -----------------------------------------------------------------
# The regiment-level combat resolution (charge multiplier, strike, volley,
# friendly-fire interception, casualty/morale/rout bookkeeping) lives in UnitCombat;
# the AI brain and support tick call UnitCombat.strike/shoot. Only resolve_soldier_melee
# stays here — a thin delegate to the per-soldier SoldierMelee, kept for _strike and the
# soldier-melee tests.

## Resolve a melee cadence per soldier against `enemy`. The resolution lives in
## SoldierMelee.resolve (the opposed contest, the wound to per-soldier health, and
## the death/re-pack); this thin wrapper keeps the call from UnitCombat and the tests.
func resolve_soldier_melee(enemy: Unit) -> void:
	SoldierMelee.resolve(self, enemy)


# --- Order response & merge -------------------------------------------------
# The per-tick condition updates live in UnitMorale and the line-relief swap in
# UnitRelief (Unit's _physics_process calls UnitMorale.tick_* and UnitRelief.update each
# frame); the order-response countdown and the regiment merge (absorb) stay here.

## Start the order-response countdown. Called by Battle after stamping new
## motion fields onto the unit. The unit holds its current action for
## order_response_delay seconds before executing the new order.
func start_order_response() -> void:
	_order_response_timer = order_response_delay
	# A move/attack order reforms a quarter-turned unit back square to its heading, so it
	# marches as a proper line rather than crabbing sideways. The bodies ease onto the
	# reformed slots via the spring (a future turn-and-widen move maneuver will make this a
	# deliberate reshape; until then a clean reform is the safe default).
	_formation_angle = 0.0


## Commit a pending reform-before-move: hand off the stored destination to the
## normal move machinery. Called when the reform timer expires or a fighting unit
## receives a move order with reform=true (fights can't be made to hold for reform).
func _commit_pending_reform() -> void:
	move_target = _reform_target
	has_move_target = true
	_reform_timer = 0.0


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
	_reform_timer = 0.0   # cancel any pending reform so a rallied unit doesn't resume a stale destination
	_conversio_target = Vector2.ZERO   # cancel any conversio; unit.facing stays at its current angle
	_quarter_target = Vector2.ZERO     # cancel any quarter-turn likewise
	_formation_angle = 0.0             # a routed unit reforms square to its heading on rally
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
	return UnitTargeting.nearest_enemy_to(self, position, RALLY_CONTACT_RADIUS) == null


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
# Historically-grounded metric values: close-order per-man frontage is
# ~0.45 m (Battle.WORLD_UNITS_PER_METER = 20), and a foot soldier's mark is sized
# to match — shoulder-to-shoulder at close order, no gap and no overlap. Cavalry
# marks are sized to a horse's ~1 m body width. World-units, not px.
const FORMATION_SPACING: float = 9.0    # world units between soldier marks (0.45 m)
const FORMATION_ASPECT: float = 1.7     # files-to-ranks ratio (> 1 = wider than deep)
const MARK_RADIUS: float = 4.5          # foot soldier mark (0.45 m across)
const CAV_MARK_RADIUS: float = 10.0     # cavalry marks are larger (1 m horse body)

# Zoom level-of-detail. Zoomed out, each soldier is a flat geometric mark (a
# disc / rect / diamond) — cheap and legible at a glance. Zoomed in past
# LOD_ZOOM_IN the marks become detailed figure silhouettes (a standing soldier,
# a mounted rider), so the regiment reads as a crowd of individuals rather than a
# field of dots. The swap reverts below LOD_ZOOM_OUT; the gap between the two is
# hysteresis so the figures don't flicker on and off at the threshold.
const LOD_ZOOM_IN: float = 1.55
const LOD_ZOOM_OUT: float = 1.30
# The figure-silhouette geometry and its foot-render-kind enum (FOOT_INFANTRY / SPEAR /
# ARCHER) live in UnitMeshes; _foot_kind maps a unit's type flags onto one of them.
const EMBLEM_SCALE: float = 0.5         # the per-type sprite, shrunk to a centre emblem
const FLAG_POLE_BASE_GAP: float = 34.0  # px above the block extent where the pole foot sits
const FLAG_POLE_HEIGHT: float = 18.0    # pole from above-bar to flag attachment point
const FLAG_WIDTH: float = 12.0          # horizontal extent of the flag rectangle
const FLAG_HEIGHT: float = 8.0          # vertical extent of the flag rectangle


const PRONE_COLOR: Color = Color(0.22, 0.22, 0.22, 0.80)   # dark grey, 80% alpha — felled soldiers are slightly translucent; stacks with rout modulate (0.45) to 0.36 for "prone AND routing"


# --- Soldier mark rendering ----------------------------------------------
# Render-time only: each living soldier draws as a mark at its simulated body position
# (_sim_soldier_pos). The render reads the sim; it never writes back into it.


## Build the cosmetic render layer: a ground shadow (Polygon2D) and two MultiMeshes
## (outline behind, body in front) for the soldier marks. z_index is RELATIVE to this
## node (z=3), so the children sit at: shadow eff 1, outline/body eff 2 — under this
## node's chrome (_draw at eff 3) but above the field (z=0). The body is added after the
## outline so it draws in front of it at the same effective z. One-time setup in _ready().
func _setup_flock_renderer() -> void:
	var mark_r: float = CAV_MARK_RADIUS if is_cavalry else MARK_RADIUS
	# Two LOD variants per unit: the flat geometric mark (zoomed out) and the
	# detailed figure silhouette (zoomed in). Both are built up front; _update_lod
	# swaps which pair the MultiMeshes draw as the camera zooms.
	_build_mark_meshes(mark_r)
	_build_figure_meshes(mark_r)

	_shadow = Polygon2D.new()
	_shadow.polygon = _ellipse_polygon()
	_shadow.color = Color(0, 0, 0, 0.22)
	_shadow.z_index = -2   # eff 1: above the field, below the marks
	add_child(_shadow)

	_mm_outline = MultiMesh.new()
	_mm_outline.transform_format = MultiMesh.TRANSFORM_2D
	_mm_outline.use_colors = true   # required for set_instance_color; outline always stays WHITE (body carries the prone tint)
	_mm_outline.mesh = _mark_outline_mesh
	_mmi_outline = MultiMeshInstance2D.new()
	_mmi_outline.multimesh = _mm_outline
	_mmi_outline.z_index = -1   # eff 2
	add_child(_mmi_outline)

	_mm_body = MultiMesh.new()
	_mm_body.transform_format = MultiMesh.TRANSFORM_2D
	_mm_body.use_colors = true     # per-instance tint for prone soldiers
	_mm_body.mesh = _mark_body_mesh
	_mmi_body = MultiMeshInstance2D.new()
	_mmi_body.multimesh = _mm_body
	_mmi_body.z_index = -1   # eff 2, added after the outline -> drawn in front of it
	add_child(_mmi_body)

	# The render reads _sim_soldier_pos directly; those bodies are seeded on the first
	# physics tick (Battle._on_soldier_tick -> SoldierBodies.step), so the marks appear
	# from frame 1. Size the shadow/chrome from the formation extent up front.
	_block_extent = SoldierFlock.compute_extent(self, UnitFormation.slots(self, soldiers))
	_update_shadow()


## Flat geometric mark meshes (zoomed-out LOD). Per-type shapes so soldiers read
## differently at a glance: spearmen = tall thin rectangle (shaft), archers =
## All three are now compact *directional* glyphs so that rotating each instance by its
## soldier's facing reads as an arrow at any angle: spearmen = a flat-backed dart, archers
## = a directional kite, cavalry/infantry = the standard pointer (semicircle + triangle
## tip). All three reach about as far forward as the pointer and stay no longer along the
## facing axis, so a rotated rank can't merge into a bar. The earlier spearmen rect and
## archer diamond were elongated/symmetric and, laid flat across a rank, striped.
func _build_mark_meshes(mark_r: float) -> void:
	if anti_cavalry:
		_mark_body_mesh    = UnitMeshes.dart_mesh(mark_r * 1.15)
		_mark_outline_mesh = UnitMeshes.dart_mesh(mark_r * 1.15 + 0.6)
	elif is_ranged:
		_mark_body_mesh    = UnitMeshes.kite_mesh(mark_r * 1.15)
		_mark_outline_mesh = UnitMeshes.kite_mesh(mark_r * 1.15 + 0.6)
	else:
		_mark_body_mesh    = UnitMeshes.pointer_mesh(mark_r)
		_mark_outline_mesh = UnitMeshes.pointer_mesh(mark_r + 0.6)


## Detailed figure-silhouette meshes (zoomed-in LOD): a standing soldier for foot,
## a mounted rider for cavalry. Both are shared/cached like the mark meshes. Foot
## soldiers carry a per-type item (spear / bow / shield) matching their mark shape.
## Each is baked facing right and mirrored facing left, so the render can swap meshes
## to face the unit's march direction.
func _build_figure_meshes(mark_r: float) -> void:
	var foot_kind: int = _foot_kind()
	_figure_body_mesh = UnitMeshes.figure_mesh(is_cavalry, foot_kind, mark_r, false, false)
	_figure_outline_mesh = UnitMeshes.figure_mesh(is_cavalry, foot_kind, mark_r, true, false)
	_figure_body_mesh_flip = UnitMeshes.figure_mesh(is_cavalry, foot_kind, mark_r, false, true)
	_figure_outline_mesh_flip = UnitMeshes.figure_mesh(is_cavalry, foot_kind, mark_r, true, true)


## Which foot-figure variant this unit uses, mirroring the per-type mark shapes
## (spearmen = shaft, archers = bow, everything else = shield). Cavalry ignores it.
func _foot_kind() -> int:
	if anti_cavalry:
		return UnitMeshes.FOOT_SPEAR
	if is_ranged:
		return UnitMeshes.FOOT_ARCHER
	return UnitMeshes.FOOT_INFANTRY


## Unit-radius ellipse outline (pre-squished) for the ground shadow; scaled in _update_shadow().
func _ellipse_polygon(segments: int = 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a: float = TAU * float(i) / float(segments)
		pts.push_back(Vector2(cos(a) * 1.1, sin(a) * 0.36))
	return pts



func _process(_delta: float) -> void:
	_update_lod()
	if state == State.DEAD:
		if _mm_body.instance_count != 0:
			_mm_body.instance_count = 0
			_mm_outline.instance_count = 0
		return
	# Block extent depends only on the soldier count and frontage, not body positions, so
	# recompute (and reshape the shadow/chrome) only when one of those changes — not the
	# fresh PackedVector2Array the old path allocated every frame.
	var fr: int = UnitFormation.frontage(self)
	if soldiers != _render_extent_n or fr != _render_extent_frontage:
		_render_extent_n = soldiers
		_render_extent_frontage = fr
		var new_extent: float = SoldierFlock.compute_extent(self, UnitFormation.slots(self, soldiers))
		if not is_equal_approx(new_extent, _block_extent):
			_block_extent = new_extent
			_update_shadow()
			queue_redraw()
	# Marks mirror the simulated bodies. Refresh only when something visible changed: a body
	# moved (SoldierBodies.step raised _render_dirty), the facing turned (mark rotation,
	# figure mirror and conversio squash all key off it), the unit is fighting (front-rank
	# churn / prone flips), or the instance count drifted from the body count.
	if _render_dirty or facing != _render_last_facing or state == State.FIGHTING \
			or _mm_body.instance_count != _sim_soldier_pos.size():
		_render_dirty = false
		_render_last_facing = facing
		_refresh_flock_render()


## Swap the soldier meshes between the flat marks and the detailed figures based on
## the camera zoom, with hysteresis so the two don't flicker at the threshold. Cheap:
## a viewport lookup, a float compare, and a MultiMesh.mesh reassignment only on the
## frame the level actually flips. Runs at render time, like the rest of the flock.
func _update_lod() -> void:
	if _mm_body == null:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var want: bool = SoldierFlock.lod_should_detail(_detailed_lod, cam.zoom.x)
	# At the figure LOD the mesh also depends on facing: figures are mirrored to face the
	# unit's march direction. Re-evaluate when either the LOD level or the facing side flips.
	var flip: bool = want and facing.x < 0.0
	if want == _detailed_lod and flip == _figure_faces_left:
		return
	var lod_changed: bool = want != _detailed_lod
	_detailed_lod = want
	_figure_faces_left = flip
	_apply_lod_meshes()
	# The centre emblem shows only at the flat-mark LOD, so redraw the chrome when the LOD
	# (not merely the facing side) changes, to hide it behind the figures or bring it back.
	if lod_changed:
		queue_redraw()


## Assign the mesh pair the MultiMeshes draw for the current LOD and, at the figure LOD,
## facing side. The flat marks are symmetric, so only the figures pick a left/right mirror.
func _apply_lod_meshes() -> void:
	if not _detailed_lod:
		_mm_body.mesh = _mark_body_mesh
		_mm_outline.mesh = _mark_outline_mesh
	elif _figure_faces_left:
		_mm_body.mesh = _figure_body_mesh_flip
		_mm_outline.mesh = _figure_outline_mesh_flip
	else:
		_mm_body.mesh = _figure_body_mesh
		_mm_outline.mesh = _figure_outline_mesh


## Push the current mark positions/colours into the two MultiMeshes (1 instance per mark).
## The figures' facing is handled by a mesh swap (see _apply_lod_meshes), not a per-instance
## transform — MultiMesh 2D can't store a reflected (mirrored) instance transform.
func _refresh_flock_render() -> void:
	var n: int = _sim_soldier_pos.size()
	if _mm_body.instance_count != n:
		_mm_body.instance_count = n
		_mm_outline.instance_count = n
	var sim_prone_n: int = _sim_prone.size()
	for i in range(n):
		# Prone: squash/rotate the mark and tint the body dark; outline stays WHITE.
		var prone: bool = i < sim_prone_n and _sim_prone[i] > 0.0
		var pos: Vector2 = _sim_soldier_pos[i] - position
		var t: Transform2D
		if prone:
			if _detailed_lod:
				t = Transform2D(PI * 0.5, pos)
			else:
				t = Transform2D(Vector2(1.3, 0.0), Vector2(0.0, 0.3), pos)
		elif _detailed_lod and _conversio_target != Vector2.ZERO:
			var progress: float = (facing.dot(-_conversio_target) + 1.0) * 0.5
			var squash: float = abs(cos(progress * PI))
			t = Transform2D(Vector2(squash, 0.0), Vector2(0.0, 1.0), pos)
		elif not _detailed_lod:
			var sf: Vector2 = _sim_soldier_facing[i] if i < _sim_soldier_facing.size() else facing
			t = Transform2D(sf.angle(), pos)
		else:
			t = Transform2D(0.0, pos)
		_mm_body.set_instance_transform_2d(i, t)
		_mm_outline.set_instance_transform_2d(i, t)
		_mm_body.set_instance_color(i, PRONE_COLOR if prone else Color.WHITE)
		_mm_outline.set_instance_color(i, Color.WHITE)
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
	# selection halo and stat bars. `_block_extent` (maintained by _process) sizes
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

	# A small per-type emblem (for at-a-glance type) at the block centre, like a standard,
	# drawn in the facing-rotated local frame (forward = up). Hidden at the zoomed-in
	# figure LOD: the per-type silhouettes already carry the type, so the centre emblem
	# would just float superimposed on the individual soldiers.
	if not _detailed_lod:
		draw_set_transform(Vector2.ZERO, facing.angle() + PI * 0.5,
				Vector2(EMBLEM_SCALE, EMBLEM_SCALE))
		if is_cavalry:
			UnitSprites.cavalry(self, body_c, dark_c, lite_c)
		elif anti_cavalry:
			UnitSprites.spear(self, body_c, dark_c, lite_c)
		elif is_ranged:
			UnitSprites.archer(self, body_c, dark_c, lite_c)
		else:
			UnitSprites.infantry(self, body_c, dark_c, lite_c)
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

	UnitSprites.flag(self, body_c, alpha, extent)
