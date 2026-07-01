extends GutTest
## SoldierBodies.couple: the phase-5 soldier->regiment coupling that slides a regiment's
## center toward its soldiers' centroid at a bounded velocity (never a snap). Pins: it never
## teleports (the step is capped), it converges onto the body centroid without overshoot,
## and it is silent when the bodies already sit on their slots (so a clean march isn't
## double-counted). Also pins the jog-speed cap that SoldierBodies.step() applies to idle
## units so frontage reshaping and formation changes never snap or sprint.

const DELTA: float = 1.0 / 60.0


func _make_unit(n: int = 60) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	u.seed_sim_soldiers()   # bodies on their slots, at rest
	return u


func _drift(u: Unit) -> Vector2:
	# body centroid - slot centroid, the quantity couple() drives to zero.
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	var bc := Vector2.ZERO
	var sc := Vector2.ZERO
	for i in range(slots.size()):
		bc += u._sim_soldier_pos[i]
		sc += slots[i]
	return (bc - sc) / float(slots.size())


func test_couple_never_teleports() -> void:
	var u := _make_unit()
	# Shove every body far off formation, so the drift is huge.
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += Vector2(1000.0, 0.0)
	var before: Vector2 = u.position
	SoldierBodies.couple(u, DELTA)
	var moved: float = u.position.distance_to(before)
	assert_lt(moved, Unit.MAX_FOLLOW_SPEED * DELTA + 1e-4,
			"the center moves at most MAX_FOLLOW_SPEED*delta -- a bounded velocity, never a snap")
	assert_gt(moved, 0.0, "but it does follow the bodies")


func test_couple_converges_without_overshoot() -> void:
	var u := _make_unit()
	# Displace bodies by a modest, fully-recoverable amount and hold them there.
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += Vector2(8.0, 0.0)
	var prev: float = _drift(u).length()
	var start: float = prev
	for _step in range(120):
		SoldierBodies.couple(u, DELTA)
		var d: float = _drift(u).length()
		assert_lte(d, prev + 1e-5, "drift never grows -- no overshoot/oscillation")
		prev = d
	assert_lt(prev, start * 0.05, "the center converges onto the body centroid")


func test_couple_is_silent_on_formation() -> void:
	var u := _make_unit()
	# Bodies seeded exactly on their slots -> zero drift -> a clean march isn't deflected.
	var before: Vector2 = u.position
	SoldierBodies.couple(u, DELTA)
	assert_almost_eq(u.position.x, before.x, 1e-5, "no drift -> no follow (march-silent)")
	assert_almost_eq(u.position.y, before.y, 1e-5, "no drift -> no follow (march-silent)")


func test_couple_determinism() -> void:
	var a := _make_unit()
	var b := _make_unit()
	for i in range(a._sim_soldier_pos.size()):
		a._sim_soldier_pos[i] += Vector2(5.0, -3.0)
		b._sim_soldier_pos[i] += Vector2(5.0, -3.0)
	for _s in range(10):
		SoldierBodies.couple(a, DELTA)
		SoldierBodies.couple(b, DELTA)
	assert_almost_eq(a.position.x, b.position.x, 1e-6, "identical inputs -> identical follow")
	assert_almost_eq(a.position.y, b.position.y, 1e-6)


# --- integration: friendly regiments separate from the soldier layer ----------

func _block(uid: int, team: int, n: int, pos: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)
	u.uid = uid
	u.team = team
	u.facing = Vector2.DOWN
	u.state = Unit.State.IDLE
	u.position = pos
	u.seed_sim_soldiers()
	return u


## One full soldier sub-tick, exactly as Battle._on_soldier_tick sequences it.
func _soldier_tick(units: Array, frame: int) -> void:
	SoldierSteering.accumulate(units, frame)
	Unit.step_all_sim_soldiers(units, DELTA)
	Unit.couple_all_sim_soldiers(units, DELTA)


## The closest cross-regiment soldier distance (the worst overlap between two blocks).
func _min_cross(a: Unit, b: Unit) -> float:
	var m := INF
	for pa: Vector2 in a._sim_soldier_pos:
		for pb: Vector2 in b._sim_soldier_pos:
			m = minf(m, pa.distance_to(pb))
	return m


func test_friendly_regiments_separate_via_soldier_layer() -> void:
	# Two heavily-overlapping idle friendlies, with NO regiment-circle separation (it skips
	# friendlies now). Running the soldier sub-tick (steering -> bodies -> coupling) pushes
	# the interpenetrating soldiers apart and slides the centers off each other -- friendly
	# collision emerges entirely from the soldier layer.
	var a := _block(0, 0, 12, Vector2(0.0, 0.0))
	var b := _block(1, 0, 12, Vector2(4.0, 0.0))   # blocks heavily overlap
	var start_gap: float = a.position.distance_to(b.position)
	var start_cross: float = _min_cross(a, b)
	for f in range(200):
		_soldier_tick([a, b], f + 1)
	assert_gt(_min_cross(a, b), start_cross + 1.0,
			"the interpenetrating soldiers are pushed substantially apart")
	assert_gt(a.position.distance_to(b.position), start_gap + 1.0,
			"and the regiment centers slide off each other")
	assert_lt(a.position.x, b.position.x, "they fan apart along their offset, not through each other")


func test_soldier_layer_separation_is_deterministic() -> void:
	var a1 := _block(0, 0, 12, Vector2(0.0, 0.0))
	var b1 := _block(1, 0, 12, Vector2(4.0, 0.0))
	var a2 := _block(0, 0, 12, Vector2(0.0, 0.0))
	var b2 := _block(1, 0, 12, Vector2(4.0, 0.0))
	for f in range(80):
		_soldier_tick([a1, b1], f + 1)
		_soldier_tick([a2, b2], f + 1)
	assert_almost_eq(a1.position.x, a2.position.x, 1e-5, "identical runs separate identically (x)")
	assert_almost_eq(a1.position.y, a2.position.y, 1e-5, "identical runs separate identically (y)")
	assert_almost_eq(b1.position.x, b2.position.x, 1e-5, "and the partner too")


# --- jog-speed cap during idle reshape (frontage changes, centre pivots) ------

func test_idle_soldier_bodies_capped_at_jog_speed() -> void:
	# Displace bodies far from their slots (simulating a large frontage change).
	# SoldierBodies.step() must not let any soldier body exceed the unit's own
	# jog_speed in a single tick when the unit is IDLE — orderly reshape, no sprinting.
	var u := _make_unit()
	u.state = Unit.State.IDLE
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += Vector2(200.0, 0.0)   # far from slots
	SoldierBodies.step(u, DELTA)
	for i in range(u._sim_body_vel.size()):
		assert_lte(u._sim_body_vel[i].length(), u.jog_speed + 1e-4,
				"idle soldier speed is capped at jog_speed during reshape")


func test_moving_soldier_bodies_not_speed_capped() -> void:
	# A marching unit's bodies must be allowed to exceed jog_speed so they
	# keep up with moving slots. The jog cap must NOT apply when state == MOVING.
	var u := _make_unit()
	u.state = Unit.State.MOVING
	u._approach_velocity = Vector2(0.0, u.jog_speed)   # full jog already from march
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += Vector2(200.0, 0.0)   # large lateral offset adds to march speed
	SoldierBodies.step(u, DELTA)
	var any_above_cap := false
	for i in range(u._sim_body_vel.size()):
		# +1.0 slack: the spring yields ~403 u/s for a 200-unit offset, so any
		# value above jog_speed+1 confirms the cap is absent. 1e-4 would also work,
		# but 1.0 makes the intent ("well above, not barely above") more readable.
		if u._sim_body_vel[i].length() > u.jog_speed + 1.0:
			any_above_cap = true
	assert_true(any_above_cap, "marching bodies can exceed jog speed — no cap while MOVING")
