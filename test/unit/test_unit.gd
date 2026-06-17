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
