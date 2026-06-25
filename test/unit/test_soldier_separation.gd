extends GutTest
## Phase 2 of individual-level collision (docs/individual-collision-design.md):
## the engaged-tier classification (with hysteresis) and the deterministic
## soldier-level separation primitive. Still gated behind
## Unit.INDIVIDUAL_COLLISION, so these exercise the functions directly.


func _make_unit(uid: int, max_soldiers: int = 120) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = max_soldiers
	add_child_autofree(u)   # _ready() sets soldiers = max_soldiers and joins groups
	u.uid = uid
	u.facing = Vector2.DOWN
	u.position = Vector2.ZERO
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


# --- wired pass (still flag-gated) ---------------------------------------

func test_separate_engaged_soldiers_resolves_an_injected_overlap() -> void:
	var u := _make_unit(0)
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)
	u.seed_sim_soldiers()
	# Force two engaged front-rank soldiers to coincide, then resolve.
	u._sim_soldier_pos[0] = Vector2(100, 100)
	u._sim_soldier_pos[1] = Vector2(100, 100)
	u.separate_engaged_soldiers()
	assert_almost_eq(u._sim_soldier_pos[0].distance_to(u._sim_soldier_pos[1]),
		u.soldier_separation_min_dist(), 0.001,
		"the engaged pass pushes overlapping front-rank soldiers to the floor")


func test_separate_engaged_soldiers_is_a_noop_when_not_engaged() -> void:
	var u := _make_unit(0)   # IDLE — not engaged
	u.seed_sim_soldiers()
	u._sim_soldier_pos[0] = Vector2(100, 100)
	u._sim_soldier_pos[1] = Vector2(100, 100)
	u.separate_engaged_soldiers()
	assert_eq(u._sim_soldier_pos[0], u._sim_soldier_pos[1],
		"an unengaged regiment runs no per-soldier separation")
