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
	# Bodies now separate under bounded arrival/steering acceleration rather than an instant
	# velocity snap, so give the sub-tick more frames to push the blocks apart. As the blocks
	# slide past each other the two closest soldiers stay near contact, so the dominant
	# separation signal is the centres sliding off (a large gap growth); the min cross-distance
	# grows more modestly.
	for f in range(1200):
		_soldier_tick([a, b], f + 1)
	assert_gt(_min_cross(a, b), start_cross + 0.5,
			"the interpenetrating soldiers are pushed apart")
	assert_gt(a.position.distance_to(b.position), start_gap + 2.0,
			"and the regiment centers slide substantially off each other")
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
	# Displace bodies far from their slots (simulating a large frontage change) and let the
	# bounded arrival ramp their speed up over many ticks. SoldierBodies.step() must never
	# let any soldier body exceed the unit's own jog_speed when the unit is IDLE — orderly
	# reshape, no sprinting.
	var u := _make_unit()
	u.state = Unit.State.IDLE
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += Vector2(200.0, 0.0)   # far from slots
	for _s in range(240):   # ~4 s: long enough for arrival to reach top speed
		SoldierBodies.step(u, DELTA)
		for i in range(u._sim_body_vel.size()):
			assert_lte(u._sim_body_vel[i].length(), u.jog_speed + 1e-4,
					"idle soldier speed is capped at jog_speed during reshape")


func test_moving_soldier_bodies_not_speed_capped() -> void:
	# A marching unit's bodies must be allowed to exceed jog_speed so they keep up with
	# moving slots: the march feed-forward is already at full jog, and the arrival term
	# toward a far lateral slot stacks on top of it. The jog cap must NOT apply when
	# state == MOVING, so the combined speed can exceed jog. Ramp over several ticks so
	# the bounded arrival builds the lateral component up.
	var u := _make_unit()
	u.state = Unit.State.MOVING
	var march := Vector2(0.0, u.jog_speed)             # full jog already from march
	u._approach_velocity = march
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += Vector2(200.0, 0.0)   # large lateral offset adds to march speed
	var any_above_cap := false
	for _s in range(240):   # ~4 s: let the bounded arrival ramp the lateral term well in
		u.position += march * DELTA                    # slots translate with the march...
		u._approach_velocity = march                   # ...and the feed-forward tracks it
		SoldierBodies.step(u, DELTA)
		for i in range(u._sim_body_vel.size()):
			# march (jog) downfield + lateral arrival (up to jog) toward the slot combine
			# to well above jog overall, which a capped body could never reach.
			if u._sim_body_vel[i].length() > u.jog_speed + 1.0:
				any_above_cap = true
	assert_true(any_above_cap, "marching bodies can exceed jog speed — no cap while MOVING")


# --- backward-walk speed cap during a maneuver --------------------------------

## Set up an idle unit whose bodies are displaced so arrival pulls every body ALONG the
## given displacement direction, ramp for enough ticks to reach the capped top speed, and
## return the peak body speed along the direction of travel (component of velocity toward
## the slot) seen across the run. The displacement is far enough that the arrival term is
## jog-capped, so the steady-state speed is set by whichever cap applies (forward jog vs.
## backward jog*fraction), not by the arrival's decel taper.
func _peak_speed_along_travel(u: Unit, displace: Vector2) -> float:
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += displace
	var travel: Vector2 = (-displace).normalized()   # slot is opposite the displacement
	var peak := 0.0
	for _s in range(240):   # ~4 s: ramp the bounded arrival up to the capped top speed
		SoldierBodies.step(u, DELTA)
		for i in range(u._sim_body_vel.size()):
			peak = maxf(peak, u._sim_body_vel[i].dot(travel))
	return peak


func test_backward_moving_body_capped_slower_than_forward() -> void:
	# facing = DOWN. A body whose slot lies BEHIND it (above, -y) must back up against
	# its facing, and the cap slows that to jog_speed * back_speed_fraction. A body whose
	# slot lies AHEAD (below, +y) steps forward and keeps the full jog cap. Same offset
	# magnitude both ways, so the arrival force is identical -- only the cap differs.
	var back_u := _make_unit()
	back_u.state = Unit.State.IDLE
	# Displace bodies DOWN so their slots sit behind (above) them -> they back up.
	var back_peak: float = _peak_speed_along_travel(back_u, Vector2(0.0, 200.0))

	var fwd_u := _make_unit()
	fwd_u.state = Unit.State.IDLE
	# Displace bodies UP so their slots sit ahead (below) them -> they step forward.
	var fwd_peak: float = _peak_speed_along_travel(fwd_u, Vector2(0.0, -200.0))

	assert_almost_eq(fwd_peak, fwd_u.jog_speed, 1e-3,
			"a body stepping forward is capped at the full jog speed")
	assert_almost_eq(back_peak, back_u.jog_speed * back_u.back_speed_fraction, 1e-3,
			"a body backing up is capped to the slower backward pace")
	assert_lt(back_peak, fwd_peak - 1.0,
			"backward motion is meaningfully slower than forward motion")


func test_sideways_body_keeps_full_jog_cap() -> void:
	# facing = DOWN. A body displaced purely sideways (x) moves perpendicular to its
	# facing -- neither forward nor backward -- so it keeps the full jog cap, unslowed.
	var u := _make_unit()
	u.state = Unit.State.IDLE
	var peak: float = _peak_speed_along_travel(u, Vector2(200.0, 0.0))
	assert_almost_eq(peak, u.jog_speed, 1e-3,
			"purely sideways motion keeps the full jog cap (no backward penalty)")


func test_diagonal_backward_body_stays_within_jog_cap() -> void:
	# facing = DOWN. A body whose slot lies behind-and-to-the-side must back up AND sidestep
	# at once, so the arrival produces a velocity with both a backward and a sideways
	# component. Capping the two axes independently could let the combined speed exceed jog;
	# the final limit_length keeps total speed within the jog ceiling, while the backward
	# axis is still slowed so the body isn't simply running at full jog.
	var u := _make_unit()
	u.state = Unit.State.IDLE
	# Displace bodies DOWN-and-RIGHT so their slots sit behind-and-left -> back up + sidestep.
	for i in range(u._sim_soldier_pos.size()):
		u._sim_soldier_pos[i] += Vector2(200.0, 200.0)
	var facing := Vector2.DOWN
	# Ramp the bounded arrival up to its capped top speed over several ticks, checking the
	# cap holds every tick (not just after one step, where the body has barely accelerated).
	for _s in range(120):
		SoldierBodies.step(u, DELTA)
		for i in range(u._sim_body_vel.size()):
			var v: Vector2 = u._sim_body_vel[i]
			assert_lte(v.length(), u.jog_speed + 1e-3,
					"a diagonal backward-and-sideways body stays within the jog ceiling")
			# The backward (against-facing) axis is capped to the slower pace, so the body's
			# reverse speed can't reach the full jog even though it's also sliding sideways.
			var back_speed: float = -v.dot(facing)   # positive = backing up
			assert_lte(back_speed, u.jog_speed * u.back_speed_fraction + 1e-3,
					"and its backward-axis speed is still capped to the slower backward pace")


func test_backward_cap_is_deterministic() -> void:
	var a := _make_unit()
	a.state = Unit.State.IDLE
	var b := _make_unit()
	b.state = Unit.State.IDLE
	var pa: float = _peak_speed_along_travel(a, Vector2(0.0, 200.0))
	var pb: float = _peak_speed_along_travel(b, Vector2(0.0, 200.0))
	assert_almost_eq(pa, pb, 1e-9, "identical setups cap identically -- replay-safe")
