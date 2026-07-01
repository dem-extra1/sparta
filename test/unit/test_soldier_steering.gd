extends GutTest
## SoldierSteering: the no-teleport friendly-avoidance pass that replaced the global
## separation pass. It writes a per-soldier velocity bias into each unit's `_sim_steer`
## (which SoldierBodies feeds forward) instead of position-correcting bodies. These pin:
## friendly overlap steers the pair apart, clear pairs don't steer, ENEMIES don't steer
## (knockback handles them), deeper overlap steers harder, the co-located tie-break is
## deterministic, and the whole pass is order-independent / replay-safe.

const MIN_DIST_FOOT: float = 2.0 * Unit.MARK_RADIUS   # the foot-vs-foot body floor


func before_each() -> void:
	# The soldier hash is static global state; isolate each test.
	SoldierSpatialHash.reset()


func _make_unit(uid: int, n: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.uid = uid
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


## An engaged (FIGHTING, latched, seeded) one-soldier regiment on `team`, so the steering
## pass picks up its single soldier. The caller then places `_sim_soldier_pos[0]`.
func _engaged(uid: int, team: int) -> Unit:
	var u := _make_unit(uid, 1)
	u.team = team
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)
	u.seed_sim_soldiers()
	return u


# --- friendly avoidance -------------------------------------------------------

func test_overlapping_friendlies_steer_apart() -> void:
	var a := _engaged(0, 0)
	var b := _engaged(1, 0)            # same team
	a._sim_soldier_pos[0] = Vector2(0.0, 0.0)
	b._sim_soldier_pos[0] = Vector2(1.0, 0.0)   # 1.0 apart, inside the MIN_DIST_FOOT floor
	SoldierSteering.accumulate([a, b], 1)
	assert_lt(a._sim_steer[0].x, 0.0, "the left soldier steers further left, away from its neighbour")
	assert_gt(b._sim_steer[0].x, 0.0, "the right soldier steers further right")
	assert_almost_eq(a._sim_steer[0].x, -b._sim_steer[0].x, 1e-4,
		"a symmetric friendly pair steers equal-and-opposite")
	assert_almost_eq(a._sim_steer[0].y, 0.0, 1e-4, "no lateral component for a head-on pair")


func test_clear_friendlies_do_not_steer() -> void:
	var a := _engaged(0, 0)
	var b := _engaged(1, 0)
	a._sim_soldier_pos[0] = Vector2(0.0, 0.0)
	b._sim_soldier_pos[0] = Vector2(20.0, 0.0)   # well beyond the floor
	SoldierSteering.accumulate([a, b], 1)
	assert_almost_eq(a._sim_steer[0].length(), 0.0, 1e-4, "soldiers already clear don't steer")
	assert_almost_eq(b._sim_steer[0].length(), 0.0, 1e-4, "neither side")


func test_deeper_overlap_steers_harder() -> void:
	var a := _engaged(0, 0)
	var b := _engaged(1, 0)
	a._sim_soldier_pos[0] = Vector2(0.0, 0.0)
	b._sim_soldier_pos[0] = Vector2(2.0, 0.0)
	SoldierSteering.accumulate([a, b], 1)
	var shallow: float = a._sim_steer[0].length()

	SoldierSpatialHash.reset()
	var c := _engaged(2, 0)
	var d := _engaged(3, 0)
	c._sim_soldier_pos[0] = Vector2(0.0, 0.0)
	d._sim_soldier_pos[0] = Vector2(0.5, 0.0)   # much deeper overlap
	SoldierSteering.accumulate([c, d], 2)
	assert_gt(c._sim_steer[0].length(), shallow, "a deeper overlap produces a stronger steer")


# --- enemies are left to knockback --------------------------------------------

func test_enemies_do_not_steer() -> void:
	var a := _engaged(0, 0)
	var b := _engaged(1, 1)            # opposing team
	a._sim_soldier_pos[0] = Vector2(0.0, 0.0)
	b._sim_soldier_pos[0] = Vector2(1.0, 0.0)   # overlapping enemy front-rankers
	SoldierSteering.accumulate([a, b], 1)
	assert_almost_eq(a._sim_steer[0].length(), 0.0, 1e-4,
		"enemy overlap is resolved by combat knockback, not steering")
	assert_almost_eq(b._sim_steer[0].length(), 0.0, 1e-4, "neither side steers off an enemy")


# --- determinism --------------------------------------------------------------

func test_colocated_friendlies_fan_apart_deterministically() -> void:
	var a := _engaged(0, 0)
	var b := _engaged(1, 0)
	a._sim_soldier_pos[0] = Vector2(5.0, 5.0)
	b._sim_soldier_pos[0] = Vector2(5.0, 5.0)   # exactly coincident
	SoldierSteering.accumulate([a, b], 1)
	var steer_a: Vector2 = a._sim_steer[0]
	assert_gt(steer_a.length(), 0.0, "co-located friendlies still fan apart")
	assert_almost_eq(steer_a.x, -b._sim_steer[0].x, 1e-4, "equal and opposite")
	assert_almost_eq(steer_a.y, -b._sim_steer[0].y, 1e-4)

	# Re-run from scratch: the id-keyed tie-break is deterministic (no RNG).
	SoldierSpatialHash.reset()
	var c := _engaged(0, 0)
	var d := _engaged(1, 0)
	c._sim_soldier_pos[0] = Vector2(5.0, 5.0)
	d._sim_soldier_pos[0] = Vector2(5.0, 5.0)
	SoldierSteering.accumulate([c, d], 1)
	assert_almost_eq(c._sim_steer[0].x, steer_a.x, 1e-6, "same inputs -> same fan-out, every run")
	assert_almost_eq(c._sim_steer[0].y, steer_a.y, 1e-6)


func test_steering_is_order_independent() -> void:
	var a1 := _engaged(0, 0)
	var b1 := _engaged(1, 0)
	a1._sim_soldier_pos[0] = Vector2(0.0, 0.0)
	b1._sim_soldier_pos[0] = Vector2(1.5, 0.0)
	SoldierSteering.accumulate([a1, b1], 1)

	SoldierSpatialHash.reset()
	var a2 := _engaged(0, 0)
	var b2 := _engaged(1, 0)
	a2._sim_soldier_pos[0] = Vector2(0.0, 0.0)
	b2._sim_soldier_pos[0] = Vector2(1.5, 0.0)
	SoldierSteering.accumulate([b2, a2], 2)   # shuffled unit order, different frame

	assert_almost_eq(a1._sim_steer[0].x, a2._sim_steer[0].x, 1e-6,
		"the pass sorts by uid, so unit order and frame don't change the result")
	assert_almost_eq(a1._sim_steer[0].y, a2._sim_steer[0].y, 1e-6)


# --- friendly-contact tier (phase 5): non-engaged overlapping friendlies ------

## An IDLE (not engaged), seeded one-soldier regiment on `team`, co-located center so the
## regiment broadphase flags an overlap with another at the origin.
func _idle_block(uid: int, team: int) -> Unit:
	var u := _make_unit(uid, 1)
	u.team = team
	u.state = Unit.State.IDLE
	u.seed_sim_soldiers()
	return u


func test_overlapping_idle_friendlies_steer_apart() -> void:
	# Neither is fighting, but their blocks overlap, so the friendly-contact tier picks
	# them up and they steer apart -- the regiment circle no longer does this.
	var a := _idle_block(0, 0)
	var b := _idle_block(1, 0)
	a._sim_soldier_pos[0] = Vector2(0.0, 0.0)
	b._sim_soldier_pos[0] = Vector2(1.0, 0.0)
	SoldierSteering.accumulate([a, b], 1)
	assert_lt(a._sim_steer[0].x, 0.0, "the idle left body steers away even though neither side is engaged")
	assert_gt(b._sim_steer[0].x, 0.0, "and the idle right body steers the other way")


func test_mover_through_idle_friendly_is_exempt() -> void:
	# A moving regiment passing through an idle friendly is exempt -- no steer (the
	# move-through-idle exemption, re-homed from _separate to the steering pass).
	var mover := _idle_block(0, 0)
	mover.state = Unit.State.MOVING
	var idle := _idle_block(1, 0)
	mover._sim_soldier_pos[0] = Vector2(0.0, 0.0)
	idle._sim_soldier_pos[0] = Vector2(1.0, 0.0)
	SoldierSteering.accumulate([mover, idle], 1)
	assert_almost_eq(mover._sim_steer[0].length(), 0.0, 1e-4, "the mover passes cleanly through the idle friendly")
	assert_almost_eq(idle._sim_steer[0].length(), 0.0, 1e-4, "and the idle friendly doesn't shove the mover")


func test_engaged_friendly_holds_and_newcomer_yields() -> void:
	# Engaged-anchor asymmetry: a fighting regiment holds its ground (zero steer) and the
	# arriving friendly yields fully, flowing around it.
	var fighter := _engaged(0, 0)
	var newcomer := _idle_block(1, 0)
	fighter._sim_soldier_pos[0] = Vector2(0.0, 0.0)
	newcomer._sim_soldier_pos[0] = Vector2(1.0, 0.0)
	SoldierSteering.accumulate([fighter, newcomer], 1)
	assert_almost_eq(fighter._sim_steer[0].length(), 0.0, 1e-4, "the fighting regiment holds the line")
	assert_gt(newcomer._sim_steer[0].length(), 0.0, "the newcomer yields fully and flows around it")
