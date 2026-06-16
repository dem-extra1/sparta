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
	# Route around terrain via the pathfinding layer when one is active; with no
	# obstacles registered the next step is the target itself (straight line).
	var step: Vector2 = point
	if PathField.active != null:
		step = PathField.active.next_step(position, point)
	var to: Vector2 = step - position
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


# --- Visuals ------------------------------------------------------------------

func _draw() -> void:
	var alpha: float = 0.45 if state == State.ROUTING else 1.0
	var body_c := Color(team_color.r, team_color.g, team_color.b, alpha)
	var dark_c := Color(body_c.r * 0.35, body_c.g * 0.35, body_c.b * 0.35, alpha)
	var lite_c := Color(minf(body_c.r + 0.30, 1.0), minf(body_c.g + 0.30, 1.0),
			minf(body_c.b + 0.30, 1.0), alpha)

	# Drop shadow (squished ellipse anchors the token to the ground).
	draw_set_transform(Vector2(0, RADIUS * 0.60), 0.0, Vector2(1.15, 0.38))
	draw_circle(Vector2.ZERO, RADIUS, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# State ring drawn behind the sprite: red = engaged, orange = routing.
	match state:
		State.FIGHTING:
			draw_arc(Vector2.ZERO, RADIUS + 3.5, 0, TAU, 28,
					Color(0.90, 0.15, 0.15, alpha), 3.5)
		State.ROUTING:
			# alpha=1.0 intentional: ring stays fully visible on the faded routing token.
			draw_arc(Vector2.ZERO, RADIUS + 3.5, 0, TAU, 28,
					Color(0.95, 0.50, 0.05, 1.0), 4.0)

	# Rotate drawing so the sprite's "forward" aligns with the unit's facing direction.
	draw_set_transform(Vector2.ZERO, facing.angle() + PI * 0.5, Vector2.ONE)

	if is_cavalry:
		_draw_cavalry_sprite(body_c, dark_c, lite_c)
	elif anti_cavalry:
		_draw_spear_sprite(body_c, dark_c, lite_c)
	else:
		_draw_infantry_sprite(body_c, dark_c, lite_c)

	# Reset to screen-space for HUD overlays.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if selected:
		draw_arc(Vector2.ZERO, RADIUS + 5.0, 0, TAU, 28, Color(0.95, 0.95, 0.3), 2.5)

	# Strength bar + morale bar stacked above the token.
	var bw: float = 38.0
	var by: float = -RADIUS - 22.0
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
