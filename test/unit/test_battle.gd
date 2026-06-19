extends GutTest
## Battle order dispatch (issue #34): the waypoint-append path of
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


# --- pending-append preview while paused (issue #62) -----------------------

func test_pending_append_is_previewed_without_being_applied() -> void:
	# An append isn't applied until the next physics tick (so it isn't doubled).
	# While paused that tick never runs, so the overlay previews it from
	# _pending_orders instead — without mutating the unit's queue (#62).
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
	# Only appends are pending-but-unapplied; a plain move is applied immediately
	# (shown via move_target), so it must not also surface as a pending preview.
	var u := _unit(1, Vector2.ZERO)
	var b := _battle([u])
	b.enqueue_order([1], Vector2(200, 0), -1)   # plain move, applied now
	assert_true(b.pending_append_points_for(u).is_empty(),
		"a plain move is not previewed as a pending append")
