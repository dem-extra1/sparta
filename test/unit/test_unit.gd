extends GutTest
## Unit tests for the deterministic combat math in scripts/Unit.gd:
## flanking multipliers and casualty/morale application. (The randomised
## damage in _strike() is intentionally not tested here.)

const FRONT := Vector2(0, 100)    # ahead of a unit facing DOWN
const SIDE := Vector2(100, 0)     # to its flank
const REAR := Vector2(0, -100)    # behind it


func _make_unit(max_soldiers: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	# _ready() (runs on add_child) sets soldiers = max_soldiers and joins groups.
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func _attacker_at(p: Vector2) -> Unit:
	var a: Unit = Unit.new()
	add_child_autofree(a)
	a.position = p
	return a


# --- _flank_multiplier -----------------------------------------------------

func test_frontal_hit_is_1x() -> void:
	var u := _make_unit()
	assert_almost_eq(u._flank_multiplier(_attacker_at(FRONT)), 1.0, 0.001)


func test_flank_hit_is_1_5x() -> void:
	var u := _make_unit()
	assert_almost_eq(u._flank_multiplier(_attacker_at(SIDE)), 1.5, 0.001)


func test_rear_hit_is_2x() -> void:
	var u := _make_unit()
	assert_almost_eq(u._flank_multiplier(_attacker_at(REAR)), 2.0, 0.001)


# --- take_casualties -------------------------------------------------------

func test_frontal_casualties_reduce_soldiers_one_for_one() -> void:
	var u := _make_unit(120)
	u.take_casualties(10, _attacker_at(FRONT))
	assert_eq(u.soldiers, 110, "frontal: 10 casualties -> -10 soldiers")


func test_rear_casualties_are_doubled() -> void:
	var u := _make_unit(120)
	u.take_casualties(10, _attacker_at(REAR))
	assert_eq(u.soldiers, 100, "rear hit doubles casualties (10 -> 20)")


func test_casualties_erode_morale() -> void:
	var u := _make_unit(120)
	u.take_casualties(10, _attacker_at(FRONT))
	assert_lt(u.morale, 100.0, "taking losses lowers morale")


func test_lethal_casualties_kill_the_unit() -> void:
	var u := _make_unit(120)
	u.take_casualties(1000, _attacker_at(FRONT))
	assert_eq(u.soldiers, 0, "soldiers floored at 0")
	assert_eq(u.state, Unit.State.DEAD, "a wiped-out unit dies")


func test_dead_unit_ignores_further_casualties() -> void:
	var u := _make_unit(120)
	u.take_casualties(1000, _attacker_at(FRONT))   # kills it
	u.take_casualties(10, _attacker_at(FRONT))     # should be a no-op
	assert_eq(u.soldiers, 0, "a dead unit takes no more casualties")


# --- order_summary ---------------------------------------------------------

func test_order_summary_idle_holds_position() -> void:
	var u := _make_unit()
	assert_eq(u.order_summary(), "Holding position",
		"a unit with no order reports holding")


func test_order_summary_reports_move_destination() -> void:
	var u := _make_unit()
	u.move_target = Vector2(420, -130)
	u.has_move_target = true
	assert_eq(u.order_summary(), "Moving to (420, -130)",
		"a move order reports its destination coordinates")


func test_order_summary_reports_attack_target_by_name() -> void:
	var u := _make_unit()
	var enemy := _attacker_at(FRONT)   # any other live unit serves as the target
	enemy.unit_name = "Infantry 2"
	enemy.team = 1
	u.target_enemy = enemy
	assert_eq(u.order_summary(), "Attacking Infantry 2",
		"an attack order names the targeted enemy")


func test_order_summary_attack_takes_priority_over_move() -> void:
	var u := _make_unit()
	var enemy := _attacker_at(FRONT)
	enemy.unit_name = "Cavalry 1"
	u.target_enemy = enemy
	u.move_target = Vector2(10, 10)
	u.has_move_target = true
	assert_eq(u.order_summary(), "Attacking Cavalry 1",
		"an explicit attack target is reported ahead of a move target")
