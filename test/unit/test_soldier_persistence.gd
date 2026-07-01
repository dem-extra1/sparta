extends GutTest
## Phase 4 (see docs/individual-collision-design.md): persistent soldier-body
## dynamics. No body teleports — every body springs toward its formation slot and
## integrates its own velocity, so a body shoved by the separation pass HOLDS the
## displacement and eases back. The unengaged bulk additionally feeds the unit's
## march velocity forward, so it tracks its moving slots with no lag instead of
## snapping. These pin: first-step seeding, the engaged spring (holds then recovers),
## the unengaged no-teleport easing, the marching feed-forward tracking, casualty
## trimming, and determinism. Still non-authoritative — combat/movement/morale are
## unchanged.

const DT: float = 1.0 / 60.0

func _make_unit(uid: int, n: int) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)            # _ready() sets soldiers = max_soldiers, joins groups
	u.uid = uid
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


## An engaged regiment: its front ranks run the persistent spring.
func _engaged_unit(uid: int, n: int) -> Unit:
	var u := _make_unit(uid, n)
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)              # latch is_engaged() true
	return u


## An idle regiment: not engaged, so every body snaps to its slot (phase-3 behaviour).
func _idle_unit(uid: int, n: int) -> Unit:
	return _make_unit(uid, n)        # state defaults to IDLE; never latched engaged


# --- first-step seeding -------------------------------------------------------

func test_first_step_seeds_bodies_on_their_slots() -> void:
	var u := _engaged_unit(1, 24)
	u.step_sim_soldiers(DT)
	assert_eq(u._sim_soldier_pos.size(), u.soldiers, "one body per soldier")
	assert_eq(u._sim_body_vel.size(), u.soldiers, "velocities are index-aligned")
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	# On the first step every body starts on its slot (no spring-in from the origin).
	for i in range(u.soldiers):
		assert_almost_eq(u._sim_soldier_pos[i].distance_to(slots[i]), 0.0, 0.01,
			"body %d seeds on its slot" % i)


# --- the engaged spring: hold, then recover -----------------------------------

func test_engaged_body_holds_then_springs_back() -> void:
	var u := _engaged_unit(2, 24)
	u.step_sim_soldiers(DT)
	var slot0: Vector2 = u.soldier_world_slots(u.soldiers)[0]
	u._sim_soldier_pos[0] = slot0 + Vector2(15.0, 0.0)   # shove the front body off its slot
	var d_start: float = u._sim_soldier_pos[0].distance_to(slot0)

	u.step_sim_soldiers(DT)
	var d_after: float = u._sim_soldier_pos[0].distance_to(slot0)
	assert_lt(d_after, d_start, "an engaged body springs back toward its slot")
	assert_gt(d_after, 0.0, "but it holds the displacement — it does not snap instantly")
	assert_gt(u._sim_body_vel[0].length(), 0.0, "the shove gives it a recovery velocity")


func test_engaged_body_eases_onto_its_slot_over_time() -> void:
	var u := _engaged_unit(3, 24)
	u.step_sim_soldiers(DT)
	var slot0: Vector2 = u.soldier_world_slots(u.soldiers)[0]
	u._sim_soldier_pos[0] = slot0 + Vector2(15.0, 0.0)
	for _i in range(180):            # ~3 seconds of the fixed tick
		u.step_sim_soldiers(DT)
	assert_almost_eq(u._sim_soldier_pos[0].distance_to(slot0), 0.0, 0.5,
		"the near-critically-damped spring settles the body onto its slot")


# --- the unengaged bulk eases, never teleports --------------------------------

func test_unengaged_body_eases_to_slot_without_teleporting() -> void:
	# An idle (unengaged) regiment carries no march velocity, so its bodies spring onto
	# their slots exactly like the engaged front rank: a shoved body recovers gradually
	# rather than snapping back in one step.
	var u := _idle_unit(4, 24)
	u.step_sim_soldiers(DT)
	var slot0: Vector2 = u.soldier_world_slots(u.soldiers)[0]
	u._sim_soldier_pos[0] = slot0 + Vector2(15.0, 0.0)
	var d_start: float = u._sim_soldier_pos[0].distance_to(slot0)

	u.step_sim_soldiers(DT)
	var d_after: float = u._sim_soldier_pos[0].distance_to(slot0)
	assert_lt(d_after, d_start, "the body moves back toward its slot")
	assert_gt(d_after, 0.0, "but holds the displacement — it does not teleport to the slot")
	assert_gt(u._sim_body_vel[0].length(), 0.0, "the shove leaves it with a recovery velocity")


func test_unengaged_body_settles_onto_its_slot_over_time() -> void:
	var u := _idle_unit(11, 24)
	u.step_sim_soldiers(DT)
	var slot0: Vector2 = u.soldier_world_slots(u.soldiers)[0]
	u._sim_soldier_pos[0] = slot0 + Vector2(15.0, 0.0)
	for _i in range(180):            # ~3 seconds of the fixed tick
		u.step_sim_soldiers(DT)
	assert_almost_eq(u._sim_soldier_pos[0].distance_to(slot0), 0.0, 0.5,
		"a still bulk body settles onto its slot")


# --- the marching bulk tracks its moving slots via feed-forward ---------------

func test_marching_bulk_tracks_its_moving_slot() -> void:
	# A marching (unengaged) regiment translates its formation slots at its march
	# velocity each tick. Feeding that velocity forward keeps a body locked onto its
	# moving slot — a plain spring with no feed-forward would lag a fixed distance
	# behind. The body starts on its slot; after the regiment marches for a while it is
	# still within a mark's width of its slot, and it never jumped there.
	var u := _idle_unit(12, 24)
	u.step_sim_soldiers(DT)            # seed bodies on their slots
	u.state = Unit.State.MOVING        # a real march is never IDLE -- exempts the jog cap
	var march: Vector2 = Vector2(0.0, 90.0)   # move_speed downfield
	for _i in range(120):             # ~2 seconds of marching
		u.position += march * DT
		u._approach_velocity = march  # what _move_to sets while the unit advances
		u.step_sim_soldiers(DT)
	var slot0: Vector2 = u.soldier_world_slots(u.soldiers)[0]
	assert_lt(u._sim_soldier_pos[0].distance_to(slot0), 2.0,
		"the feed-forward holds the marching body on its moving slot (no lag)")
	assert_almost_eq(u._sim_body_vel[0].y, march.y, 1.0,
		"and its velocity has converged onto the march velocity")


# --- casualties trim the body arrays ------------------------------------------

func test_casualty_trims_the_body_arrays() -> void:
	var u := _engaged_unit(5, 24)
	u.step_sim_soldiers(DT)
	assert_eq(u._sim_soldier_pos.size(), 24)
	u.soldiers = 20                  # four men fall
	u.step_sim_soldiers(DT)
	assert_eq(u._sim_soldier_pos.size(), 20, "the body array tracks the live count")
	assert_eq(u._sim_body_vel.size(), 20, "velocities track it too")


func test_growth_seeds_new_bodies_on_slots() -> void:
	# Defensive: if the count ever grows, the new tail bodies seed on their slots
	# at rest, never springing in from the array default (0, 0).
	var u := _engaged_unit(6, 12)
	u.step_sim_soldiers(DT)
	u.soldiers = 18
	u.step_sim_soldiers(DT)
	var slots: PackedVector2Array = u.soldier_world_slots(u.soldiers)
	for i in range(12, 18):
		assert_almost_eq(u._sim_soldier_pos[i].distance_to(slots[i]), 0.0, 0.01,
			"new body %d seeds on its slot" % i)


# --- determinism --------------------------------------------------------------

func test_step_is_deterministic() -> void:
	var a := _engaged_unit(7, 24)
	var b := _engaged_unit(7, 24)
	a.step_sim_soldiers(DT)
	b.step_sim_soldiers(DT)
	var slot0: Vector2 = a.soldier_world_slots(a.soldiers)[0]
	a._sim_soldier_pos[0] = slot0 + Vector2(15.0, 0.0)
	b._sim_soldier_pos[0] = slot0 + Vector2(15.0, 0.0)
	for _i in range(30):
		a.step_sim_soldiers(DT)
		b.step_sim_soldiers(DT)
	for i in range(a.soldiers):
		assert_almost_eq(a._sim_soldier_pos[i].x, b._sim_soldier_pos[i].x, 1e-6)
		assert_almost_eq(a._sim_soldier_pos[i].y, b._sim_soldier_pos[i].y, 1e-6)


# --- the static orchestrator --------------------------------------------------

func test_step_all_advances_every_regiment() -> void:
	var u1 := _engaged_unit(8, 12)
	var u2 := _engaged_unit(9, 12)
	Unit.step_all_sim_soldiers([u1, u2], DT)
	assert_eq(u1._sim_soldier_pos.size(), 12)
	assert_eq(u2._sim_soldier_pos.size(), 12)


func test_step_all_skips_dead_regiments() -> void:
	var dead := _engaged_unit(10, 12)
	dead.state = Unit.State.DEAD
	Unit.step_all_sim_soldiers([dead], DT)
	assert_eq(dead._sim_soldier_pos.size(), 0, "a dead regiment's bodies are not stepped")
