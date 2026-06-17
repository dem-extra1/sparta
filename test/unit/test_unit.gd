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


# --- charge lifecycle (issue #29) ------------------------------------------

func test_consume_charge_spends_exactly_once() -> void:
	var u := _make_unit()
	u.is_cavalry = true   # charges are a cavalry mechanic
	assert_true(u.consume_charge(), "a fresh unit has a charge available")
	assert_false(u.consume_charge(), "the charge is spent after one consume")


func test_rearm_charge_restores_availability() -> void:
	var u := _make_unit()
	u.is_cavalry = true
	u.consume_charge()
	u.rearm_charge()
	assert_true(u.consume_charge(), "rearm makes a charge available again")


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
	assert_lt(a_push.dot(b_push), 0.0,
		"equal-uid co-located units fall back to the instance-id sign and fan apart")


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
