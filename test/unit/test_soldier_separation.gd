extends GutTest
## Phase 2 of individual-level collision (docs/individual-collision-design.md):
## the engaged-tier classification (with hysteresis), the deterministic
## same-set separation primitive, and the GLOBAL cross-regiment engaged-soldier
## pass. The layer is active (Unit.INDIVIDUAL_COLLISION on) but non-authoritative,
## so these exercise the functions directly with no Battle running.


func before_each() -> void:
	# The soldier hash is static global state; isolate each test.
	SoldierSpatialHash.reset()


func _make_unit(uid: int, max_soldiers: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.uid = uid
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
	return u


## An engaged regiment (FIGHTING, latched, seeded) for the global-pass tests.
func _engaged(uid: int, team: int, n: int = 1, cav: bool = false, anti_cav: bool = false) -> Unit:
	var u := _make_unit(uid, n)
	u.team = team
	u.is_cavalry = cav
	u.anti_cavalry = anti_cav
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)
	u.seed_sim_soldiers()
	return u


# --- separation primitive ------------------------------------------------

func test_overlapping_pair_is_pushed_to_exactly_min_dist() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(1, 0)])
	var ids := PackedInt32Array([0, 1])
	var out := Unit.separate_soldier_bodies(pts, ids, 3.4)
	assert_almost_eq(out[0].distance_to(out[1]), 3.4, 0.001,
		"an overlapping pair ends exactly at the separation floor")


func test_non_overlapping_pair_is_unchanged() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	var ids := PackedInt32Array([0, 1])
	var out := Unit.separate_soldier_bodies(pts, ids, 3.4)
	assert_eq(out, pts, "bodies already apart by more than the floor don't move")


func test_input_array_is_not_mutated() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(1, 0)])
	var before := pts.duplicate()
	Unit.separate_soldier_bodies(pts, PackedInt32Array([0, 1]), 3.4)
	assert_eq(pts, before, "the primitive is pure — it copies, it doesn't mutate its input")


func test_colocated_pair_fans_apart_deterministically() -> void:
	var pts := PackedVector2Array([Vector2(5, 5), Vector2(5, 5)])
	var ids := PackedInt32Array([10, 20])
	var a := Unit.separate_soldier_bodies(pts, ids, 3.4)
	var b := Unit.separate_soldier_bodies(pts, ids, 3.4)
	assert_eq(a, b, "co-located separation is deterministic (id-keyed, no RNG)")
	assert_almost_eq(a[0].distance_to(a[1]), 3.4, 0.001, "and lands at the separation floor")
	assert_true(a[0] != a[1], "the co-located pair actually separates")


# --- engaged-tier classification + hysteresis ----------------------------

func test_idle_regiment_has_no_engaged_soldiers() -> void:
	var u := _make_unit(0)
	assert_false(u.is_engaged(), "an idle regiment is not engaged")
	assert_eq(u.engaged_soldier_indices(u.soldiers).size(), 0,
		"so none of its soldiers run the full pass")


func test_fighting_regiment_engages_its_front_ranks() -> void:
	var u := _make_unit(0)
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)
	assert_true(u.is_engaged(), "a fighting regiment is engaged")
	var engaged := u.engaged_soldier_indices(u.soldiers)
	var expected: int = mini(u.soldiers, u._formation_files(u.soldiers) * Unit.ENGAGED_RANKS)
	assert_eq(engaged.size(), expected, "the front ENGAGED_RANKS ranks are engaged")
	assert_eq(engaged[0], 0, "engaged indices start at the front rank")
	assert_eq(engaged[engaged.size() - 1], expected - 1, "and run contiguously through the front ranks")


func test_engaged_tier_lingers_then_clears_after_fighting_stops() -> void:
	var u := _make_unit(0)
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)
	assert_true(u.is_engaged(), "engaged while fighting")
	# Stop fighting: the latch lingers (hysteresis) then clears.
	u.state = Unit.State.IDLE
	u.tick_engaged(Unit.ENGAGED_LINGER - 0.1)
	assert_true(u.is_engaged(), "stays engaged briefly after fighting stops")
	u.tick_engaged(0.2)
	assert_false(u.is_engaged(), "clears once the linger elapses")


# --- global engaged-soldier pass (cross-regiment) ------------------------

func test_cross_regiment_overlap_resolves_to_the_floor() -> void:
	var a := _engaged(0, 0)
	var b := _engaged(1, 1)
	a._sim_soldier_pos[0] = Vector2(100, 100)
	b._sim_soldier_pos[0] = Vector2(100, 100)   # coincident enemy front-rank soldiers
	Unit.separate_engaged_global([a, b], 1)
	assert_almost_eq(a._sim_soldier_pos[0].distance_to(b._sim_soldier_pos[0]),
		a.soldier_body_radius() + b.soldier_body_radius(), 0.001,
		"enemy soldiers from different regiments separate to the sum of their radii")


func test_spear_soldier_hard_blocks_a_cavalry_soldier() -> void:
	# Enemy spear vs cavalry: the spear holds firm (share 0), the horse is shoved
	# fully clear (share 1) — the regiment hard-block carried down per soldier.
	var spear := _engaged(0, 0, 1, false, true)
	var cav := _engaged(1, 1, 1, true, false)
	var held := Vector2(50, 50)
	spear._sim_soldier_pos[0] = held
	cav._sim_soldier_pos[0] = Vector2(50.5, 50)   # overlapping the spear
	Unit.separate_engaged_global([spear, cav], 2)
	assert_eq(spear._sim_soldier_pos[0], held, "the spear soldier does not yield")
	assert_almost_eq(spear._sim_soldier_pos[0].distance_to(cav._sim_soldier_pos[0]),
		spear.soldier_body_radius() + cav.soldier_body_radius(), 0.001,
		"and the cavalry soldier is shoved out to the floor on its own")


func test_mismatched_types_use_the_summed_radii_floor() -> void:
	var cav := _engaged(0, 0, 1, true, false)
	var inf := _engaged(1, 1, 1, false, false)
	cav._sim_soldier_pos[0] = Vector2.ZERO
	inf._sim_soldier_pos[0] = Vector2.ZERO
	Unit.separate_engaged_global([cav, inf], 3)
	assert_almost_eq(cav._sim_soldier_pos[0].distance_to(inf._sim_soldier_pos[0]),
		Unit.CAV_MARK_RADIUS + Unit.MARK_RADIUS, 0.001,
		"a cavalry + infantry pair separates to 2.6 + 1.7 = 4.3")


func test_allied_cross_regiment_pair_splits_evenly() -> void:
	var a := _engaged(0, 0)
	var b := _engaged(1, 0)   # same team
	a._sim_soldier_pos[0] = Vector2(0, 0)
	b._sim_soldier_pos[0] = Vector2(1, 0)
	Unit.separate_engaged_global([a, b], 4)
	assert_almost_eq(a._sim_soldier_pos[0].x + b._sim_soldier_pos[0].x, 1.0, 0.001,
		"allied soldiers split the push 50/50 — symmetric about their midpoint")
	assert_almost_eq(a._sim_soldier_pos[0].distance_to(b._sim_soldier_pos[0]),
		a.soldier_body_radius() + b.soldier_body_radius(), 0.001, "and reach the floor")


func test_intra_regiment_overlap_resolves_through_the_global_pass() -> void:
	var u := _engaged(0, 0, 4)   # several engaged front-rank soldiers
	u._sim_soldier_pos[0] = Vector2(10, 10)
	u._sim_soldier_pos[1] = Vector2(10, 10)
	Unit.separate_engaged_global([u], 5)
	assert_almost_eq(u._sim_soldier_pos[0].distance_to(u._sim_soldier_pos[1]),
		u.soldier_separation_min_dist(), 0.001,
		"same-regiment soldiers separate through the unified global pass too")


func test_unengaged_regiments_contribute_nothing() -> void:
	var u := _make_unit(0, 2)   # IDLE — not engaged
	u.seed_sim_soldiers()
	u._sim_soldier_pos[0] = Vector2(100, 100)
	u._sim_soldier_pos[1] = Vector2(100, 100)
	Unit.separate_engaged_global([u], 6)
	assert_eq(u._sim_soldier_pos[0], u._sim_soldier_pos[1],
		"an unengaged regiment contributes no soldiers to the global pass")


func test_global_pass_is_deterministic_and_order_independent() -> void:
	# Two identical configs; run the pass with the units in OPPOSITE array order.
	# The id-sorted gather + Jacobi accumulate-then-apply must give identical
	# results regardless of units[] order (the replay-determinism property).
	var a1 := _engaged(0, 0, 3); var b1 := _engaged(1, 1, 3)
	var a2 := _engaged(0, 0, 3); var b2 := _engaged(1, 1, 3)
	a1._sim_soldier_pos[0] = Vector2(5, 5); b1._sim_soldier_pos[0] = Vector2(5, 5)
	a2._sim_soldier_pos[0] = Vector2(5, 5); b2._sim_soldier_pos[0] = Vector2(5, 5)
	Unit.separate_engaged_global([a1, b1], 7)
	Unit.separate_engaged_global([b2, a2], 8)   # shuffled order, different frame
	assert_eq(a1._sim_soldier_pos, a2._sim_soldier_pos,
		"identical configs give identical results regardless of units[] order")
	assert_eq(b1._sim_soldier_pos, b2._sim_soldier_pos,
		"(the id-sorted gather removes any group-iteration-order dependence)")


func test_global_pass_perf_smoke_at_scale() -> void:
	# Stress: two opposing lines of regiments meeting at a contact face, spread
	# across a realistic frontage (not stacked) so cell density mirrors a real
	# clash. Asserts the per-tick cost fits the 60 Hz budget, and logs the mean so
	# the number is visible in review. Validates decisions 2-3 of the design doc
	# (the ~1-1.5k-engaged budget).
	var units: Array = []
	for r in range(12):
		var top := _engaged(r * 2, 0, 120)
		top.facing = Vector2.DOWN
		top.position = Vector2(150 + r * 110.0, 492)
		top.seed_sim_soldiers()   # re-seed at the line position/facing
		var bot := _engaged(r * 2 + 1, 1, 120)
		bot.facing = Vector2.UP
		bot.position = Vector2(150 + r * 110.0, 508)   # front ranks meet the top line
		bot.seed_sim_soldiers()
		units.append(top)
		units.append(bot)
	var engaged_total := 0
	for o in units:
		engaged_total += (o as Unit).engaged_soldier_indices((o as Unit)._sim_soldier_pos.size()).size()
	var iters := 20
	var t0 := Time.get_ticks_usec()
	for it in range(iters):
		SoldierSpatialHash.reset()
		Unit.separate_engaged_global(units, 1000 + it)
	var per_tick_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(iters)
	gut.p("[perf] global soldier pass: %d engaged bodies, %.3f ms/tick" % [engaged_total, per_tick_ms])
	assert_lt(per_tick_ms, 16.0,
		"the global engaged-soldier pass stays within the 60 Hz tick budget at scale")
