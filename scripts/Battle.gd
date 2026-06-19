extends Node2D
## Sets up the battlefield, spawns both armies, runs the enemy AI, and decides
## when the battle is won or lost.

# Preload instead of relying on Unit's global class_name, so the project loads
# without the editor-built global-class cache (works headless / first run / CI).
const UnitRef = preload("res://scripts/Unit.gd")

const FIELD := Rect2(0, 0, 1600, 1000)

# Sentinel order target (#34): a move order carrying this as its `target` appends
# its destination to the units' waypoint queue instead of replacing the route.
# Overloads the existing int field (like merge/relief) so the replay format is
# unchanged — real merge/attack/relief targets are uids >= 0, a plain move is -1.
const ORDER_APPEND_WAYPOINT := -2

# Global movement scale: lower = units move slower (relative speeds preserved).
const SPEED_SCALE := 0.6

# Enemy AI re-evaluates on a fixed tick cadence (not a wall-clock timer) so the
# simulation is deterministic and replayable. 60 ticks == 1 second at 60 Hz.
const AI_PERIOD := 60

@onready var _units: Node2D = $Units
@onready var _hud = $HUD
@onready var _camera: Camera2D = $Camera2D

# Fixed-step clock driving the whole simulation; also the timeline for replays.
var _tick: int = 0
var _ended: bool = false

# uid -> Unit, so recorded orders can resolve their units after a scene reload.
var _by_uid: Dictionary = {}
# Player orders received since the last physics step (live play only). Applied
# and recorded at the next tick so live and replayed orders take identical paths.
var _pending_orders: Array = []
var _next_uid: int = 0


func _ready() -> void:
	# Start a fresh recording for every live battle (so any battle can be
	# replayed for debugging). During playback the recorder is already armed by
	# the seed loaded from the file, so we leave it alone.
	if Replay.mode != Replay.Mode.PLAYBACK:
		Replay.start_recording()

	_camera.bounds = FIELD
	_camera.position = FIELD.position + FIELD.size * 0.5

	# Publish the pathfinding layer over the field. No terrain obstacles are
	# registered yet, so routes are straight lines today; placing a block_rect()
	# here (e.g. for a future rock/wall) is all it takes to make units route
	# around it. Kept deterministic (grid A*) so replays stay reproducible.
	# Cleared in _exit_tree() so it doesn't outlive this battle.
	PathField.active = PathField.new(FIELD)

	# Player army (team 0) deploys along the top, facing down.
	_spawn_line(0, Vector2.DOWN, 300)
	# Enemy army (team 1) deploys along the bottom, facing up.
	_spawn_line(1, Vector2.UP, 700)


func _exit_tree() -> void:
	# Don't let this battle's pathfinding grid outlive it (e.g. across a scene
	# reload or a future return-to-map flow). The next Battle._ready() republishes.
	PathField.active = null


func _draw() -> void:
	# Simple grass field + a center line, so the world is readable before art.
	draw_rect(FIELD, Color(0.34, 0.42, 0.27))
	draw_rect(FIELD, Color(0.2, 0.25, 0.16), false, 4.0)
	draw_line(Vector2(0, FIELD.size.y * 0.5), Vector2(FIELD.size.x, FIELD.size.y * 0.5),
		Color(1, 1, 1, 0.08), 2.0)


func _spawn_line(team: int, facing: Vector2, y: float) -> void:
	# Loadout: spearmen, infantry, archers, cavalry, cavalry. The archers (#37)
	# skirmish from range — softer in melee, but they soften the line before contact.
	var loadout := [
		{"name": "Spearmen", "anti_cav": true, "cav": false, "soldiers": 140, "atk": 11, "def": 8, "spd": 80},
		{"name": "Infantry", "anti_cav": false, "cav": false, "soldiers": 120, "atk": 13, "def": 6, "spd": 90},
		{"name": "Archers", "anti_cav": false, "cav": false, "ranged": true, "soldiers": 90, "atk": 10, "def": 4, "spd": 95},
		{"name": "Cavalry", "anti_cav": false, "cav": true, "soldiers": 80, "atk": 16, "def": 5, "spd": 160},
		{"name": "Cavalry", "anti_cav": false, "cav": true, "soldiers": 80, "atk": 16, "def": 5, "spd": 160},
	]
	var count: int = loadout.size()
	var spacing: float = 150.0
	var start_x: float = FIELD.size.x * 0.5 - (count - 1) * spacing * 0.5

	for i in range(count):
		var d: Dictionary = loadout[i]
		var u := UnitRef.new()
		u.uid = _next_uid
		_next_uid += 1
		_by_uid[u.uid] = u
		u.unit_name = "%s %d" % [d["name"], i + 1]
		u.team = team
		u.anti_cavalry = d["anti_cav"]
		u.is_cavalry = d["cav"]
		u.is_ranged = d.get("ranged", false)
		u.max_soldiers = d["soldiers"]
		u.attack = d["atk"]
		u.defense = d["def"]
		u.move_speed = d["spd"] * SPEED_SCALE
		u.facing = facing
		u.position = Vector2(start_x + i * spacing, y)
		_units.add_child(u)


func _physics_process(_delta: float) -> void:
	# Runs before the Units' own _physics_process (parent precedes children in
	# tree order), so orders and AI for this tick are applied before units act.
	if _ended:
		return

	# Rebuild the shared spatial hash once per tick, before the Units process, so
	# every unit's _separate() this frame queries a current grid (O(n) bucketing
	# instead of an O(n^2) all-pairs scan).
	SpatialHash.rebuild(get_tree(), Engine.get_physics_frames())

	# Apply this tick's orders: recorded ones during playback, queued live input
	# (also recorded) otherwise.
	if Replay.mode == Replay.Mode.PLAYBACK:
		for cmd in Replay.orders_for_tick(_tick):
			_apply_order_cmd(cmd)
	else:
		for o in _pending_orders:
			Replay.record_order(_tick, o["units"], Vector2(o["x"], o["y"]), o["target"])
			_apply_order_cmd(o)
		_pending_orders.clear()

	# Enemy AI is part of the deterministic sim (not player input): re-run it on
	# the same cadence during playback so it reaches the same decisions.
	if _tick % AI_PERIOD == 0:
		_run_enemy_ai()

	_check_victory()
	_tick += 1


## Called by SelectionManager when the player issues a right-click order. The
## order is recorded and re-applied on the next physics tick (live play only),
## but we also apply it immediately so it takes effect with no input latency and
## the order overlay reflects the new destination right away — including while
## paused, when the physics tick that drains _pending_orders isn't running. The
## tick's re-application is idempotent (same cmd, same _apply_order_cmd), so live
## and replayed orders stay on the same deterministic code path.
func enqueue_order(uids: Array, world_pos: Vector2, target_uid: int) -> void:
	if Replay.mode == Replay.Mode.PLAYBACK:
		return
	var cmd := {
		"units": uids,
		"x": world_pos.x,
		"y": world_pos.y,
		"target": target_uid,
	}
	_pending_orders.append(cmd)
	# Apply immediately for zero-latency feedback and paused preview — EXCEPT a
	# waypoint append (#34), which is NOT idempotent: the tick re-applies every
	# pending cmd, and a second u.waypoints.append() would duplicate the leg. An
	# append is also tick-authoritative anyway (its point is derived from positions
	# at the tick, matching replay), so it's applied once, on that tick.
	if target_uid != ORDER_APPEND_WAYPOINT:
		_apply_order_cmd(cmd)


## Apply one order (move or attack) to its units. Shared by live play and
## playback so both produce identical results.
func _apply_order_cmd(cmd: Dictionary) -> void:
	var target_uid: int = int(cmd["target"])
	# Merge (#3): the target is the primary and is itself one of the ordered units
	# (a relief's target is a friendly OUTSIDE the selection — that's the
	# disambiguator). Handle it first, then fall through to attack/relief/move.
	if target_uid >= 0 and _uids_contain(cmd["units"], target_uid):
		_apply_merge(cmd["units"], target_uid)
		return
	# A move whose target is the append sentinel queues a waypoint instead of
	# replacing the route (#34); any other order resets the queue first.
	var append: bool = target_uid == ORDER_APPEND_WAYPOINT
	# The target uid may be an enemy (attack) or a friendly (line relief, #4); a
	# plain move has no target. Resolve it and dispatch per ordered unit by team.
	var target_unit: Unit = _unit_by_uid(target_uid) if target_uid >= 0 else null
	var is_move: bool = target_unit == null
	var dest := Vector2(float(cmd["x"]), float(cmd["y"]))
	# Formation cohesion: a move order translates the regiment as a block. Each
	# unit keeps its offset from the group's current centroid, so the formation
	# holds its shape (line stays a line) instead of collapsing and re-packing
	# into a fresh grid. Computed from live positions, so live play and playback
	# (which reach the same positions at this tick) stay in lockstep.
	var centroid := Vector2.ZERO
	if is_move:
		centroid = _centroid_of_uids(cmd["units"])
	var relieved: bool = false
	var relief_foe: Unit = null
	for uid in cmd["units"]:
		var u: Unit = _unit_by_uid(int(uid))
		if u == null:
			continue
		# A fresh order (anything but a waypoint append) discards the queued route.
		if not append:
			u.waypoints.clear()
		if target_unit != null and target_unit != u and target_unit.team != u.team:
			u.target_enemy = target_unit   # attack an enemy
			u.has_move_target = false
		elif target_unit != null and target_unit != u and target_unit.team == u.team:
			# Relief: the first reliever swaps with the tired unit; any others just
			# advance on the same fight so they don't shove the retreating unit.
			if not relieved:
				u.begin_relief(target_unit)
				# Capture the foe begin_relief() resolved (it clears the tired
				# unit's target_enemy, so later relievers can't read it from there).
				relief_foe = u.target_enemy
				relieved = true
			else:
				u.target_enemy = relief_foe
				u.has_move_target = false
		else:
			var point: Vector2 = dest + (u.position - centroid)   # formation move
			u.target_enemy = null
			if append:
				# Queue the point; start marching it now if the unit was idle.
				u.waypoints.append(point)
				if not u.has_move_target:
					u.move_target = u.waypoints.pop_front()
					u.has_move_target = true
			else:
				u.move_target = point
				u.has_move_target = true


func _uids_contain(uids: Array, target: int) -> bool:
	for u in uids:
		if int(u) == target:
			return true
	return false


## Merge every other ordered unit into the primary (#3). Same-team only.
func _apply_merge(uids: Array, primary_uid: int) -> void:
	var primary: Unit = _unit_by_uid(primary_uid)
	if primary == null:
		return
	for uid in uids:
		var u: Unit = _unit_by_uid(int(uid))
		if u == null or u == primary or u.team != primary.team:
			continue
		# Don't fold a routing or dead unit into a steady regiment (a unit can rout
		# between selecting it and the merge applying); it's no longer a valid body.
		if u.state == UnitRef.State.ROUTING or u.state == UnitRef.State.DEAD:
			continue
		primary.absorb(u)


## Average of a set of positions — the anchor a formation move translates from,
## so the block keeps its shape. Returns ZERO for an empty set.
static func formation_centroid(positions: Array[Vector2]) -> Vector2:
	if positions.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in positions:
		sum += p
	return sum / float(positions.size())


## Formation centroid of the live positions of the given unit uids (the anchor a
## formation move translates from). Shared by _apply_order_cmd and the overlay's
## pending-append preview so both compute the same per-unit offset.
func _centroid_of_uids(uids: Array) -> Vector2:
	var ps: Array[Vector2] = []
	for uid in uids:
		var cu: Unit = _unit_by_uid(int(uid))
		if cu != null:
			ps.append(cu.position)
	return formation_centroid(ps)


## Points for a unit's not-yet-applied waypoint appends (#62), in queue order.
## While the sim is paused _physics_process doesn't drain _pending_orders, so an
## appended leg isn't written to u.waypoints until the player unpauses; the order
## overlay calls this to preview those queued legs without mutating state. Each
## point is derived exactly as _apply_order_cmd will (same formation centroid),
## and positions are frozen while paused, so the preview matches the eventual leg.
func pending_append_points_for(u: Unit) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for cmd in _pending_orders:
		if int(cmd["target"]) != ORDER_APPEND_WAYPOINT:
			continue
		if not _uids_contain(cmd["units"], u.uid):
			continue
		var dest := Vector2(float(cmd["x"]), float(cmd["y"]))
		points.append(dest + (u.position - _centroid_of_uids(cmd["units"])))
	return points


func _unit_by_uid(uid: int) -> UnitRef:
	var u = _by_uid.get(uid)
	return u if (u != null and is_instance_valid(u)) else null


func _run_enemy_ai() -> void:
	# Each idle enemy advances on the nearest player unit; combat auto-resolves.
	var players := _team_units(0)
	if players.is_empty():
		return
	for u in _team_units(1):
		if u.state == UnitRef.State.FIGHTING:
			continue
		var nearest = null
		var best: float = INF
		for p in players:
			var d: float = u.position.distance_to(p.position)
			if d < best:
				best = d
				nearest = p
		if nearest != null:
			u.target_enemy = nearest


func _team_units(team: int) -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group("units"):
		var u = node as UnitRef
		if u != null and u.team == team:
			out.append(u)
	return out


func _check_victory() -> void:
	var p: int = _team_units(0).size()
	var e: int = _team_units(1).size()
	if p == 0 and e == 0:
		_end("Mutual Destruction")
	elif e == 0:
		_end("Victory!")
	elif p == 0:
		_end("Defeat")


func _end(text: String) -> void:
	_ended = true
	# Persist the just-played battle so it can be replayed. Playback doesn't
	# re-save (the file already exists).
	if Replay.mode == Replay.Mode.RECORD:
		Replay.save(text, _tick)
	_hud.show_end(text)
