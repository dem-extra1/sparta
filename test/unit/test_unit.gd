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


# --- hold location (#84) ---------------------------------------------------

func test_hold_unit_does_not_chase_a_nearby_enemy() -> void:
	var u := _make_unit()
	u.team = 0
	u.order_mode = Unit.ORDER_HOLD
	u.position = Vector2.ZERO
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(100, 0)   # inside DETECTION_RANGE, out of melee contact
	var before := u.position
	u._think(0.1)
	assert_eq(u.position, before, "a holding unit doesn't advance on a detected enemy")
	assert_eq(u.state, Unit.State.IDLE, "and stays idle")


func test_normal_unit_chases_a_nearby_enemy() -> void:
	# Contrast: the same setup without HOLD advances — confirming the guard is what
	# pins a held unit in place, not the test geometry.
	var u := _make_unit()
	u.team = 0
	u.position = Vector2.ZERO        # order_mode defaults to NORMAL
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(100, 0)
	var before := u.position
	u._think(0.1)
	assert_ne(u.position, before, "a normal unit advances on a detected enemy")


func test_hold_unit_still_fights_an_enemy_in_contact() -> void:
	# HOLD suppresses only chasing — a held unit defends itself when reached.
	var u := _make_unit()
	u.team = 0
	u.order_mode = Unit.ORDER_HOLD
	u.position = Vector2.ZERO
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(u.attack_range + Unit.RADIUS + enemy.RADIUS - 1.0, 0)
	u._think(0.1)
	assert_eq(u.state, Unit.State.FIGHTING, "a held unit still fights an enemy in melee contact")


func test_hold_ranged_unit_still_fires_within_range() -> void:
	var u := _make_unit()
	u.team = 0
	u.is_ranged = true
	u.order_mode = Unit.ORDER_HOLD
	u.position = Vector2.ZERO
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(Unit.RANGED_RANGE - 20.0, 0)   # in ranged range, out of melee
	u._think(0.1)
	assert_eq(u.state, Unit.State.FIGHTING, "a held ranged unit still looses volleys in range")


# --- skirmish kiting (#85) -------------------------------------------------

func test_skirmish_ranged_unit_retreats_from_a_close_enemy() -> void:
	var u := _make_unit()
	u.team = 0
	u.is_ranged = true
	u.order_mode = Unit.ORDER_SKIRMISH
	u.position = Vector2.ZERO
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(Unit.SKIRMISH_KITE_DISTANCE - 40.0, 0)   # inside the kite distance
	u._think(0.1)
	assert_lt(u.position.x, 0.0, "a skirmisher backs away from an enemy inside the kite distance")


func test_skirmish_ranged_unit_fires_at_standoff_range() -> void:
	var u := _make_unit()
	u.team = 0
	u.is_ranged = true
	u.order_mode = Unit.ORDER_SKIRMISH
	u.position = Vector2.ZERO
	var enemy := _make_unit()
	enemy.team = 1
	# Beyond the kite distance but within RANGED_RANGE -> fire, don't retreat.
	enemy.position = Vector2(Unit.SKIRMISH_KITE_DISTANCE + 40.0, 0)
	u._think(0.1)
	assert_eq(u.state, Unit.State.FIGHTING, "a skirmisher fires at a standoff-range enemy")
	assert_eq(u.position, Vector2.ZERO, "and holds its ground while firing")


func test_skirmish_cornered_unit_fires_instead_of_freezing() -> void:
	# A skirmisher pinned against the field edge can't retreat (the clamp snaps the
	# target onto its position). It must fall through and fire, not stand idle.
	var u := _make_unit()
	u.team = 0
	u.is_ranged = true
	u.order_mode = Unit.ORDER_SKIRMISH
	u.field_bounds = Rect2(0, 0, 1000, 1000)
	u.position = Vector2(0, 500)                 # against the left edge
	var enemy := _make_unit()
	enemy.team = 1
	# Right of it, inside the kite distance but beyond melee contact (a standoff foe).
	enemy.position = Vector2(Unit.SKIRMISH_KITE_DISTANCE - 20.0, 500)
	u._think(0.1)
	assert_eq(u.position.x, 0.0, "a cornered kiter stays clamped on the field edge")
	assert_eq(u.state, Unit.State.FIGHTING, "and fires rather than freezing")


func test_skirmish_ranged_unit_does_not_kite_on_a_plain_move_order() -> void:
	# A plain move order (move target, no explicit attack target) disengages: the
	# skirmisher marches to the destination instead of kiting. Geometry is chosen so
	# kiting (-x, away from the enemy) and marching (+x, toward the destination) pull
	# opposite ways, so the assertion actually distinguishes them.
	var u := _make_unit()
	u.team = 0
	u.is_ranged = true
	u.order_mode = Unit.ORDER_SKIRMISH
	u.position = Vector2(500, 500)
	u.move_target = Vector2(600, 500)   # destination is to the +x side
	u.has_move_target = true
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = u.position + Vector2(Unit.SKIRMISH_KITE_DISTANCE - 20.0, 0.0)  # +x, inside kite range
	u._think(0.1)
	assert_gt(u.position.x, 500.0, "a skirmisher under a move order marches to its destination, not away")


# --- support / defend a friendly (#86) -------------------------------------

func test_support_unit_moves_toward_its_ward_with_no_threat() -> void:
	var u := _make_unit()
	u.team = 0
	u.order_mode = Unit.ORDER_SUPPORT
	u.position = Vector2.ZERO
	var ward := _make_unit()
	ward.team = 0
	ward.position = Vector2(300, 0)   # well beyond the follow standoff, no enemy about
	u.support_target = ward
	u._think(0.1)
	assert_gt(u.position.x, 0.0, "a supporter with no threat near its ward closes on the ward")


func test_support_unit_holds_station_when_near_its_ward() -> void:
	var u := _make_unit()
	u.team = 0
	u.order_mode = Unit.ORDER_SUPPORT
	u.position = Vector2.ZERO
	var ward := _make_unit()
	ward.team = 0
	ward.position = Vector2(Unit.SUPPORT_FOLLOW_DISTANCE - 20.0, 0)   # already at standoff
	u.support_target = ward
	u._think(0.1)
	assert_eq(u.position, Vector2.ZERO, "a supporter already at standoff from its ward holds station")
	assert_eq(u.state, Unit.State.IDLE, "and goes idle")


func test_support_unit_engages_a_threat_near_its_ward() -> void:
	var u := _make_unit()
	u.team = 0
	u.order_mode = Unit.ORDER_SUPPORT
	u.position = Vector2.ZERO
	var ward := _make_unit()
	ward.team = 0
	ward.position = Vector2(60, 0)
	u.support_target = ward
	var threat := _make_unit()
	threat.team = 1
	# Near the ward (inside SUPPORT_GUARD_RADIUS) and in melee contact with the supporter.
	threat.position = Vector2(u.attack_range + Unit.RADIUS + threat.RADIUS - 2.0, 0)
	var before: int = threat.soldiers
	u._think(0.1)
	assert_eq(u.state, Unit.State.FIGHTING, "a supporter fights a threat that reached its ward")
	assert_lt(threat.soldiers, before, "and deals casualties to it")


func test_support_unit_advances_on_a_distant_threat_near_its_ward() -> void:
	var u := _make_unit()
	u.team = 0
	u.order_mode = Unit.ORDER_SUPPORT
	u.position = Vector2.ZERO
	var ward := _make_unit()
	ward.team = 0
	ward.position = Vector2(150, 0)
	u.support_target = ward
	var threat := _make_unit()
	threat.team = 1
	threat.position = Vector2(140, 0)   # near the ward, far from the supporter
	u._think(0.1)
	assert_gt(u.position.x, 0.0, "a supporter closes on a threat near its ward but out of its reach")


func test_support_ranged_unit_fires_at_a_threat_near_its_ward() -> void:
	var u := _make_unit()
	u.team = 0
	u.is_ranged = true
	u.order_mode = Unit.ORDER_SUPPORT
	u.position = Vector2.ZERO
	var ward := _make_unit()
	ward.team = 0
	ward.position = Vector2(120, 0)
	u.support_target = ward
	var threat := _make_unit()
	threat.team = 1
	# Near the ward, within the supporter's ranged range but beyond melee contact.
	threat.position = Vector2(Unit.RANGED_RANGE - 40.0, 0)
	var before: int = threat.soldiers
	u._think(0.1)
	assert_eq(u.state, Unit.State.FIGHTING, "a ranged supporter looses on a threat near its ward")
	assert_eq(u.position, Vector2.ZERO, "firing from where it stands, not closing in")
	assert_lt(threat.soldiers, before, "the volley hits the threat")


func test_support_unit_reverts_to_normal_when_ward_dies() -> void:
	# Once the guarded ward is gone the support order is spent: the unit drops the
	# dangling reference and reverts to NORMAL auto-behaviour.
	var u := _make_unit()
	u.team = 0
	u.order_mode = Unit.ORDER_SUPPORT
	u.position = Vector2.ZERO
	var ward := _make_unit()
	ward.team = 0
	u.support_target = ward
	ward.state = Unit.State.DEAD
	u._think(0.1)
	assert_eq(u.order_mode, 0, "a supporter whose ward is gone reverts to NORMAL")
	assert_null(u.support_target, "and drops the dangling ward reference")


func test_order_summary_reports_support_ward() -> void:
	var u := _make_unit()
	u.order_mode = Unit.ORDER_SUPPORT
	var ward := _make_unit()
	ward.unit_name = "Archers 3"
	u.support_target = ward
	assert_eq(u.order_summary(), "Supporting Archers 3",
		"a supporting unit reports the ward it's guarding")


# --- attack flank / rear approach (#82) ------------------------------------

func test_attack_rear_approach_point_is_behind_the_target() -> void:
	var u := _make_unit()
	u.order_mode = Unit.ORDER_ATTACK_REAR
	var enemy := _make_unit()
	enemy.facing = Vector2.DOWN     # facing +y
	enemy.position = Vector2.ZERO
	var contact: float = u.attack_range + Unit.RADIUS + enemy.RADIUS
	assert_eq(u._attack_approach_point(enemy), Vector2(0, -contact),
		"rear approach is directly behind the target (opposite its facing)")


func test_attack_flank_approach_point_is_on_the_near_side() -> void:
	var u := _make_unit()
	u.order_mode = Unit.ORDER_ATTACK_FLANK
	u.position = Vector2(100, 0)    # to the enemy's right
	var enemy := _make_unit()
	enemy.facing = Vector2.DOWN
	enemy.position = Vector2.ZERO
	var contact: float = u.attack_range + Unit.RADIUS + enemy.RADIUS
	assert_eq(u._attack_approach_point(enemy), Vector2(contact, 0),
		"flank approach is on the side the attacker is already nearer")


func test_attack_flank_tie_break_picks_the_perp_side() -> void:
	# Attacker exactly on the enemy's forward axis: the dot-product tie-break (>= 0)
	# sends it to the enemy's perp side deterministically (not the shortest route).
	var u := _make_unit()
	u.order_mode = Unit.ORDER_ATTACK_FLANK
	u.position = Vector2(0, 100)    # directly in front of an enemy facing +y
	var enemy := _make_unit()
	enemy.facing = Vector2.DOWN
	enemy.position = Vector2.ZERO
	var contact: float = u.attack_range + Unit.RADIUS + enemy.RADIUS
	# perp = (-facing.y, facing.x) = (-1, 0); dot == 0 -> side = +1 -> perp * contact.
	assert_eq(u._attack_approach_point(enemy), Vector2(-contact, 0),
		"an on-axis flank attack breaks the tie to the enemy's perp side")


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


func test_order_summary_routing_overrides_any_queued_order() -> void:
	var u := _make_unit()
	u.state = Unit.State.ROUTING
	u.move_target = Vector2(50, 50)
	u.has_move_target = true
	assert_eq(u.order_summary(), "Routing!",
		"a routing unit reports routing regardless of any queued order")


func test_order_summary_fighting_without_target_is_engaged() -> void:
	var u := _make_unit()
	u.state = Unit.State.FIGHTING
	assert_eq(u.order_summary(), "Engaged",
		"auto-fighting (no explicit target) reports Engaged")


func test_order_summary_moving_without_target_advances() -> void:
	var u := _make_unit()
	u.state = Unit.State.MOVING
	assert_eq(u.order_summary(), "Advancing on enemy",
		"moving with no explicit destination reports advancing on the enemy")


func test_order_summary_ignores_routing_target() -> void:
	var u := _make_unit()
	var enemy := _attacker_at(FRONT)
	enemy.unit_name = "Infantry 9"
	u.target_enemy = enemy
	enemy.state = Unit.State.ROUTING
	# A routing enemy is no longer a valid attack target, so the order falls
	# through to the move/state description (here: idle -> holding).
	assert_eq(u.order_summary(), "Holding position",
		"a routing target is not reported as an attack order")


func test_order_summary_ignores_dead_target() -> void:
	var u := _make_unit()
	var enemy := _attacker_at(FRONT)
	enemy.unit_name = "Infantry 9"
	u.target_enemy = enemy
	enemy.state = Unit.State.DEAD
	# Likewise a dead (but not yet pruned) target is not a valid attack order.
	assert_eq(u.order_summary(), "Holding position",
		"a dead target is not reported as an attack order")


# --- physics-based cavalry charge (issue #100) -----------------------------

func test_charge_full_on_headon_gallop() -> void:
	var u := _cavalry()
	u.position = Vector2.ZERO
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(100, 0)                  # straight ahead
	u._approach_velocity = Vector2(u.move_speed, 0)   # full-speed, dead-on
	var expected: float = 1.0 + Unit.CHARGE_BONUS_AT_REF_SPEED * (u.move_speed / Unit.CHARGE_REFERENCE_SPEED)
	assert_almost_eq(u.charge_multiplier(enemy), expected, 0.001,
		"a full-speed head-on charge lands the full momentum bonus")


func test_charge_none_when_stationary() -> void:
	var u := _cavalry()
	u.position = Vector2.ZERO
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(100, 0)
	u._approach_velocity = Vector2.ZERO              # carrying no momentum
	assert_almost_eq(u.charge_multiplier(enemy), 1.0, 0.001,
		"a stationary cavalry unit (no impact velocity) gets no charge")


func test_charge_ignores_motion_across_the_target() -> void:
	var u := _cavalry()
	u.position = Vector2.ZERO
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(100, 0)                 # target on the +x axis
	u._approach_velocity = Vector2(0, u.move_speed)  # moving perpendicular to it
	assert_almost_eq(u.charge_multiplier(enemy), 1.0, 0.001,
		"velocity across the target (not toward it) earns no charge")


func test_charge_glancing_is_between_none_and_full() -> void:
	var u := _cavalry()
	u.position = Vector2.ZERO
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(100, 0)
	u._approach_velocity = Vector2(u.move_speed, 0)
	var full: float = u.charge_multiplier(enemy)
	u._approach_velocity = Vector2(1, 1).normalized() * u.move_speed   # 45-degree approach
	var glancing: float = u.charge_multiplier(enemy)
	assert_gt(glancing, 1.0, "a glancing charge still lands some bonus")
	assert_lt(glancing, full, "but less than a head-on charge at the same speed")


func test_charge_into_spears_backfires_into_a_penalty() -> void:
	var u := _cavalry()
	u.position = Vector2.ZERO
	var spear := _spearman_unit()                   # anti_cavalry = true
	spear.team = 1
	spear.position = Vector2(100, 0)
	u._approach_velocity = Vector2(u.move_speed, 0)  # full charge onto braced spears
	assert_lt(u.charge_multiplier(spear), 1.0,
		"charging a braced spear line backfires into a damage penalty")
	assert_gte(u.charge_multiplier(spear), Unit.ANTI_CAV_CHARGE_FLOOR,
		"the backfire is floored so it never zeroes the rider's damage")


func test_non_cavalry_never_charges() -> void:
	var u := _make_unit()                            # infantry
	u.position = Vector2.ZERO
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(100, 0)
	u._approach_velocity = Vector2(u.move_speed, 0)
	assert_almost_eq(u.charge_multiplier(enemy), 1.0, 0.001,
		"only cavalry get a charge bonus")


func test_cavalry_does_not_charge_cavalry() -> void:
	var u := _cavalry()
	u.position = Vector2.ZERO
	var enemy := _cavalry()
	enemy.team = 1
	enemy.position = Vector2(100, 0)
	u._approach_velocity = Vector2(u.move_speed, 0)
	assert_almost_eq(u.charge_multiplier(enemy), 1.0, 0.001,
		"a charge doesn't apply cavalry-vs-cavalry")


func test_move_to_records_approach_velocity() -> void:
	var u := _cavalry()
	u.position = Vector2.ZERO
	u._move_to(Vector2(100, 0), 0.1)
	assert_almost_eq(u._approach_velocity.x, u.move_speed, 0.001,
		"moving toward a point records the closing speed for the charge model")
	assert_almost_eq(u._approach_velocity.y, 0.0, 0.001, "in the direction of travel")


func test_approach_velocity_clears_after_a_stationary_frame() -> void:
	# A stationary, non-fighting unit carries no momentum: the impact velocity is dropped
	# so a later standing strike can't charge off stale motion.
	var u := _cavalry()
	u.position = Vector2.ZERO
	u._approach_velocity = Vector2(u.move_speed, 0)   # as if it just galloped in
	u._physics_process(0.016)                          # a frame with no enemy / no move
	assert_eq(u._approach_velocity, Vector2.ZERO,
		"an idle frame with no movement clears the carried impact velocity")


func test_strike_spends_the_charge_velocity() -> void:
	# The charge is spent on the strike that lands it, so follow-up grinding strikes in
	# the same melee don't each re-charge off the same approach.
	var u := _cavalry()
	u.position = Vector2.ZERO
	u._approach_velocity = Vector2(u.move_speed, 0)
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(100, 0)
	u._strike(enemy)
	assert_eq(u._approach_velocity, Vector2.ZERO,
		"a strike consumes the carried impact velocity")


func test_approach_velocity_survives_a_cooldown_wait_in_contact() -> void:
	# If a cavalry reaches contact while its attack is still on cooldown, the impact
	# velocity must survive the wait frame (it's FIGHTING, not idle) so the first actual
	# strike still charges — rather than being cleared as if the unit had stopped.
	var u := _cavalry()
	u.position = Vector2.ZERO
	u._approach_velocity = Vector2(u.move_speed, 0)
	u._attack_cd = 1.0                       # not ready to strike yet
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(u.attack_range + Unit.RADIUS + enemy.RADIUS - 2.0, 0)  # in contact
	# Contact frame: _think enters the in-contact branch → state = FIGHTING, but no strike
	# (cd > 0) and no _move_to. The end-of-frame idle-clear is skipped *because* state is
	# FIGHTING, so the carried velocity survives to the first real strike once cd elapses.
	u._physics_process(0.016)
	assert_eq(u.state, Unit.State.FIGHTING, "the unit is in contact and fighting")
	assert_gt(u._approach_velocity.length(), 0.0,
		"impact velocity is kept through the cooldown wait, not cleared as if idle")


func test_stationary_cavalry_takes_no_spear_penalty() -> void:
	# Physics model (#100): the anti-cavalry penalty IS the charge backfiring, so a
	# cavalry unit that isn't charging (no impact velocity) fights spearmen at full
	# effectiveness — unlike the old flat first-strike x0.6. Recorded as intended.
	var u := _cavalry()
	u.position = Vector2.ZERO
	var spear := _spearman_unit()            # anti_cavalry = true
	spear.team = 1
	spear.position = Vector2(100, 0)
	u._approach_velocity = Vector2.ZERO      # standing, not charging
	assert_almost_eq(u.charge_multiplier(spear), 1.0, 0.001,
		"a stationary (non-charging) cavalry unit takes no anti-cavalry penalty")


# --- per-type footprint (issue #6) -----------------------------------------

func _cavalry() -> Unit:
	var u: Unit = Unit.new()
	u.is_cavalry = true                 # set before _ready() so footprint is cavalry
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func test_cavalry_footprint_wider_than_infantry() -> void:
	var inf := _make_unit()
	var cav := _cavalry()
	assert_gt(cav.separation_radius, inf.separation_radius,
		"cavalry should have a wider collision footprint than infantry")


func test_infantry_pair_clear_at_40px_not_pushed() -> void:
	# 40px exceeds the infantry floor (18+18=36), so there is no separation push.
	var a := _make_unit()
	var b := _make_unit()
	a.position = Vector2.ZERO
	b.position = Vector2(40.0, 0.0)
	a._separate()
	assert_almost_eq(a.position.x, 0.0, 0.001, "infantry at 40px are already clear")


func test_cavalry_pair_overlap_at_40px_pushed_apart() -> void:
	# 40px is inside the cavalry floor (24+24=48), so the pair pushes apart.
	var a := _cavalry()
	var b := _cavalry()
	a.position = Vector2.ZERO
	b.position = Vector2(40.0, 0.0)
	a._separate()
	assert_lt(a.position.x, 0.0, "cavalry at 40px overlap by footprint and push apart")


func _spearman_unit() -> Unit:
	var u: Unit = Unit.new()
	u.anti_cavalry = true   # set before _ready() so the footprint is spearmen
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func test_spearmen_footprint_between_infantry_and_cavalry() -> void:
	var spear := _spearman_unit()
	assert_gt(spear.separation_radius, _make_unit().separation_radius,
		"spearmen footprint exceeds infantry")
	assert_lt(spear.separation_radius, _cavalry().separation_radius,
		"spearmen footprint is below cavalry")


func test_spearmen_pair_overlap_at_38px_pushed_apart() -> void:
	# 38px is inside the spearmen floor (20+20=40) but outside the infantry
	# floor (18+18=36), so only spearmen push at this gap.
	var a := _spearman_unit()
	var b := _spearman_unit()
	a.position = Vector2.ZERO
	b.position = Vector2(38.0, 0.0)
	a._separate()
	assert_lt(a.position.x, 0.0, "spearmen at 38px overlap by footprint and push apart")


# --- co-located fan-out determinism (issue #50) ----------------------------

func test_co_located_pair_fans_apart_by_uid() -> void:
	# Two regiments stacked on the exact same spot must push in OPPOSITE
	# directions so they fan apart instead of staying welded together.
	var a := _make_unit()
	var b := _make_unit()
	a.uid = 5
	b.uid = 7
	a.position = Vector2.ZERO
	b.position = Vector2.ZERO
	a._separate()
	var a_push: Vector2 = a.position
	a.position = Vector2.ZERO   # reset so b sees the same co-located pair
	b._separate()
	var b_push: Vector2 = b.position
	assert_gt(a_push.length(), 0.0, "a co-located unit is pushed off the stack")
	assert_gt(b_push.length(), 0.0, "its partner is pushed too")
	assert_lt(a_push.dot(b_push), 0.0, "the pair fans apart in opposite directions")


func test_co_located_push_matches_uid_formula() -> void:
	# The fan-out angle and sign are keyed off the stable uid (issue #50): keyed
	# off get_instance_id() — which is assigned per launch — a live run and its
	# replay would push co-located units different ways and desync. Pin the exact
	# vector the uid formula produces so a regression to instance ids is caught.
	var a := _make_unit()
	var b := _make_unit()
	a.uid = 5
	b.uid = 7
	a.position = Vector2.ZERO
	b.position = Vector2.ZERO
	a._separate()
	# lo = min(5, 7) = 5 -> angle = 5/100 * TAU; a holds the lower uid so dir = -1.
	# magnitude = (sep_a + sep_b) * share, share = 0.5 for two infantry friendlies.
	var magnitude: float = (a.separation_radius + b.separation_radius) * 0.5
	var expected: Vector2 = Vector2.RIGHT.rotated(0.05 * TAU) * -1.0 * magnitude
	assert_almost_eq(a.position.x, expected.x, 0.001, "co-located push x matches the uid formula")
	assert_almost_eq(a.position.y, expected.y, 0.001, "co-located push y matches the uid formula")


func test_co_located_equal_uid_pair_still_fans_apart() -> void:
	# Two unspawned units share the default uid (-1), so there's no stable uid
	# order to break the tie. The sign falls back to instance id (always distinct
	# between two objects) so the pair still fans apart rather than stacking.
	var a := _make_unit()
	var b := _make_unit()
	assert_eq(a.uid, -1, "unspawned units keep the default uid")
	assert_eq(b.uid, -1, "unspawned units keep the default uid")
	a.position = Vector2.ZERO
	b.position = Vector2.ZERO
	a._separate()
	var a_push: Vector2 = a.position
	a.position = Vector2.ZERO
	b._separate()
	var b_push: Vector2 = b.position
	# Guard non-zero pushes explicitly: a dot product with a zero vector is 0 (not
	# negative), so the opposite-direction check below can't on its own tell
	# "fanned apart" from "one push short-circuited to zero".
	assert_gt(a_push.length(), 0.0, "the first unit is pushed off the stack")
	assert_gt(b_push.length(), 0.0, "its partner is pushed too")
	assert_lt(a_push.dot(b_push), 0.0,
		"equal-uid co-located units fall back to the instance-id sign and fan apart")


# --- waypoints (issue #34) -------------------------------------------------

func test_unit_advances_to_next_waypoint_on_arrival() -> void:
	var u := _make_unit()
	u.position = Vector2(100, 100)
	u.move_target = Vector2(100, 100)   # already arrived (within the 5px threshold)
	u.has_move_target = true
	u.waypoints.append(Vector2(300, 100))
	u._think(0.016)
	assert_eq(u.move_target, Vector2(300, 100), "arriving pops the next waypoint into move_target")
	assert_true(u.waypoints.is_empty(), "the consumed waypoint leaves the queue")
	assert_true(u.has_move_target, "the unit keeps marching toward the new leg")


func test_unit_goes_idle_after_draining_waypoints() -> void:
	var u := _make_unit()
	u.position = Vector2(100, 100)
	u.move_target = Vector2(100, 100)   # arrived, with nothing queued behind it
	u.has_move_target = true
	u._think(0.016)
	assert_false(u.has_move_target, "with the route drained the unit drops its move target")
	assert_eq(u.state, Unit.State.IDLE, "and returns to idle")


func test_order_summary_reports_waypoint_count() -> void:
	var u := _make_unit()
	u.move_target = Vector2(420, -130)
	u.has_move_target = true
	u.waypoints.append(Vector2(500, 0))
	u.waypoints.append(Vector2(600, 0))
	assert_eq(
		u.order_summary(),
		"Moving to (420, -130) (+2 waypoints)",
		"the order summary notes how many waypoints remain"
	)


func test_order_summary_singular_waypoint() -> void:
	var u := _make_unit()
	u.move_target = Vector2(10, 20)
	u.has_move_target = true
	u.waypoints.append(Vector2(50, 50))
	assert_eq(
		u.order_summary(),
		"Moving to (10, 20) (+1 waypoint)",
		"a single remaining waypoint is reported in the singular"
	)


# --- ranged units (issue #37) ----------------------------------------------

func _archer() -> Unit:
	var u: Unit = Unit.new()
	u.is_ranged = true   # set before _ready() so the unit is configured as ranged
	add_child_autofree(u)
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


func test_archer_shoots_enemy_within_range() -> void:
	var archer := _archer()
	var enemy := _make_unit()
	enemy.team = 1
	# Derived from the constant so the test tracks RANGED_RANGE tuning: 40px inside
	# ranged range, comfortably beyond melee contact (~62px).
	enemy.position = Vector2(Unit.RANGED_RANGE - 40.0, 0)
	var before: int = enemy.soldiers
	archer._think(0.016)
	assert_eq(archer.state, Unit.State.FIGHTING, "an archer in range stands and fires")
	assert_eq(archer.position, Vector2.ZERO, "it shoots from where it stands, not closing in")
	assert_lt(enemy.soldiers, before, "the volley inflicts casualties")


func test_archer_advances_toward_enemy_beyond_range() -> void:
	var archer := _archer()
	var enemy := _make_unit()
	enemy.team = 1
	# Just beyond RANGED_RANGE but still inside DETECTION_RANGE, derived so the
	# test stays valid if either constant moves (asserts RANGED_RANGE < DETECTION_RANGE).
	enemy.position = Vector2(Unit.RANGED_RANGE + 20.0, 0)
	var before: int = enemy.soldiers
	archer._think(0.016)
	assert_gt(archer.position.x, 0.0, "an archer out of range advances to close the gap")
	assert_eq(enemy.soldiers, before, "no volley until the enemy is within range")


func test_archer_melees_when_enemy_in_contact() -> void:
	var archer := _archer()
	var enemy := _make_unit()
	enemy.team = 1
	# Inside melee contact (attack_range + both radii), derived so the test tracks
	# the contact-distance formula rather than a hard-coded ~62px.
	var contact: float = archer.attack_range + Unit.RADIUS + enemy.RADIUS
	enemy.position = Vector2(contact - 22.0, 0)
	var before: int = enemy.soldiers
	archer._think(0.016)
	assert_eq(archer.state, Unit.State.FIGHTING, "a cornered archer still fights in melee")
	assert_lt(enemy.soldiers, before, "and deals melee casualties")


# --- friendly pass-through (issue #5) --------------------------------------

func test_mover_passes_through_idle_friendly() -> void:
	var mover := _make_unit()
	var idle := _make_unit()
	mover.team = 0
	idle.team = 0
	mover.state = Unit.State.MOVING
	idle.state = Unit.State.IDLE
	mover.position = Vector2.ZERO
	idle.position = Vector2(10.0, 0.0)        # deep overlap (infantry floor 36)
	mover._separate()
	assert_almost_eq(mover.position.x, 0.0, 0.001,
		"a moving unit is not pushed off an idle friendly — it passes through")


func test_two_idle_friendlies_still_separate() -> void:
	var a := _make_unit()
	var b := _make_unit()
	a.team = 0
	b.team = 0
	a.state = Unit.State.IDLE
	b.state = Unit.State.IDLE
	a.position = Vector2.ZERO
	b.position = Vector2(10.0, 0.0)
	a._separate()
	assert_lt(a.position.x, 0.0, "two idle friendlies are solid and push apart")


func test_mover_does_not_pass_through_idle_enemy() -> void:
	var mover := _make_unit()
	var enemy := _make_unit()
	mover.team = 0
	enemy.team = 1
	mover.state = Unit.State.MOVING
	enemy.state = Unit.State.IDLE
	mover.position = Vector2.ZERO
	enemy.position = Vector2(10.0, 0.0)
	mover._separate()
	assert_lt(mover.position.x, 0.0, "an enemy is never exempt — the mover is blocked")


func test_idle_friendly_does_not_push_the_mover_either() -> void:
	# The exemption is symmetric: the idle unit's own _separate() must also leave
	# the passing mover untouched.
	var mover := _make_unit()
	var idle := _make_unit()
	mover.team = 0
	idle.team = 0
	mover.state = Unit.State.MOVING
	idle.state = Unit.State.IDLE
	mover.position = Vector2.ZERO
	idle.position = Vector2(10.0, 0.0)
	idle._separate()
	assert_almost_eq(idle.position.x, 10.0, 0.001,
		"idle does not push itself off the mover — the exemption fires from both sides")


func test_mover_does_not_pass_through_fighting_friendly() -> void:
	# Only IDLE friendlies are passed through; a FIGHTING friendly is solid.
	var mover := _make_unit()
	var fighter := _make_unit()
	mover.team = 0
	fighter.team = 0
	mover.state = Unit.State.MOVING
	fighter.state = Unit.State.FIGHTING
	mover.position = Vector2.ZERO
	fighter.position = Vector2(10.0, 0.0)
	mover._separate()
	assert_lt(mover.position.x, 0.0, "a moving unit cannot pass through a fighting friendly")


# --- hard blocking: spearmen stop cavalry (issue #8) -----------------------

func test_spearman_holds_line_against_enemy_cavalry() -> void:
	var spear := _spearman_unit()              # team 0
	var cav := _cavalry()
	cav.team = 1                          # enemy cavalry
	spear.position = Vector2.ZERO
	cav.position = Vector2(20.0, 0.0)     # overlapping (floor 20+24 = 44)
	spear._separate()
	assert_almost_eq(spear.position.x, 0.0, 0.001,
		"a spearman yields nothing to enemy cavalry — the line holds")


func test_enemy_cavalry_shoved_clear_of_spear_line() -> void:
	var spear := _spearman_unit()              # team 0
	var cav := _cavalry()
	cav.team = 1                          # enemy cavalry
	spear.position = Vector2.ZERO
	cav.position = Vector2(20.0, 0.0)
	cav._separate()
	assert_gt(cav.position.x, 20.0,
		"enemy cavalry takes the full push-out and is shoved clear of the spears")


func test_enemy_infantry_still_separates_softly_from_spearman() -> void:
	# Hard block is cavalry-specific: a spearman still splits separation 50/50
	# with enemy infantry, so it is displaced (not an immovable wall to everyone).
	var spear := _spearman_unit()              # team 0
	var inf := _make_unit()
	inf.team = 1                          # enemy infantry (not cavalry)
	spear.position = Vector2.ZERO
	inf.position = Vector2(20.0, 0.0)
	spear._separate()
	assert_lt(spear.position.x, 0.0,
		"a spearman is only a hard wall to cavalry — infantry shoves it normally")


# --- fatigue + line relief (issue #4) --------------------------------------

func test_fatigue_builds_while_fighting() -> void:
	var u := _make_unit()
	u.state = Unit.State.FIGHTING
	u.tick_fatigue(1.0)
	assert_almost_eq(u.fatigue, 8.0, 0.001, "a fighting unit accrues fatigue")


func test_fatigue_recovers_while_resting() -> void:
	var u := _make_unit()
	u.fatigue = 20.0
	u.state = Unit.State.IDLE
	u.tick_fatigue(1.0)
	assert_almost_eq(u.fatigue, 15.0, 0.001, "a resting unit recovers fatigue")


func test_fatigue_reduces_attack_factor() -> void:
	var u := _make_unit()
	u.fatigue = 0.0
	assert_almost_eq(u.fatigue_attack_factor(), 1.0, 0.001, "fresh = full attack")
	u.fatigue = 100.0
	assert_almost_eq(u.fatigue_attack_factor(), 0.6, 0.001, "spent = 60% attack")


func test_relief_swaps_the_fight_and_exempts_the_pair() -> void:
	var fresh := _make_unit()
	var tired := _make_unit()
	var foe := _make_unit()
	fresh.team = 0
	tired.team = 0
	foe.team = 1
	tired.target_enemy = foe
	fresh.begin_relief(tired)
	assert_eq(fresh.target_enemy, foe, "the reliever takes over the tired unit's fight")
	assert_null(tired.target_enemy, "the tired unit disengages")
	assert_true(tired.has_move_target, "the tired unit peels back to the rear")
	assert_true(fresh._separation_exempt(tired), "the swapping pair passes through")
	assert_true(tired._separation_exempt(fresh), "the relief exemption is mutual")


func test_relief_inherits_nearest_enemy_when_target_is_unset() -> void:
	# A unit can be FIGHTING an auto-acquired foe with target_enemy still null.
	var fresh := _make_unit()
	var tired := _make_unit()
	var foe := _make_unit()
	fresh.team = 0
	tired.team = 0
	foe.team = 1
	tired.position = Vector2.ZERO
	foe.position = Vector2(30.0, 0.0)   # within tired's detection range
	tired.target_enemy = null
	fresh.begin_relief(tired)
	assert_eq(fresh.target_enemy, foe,
		"the reliever inherits the tired unit's nearest enemy even when unset")


func test_relief_exemption_clears_when_partner_routs() -> void:
	var fresh := _make_unit()
	var tired := _make_unit()
	fresh.team = 0
	tired.team = 0
	fresh.position = Vector2.ZERO
	tired.position = Vector2(5.0, 0.0)   # still adjacent, so it's not "apart"
	fresh.begin_relief(tired)
	assert_true(fresh._separation_exempt(tired), "exempt during the swap")
	tired.state = Unit.State.ROUTING
	fresh._update_relief()
	assert_false(fresh._separation_exempt(tired),
		"a routed partner is no longer exempt — it gets shouldered again")


func test_relief_exemption_clears_once_pair_moves_apart() -> void:
	var fresh := _make_unit()
	var tired := _make_unit()
	fresh.team = 0
	tired.team = 0
	tired.position = Vector2.ZERO
	fresh.position = Vector2.ZERO
	fresh.begin_relief(tired)
	assert_true(fresh._separation_exempt(tired), "exempt while still overlapping")
	# Move the reliever well clear of the tired unit (past the clear distance).
	fresh.position = Vector2(fresh.separation_radius + tired.separation_radius + 50.0, 0.0)
	fresh._update_relief()
	assert_false(fresh._separation_exempt(tired),
		"the exemption ends once the swapping pair has moved apart")


# --- unit merging (issue #3) -----------------------------------------------

func test_merge_pools_soldiers_and_sums_max() -> void:
	var a := _make_unit(100)
	var b := _make_unit(60)
	a.absorb(b)
	assert_eq(a.soldiers, 160, "soldier counts are pooled")
	assert_eq(a.max_soldiers, 160, "max_soldiers are summed")


func test_merge_blends_attack_weighted_by_strength() -> void:
	var a := _make_unit(100)
	a.attack = 10
	var b := _make_unit(60)
	b.attack = 20
	a.absorb(b)
	# (10*100 + 20*60) / 160 = 13.75 -> 14
	assert_eq(a.attack, 14, "attack is strength-weighted between the two regiments")


func test_merge_starts_with_a_strangers_debuff() -> void:
	var a := _make_unit(100)
	var b := _make_unit(60)
	a.absorb(b)
	assert_lt(a.cohesion, 1.0, "a freshly merged unit starts below full cohesion")
	a.tick_cohesion(1.0)
	assert_almost_eq(a.cohesion, Unit.MERGE_COHESION_FLOOR + 0.1, 0.001,
		"cohesion ramps back toward full over time")


func test_absorbed_unit_is_removed_from_play() -> void:
	var a := _make_unit(100)
	var b := _make_unit(60)
	a.absorb(b)
	assert_eq(b.state, Unit.State.DEAD, "the absorbed unit leaves play")
	assert_false(b.is_in_group("units"), "the absorbed unit leaves the units group")


func test_merged_footprint_is_capped_below_melee_reach() -> void:
	# Repeated merges must not grow the footprint past the contact ceiling, or two
	# mega-units would shove apart beyond attack reach and never fight.
	var a := _cavalry()
	for _i in range(10):
		var b := _cavalry()
		a.absorb(b)
	assert_lte(a.separation_radius, Unit.SEPARATION_RADIUS_MAX,
		"footprint is clamped so merged units still reach melee contact")


func test_merge_blends_using_current_soldiers_not_max() -> void:
	# A depleted unit contributes its CURRENT strength to the weighted blend,
	# while max_soldiers still sums.
	var a := _make_unit(100)
	a.take_casualties(30, _attacker_at(FRONT))   # 100 -> 70 soldiers
	a.attack = 10
	var b := _make_unit(60)
	b.attack = 20
	a.absorb(b)
	assert_eq(a.max_soldiers, 160, "max_soldiers sum regardless of casualties")
	assert_eq(a.soldiers, 130, "pooled soldiers = 70 + 60")
	# Weighted by current strength: (10*70 + 20*60) / 130 = 14.6 -> 15.
	assert_eq(a.attack, 15, "attack weights by current soldiers, not max")


# --- rout timeout teardown (issue #61) -------------------------------------

func test_rout_timeout_leaves_groups_synchronously() -> void:
	var u := _make_unit()
	# An enemy in contact means the rout can't rally, so it SHATTERS at timeout (#68) —
	# the removal path that must still tear groups down synchronously (#61).
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(20, 0)   # well inside RALLY_CONTACT_RADIUS
	u._rout()
	assert_true(u.is_in_group("routers"), "a routing unit joins the routers group")
	assert_false(u.is_in_group("units"), "a routing unit has left the units group")
	# Expire the rout timer so the next call triggers the timeout.
	u._rout_timer = 0.0
	u._process_rout(0.016)
	assert_eq(u.state, Unit.State.DEAD, "a rout that can't rally shatters at timeout")
	# queue_free() is deferred to end of frame, but the group memberships must be
	# dropped synchronously so a DEAD unit never lingers in the spatial-hash /
	# separation scans (both of which include the routers group) for the rest of
	# the tick — see issue #61.
	assert_false(u.is_in_group("routers"),
		"a shattered unit leaves the routers group the same tick it dies")
	assert_false(u.is_in_group("units"),
		"a shattered unit is not in the units group either")


# --- rout recovery: rally vs shatter (issue #68) ---------------------------

func test_rout_rallies_after_breaking_contact() -> void:
	# No enemy nearby and plenty of men left: the rout times out into a RALLY, returning
	# the unit to play under the player's control at low (fragile) morale.
	var u := _make_unit()
	u._rout()
	u._rout_timer = 0.0
	u._process_rout(0.016)
	assert_eq(u.state, Unit.State.IDLE, "a unit that broke contact rallies, not dies")
	assert_true(u.is_in_group("units"), "a rallied unit rejoins the fightable units")
	assert_false(u.is_in_group("routers"), "and leaves the routers group")
	assert_almost_eq(u.morale, Unit.RALLY_MORALE, 0.001, "it reforms at low, fragile morale")


func test_rout_shatters_when_still_in_contact() -> void:
	var u := _make_unit()
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(30, 0)   # inside RALLY_CONTACT_RADIUS — still pursued
	u._rout()
	u._rout_timer = 0.0
	u._process_rout(0.016)
	assert_eq(u.state, Unit.State.DEAD, "a unit still in contact shatters")


func test_rout_shatters_when_gutted_even_if_clear() -> void:
	# Broke contact, but too few men remain to reform -> shatter.
	var u := _make_unit(100)
	u._rout()
	u.soldiers = 5   # below SHATTER_STRENGTH_FRAC * 100 (= 15)
	u._rout_timer = 0.0
	u._process_rout(0.016)
	assert_eq(u.state, Unit.State.DEAD, "a gutted rout shatters even with no enemy near")


# --- individual-soldier formation layout (issue #32, Stage A) ---------------

func test_formation_slots_one_per_soldier() -> void:
	var u := _make_unit(120)
	assert_eq(u._formation_slots(120).size(), 120, "one slot per living soldier")
	assert_eq(u._formation_slots(1).size(), 1, "a single soldier gets one slot")
	assert_eq(u._formation_slots(0).size(), 0, "no soldiers -> no slots (an empty block)")


func test_formation_block_is_centered() -> void:
	# A full block (50 = 10 files x 5 ranks) is centred on the unit origin.
	var u := _make_unit()
	var slots := u._formation_slots(50)
	var sum := Vector2.ZERO
	for s in slots:
		sum += s
	var mean: Vector2 = sum / float(slots.size())
	assert_almost_eq(mean.x, 0.0, 0.001, "block is centred horizontally on the unit")
	assert_almost_eq(mean.y, 0.0, 0.001, "and vertically")


func test_formation_is_wider_than_deep() -> void:
	# Soldiers form up wider than they are deep (files > ranks for a full block).
	var u := _make_unit()
	var slots := u._formation_slots(100)
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for s in slots:
		min_x = minf(min_x, s.x)
		max_x = maxf(max_x, s.x)
		min_y = minf(min_y, s.y)
		max_y = maxf(max_y, s.y)
	assert_gt(max_x - min_x, max_y - min_y, "the formation is wider than it is deep")


func test_can_rally_at_exactly_the_strength_floor() -> void:
	# Boundary: soldiers == floor(max * SHATTER_STRENGTH_FRAC) still rallies (the gate is
	# "< floor" → shatter, ">= floor" → can rally). Pins the >= semantics in the doc.
	var u := _make_unit(100)
	u._rout()
	u.soldiers = int(round(100 * Unit.SHATTER_STRENGTH_FRAC))   # exactly the floor (15)
	assert_true(u._can_rally(), "a unit exactly at the strength floor can still rally")
	u.soldiers -= 1
	assert_false(u._can_rally(), "one man below the floor shatters")


func test_can_rally_requires_broken_contact_and_strength() -> void:
	var u := _make_unit(100)
	u._rout()
	assert_true(u._can_rally(), "clear of enemies and at strength -> can rally")
	u.soldiers = 5
	assert_false(u._can_rally(), "gutted below the floor -> cannot rally")
	u.soldiers = 100
	var enemy := _make_unit()
	enemy.team = 1
	enemy.position = Vector2(40, 0)
	assert_false(u._can_rally(), "an enemy within contact radius -> cannot rally")
