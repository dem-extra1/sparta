extends GutTest
## Formation-grid operations (#367): the pure layout primitives a maneuver reshapes a
## block with -- the general centred grid (block_slots), the rank count, and the
## transpose / widen / narrow file-count helpers. All pure functions of (n, files,
## spacing), so they're directly unit-testable and replay-safe; a maneuver layers the
## body relabel (which soldier takes which slot) on top.


func _centroid(slots: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for s in slots:
		c += s
	return c / float(slots.size()) if slots.size() > 0 else Vector2.ZERO


# --- block_slots ------------------------------------------------------------

func test_block_slots_has_one_slot_per_soldier() -> void:
	assert_eq(UnitFormation.block_slots(40, 8, 3.4).size(), 40, "one slot per soldier")


func test_block_slots_is_centred_on_the_origin() -> void:
	# A full grid is symmetric about the unit centre, so its centroid is ~0.
	var c := _centroid(UnitFormation.block_slots(40, 8, 3.4))
	assert_almost_eq(c.x, 0.0, 0.001, "centred on X")
	assert_almost_eq(c.y, 0.0, 0.001, "centred on Y")


func test_block_slots_front_rank_is_toward_negative_y() -> void:
	# The first `files` slots are the front rank; it sits at the most-negative Y (forward).
	var slots := UnitFormation.block_slots(40, 8, 3.4)
	var front_y: float = slots[0].y
	var back_y: float = slots[39].y
	assert_lt(front_y, back_y, "the front rank is ahead (-Y) of the rear rank")


func test_block_slots_spacing_scales_the_grid() -> void:
	var slots := UnitFormation.block_slots(40, 8, 5.0)
	# Adjacent files in the front rank are exactly `spacing` apart.
	assert_almost_eq(slots[0].distance_to(slots[1]), 5.0, 0.001, "files are one spacing apart")


func test_block_slots_partial_last_rank_stays_laterally_centred() -> void:
	# 10 soldiers, 4 files -> ranks of 4, 4, 2. Each rank is centred on its own count, so the
	# short last rank doesn't pull the block sideways: the X-centroid stays on the origin.
	# (The Y-centroid sits slightly forward of centre because the rear rank is short -- that's
	# a depth effect, not a lateral lean, so only X is asserted here.)
	var c := _centroid(UnitFormation.block_slots(10, 4, 3.4))
	assert_almost_eq(c.x, 0.0, 0.02, "a partial last rank doesn't pull the block off centre laterally")


func test_block_slots_partial_rear_rank_closes_toward_the_centre() -> void:
	# The short rear rank fills the CENTRE files first -- the wings close in toward the
	# standard while the centre files stay deepest. 10 in 4 files -> ranks 4, 4, 2; the 2-man
	# rear rank sits on the inner columns (+/- half a spacing), never spread out to the wings
	# (which for a full rank would be +/- 1.5 spacings). This is the file-closing behaviour:
	# survivors cluster centrally rather than leaving a ragged gap-toothed rear rank.
	var slots := UnitFormation.block_slots(10, 4, 4.0)
	for i in range(8, 10):
		assert_almost_eq(absf(slots[i].x), 2.0, 0.001,
			"rear-rank survivor %d closes onto an INNER file, not a wing" % i)


func test_block_slots_rear_rank_never_wider_than_a_full_rank() -> void:
	# However the rear rank thins, its survivors stay within the block's full frontage -- the
	# line never bulges sideways as it closes up. Check across a spread of partial counts.
	var full := UnitFormation.block_slots(24, 6, 3.0)          # 6 x 4, full
	var edge: float = absf(full[0].x)                          # a full rank's outermost |x|
	for n in [19, 20, 21, 22, 23]:                             # assorted partial rear ranks
		for s in UnitFormation.block_slots(n, 6, 3.0):
			assert_true(absf(s.x) <= edge + 0.001,
				"n=%d: no slot sits outside the full frontage as the block closes" % n)


func test_block_slots_empty_for_nonpositive_inputs() -> void:
	assert_eq(UnitFormation.block_slots(0, 8, 3.4).size(), 0, "no soldiers -> no slots")
	assert_eq(UnitFormation.block_slots(40, 0, 3.4).size(), 0, "no files -> no slots")


# --- ranks_for --------------------------------------------------------------

func test_ranks_for_divides_and_rounds_up() -> void:
	assert_eq(UnitFormation.ranks_for(40, 8), 5, "40 in 8 files = 5 ranks")
	assert_eq(UnitFormation.ranks_for(41, 8), 6, "a partial rank rounds up")
	assert_eq(UnitFormation.ranks_for(0, 8), 0, "no soldiers, no ranks")


# --- transpose (ranks <-> columns) ------------------------------------------

func test_transposed_files_swaps_frontage_and_depth() -> void:
	# 40 in 8 files is 5 ranks; transposed it is 5 files (the old depth becomes the width).
	assert_eq(UnitFormation.transposed_files(40, 8), 5, "frontage becomes the old rank count")


func test_double_transpose_returns_to_original_for_a_full_grid() -> void:
	# A full grid (n = files * ranks) transposes back to its original frontage.
	var files := 8
	var n := 40                                   # 8 x 5, full
	var once := UnitFormation.transposed_files(n, files)
	var twice := UnitFormation.transposed_files(n, once)
	assert_eq(twice, files, "transposing a full grid twice restores the frontage")


func test_transposed_files_is_at_least_one() -> void:
	assert_eq(UnitFormation.transposed_files(0, 8), 1, "never returns a zero file count")


# --- widen / narrow (explicatio / duplicatio) -------------------------------

func test_widened_files_doubles_the_frontage() -> void:
	assert_eq(UnitFormation.widened_files(40, 8), 16, "explicatio doubles the files")


func test_widened_files_caps_at_a_single_rank() -> void:
	assert_eq(UnitFormation.widened_files(10, 8), 10, "can't have more files than soldiers")


func test_narrowed_files_halves_the_frontage() -> void:
	assert_eq(UnitFormation.narrowed_files(8), 4, "duplicatio halves the files")


func test_narrowed_files_floors_at_one() -> void:
	assert_eq(UnitFormation.narrowed_files(1), 1, "never narrower than a single column")


# --- casualty adaptation (recompute from the LIVE count) --------------------
# A unit can take casualties mid-maneuver, so a maneuver recomputes its target shape from
# the live soldier count every tick rather than caching it. These pin the property the
# grid-ops give it: every helper is a pure function of the count passed in, and the layout
# thins from the rear (frontage held) as men fall -- so passing the live count Just Works.

func test_block_slots_thins_from_the_rear_when_men_fall() -> void:
	# Hold the file count and drop the soldier count: the front ranks are untouched and the
	# rear rank thins -- the line keeps its width and loses depth, never reflowing the front.
	var full := UnitFormation.block_slots(40, 8, 3.4)     # 8 x 5, full
	var after := UnitFormation.block_slots(36, 8, 3.4)    # 8 x 5 with a 4-man last rank
	assert_eq(after.size(), 36, "the slot count follows the live soldier count")
	for i in range(32):                                   # the four full front ranks
		assert_true(after[i].is_equal_approx(full[i]),
			"front-rank slot %d is unchanged when the rear thins" % i)


func test_transposed_files_tracks_the_live_count() -> void:
	# The 90° turn's target frontage is the live rank count, so heavy casualties shrink it:
	# a maneuver that recomputes each tick narrows its turned frontage as men fall.
	assert_eq(UnitFormation.transposed_files(40, 8), 5, "full strength: 5 ranks -> 5 files")
	assert_eq(UnitFormation.transposed_files(24, 8), 3, "after losses: 3 ranks -> 3 files")


func test_widened_files_tracks_the_live_count() -> void:
	# Explicatio's cap is the live count, so a depleted unit can't be told to widen past a
	# single rank -- the target adapts to however many men remain.
	assert_eq(UnitFormation.widened_files(40, 8), 16, "full strength widens to 16 files")
	assert_eq(UnitFormation.widened_files(12, 8), 12, "depleted: capped at the live count")


# --- square grid (#530: a real square footprint, not the wide-line frontage) -------

func test_square_files_is_roughly_sqrt_n() -> void:
	assert_eq(UnitFormation.square_files(120), 11, "ceil(sqrt(120)) = 11")
	assert_eq(UnitFormation.square_files(100), 10, "a perfect square: ceil(sqrt(100)) = 10")
	assert_eq(UnitFormation.square_files(0), 1, "never fewer than one file")


func test_square_files_is_narrower_than_the_wide_line_frontage() -> void:
	# The whole point: the line frontage (_files, via UnitFormation.frontage) is
	# deliberately wider-than-deep (FORMATION_ASPECT > 1); the square is not.
	var u := Unit.new()
	u.max_soldiers = 120
	add_child_autofree(u)
	assert_lt(UnitFormation.square_files(120), UnitFormation.frontage(u),
		"the square packs narrower than the line's wide frontage")


func test_square_slots_bbox_aspect_is_about_one() -> void:
	# The defining geometric property (#530): a real square footprint, not the 2:1
	# rectangle the wide-line frontage produces for the same count.
	var n := 120
	var files := UnitFormation.square_files(n)
	var ranks := UnitFormation.ranks_for(n, files)
	var slots := UnitFormation.square_slots(n, 9.0)
	var min_p: Vector2 = slots[0]
	var max_p: Vector2 = slots[0]
	for s in slots:
		min_p.x = minf(min_p.x, s.x)
		min_p.y = minf(min_p.y, s.y)
		max_p.x = maxf(max_p.x, s.x)
		max_p.y = maxf(max_p.y, s.y)
	var w: float = max_p.x - min_p.x
	var h: float = max_p.y - min_p.y
	assert_almost_eq(w / h, 1.0, 0.15,
		"bbox aspect (w/h=%.2f, files=%d, ranks=%d) is close to square" % [w / h, files, ranks])


func test_square_slots_has_one_slot_per_soldier() -> void:
	assert_eq(UnitFormation.square_slots(120, 9.0).size(), 120, "one slot per soldier")


func test_square_is_perimeter_flags_the_outer_ring_only() -> void:
	# A 3x3 full square (9 soldiers, 3 files): index layout is
	#   0 1 2
	#   3 4 5
	#   6 7 8
	# every slot except the dead centre (index 4) sits on the outer ring.
	for i in range(9):
		var expected: bool = i != 4
		assert_eq(UnitFormation.square_is_perimeter(i, 9, 3), expected,
			"slot %d perimeter membership" % i)


func test_square_is_perimeter_handles_a_partial_last_rank() -> void:
	# 10 soldiers at 4 files -> ranks of 4, 4, 2 (a 2-man partial last rank). The last
	# rank's two survivors are both edges of their own (2-wide) rank, so both flag as
	# perimeter; the full middle rank's inner two slots (indices 5, 6) do not.
	assert_false(UnitFormation.square_is_perimeter(5, 10, 4), "middle rank, inner-left: not perimeter")
	assert_false(UnitFormation.square_is_perimeter(6, 10, 4), "middle rank, inner-right: not perimeter")
	assert_true(UnitFormation.square_is_perimeter(8, 10, 4), "last (partial) rank: both slots perimeter")
	assert_true(UnitFormation.square_is_perimeter(9, 10, 4), "last (partial) rank: both slots perimeter")


func test_square_is_perimeter_out_of_range_is_false() -> void:
	assert_false(UnitFormation.square_is_perimeter(-1, 9, 3), "negative index")
	assert_false(UnitFormation.square_is_perimeter(9, 9, 3), "index == n is out of range")
