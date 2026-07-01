extends GutTest
## Anti-cavalry square (orbis / schiltron): the all-around defensive stance.
## Its defining trait is that it has NO weak flank/rear facing vs cavalry -- the
## flank/rear damage multiplier no longer applies, and a charge from any direction
## is braced (backfires) instead of landing its impact bonus. The stance costs
## mobility and offensive output. These lock the combat + formation wiring.

const FRONT := Vector2(0, 100)    # ahead of a unit facing DOWN
const SIDE := Vector2(100, 0)     # to its flank
const REAR := Vector2(0, -100)    # behind it


func _make_unit(max_soldiers: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func _attacker_at(p: Vector2) -> Unit:
	var a: Unit = Unit.new()
	add_child_autofree(a)
	a.position = p
	return a


# --- all-around defence: no flank/rear multiplier -----------------------------

func test_normal_unit_takes_the_flank_and_rear_multipliers() -> void:
	# Baseline (the contrast case): an ordinary unit is soft on the flank and rear.
	var u := _make_unit()
	assert_almost_eq(UnitCombat.flank_multiplier(u, _attacker_at(FRONT)), 1.0, 0.001,
		"frontal is x1.0")
	assert_almost_eq(UnitCombat.flank_multiplier(u, _attacker_at(SIDE)), 1.5, 0.001,
		"a flank hit is x1.5")
	assert_almost_eq(UnitCombat.flank_multiplier(u, _attacker_at(REAR)), 2.0, 0.001,
		"a rear hit is x2.0")


func test_squared_unit_takes_no_flank_or_rear_multiplier() -> void:
	# The defining mechanic: in square, an attack from ANY direction lands as frontal.
	var u := _make_unit()
	u.set_formation(Unit.FORMATION_SQUARE)
	var front := UnitCombat.flank_multiplier(u, _attacker_at(FRONT))
	var flank := UnitCombat.flank_multiplier(u, _attacker_at(SIDE))
	var rear := UnitCombat.flank_multiplier(u, _attacker_at(REAR))
	assert_almost_eq(front, 1.0, 0.001, "frontal is x1.0")
	assert_almost_eq(flank, front, 0.001, "a squared unit's flank equals its front (no bonus)")
	assert_almost_eq(rear, front, 0.001, "a squared unit's rear equals its front (no bonus)")


# --- braces the charge from any direction -------------------------------------

func _cavalry_charging_from(target: Unit, from: Vector2) -> Unit:
	# A cavalry unit sitting at `from`, carrying a full-gallop approach velocity aimed
	# straight at `target` -- the input the physics-based charge multiplier reads.
	var cav := _attacker_at(from)
	cav.is_cavalry = true
	var dir: Vector2 = (target.position - cav.position).normalized()
	cav._approach_velocity = dir * Unit.CHARGE_REFERENCE_SPEED
	return cav


func test_normal_unit_is_charged_harder_from_the_rear() -> void:
	# Baseline: an ordinary unit rewards a charge (multiplier > 1) from any side.
	var u := _make_unit()
	var front_cav := _cavalry_charging_from(u, REAR)   # charges toward the unit's FRONT edge
	assert_gt(UnitCombat.charge_multiplier(front_cav, u), 1.0,
		"a charge into a normal unit lands an impact bonus")


func test_squared_unit_braces_a_charge_from_any_direction() -> void:
	# A charge into the square backfires (multiplier < 1) whether it comes from the
	# front, flank, or rear -- there is no open side to hit at full impact.
	var u := _make_unit()
	u.set_formation(Unit.FORMATION_SQUARE)
	for from: Vector2 in [FRONT, SIDE, REAR]:
		var cav := _cavalry_charging_from(u, from)
		var mult := UnitCombat.charge_multiplier(cav, u)
		assert_lt(mult, 1.0, "a charge from %s backfires into the square" % from)
		assert_gte(mult, Unit.SQUARE_CHARGE_FLOOR - 0.001,
			"the backfire is floored at SQUARE_CHARGE_FLOOR")


func test_square_charge_backfire_is_direction_independent() -> void:
	# The braced backfire is identical from front and rear -- the all-around ring
	# presents the same set spears on every side (the whole point of the stance).
	var u := _make_unit()
	u.set_formation(Unit.FORMATION_SQUARE)
	var from_front := UnitCombat.charge_multiplier(_cavalry_charging_from(u, FRONT), u)
	var from_rear := UnitCombat.charge_multiplier(_cavalry_charging_from(u, REAR), u)
	assert_almost_eq(from_rear, from_front, 0.001,
		"a rear charge into the square is braced exactly like a front charge")


# --- the cost: mobility and offence -------------------------------------------

func test_square_reduces_offensive_output() -> void:
	var u := _make_unit()
	assert_almost_eq(u.formation_attack_factor(), 1.0, 0.001, "normal stance hits at full")
	u.set_formation(Unit.FORMATION_SQUARE)
	assert_almost_eq(u.formation_attack_factor(), Unit.SQUARE_ATTACK_FACTOR, 0.001,
		"square hits softer")
	assert_lt(Unit.SQUARE_ATTACK_FACTOR, 1.0, "the offence penalty is a real reduction")


func test_square_crawls_relative_to_normal() -> void:
	# Same move order from the same spot: the squared unit advances less this frame.
	# High accel so the per-frame speed is capped by the chosen PACE, not the ramp --
	# that isolates the square's pace penalty (SQUARE_MOVE_FACTOR) from acceleration.
	var normal := _make_unit()
	normal.move_speed = 90.0
	normal.walk_speed = 90.0
	normal.jog_speed = 90.0
	normal.accel = 10000.0
	normal.facing = Vector2.DOWN
	normal.has_move_target = true
	normal.move_target = Vector2(0, 1000)
	normal._order_response_timer = 0.0
	normal._think(0.2)

	var squared := _make_unit()
	squared.move_speed = 90.0
	squared.walk_speed = 90.0
	squared.jog_speed = 90.0
	squared.accel = 10000.0
	squared.facing = Vector2.DOWN
	squared.set_formation(Unit.FORMATION_SQUARE)
	squared.has_move_target = true
	squared.move_target = Vector2(0, 1000)
	squared._order_response_timer = 0.0
	squared._think(0.2)

	assert_gt(normal.position.y, 0.0, "the normal unit advanced")
	assert_lt(squared.position.y, normal.position.y,
		"the squared unit crawls -- it advances less than the normal unit")


# --- formation mode wiring (set / label / cycle) ------------------------------

func test_set_formation_records_square_and_close_order_footprint() -> void:
	var u := _make_unit()
	var base := u._base_separation_radius
	u.set_formation(Unit.FORMATION_SQUARE)
	assert_eq(u.formation_mode, Unit.FORMATION_SQUARE, "the mode is set")
	assert_true(u.in_square(), "in_square() reports the stance")
	# Square packs to the same close-order floor as Tight.
	assert_almost_eq(u.separation_radius, base * Unit.TIGHT_SEPARATION_SCALE, 0.001,
		"square closes ranks to the tight footprint")
	assert_almost_eq(u.spacing_scale, 1.0, 0.001, "and holds the close-order grid spacing")


func test_formation_summary_labels_square() -> void:
	var u := _make_unit()
	u.set_formation(Unit.FORMATION_SQUARE)
	assert_eq(u.formation_summary(), "Square", "the HUD label reads Square")


func test_t_cycle_reaches_square() -> void:
	# The T-key cycle order includes SQUARE, so the player can reach it by cycling.
	const SM = preload("res://scripts/SelectionManager.gd")
	assert_true(SM.FORMATION_CYCLE.has(Unit.FORMATION_SQUARE),
		"the formation cycle includes the square")
