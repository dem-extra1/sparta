extends GutTest
## Unit's general orders queue (docs/orders-queue-design.md phase 1, #522): the append/replace/
## retire/clear queue operations, and _update_current_order's read-of-legacy-state bookkeeping
## (phase transition + retirement) for each order kind. These are bare-Unit, node-only tests --
## no Battle scene needed, since phase 1 is additive bookkeeping that mirrors the SAME legacy
## fields (has_move_target, waypoints, target_enemy, _wheel_target, ...) the rest of Unit already
## reads and mutates; see test_wheel_battle.gd / test_file_doubling_battle.gd / test_nudge_maneuver.gd
## for the full-scene tick-by-tick proof that this bookkeeping changes no sim behaviour.


func _make_unit(uid: int = 1) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 10
	add_child_autofree(u)   # _ready() joins groups, seeds soldiers
	u.uid = uid
	return u


func test_a_fresh_unit_has_no_current_order() -> void:
	var u := _make_unit()
	assert_null(u.current_order)
	assert_true(u.orders.is_empty())


func test_set_current_order_replaces_the_queue_and_becomes_current() -> void:
	var u := _make_unit()
	var o := Order.new_wheel(1)
	u.set_current_order(o)
	assert_eq(u.current_order, o)
	assert_eq(u.orders.size(), 1)
	assert_eq(u.orders[0], o)


func test_set_current_order_drops_any_previously_queued_orders() -> void:
	var u := _make_unit()
	u.append_order(Order.new_move(Vector2(1, 1)))
	u.append_order(Order.new_move(Vector2(2, 2)))
	var fresh := Order.new_attack(9)
	u.set_current_order(fresh)
	assert_eq(u.orders.size(), 1)
	assert_eq(u.current_order, fresh)


func test_set_current_order_null_clears_the_queue() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_wheel(1))
	u.set_current_order(null)
	assert_null(u.current_order)
	assert_true(u.orders.is_empty())


func test_append_order_becomes_current_when_the_unit_is_idle() -> void:
	var u := _make_unit()
	var o := Order.new_move(Vector2(3, 3))
	u.append_order(o)
	assert_eq(u.current_order, o)
	assert_eq(u.orders.size(), 1)


func test_append_order_queues_behind_an_existing_current_order() -> void:
	var u := _make_unit()
	var first := Order.new_move(Vector2(1, 1))
	var second := Order.new_move(Vector2(2, 2))
	u.set_current_order(first)
	u.append_order(second)
	assert_eq(u.current_order, first)   # unchanged -- still marching the first leg
	assert_eq(u.orders.size(), 2)
	assert_eq(u.orders[1], second)


func test_retire_current_order_promotes_the_next_queued_order() -> void:
	var u := _make_unit()
	var first := Order.new_move(Vector2(1, 1))
	var second := Order.new_move(Vector2(2, 2))
	u.set_current_order(first)
	u.orders.append(second)
	u.retire_current_order()
	assert_eq(u.current_order, second)
	assert_eq(u.orders.size(), 1)


func test_retire_current_order_on_the_last_queued_order_clears_current() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_wheel(1))
	u.retire_current_order()
	assert_null(u.current_order)
	assert_true(u.orders.is_empty())


func test_retire_current_order_on_an_empty_queue_is_a_no_op() -> void:
	var u := _make_unit()
	u.retire_current_order()   # nothing queued -- must not error
	assert_null(u.current_order)


func test_clear_orders_empties_the_queue_and_current_order() -> void:
	var u := _make_unit()
	u.append_order(Order.new_move(Vector2(1, 1)))
	u.append_order(Order.new_move(Vector2(2, 2)))
	u.clear_orders()
	assert_null(u.current_order)
	assert_true(u.orders.is_empty())


# --- _update_current_order: retirement / phase bookkeeping ------------------

func test_update_current_order_is_a_no_op_when_idle() -> void:
	var u := _make_unit()
	u._update_current_order()   # must not error with no current order
	assert_null(u.current_order)


func test_move_order_retires_on_arrival() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_move(Vector2(10, 10)))
	u.has_move_target = false   # arrived; no queued waypoint leg
	u._update_current_order()
	assert_null(u.current_order)


func test_move_order_stays_current_while_still_marching() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_move(Vector2(10, 10)))
	u.has_move_target = true
	u._update_current_order()
	assert_not_null(u.current_order)
	assert_eq(u.current_order.type, Order.Type.MOVE)


func test_phased_move_order_transitions_turn_to_march_once_the_about_face_hands_off() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_move(Vector2(10, 10), 0, true))
	assert_eq(u.current_order.phase, Order.Phase.TURN)
	# The conversio has completed and committed the parked march (mirrors _think()'s
	# has_move_target=true / _conversio_target cleared / _has_pending_march consumed).
	u._conversio_target = Vector2.ZERO
	u._has_pending_march = false
	u.has_move_target = true
	u._update_current_order()
	assert_eq(u.current_order.phase, Order.Phase.MARCH)


func test_phased_move_order_stays_in_turn_phase_while_the_about_face_is_still_running() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_move(Vector2(10, 10), 0, true))
	u._conversio_target = Vector2(0, 1)   # still turning
	u._update_current_order()
	assert_eq(u.current_order.phase, Order.Phase.TURN)
	assert_not_null(u.current_order)   # not retired mid-turn


func test_attack_order_retires_once_the_target_enemy_is_cleared() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_attack(2))
	u.target_enemy = null
	u._update_current_order()
	assert_null(u.current_order)


func test_attack_order_stays_current_while_a_target_enemy_is_set() -> void:
	var u := _make_unit()
	var enemy := _make_unit(2)
	u.set_current_order(Order.new_attack(2))
	u.target_enemy = enemy
	u._update_current_order()
	assert_not_null(u.current_order)


func test_support_order_retires_once_the_ward_is_cleared() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_support(3))
	u.support_target = null
	u._update_current_order()
	assert_null(u.current_order)


func test_wheel_order_retires_once_the_wheel_target_clears() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_wheel(1))
	u._wheel_target = Vector2.ZERO
	u._update_current_order()
	assert_null(u.current_order)


func test_wheel_order_stays_current_while_the_wheel_is_still_swinging() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_wheel(1))
	u._wheel_target = Vector2(1, 0)
	u._update_current_order()
	assert_not_null(u.current_order)


func test_formation_order_retires_immediately() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_formation(1))
	u._update_current_order()
	assert_null(u.current_order)


func test_frontage_order_retires_immediately() -> void:
	var u := _make_unit()
	u.set_current_order(Order.new_frontage(4))
	u._update_current_order()
	assert_null(u.current_order)


# --- Teardown: death and rout drop every in-progress order -------------------

func test_rout_clears_the_orders_queue() -> void:
	var u := _make_unit()
	u.append_order(Order.new_move(Vector2(1, 1)))
	u.append_order(Order.new_move(Vector2(2, 2)))
	u._rout()
	assert_null(u.current_order)
	assert_true(u.orders.is_empty())
