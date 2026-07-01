extends GutTest
## Engage/attack re-facing: a unit that engages an enemy roughly a quarter-turn (or more) off
## its current fronting must TURN IN PLACE gradually to bring its front to bear — not snap the
## facing (which rotates the slot grid 90° in one tick and surges the men). These pin the fix:
## a large re-face rotates over several ticks, the soldier bodies hold their positions while it
## turns, and the strike is withheld until the front comes to bear. A small correction still
## snaps and fights immediately, so close-quarters combat stays responsive; the standalone drill
## turns (conversio / quarter-turn) are untouched.

const SEED: int = 1234567


func before_each() -> void:
	Replay.rng.seed = SEED


func _unit(uid: int, team: int, pos: Vector2, face: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 40
	add_child_autofree(u)            # _ready() sets soldiers = max_soldiers, joins groups
	u.uid = uid
	u.team = team
	u.position = pos
	u.facing = face
	u.attack_range = 26.0
	u.seed_sim_soldiers()
	return u


func _bbox(ps: PackedVector2Array) -> Vector2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in ps:
		mn.x = minf(mn.x, p.x); mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x); mx.y = maxf(mx.y, p.y)
	return mx - mn


func _max_step(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var m := 0.0
	for i in range(mini(a.size(), b.size())):
		m = maxf(m, a[i].distance_to(b[i]))
	return m


# --- a large re-face turns gradually, not in one snap ------------------------

func test_large_reface_rotates_gradually() -> void:
	# Attacker faces RIGHT; the enemy sits directly BELOW it in melee contact — a ~90°
	# offset, well over the turn-in-place threshold.
	var a := _unit(1, 0, Vector2(0, 0), Vector2.RIGHT)
	var enemy := _unit(2, 1, Vector2(0, 40), Vector2.UP)
	assert_true(a.position.distance_to(enemy.position) <= a.attack_range + Unit.RADIUS + enemy.RADIUS,
		"the two are in melee contact")

	var start_offset: float = absf(angle_difference(a.facing.angle(), (enemy.position - a.position).angle()))
	assert_gt(start_offset, Unit.ENGAGE_TURN_THRESHOLD,
		"the engage offset starts beyond the turn-in-place threshold")

	# One think tick must NOT snap the facing onto the enemy.
	a._think(0.05)
	var after_one: float = absf(angle_difference(a.facing.angle(), (enemy.position - a.position).angle()))
	assert_gt(after_one, deg_to_rad(1.0),
		"a single tick does not snap the facing to the enemy (it turns gradually)")
	assert_lt(after_one, start_offset,
		"but the unit has begun turning toward the enemy")
	assert_true(a._engage_turn_target != Vector2.ZERO,
		"a turn-in-place is in progress")

	# Keep ticking: the unit eventually comes to bear on the enemy.
	for _i in range(60):
		a._think(0.05)
		if a._engage_turn_target == Vector2.ZERO:
			break
	var final_offset: float = absf(angle_difference(a.facing.angle(), (enemy.position - a.position).angle()))
	assert_lt(final_offset, deg_to_rad(2.0),
		"the unit finishes facing the enemy")
	assert_eq(a._engage_turn_target, Vector2.ZERO, "the turn has completed")


# --- the men hold their positions during the turn ----------------------------

func test_men_hold_positions_during_reface() -> void:
	var a := _unit(1, 0, Vector2(0, 0), Vector2.RIGHT)
	var _enemy := _unit(2, 1, Vector2(0, 40), Vector2.UP)

	var start_bbox: Vector2 = _bbox(a._sim_soldier_pos)
	var start_center: Vector2 = a.position
	var prev: PackedVector2Array = a._sim_soldier_pos.duplicate()
	var worst_step := 0.0
	var worst_bbox_drift := 0.0
	var center_drift_while_turning := 0.0
	var ticks_turning := 0
	# Measure only WHILE the turn is in progress: the men must hold their ground and the
	# regiment must not reposition as it pivots. (Once the front comes to bear the unit is
	# fighting and legitimately presses into contact — a separate, intended motion.)
	for _i in range(60):
		a._think(0.05)
		a.step_sim_soldiers(0.05)          # advance the persistent bodies, as the battle loop does
		# Count a tick as "turning" only if the turn is STILL in progress after the think —
		# the tick it completes, the unit is fighting and may press, which is a separate motion.
		var still_turning: bool = a._engage_turn_target != Vector2.ZERO
		if still_turning:
			ticks_turning += 1
			worst_step = maxf(worst_step, _max_step(prev, a._sim_soldier_pos))
			worst_bbox_drift = maxf(worst_bbox_drift, (_bbox(a._sim_soldier_pos) - start_bbox).length())
			center_drift_while_turning = maxf(center_drift_while_turning, a.position.distance_to(start_center))
		prev = a._sim_soldier_pos.duplicate()
		if not still_turning and _i > 0:
			break

	assert_gt(ticks_turning, 3, "the re-face genuinely spans several ticks (gradual, not a snap)")
	assert_lt(worst_step, 1.0,
		"no body jumps on any tick of the re-face (worst %.3f px)" % worst_step)
	assert_lt(worst_bbox_drift, 2.0,
		"the block keeps its footprint — no collapse/re-expand (worst drift %.3f px)" % worst_bbox_drift)
	assert_lt(center_drift_while_turning, 1.0,
		"the regiment turns in place — it does not reposition while pivoting")


# --- the strike is withheld until the front comes to bear --------------------

func test_strike_withheld_until_faced() -> void:
	var a := _unit(1, 0, Vector2(0, 0), Vector2.RIGHT)
	var enemy := _unit(2, 1, Vector2(0, 40), Vector2.UP)
	var start_soldiers: int = enemy.soldiers

	# First tick: still turning, way off — no casualties yet.
	a._think(0.05)
	assert_eq(enemy.soldiers, start_soldiers,
		"no blow lands while the unit is still turning to face the enemy")

	# Finish the turn; once faced, the strike lands (attack cooldown permitting).
	for _i in range(80):
		a._think(0.05)
		if enemy.soldiers < start_soldiers:
			break
	assert_lt(enemy.soldiers, start_soldiers,
		"once the front is brought to bear, the unit strikes")


# --- a small correction still snaps and fights now ---------------------------

func test_small_offset_snaps_and_fights() -> void:
	# Enemy nearly straight ahead: a tiny offset, under the threshold.
	var a := _unit(1, 0, Vector2(0, 0), Vector2.RIGHT)
	var enemy := _unit(2, 1, Vector2(40, 4), Vector2.LEFT)
	var start_soldiers: int = enemy.soldiers

	a._think(0.05)
	assert_eq(a._engage_turn_target, Vector2.ZERO,
		"a small offset does not start a turn-in-place")
	assert_lt(enemy.soldiers, start_soldiers,
		"a small correction snaps and the unit fights on the same tick")


# --- the turn state is cleared when the enemy vanishes mid-turn ---------------

func test_enemy_killed_mid_turn_clears_the_turn() -> void:
	# A large-offset engage starts a turn-in-place; the target is then removed while the
	# turn is still running. The unit must settle and clear the turn, or the soldier-body
	# spring stays frozen forever and the men are stuck in place.
	var a := _unit(1, 0, Vector2(0, 0), Vector2.RIGHT)
	var enemy := _unit(2, 1, Vector2(0, 40), Vector2.UP)

	a._think(0.05)   # begins the engage turn
	assert_true(a._engage_turn_target != Vector2.ZERO, "the turn is in progress")
	var partial_facing: Vector2 = a.facing   # it has turned part-way, not all the way
	assert_gt(absf(angle_difference(a.facing.angle(), Vector2.DOWN.angle())), deg_to_rad(2.0),
		"the turn has NOT completed yet (still mid-swing)")

	enemy._remove_from_play()   # target dies while the unit is still turning
	a._think(0.05)              # no enemy now: the unit goes idle and must settle the turn

	assert_eq(a._engage_turn_target, Vector2.ZERO,
		"the engage turn is cleared once the enemy is gone")
	assert_eq(a.state, Unit.State.IDLE, "the unit goes idle with no enemy")
	# The partial rotation is preserved (facing did not snap back); it was folded into
	# _formation_angle by the settle, so the bodies won't surge when the spring re-enables.
	assert_true(a.facing.is_equal_approx(partial_facing),
		"the partial turn is preserved — facing stays where the interrupted turn left it")

	# The spring is no longer frozen. A clean settle folded the rotation into
	# _formation_angle, so the slots already match the men (zero error, no surge). To prove
	# the restoring force is live again, nudge one body off its slot and confirm it springs
	# back — while the turn was frozen the restoring force was zeroed and it would not.
	var slots: PackedVector2Array = a.soldier_world_slots(a.soldiers)
	a._sim_soldier_pos[0] = slots[0] + Vector2(20.0, 0.0)   # displace one man 20 px off-slot
	var err_before: float = a._sim_soldier_pos[0].distance_to(slots[0])
	for _i in range(20):
		a.step_sim_soldiers(0.05)
	var err_after: float = a._sim_soldier_pos[0].distance_to(a.soldier_world_slots(a.soldiers)[0])
	assert_lt(err_after, err_before,
		"with the turn cleared the restoring force is live again — a displaced body springs back")


func test_enemy_leaves_range_mid_turn_settles_the_turn() -> void:
	# The enemy breaks contact (still alive and targeted) while the unit is mid-turn: the
	# unit chases via _move_to, so the frozen spring must release or the marching bodies
	# can't keep up. The turn is settled and resumes on the next contact.
	var a := _unit(1, 0, Vector2(0, 0), Vector2.RIGHT)
	var enemy := _unit(2, 1, Vector2(0, 40), Vector2.UP)

	a._think(0.05)   # begins the engage turn (in contact, large offset)
	assert_true(a._engage_turn_target != Vector2.ZERO, "the turn is in progress")

	enemy.position = Vector2(0, 400)   # break contact — far out of melee reach
	a._think(0.05)                     # the unit chases; the turn must settle

	assert_eq(a._engage_turn_target, Vector2.ZERO,
		"the engage turn is settled when the enemy breaks contact and the unit chases")


# --- the same dangling-turn cleanup applies in the support stance -------------

func test_support_threat_killed_mid_turn_clears_the_turn() -> void:
	# A supporting unit engages a threat near its ward with a large-offset re-face, then the
	# threat vanishes mid-turn. The support tick has its own combat exits (chase / shadow /
	# idle) that must settle the dangling turn too, or the body spring stays frozen forever.
	var a := _unit(1, 0, Vector2(0, 0), Vector2.RIGHT)
	var ward := _unit(3, 0, Vector2(60, 0), Vector2.RIGHT)   # friendly ward this unit guards
	var threat := _unit(2, 1, Vector2(0, 40), Vector2.UP)    # in contact, a quarter-turn off
	a.order_mode = Unit.ORDER_SUPPORT
	a.support_target = ward

	a._think(0.05)   # support tick engages the threat and begins the re-face turn
	assert_true(a._engage_turn_target != Vector2.ZERO, "the support re-face turn is in progress")

	threat._remove_from_play()   # the guarded threat dies while the unit is still turning
	a._think(0.05)               # no threat: the supporter shadows/idles and must settle

	assert_eq(a._engage_turn_target, Vector2.ZERO,
		"the engage turn is cleared in the support stance once the threat is gone")
