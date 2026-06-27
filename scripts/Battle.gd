extends Node2D
## Sets up the battlefield, spawns both armies, runs the enemy AI, and decides
## when the battle is won or lost.

# Preload instead of relying on Unit's global class_name, so the project loads
# without the editor-built global-class cache (works headless / first run / CI).
const UnitRef = preload("res://scripts/Unit.gd")
const CampaignBattle = preload("res://scripts/campaign/CampaignBattle.gd")

const FIELD := Rect2(0, 0, 1600, 1000)

# Terrain patches; type keys into TERRAIN_COLOR. kind="block" is impassable; kind="slow" is a speed zone.
const TERRAIN: Array = [
	{"rect": Rect2(200,  380, 250, 200), "type": "forest", "kind": "slow", "speed": 0.6},
	{"rect": Rect2(1150, 380, 250, 200), "type": "hill",   "kind": "block"},
]
const TERRAIN_COLOR := {
	"forest": Color(0.12, 0.28, 0.10),
	"hill":   Color(0.55, 0.48, 0.32),
}

# Sentinel order target: a move order carrying this as its `target` appends
# its destination to the units' waypoint queue instead of replacing the route.
# Overloads the existing int field (like merge/relief) so the replay format is
# unchanged — real merge/attack/relief targets are uids >= 0, a plain move is -1.
const ORDER_APPEND_WAYPOINT := -2
# Sentinel for a formation-change-only order (no movement, no target). Handled
# before the main move/attack/merge logic so it doesn't clear waypoints or stances.
const ORDER_FORMATION_ONLY := -3

## Order modes: the "stance" an order applies to its units. NORMAL is the
## current move/attack behaviour. The smart modes are chosen by the player's armed
## mode (SelectionManager), recorded in the replay ("mode") and stamped on
## Unit.order_mode; the per-unit behaviour for each is added in the sibling issues.
## Until then a non-NORMAL stance is stored but behaves as
## NORMAL. NORMAL is 0 so it matches Unit.order_mode's default.
enum OrderMode { NORMAL, HOLD, ATTACK_FLANK, ATTACK_REAR, SKIRMISH, SUPPORT }

## Human-readable mode names for the HUD / cursor indicator.
const ORDER_MODE_NAMES := {
	OrderMode.NORMAL: "Normal",
	OrderMode.HOLD: "Hold",
	OrderMode.ATTACK_FLANK: "Attack flank",
	OrderMode.ATTACK_REAR: "Attack rear",
	OrderMode.SKIRMISH: "Skirmish",
	OrderMode.SUPPORT: "Support",
}

## Rebindable order-mode hotkeys, in menu/HUD order. Each entry pairs the
## OrderMode it arms with a stable cfg "slug"; the Settings autoload persists
## slug -> physical keycode (defaults in Settings.DEFAULT_ORDER_BINDINGS), and the
## keybindings dialog labels rows via ORDER_MODE_NAMES. NORMAL (Esc, "clear stance")
## is intentionally absent — it stays a fixed, non-rebindable key.
const ORDER_MODE_HOTKEYS := [
	{"mode": OrderMode.HOLD, "slug": "hold"},
	{"mode": OrderMode.ATTACK_FLANK, "slug": "attack_flank"},
	{"mode": OrderMode.ATTACK_REAR, "slug": "attack_rear"},
	{"mode": OrderMode.SKIRMISH, "slug": "skirmish"},
	{"mode": OrderMode.SUPPORT, "slug": "support"},
]

# Global movement scale: lower = units move slower (relative speeds preserved).
const SPEED_SCALE := 0.6

# World scale: how many sim/world units make up one metre. Used to express
# real-world lengths (weapon reach, and later movement speed) in metres and
# convert them to the world units the sim runs in. These are WORLD units, not
# screen pixels: Godot renders the fixed FIELD onto any window via the viewport
# stretch (canvas_items / expand) and the Camera2D zoom, so the display
# resolution is independent of this scale. At 20 u/m the 1600x1000 field is an
# 80 m x 50 m engagement frontage. It's a single named knob, so the world's
# unit scale can be rebased here without hunting down hard-coded distances.
const WORLD_UNITS_PER_METER := 20.0

# Enemy AI re-evaluates on a fixed tick cadence (not a wall-clock timer) so the
# simulation is deterministic and replayable. 60 ticks == 1 second at 60 Hz.
const AI_PERIOD := 60

# Fraction of the remaining distance the demo camera closes toward its recorded
# target each tick (exponential smoothing). < 1 low-passes any jitter in the
# recorded presentation track so the clip glides instead of snapping keyframe to
# keyframe; ~0.15/tick at 60 Hz settles a step in ~0.3 s — smooth but responsive.
const CAMERA_SMOOTHING := 0.15

@onready var _units: Node2D = $Units
@onready var _hud = $HUD
@onready var _camera: Camera2D = $Camera2D

# Fixed-step clock driving the whole simulation; also the timeline for replays.
var _tick: int = 0
var _ended: bool = false

# Units deployed per side when this is a campaign-launched battle; used to
# scale survivors back to campaign army strength when the battle ends.
var _camp_atk_spawned: int = 0
var _camp_dfn_spawned: int = 0

# uid -> Unit, so recorded orders can resolve their units after a scene reload.
var _by_uid: Dictionary = {}
# Player orders received since the last physics step (live play only). Applied
# and recorded at the next tick so live and replayed orders take identical paths.
var _pending_orders: Array = []
var _next_uid: int = 0


func _ready() -> void:
	# Unit mirrors a few OrderMode values as plain ints (it can't reference our
	# enum without a preload cycle). Assert the mirror here — where we already hold
	# UnitRef — so a future enum reorder fails loudly instead of misbehaving.
	assert(UnitRef.ORDER_HOLD == OrderMode.HOLD \
			and UnitRef.ORDER_ATTACK_FLANK == OrderMode.ATTACK_FLANK \
			and UnitRef.ORDER_ATTACK_REAR == OrderMode.ATTACK_REAR \
			and UnitRef.ORDER_SKIRMISH == OrderMode.SKIRMISH \
			and UnitRef.ORDER_SUPPORT == OrderMode.SUPPORT,
			"Unit order-mode mirror constants are out of sync with Battle.OrderMode")

	# Start a fresh recording for every live battle (so any battle can be
	# replayed for debugging). During playback the recorder is already armed by
	# the seed loaded from the file, so we leave it alone.
	if Replay.mode != Replay.Mode.PLAYBACK:
		Replay.start_recording()

	_camera.bounds = FIELD
	_camera.position = FIELD.position + FIELD.size * 0.5
	# When the demo recorder replays a presentation track, start already framed on the
	# first keyframe so the smoothing below has nothing to glide in from.
	if Replay.mode == Replay.Mode.PLAYBACK and Replay.drive_camera and Replay.has_camera_track():
		var first: Dictionary = Replay.camera_for_tick(0)
		_camera.position = Vector2(first["x"], first["y"])
		_camera.zoom = Vector2(first["zoom"], first["zoom"])

	# Register terrain patches as PathField obstacles or speed zones; cleared in _exit_tree().
	PathField.active = PathField.new(FIELD)
	for patch in TERRAIN:
		if patch.get("kind", "block") == "slow":
			assert(patch.has("speed"), "slow terrain patch missing required 'speed' key")
			PathField.active.set_speed_rect(patch["rect"], float(patch["speed"]))
		else:
			PathField.active.block_rect(patch["rect"])

	# Army sizes: a campaign-launched clash deploys units scaled to the two
	# clashing armies' strengths; a standalone battle uses the default 5-unit line.
	var atk_count := 5
	var dfn_count := 5
	if CampaignBattle.active and not CampaignBattle.pending.is_empty():
		atk_count = CampaignBattle.units_for(int(CampaignBattle.pending["attacker_strength"]))
		dfn_count = CampaignBattle.units_for(int(CampaignBattle.pending["defender_strength"]))
		_camp_atk_spawned = atk_count
		_camp_dfn_spawned = dfn_count
	# Player army (team 0) deploys along the top, facing down.
	_spawn_line(0, Vector2.DOWN, 300, atk_count)
	# Enemy army (team 1) deploys along the bottom, facing up.
	_spawn_line(1, Vector2.UP, 700, dfn_count)


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
	# Terrain patches — drawn over the field, under units (Battle is the parent).
	for patch in TERRAIN:
		var col: Color = TERRAIN_COLOR.get(patch["type"], Color(0.4, 0.4, 0.4))
		draw_rect(patch["rect"], col)
		draw_rect(patch["rect"], col.darkened(0.35), false, 2.0)


func _spawn_line(team: int, facing: Vector2, y: float, count: int = 5) -> void:
	# Loadout: spearmen, infantry, archers, cavalry, cavalry. The archers
	# skirmish from range — softer in melee, but they soften the line before contact.
	# `count` units deploy, cycling this composition so a larger army (a bigger
	# campaign stack) fields more of the same mix.
	#
	# `reach_m` is the weapon's effective melee reach in metres, converted to the
	# unit's attack_range below. Longer-reach weapons strike while a shorter-weapon
	# enemy is still closing the gap, so a spearman lands the first blows of a clash.
	# Infantry's sword sits at the 1.3 m baseline (= the old flat 26-unit reach);
	# the spear out-reaches it, the cavalry sword a touch longer than the foot sword,
	# and the archers' sidearm is short (they fight at range, not in the press).
	var loadout := [
		{"name": "Spearmen", "anti_cav": true, "cav": false, "soldiers": 140, "atk": 11, "def": 8, "spd": 80, "reach_m": 2.4, "training": 0.75},
		{"name": "Infantry", "anti_cav": false, "cav": false, "soldiers": 120, "atk": 13, "def": 6, "spd": 90, "reach_m": 1.3, "training": 0.5},
		{"name": "Archers", "anti_cav": false, "cav": false, "ranged": true, "soldiers": 90, "atk": 10, "def": 4, "spd": 95, "reach_m": 0.6, "training": 0.3},
		{"name": "Cavalry", "anti_cav": false, "cav": true, "soldiers": 80, "atk": 16, "def": 5, "spd": 160, "reach_m": 1.5, "training": 0.6},
		{"name": "Cavalry", "anti_cav": false, "cav": true, "soldiers": 80, "atk": 16, "def": 5, "spd": 160, "reach_m": 1.5, "training": 0.6},
	]
	# Tighten spacing as the line grows so even a max stack stays on the field.
	var spacing: float = minf(150.0, (FIELD.size.x - 200.0) / maxf(1.0, count - 1))
	var start_x: float = FIELD.size.x * 0.5 - (count - 1) * spacing * 0.5

	for i in range(count):
		var d: Dictionary = loadout[i % loadout.size()]
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
		# Weapon reach (metres) -> world units. Falls back to the unit default if a
		# loadout entry omits it.
		if d.has("reach_m"):
			u.attack_range = d["reach_m"] * WORLD_UNITS_PER_METER
		u.training = d.get("training", 0.0)
		# Cavalry respond faster — more mobile and battle-conditioned.
		if d["cav"]:
			u.order_response_delay = 0.3
		u.facing = facing
		u.position = Vector2(start_x + i * spacing, y)
		u.field_bounds = FIELD   # so a skirmisher kites without backing off the map
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
		# Drive the camera from the recorded presentation track so the replay is framed
		# (zoom/pan) as it was played — only when asked (the demo recorder), so in-app
		# Watch Replay keeps free pan/zoom. No track -> static camera, as before.
		if Replay.drive_camera:
			var cam: Dictionary = Replay.camera_for_tick(_tick)
			if not cam.is_empty():
				# Ease toward the recorded framing rather than snapping to it, so jitter in
				# the track (e.g. a recording that followed the shifting melee) is low-passed
				# into a smooth glide.
				var target_pos := Vector2(cam["x"], cam["y"])
				var target_zoom := Vector2(cam["zoom"], cam["zoom"])
				_camera.position = _camera.position.lerp(target_pos, CAMERA_SMOOTHING)
				_camera.zoom = _camera.zoom.lerp(target_zoom, CAMERA_SMOOTHING)
	else:
		for o in _pending_orders:
			Replay.record_order(_tick, o["units"], Vector2(o["x"], o["y"]), o["target"],
					int(o.get("mode", OrderMode.NORMAL)),
					int(o.get("formation", UnitRef.FORMATION_NORMAL)))
			_apply_order_cmd(o)
		_pending_orders.clear()
		# Capture the camera each tick so a live recording reproduces what the player saw.
		Replay.record_camera(_tick, _camera.position, _camera.zoom.x)

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
func enqueue_order(uids: Array, world_pos: Vector2, target_uid: int,
		order_mode: int = OrderMode.NORMAL) -> void:
	if Replay.mode == Replay.Mode.PLAYBACK:
		return
	var cmd := {
		"units": uids,
		"x": world_pos.x,
		"y": world_pos.y,
		"target": target_uid,
		"mode": order_mode,
	}
	_pending_orders.append(cmd)
	# Apply immediately for zero-latency feedback and paused preview — EXCEPT a
	# waypoint append, which is NOT idempotent: the tick re-applies every
	# pending cmd, and a second u.waypoints.append() would duplicate the leg. An
	# append is also tick-authoritative anyway (its point is derived from positions
	# at the tick, matching replay), so it's applied once, on that tick.
	if target_uid != ORDER_APPEND_WAYPOINT:
		_apply_order_cmd(cmd)


## Change the formation mode for a set of units. Recorded so replays stay exact.
func enqueue_formation(uids: Array, formation: int) -> void:
	if Replay.mode == Replay.Mode.PLAYBACK:
		return
	var cmd := {
		"units": uids,
		"x": 0.0,
		"y": 0.0,
		"target": ORDER_FORMATION_ONLY,
		"mode": OrderMode.NORMAL,
		"formation": formation,
	}
	_pending_orders.append(cmd)
	_apply_order_cmd(cmd)


## Apply one order (move or attack) to its units. Shared by live play and
## playback so both produce identical results.
func _apply_order_cmd(cmd: Dictionary) -> void:
	var target_uid: int = int(cmd["target"])
	# Formation-change-only: update each unit's formation and separation footprint,
	# leaving all movement and order-mode state untouched.
	if target_uid == ORDER_FORMATION_ONLY:
		var fm: int = int(cmd.get("formation", UnitRef.FORMATION_NORMAL))
		for uid in cmd["units"]:
			var u: Unit = _unit_by_uid(int(uid))
			if u != null:
				u.set_formation(fm)
		return
	# Merge: the target is the primary and is itself one of the ordered units
	# (a relief's target is a friendly OUTSIDE the selection — that's the
	# disambiguator). Handle it first, then fall through to attack/relief/move.
	if target_uid >= 0 and _uids_contain(cmd["units"], target_uid):
		_apply_merge(cmd["units"], target_uid)
		return
	# A move whose target is the append sentinel queues a waypoint instead of
	# replacing the route; any other order resets the queue first.
	var append: bool = target_uid == ORDER_APPEND_WAYPOINT
	# The order's stance, stamped on each ordered unit below for the smart-
	# order behaviours to consume. Defaults to NORMAL for older replays / merges.
	var mode: int = int(cmd.get("mode", OrderMode.NORMAL))
	# The target uid may be an enemy (attack) or a friendly (line relief); a
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
		# A fresh order (anything but a waypoint append) discards the queued route
		# and sets the unit's stance; an append continues the current march/stance.
		# Clearing any prior support ward means a plain order drops the guard
		# duty; a SUPPORT order re-sets it in the friendly-target branch below.
		if not append:
			u.waypoints.clear()
			u.order_mode = mode
			u.support_target = null
		if target_unit != null and target_unit != u and target_unit.team != u.team:
			u.target_enemy = target_unit   # attack an enemy
			u.has_move_target = false
		elif target_unit != null and target_unit != u and target_unit.team == u.team:
			if mode == OrderMode.SUPPORT:
				# Support: guard the targeted friendly. Every ordered unit shadows
				# the same ward and engages threats near it — no relief swap.
				u.support_target = target_unit
				u.target_enemy = null
				u.has_move_target = false
			elif not relieved:
				# Relief: the first reliever swaps with the tired unit; any others
				# just advance on the same fight so they don't shove the retreating unit.
				u.begin_relief(target_unit)
				# Capture the foe begin_relief() resolved (it clears the tired
				# unit's target_enemy, so later relievers can't read it from there).
				relief_foe = u.target_enemy
				relieved = true
				# Skip the order-response delay for the primary reliever — it needs
				# to advance immediately or the tired unit retreats into an uncovered gap.
				continue
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
		if not append:
			u.start_order_response()


func _uids_contain(uids: Array, target: int) -> bool:
	for u in uids:
		if int(u) == target:
			return true
	return false


## Merge every other ordered unit into the primary. Same-team only.
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


## Points for a unit's not-yet-applied waypoint appends, in queue order.
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
	# Report the outcome back to the campaign if this clash was launched from the map,
	# before the HUD's "Return to Campaign" button can act on it.
	if CampaignBattle.active:
		_report_campaign_result(text)
	# Fanfare on a win; the somber sting otherwise. A mutual-destruction draw
	# isn't a win either, so it shares the defeat sound.
	Sfx.play(&"victory" if text == "Victory!" else &"defeat")
	_hud.show_end(text)


## Translate the battle's end state into a campaign result: the winning side's
## surviving units scale back to campaign army strength. Replay playback doesn't
## overwrite a result the live battle already reported.
func _report_campaign_result(text: String) -> void:
	if Replay.mode == Replay.Mode.PLAYBACK:
		return
	var pending: Dictionary = CampaignBattle.pending
	if text == "Victory!":
		CampaignBattle.result = {
			"attacker_won": true,
			"survivors": CampaignBattle.survivors_strength(
					int(pending.get("attacker_strength", 1)), _camp_atk_spawned, _team_units(0).size()),
		}
	elif text == "Defeat":
		CampaignBattle.result = {
			"attacker_won": false,
			"survivors": CampaignBattle.survivors_strength(
					int(pending.get("defender_strength", 1)), _camp_dfn_spawned, _team_units(1).size()),
		}
	else:
		# Mutual destruction: the assault fails and the province holds with a token
		# garrison (mirrors auto-resolve's guaranteed >= 1 survivor).
		CampaignBattle.result = {"attacker_won": false, "survivors": 1}
