extends GutTest
## Battle order dispatch: the waypoint-append path of
## _apply_order_cmd. A Battle is exercised directly via the script — not spawned
## into the scene — with units registered by uid, so the append/replace logic is
## covered without standing up a full battle. (_apply_order_cmd reads only the
## _by_uid map and the static formation_centroid, never the @onready scene nodes.)

const BattleScript = preload("res://scripts/Battle.gd")
const UnitScript = preload("res://scripts/Unit.gd")


func _unit(uid: int, pos: Vector2) -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)   # runs _ready(): joins groups, sets the footprint
	u.uid = uid
	u.position = pos
	return u


func _battle(units: Array) -> Node:
	var b = BattleScript.new()
	autofree(b)
	for u in units:
		b._by_uid[u.uid] = u
	return b


func test_plain_move_sets_target_and_clears_waypoints() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.waypoints.append(Vector2(999, 999))   # a stale queued route
	u.has_move_target = true
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1})
	assert_eq(u.move_target, Vector2(50, 0), "a plain move sets the destination")
	assert_true(u.has_move_target, "and marks the unit as moving")
	assert_true(u.waypoints.is_empty(), "a fresh order discards any queued route")


func test_append_queues_a_waypoint_behind_the_current_target() -> void:
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 200.0, "y": 0.0, "target": -1})
	b._apply_order_cmd(
		{"units": [1], "x": 400.0, "y": 0.0, "target": BattleScript.ORDER_APPEND_WAYPOINT}
	)
	assert_eq(u.move_target, Vector2(200, 0), "append leaves the current destination intact")
	assert_eq(u.waypoints.size(), 1, "append adds exactly one leg")
	assert_eq(u.waypoints[0], Vector2(400, 0), "the queued leg is the appended point")


func test_append_to_idle_unit_starts_it_marching() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.has_move_target = false
	var b := _battle([u])
	b._apply_order_cmd(
		{"units": [1], "x": 150.0, "y": 0.0, "target": BattleScript.ORDER_APPEND_WAYPOINT}
	)
	assert_true(u.has_move_target, "appending to an idle unit starts it moving")
	assert_eq(u.move_target, Vector2(150, 0), "the first appended point becomes the target")
	assert_true(u.waypoints.is_empty(), "nothing is left queued behind it")


func test_append_via_enqueue_is_not_double_applied() -> void:
	# enqueue_order applies non-append orders immediately AND _physics_process
	# re-applies every pending cmd on the next tick. An append must run only on the
	# tick or the queue would grow a duplicate leg. Simulate a live append on a unit
	# already marching, then drain _pending_orders exactly as the next tick does.
	var u := _unit(1, Vector2.ZERO)
	u.move_target = Vector2(200, 0)
	u.has_move_target = true   # already en route
	var b := _battle([u])
	b.enqueue_order([1], Vector2(400, 0), BattleScript.ORDER_APPEND_WAYPOINT)
	for o in b._pending_orders:
		b._apply_order_cmd(o)
	assert_eq(u.waypoints.size(), 1, "an appended waypoint is queued exactly once, not doubled")
	assert_eq(u.waypoints[0], Vector2(400, 0), "and holds the appended point")


# --- pending-append preview while paused -----------------------

func test_pending_append_is_previewed_without_being_applied() -> void:
	# An append isn't applied until the next physics tick (so it isn't doubled).
	# While paused that tick never runs, so the overlay previews it from
	# _pending_orders instead — without mutating the unit's queue.
	var u := _unit(1, Vector2.ZERO)
	u.has_move_target = false
	var b := _battle([u])
	b.enqueue_order([1], Vector2(300, 0), BattleScript.ORDER_APPEND_WAYPOINT)
	assert_false(u.has_move_target, "the append is not applied yet (no tick ran)")
	assert_true(u.waypoints.is_empty(), "and nothing is queued on the unit yet")
	var preview: Array = b.pending_append_points_for(u)
	assert_eq(preview.size(), 1, "the pending append is previewed")
	assert_eq(preview[0], Vector2(300, 0), "at the appended point (single unit: no offset)")


func test_pending_append_preview_uses_formation_offset() -> void:
	# A multi-unit append keeps each unit's offset from the group centroid; the
	# preview reproduces that exactly (positions are frozen while paused, so it
	# matches what the tick will apply).
	var a := _unit(1, Vector2(0, 0))
	var c := _unit(2, Vector2(100, 0))
	var b := _battle([a, c])
	b.enqueue_order([1, 2], Vector2(300, 0), BattleScript.ORDER_APPEND_WAYPOINT)
	# Centroid of (0,0) and (100,0) is (50,0); offsets are -50 and +50.
	assert_eq(b.pending_append_points_for(a)[0], Vector2(250, 0),
		"unit a previews at dest + its offset from the centroid")
	assert_eq(b.pending_append_points_for(c)[0], Vector2(350, 0),
		"unit c previews at dest + its offset from the centroid")


func test_pending_plain_move_is_not_previewed_as_append() -> void:
	# A plain move is applied immediately (shown via move_target) but its cmd still
	# sits in _pending_orders. pending_append_points_for filters on
	# target == ORDER_APPEND_WAYPOINT, so the plain move is excluded by target, not
	# by queue absence — it must not surface as a pending preview.
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b.enqueue_order([1], Vector2(200, 0), -1)   # plain move
	assert_true(b.pending_append_points_for(u).is_empty(),
		"a plain move is not previewed as a pending append")


# --- order-mode framework --------------------------------------

func test_order_mode_is_stamped_on_a_fresh_order() -> void:
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1,
		"mode": BattleScript.OrderMode.HOLD})
	assert_eq(u.order_mode, BattleScript.OrderMode.HOLD,
		"a fresh order stamps its stance on the unit")


func test_order_mode_defaults_to_normal_when_absent() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.order_mode = BattleScript.OrderMode.HOLD   # a prior stance
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1})   # no "mode"
	assert_eq(u.order_mode, BattleScript.OrderMode.NORMAL,
		"a mode-less / plain order resets the stance to NORMAL")


func test_enqueue_order_carries_the_mode() -> void:
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b.enqueue_order([1], Vector2(50, 0), -1, BattleScript.OrderMode.SKIRMISH)
	assert_eq(int(b._pending_orders[-1]["mode"]), BattleScript.OrderMode.SKIRMISH,
		"the armed mode is recorded on the pending order")


func test_append_preserves_the_existing_stance() -> void:
	var u := _unit(1, Vector2.ZERO)
	u.move_target = Vector2(200, 0)
	u.has_move_target = true
	u.order_mode = BattleScript.OrderMode.HOLD
	var b := _battle([u])
	b._apply_order_cmd({"units": [1], "x": 400.0, "y": 0.0,
		"target": BattleScript.ORDER_APPEND_WAYPOINT, "mode": BattleScript.OrderMode.NORMAL})
	assert_eq(u.order_mode, BattleScript.OrderMode.HOLD,
		"a waypoint append leaves the unit's stance unchanged")


# --- support / defend ------------------------------------------------

func test_support_order_sets_the_ward_not_a_relief() -> void:
	var supporter := _unit(1, Vector2.ZERO)
	supporter.team = 0
	var ward := _unit(2, Vector2(100, 0))
	ward.team = 0
	ward.state = UnitScript.State.FIGHTING   # would be a line-relief target without SUPPORT
	var b := _battle([supporter, ward])
	b._apply_order_cmd({"units": [1], "x": 0.0, "y": 0.0, "target": 2,
		"mode": BattleScript.OrderMode.SUPPORT})
	assert_eq(supporter.support_target, ward, "a SUPPORT order guards the targeted friendly")
	assert_eq(supporter.order_mode, BattleScript.OrderMode.SUPPORT, "and stamps the SUPPORT stance")
	assert_null(supporter._relief_partner, "it does not start a line relief on the ward")


func test_plain_order_clears_a_prior_support_ward() -> void:
	var supporter := _unit(1, Vector2.ZERO)
	var ward := _unit(2, Vector2(100, 0))
	supporter.support_target = ward
	supporter.order_mode = BattleScript.OrderMode.SUPPORT
	var b := _battle([supporter, ward])
	b._apply_order_cmd({"units": [1], "x": 50.0, "y": 0.0, "target": -1})   # plain move
	assert_null(supporter.support_target, "a fresh plain order drops the guard duty")
	assert_eq(supporter.order_mode, BattleScript.OrderMode.NORMAL, "and resets the stance")


func test_append_preserves_a_support_ward() -> void:
	# An append continues the current order, so — like the stance — it leaves a
	# unit's support ward intact rather than clearing it.
	var supporter := _unit(1, Vector2.ZERO)
	var ward := _unit(2, Vector2(100, 0))
	supporter.support_target = ward
	supporter.order_mode = BattleScript.OrderMode.SUPPORT
	supporter.move_target = Vector2(200, 0)
	supporter.has_move_target = true
	var b := _battle([supporter, ward])
	b._apply_order_cmd({"units": [1], "x": 400.0, "y": 0.0,
		"target": BattleScript.ORDER_APPEND_WAYPOINT, "mode": BattleScript.OrderMode.NORMAL})
	assert_eq(supporter.support_target, ward, "a waypoint append leaves the support ward intact")


# --- terrain / pathfinding integration ---------------------------------

## Mirrors Battle._ready() terrain registration — keep in sync if Battle changes.
func _registered_pathfield() -> PathField:
	var pf := PathField.new(BattleScript.FIELD)
	for patch in BattleScript.TERRAIN:
		if patch.get("kind", "block") == "slow":
			assert_true(patch.has("speed"), "slow terrain patch missing required 'speed' key")
			pf.set_speed_rect(patch["rect"], float(patch["speed"]))
		else:
			pf.block_rect(patch["rect"])
	return pf


func _patch_by_type(type: String) -> Dictionary:
	var matches := BattleScript.TERRAIN.filter(func(p): return p["type"] == type)
	assert_true(matches.size() > 0, "TERRAIN has no patch of type '%s'" % type)
	return matches[0]


func test_hill_blocks_pathfinding() -> void:
	var pf := _registered_pathfield()
	var hill: Dictionary = _patch_by_type("hill")
	var center := hill["rect"].position + hill["rect"].size * 0.5
	assert_true(pf.is_blocked(center), "the hill terrain patch blocks movement at its centre")


func test_hill_route_avoids_patch() -> void:
	var pf := _registered_pathfield()
	var hill: Dictionary = _patch_by_type("hill")
	var cx: float = hill["rect"].position.x + hill["rect"].size.x * 0.5
	var above := Vector2(cx, hill["rect"].position.y - 100)
	var below := Vector2(cx, hill["rect"].end.y + 100)
	var route := pf.find_path(above, below)
	assert_true(route.size() > 0,
			"A* finds a route around the hill (field is wide enough to detour)")
	for p in route:
		assert_false(hill["rect"].has_point(p), "no A* waypoint passes through the hill rect")


func test_forest_is_not_blocked() -> void:
	# Forest is a slow zone, not impassable: units can enter it.
	var pf := _registered_pathfield()
	var forest: Dictionary = _patch_by_type("forest")
	var center := forest["rect"].position + forest["rect"].size * 0.5
	assert_false(pf.is_blocked(center), "the forest patch is passable (slow, not blocked)")


func test_forest_slows_movement() -> void:
	var pf := _registered_pathfield()
	var forest: Dictionary = _patch_by_type("forest")
	var center := forest["rect"].position + forest["rect"].size * 0.5
	assert_almost_eq(pf.speed_at(center), float(forest["speed"]), 0.001,
			"the forest speed zone returns the configured speed scale")
