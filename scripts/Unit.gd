extends Node2D
class_name Unit
## A regiment: one selectable token with a soldier count, morale, and a
## simple state machine. Draws itself with primitives so the game runs before
## any art is added. Swap _draw() for a Sprite2D later (see README).

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

# --- Runtime state ---
var soldiers: int
var morale: float = 100.0
var state: int = State.IDLE
var facing: Vector2 = Vector2.DOWN
var move_target: Vector2 = Vector2.ZERO
var has_move_target: bool = false
var target_enemy: Unit = null
var selected: bool = false

const RADIUS: float = 18.0
const DETECTION_RANGE: float = 190.0
const ATTACK_INTERVAL: float = 0.6
const ROUT_TIME: float = 6.0

var _attack_cd: float = 0.0
var _rout_timer: float = 0.0
var _moved_last_frame: bool = false
var _charge_ready: bool = true   # cavalry get one charge bonus per engagement
var team_color: Color = Color.WHITE


func _ready() -> void:
	soldiers = max_soldiers
	team_color = Color("4a7fd6") if team == 0 else Color("d65a4a")
	add_to_group("units")
	z_index = 1
	queue_redraw()


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	if state == State.ROUTING:
		_process_rout(delta)
		if state != State.DEAD:   # the timer may have expired and freed us
			_separate()   # routers still shoulder past anyone in their path
		return

	_attack_cd = max(0.0, _attack_cd - delta)
	_moved_last_frame = false

	_think(delta)

	# Units are solid: resolve any overlap so an advancing regiment can't
	# walk straight through (or over) the one in front of it.
	_separate()

	if not _moved_last_frame and state != State.FIGHTING:
		_charge_ready = true   # rearm charge once disengaged
	queue_redraw()


## Decide what to do this frame: fight if in contact, otherwise move.
func _think(delta: float) -> void:
	var enemy: Unit = _current_target()
	if enemy != null:
		var dist: float = position.distance_to(enemy.position)
		var in_contact: bool = dist <= attack_range + RADIUS + enemy.RADIUS
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
			_move_to(enemy.position, delta)
			return

	# Obey a move order (disengaging if needed), else auto-advance on a near enemy.
	if has_move_target:
		if position.distance_to(move_target) > 5.0:
			_move_to(move_target, delta)
		else:
			has_move_target = false
			state = State.IDLE
	elif enemy != null:
		_move_to(enemy.position, delta)
	else:
		state = State.IDLE


# --- Targeting -------------------------------------------------------------

func _current_target() -> Unit:
	if target_enemy != null and is_instance_valid(target_enemy) and target_enemy.state != State.DEAD and target_enemy.state != State.ROUTING:
		return target_enemy
	target_enemy = null
	return _nearest_enemy()


func _nearest_enemy() -> Unit:
	var best: Unit = null
	var best_d: float = DETECTION_RANGE
	for u in get_tree().get_nodes_in_group("units"):
		var other: Unit = u as Unit
		if other == null or other.team == team:
			continue
		if other.state == State.DEAD or other.state == State.ROUTING:
			continue
		var d: float = position.distance_to(other.position)
		if d < best_d:
			best_d = d
			best = other
	return best


# --- Movement --------------------------------------------------------------

func _move_to(point: Vector2, delta: float) -> void:
	var to: Vector2 = point - position
	if to.length() < 1.0:
		return
	var dir: Vector2 = to.normalized()
	_face_dir(dir)
	position += dir * move_speed * delta
	state = State.MOVING
	_moved_last_frame = true


func _face(point: Vector2) -> void:
	_face_dir(point - position)


func _face_dir(dir: Vector2) -> void:
	if dir.length() > 0.01:
		facing = dir.normalized()


## Push out of any overlapping unit so regiments form a solid line instead of
## passing through each other. Each pair shares the correction (half each).
## Since units move sequentially (each only moves itself), one frame reduces an
## overlap by ~75%; it converges to zero within a few frames.
func _separate() -> void:
	if state == State.DEAD:
		return
	# Consider living units and routers alike: nobody gets walked through.
	var others: Array = get_tree().get_nodes_in_group("units")
	others.append_array(get_tree().get_nodes_in_group("routers"))
	for o in others:
		var other: Unit = o as Unit
		# DEAD: queue_free'd but not yet removed from its group this frame.
		if other == null or other == self or other.state == State.DEAD:
			continue
		var min_dist: float = RADIUS + other.RADIUS
		var offset: Vector2 = position - other.position
		var d: float = offset.length()
		if d >= min_dist:
			continue
		var push: Vector2
		if d > 0.01:
			push = offset / d * ((min_dist - d) * 0.5)
		else:
			# Exactly co-located: both units of the pair derive the SAME angle
			# (from the lower id, for determinism) and push in OPPOSITE
			# directions, so they reliably fan apart instead of drifting
			# together. Using each unit's own id here would push near-adjacent
			# ids in almost the same direction and never separate them.
			var lo: int = mini(get_instance_id(), other.get_instance_id())
			var angle: float = float(lo % 100) / 100.0 * TAU
			var dir: float = 1.0 if get_instance_id() > other.get_instance_id() else -1.0
			push = Vector2.RIGHT.rotated(angle) * dir * (min_dist * 0.5)
		position += push


# --- Combat ----------------------------------------------------------------

func _strike(enemy: Unit) -> void:
	var base: float = float(max(1, attack - enemy.defense))
	# Draw from the seeded replay RNG (one stream, stable order) so battles are
	# reproducible. This is the simulation's only source of randomness.
	var dmg: float = base * Replay.rng.randf_range(0.6, 1.4)

	# Cavalry charge bonus on first contact, blunted by anti-cavalry spears.
	if is_cavalry and _charge_ready and not enemy.is_cavalry:
		dmg *= 0.6 if enemy.anti_cavalry else 1.8
		_charge_ready = false

	enemy.take_casualties(int(round(dmg)), self)


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
	elif morale <= 0.0:
		_rout()

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


# --- Death & routing -------------------------------------------------------

func _die() -> void:
	state = State.DEAD
	selected = false
	remove_from_group("units")
	queue_free()


func _rout() -> void:
	if state == State.ROUTING:
		return
	state = State.ROUTING
	selected = false
	target_enemy = null
	has_move_target = false
	_rout_timer = ROUT_TIME
	remove_from_group("units")   # no longer counts as a fighting unit
	add_to_group("routers")
	# Routing is contagious: shake nearby friends.
	for u in get_tree().get_nodes_in_group("units"):
		var friend: Unit = u as Unit
		if friend != null and friend.team == team:
			if position.distance_to(friend.position) < 140.0:
				friend.morale -= 12.0
	queue_redraw()


func _process_rout(delta: float) -> void:
	# Flee toward own back edge (team 0 started at top, team 1 at bottom).
	var flee: Vector2 = Vector2.UP if team == 0 else Vector2.DOWN
	facing = flee
	position += flee * (move_speed * 1.3) * delta
	_rout_timer -= delta
	if _rout_timer <= 0.0:
		state = State.DEAD
		queue_free()
	else:
		queue_redraw()


# --- Visuals (placeholder primitives; replace with a Sprite2D later) -------

func _draw() -> void:
	var alpha: float = 0.45 if state == State.ROUTING else 1.0
	var body: Color = team_color
	body.a = alpha

	# Regiment token.
	if is_cavalry:
		draw_circle(Vector2.ZERO, RADIUS, body)
		draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 24, Color(1, 1, 1, alpha), 2.0)
	else:
		var r := Rect2(-RADIUS, -RADIUS, RADIUS * 2.0, RADIUS * 2.0)
		draw_rect(r, body)
		draw_rect(r, Color(0, 0, 0, alpha * 0.6), false, 2.0)

	# Anti-cavalry marker (spear tip).
	if anti_cavalry:
		draw_line(Vector2(0, -2), facing * (RADIUS + 8.0), Color(0.9, 0.9, 0.7, alpha), 2.0)

	# Facing indicator.
	draw_line(Vector2.ZERO, facing * (RADIUS + 4.0), Color(0, 0, 0, alpha * 0.7), 3.0)

	# Selection ring.
	if selected:
		draw_arc(Vector2.ZERO, RADIUS + 5.0, 0, TAU, 28, Color(0.95, 0.95, 0.3), 2.5)

	# Strength bar.
	var bw: float = 38.0
	var by: float = -RADIUS - 12.0
	var frac: float = clampf(float(soldiers) / float(max_soldiers), 0.0, 1.0)
	draw_rect(Rect2(-bw * 0.5, by, bw, 5.0), Color(0.15, 0.15, 0.15, alpha))
	draw_rect(Rect2(-bw * 0.5, by, bw * frac, 5.0), Color(0.3, 0.8, 0.3, alpha))

	# Soldier count.
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-bw * 0.5, by - 3.0), str(soldiers),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, alpha))
