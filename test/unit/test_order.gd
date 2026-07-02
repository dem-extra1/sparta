extends GutTest
## Order value type (docs/orders-queue-design.md phase 1, #522): pure, node-free tests for the
## enum-name tables, the readable describe() string, and the constructor helpers Battle uses to
## build each order kind.


func test_type_name_maps_every_known_type() -> void:
	assert_eq(Order.type_name(Order.Type.MOVE), "MOVE")
	assert_eq(Order.type_name(Order.Type.ATTACK), "ATTACK")
	assert_eq(Order.type_name(Order.Type.RELIEF), "RELIEF")
	assert_eq(Order.type_name(Order.Type.SUPPORT), "SUPPORT")
	assert_eq(Order.type_name(Order.Type.WHEEL), "WHEEL")
	assert_eq(Order.type_name(Order.Type.NUDGE), "NUDGE")
	assert_eq(Order.type_name(Order.Type.FORMATION), "FORMATION")
	assert_eq(Order.type_name(Order.Type.FRONTAGE), "FRONTAGE")


func test_phase_name_maps_every_known_phase() -> void:
	assert_eq(Order.phase_name(Order.Phase.NONE), "NONE")
	assert_eq(Order.phase_name(Order.Phase.TURN), "TURN")
	assert_eq(Order.phase_name(Order.Phase.MARCH), "MARCH")


func test_type_name_falls_back_for_an_unmapped_value() -> void:
	assert_eq(Order.type_name(99), "TYPE(99)")


func test_phase_name_falls_back_for_an_unmapped_value() -> void:
	assert_eq(Order.phase_name(99), "PHASE(99)")


func test_describe_omits_the_phase_when_unphased() -> void:
	var o := Order.new_wheel(1)
	assert_eq(o.describe(), "WHEEL")


func test_describe_includes_the_phase_when_phased() -> void:
	var o := Order.new_move(Vector2(1, 2), 0, true)
	assert_eq(o.describe(), "MOVE:TURN")


func test_new_move_defaults_to_unphased() -> void:
	var o := Order.new_move(Vector2(5, 5))
	assert_eq(o.type, Order.Type.MOVE)
	assert_eq(o.phase, Order.Phase.NONE)
	assert_eq(o.target_pos, Vector2(5, 5))


func test_new_move_phased_starts_in_the_turn_phase() -> void:
	var o := Order.new_move(Vector2(5, 5), 0, true)
	assert_eq(o.phase, Order.Phase.TURN)


func test_new_attack_carries_target_uid_and_mode() -> void:
	var o := Order.new_attack(7, 2)
	assert_eq(o.type, Order.Type.ATTACK)
	assert_eq(o.target_uid, 7)
	assert_eq(o.order_mode, 2)


func test_new_relief_and_new_support_carry_target_uid() -> void:
	assert_eq(Order.new_relief(3).target_uid, 3)
	assert_eq(Order.new_support(4).target_uid, 4)


func test_new_wheel_and_new_nudge_carry_direction() -> void:
	assert_eq(Order.new_wheel(-1).dir, -1)
	assert_eq(Order.new_nudge(2).dir, 2)


func test_new_formation_and_new_frontage_carry_their_value() -> void:
	assert_eq(Order.new_formation(3).formation, 3)
	assert_eq(Order.new_frontage(6).frontage, 6)
