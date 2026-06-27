extends GutTest
## The soldier-scale spatial hash that bounds the global engaged-soldier pass
## (SoldierSpatialHash). It buckets record INDICES by world position; the pass
## queries the 3x3 cell block to get a superset of every soldier within the
## separation floor. Determinism (id-ordered insertion + fixed 3x3 traversal) is
## exercised by the cross-regiment tests in test_soldier_separation.gd; here we
## pin the grid's own contract: framing, supersets, and boundary straddling.


func before_each() -> void:
	SoldierSpatialHash.reset()


func test_is_current_tracks_the_built_frame() -> void:
	assert_false(SoldierSpatialHash.is_current(5), "nothing built yet")
	SoldierSpatialHash.rebuild(PackedVector2Array([Vector2.ZERO]), 5)
	assert_true(SoldierSpatialHash.is_current(5), "current for the frame it was built on")
	assert_false(SoldierSpatialHash.is_current(6), "but not a later frame")


func test_query_returns_indices_into_the_input_array() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(3, 0), Vector2(1000, 1000)])
	SoldierSpatialHash.rebuild(pts, 1)
	var near := SoldierSpatialHash.query(Vector2(0, 0))
	assert_true(near.has(0) and near.has(1), "soldiers 0 and 1 (within a cell) are candidates")
	assert_false(near.has(2), "the far soldier is not in the 3x3 block")


func test_query_is_a_superset_within_the_floor_across_a_cell_boundary() -> void:
	# Two soldiers within the cavalry floor (5.2) but straddling a CELL_SIZE (8)
	# boundary must still surface each other — the 3x3 block guarantees it.
	var pts := PackedVector2Array([Vector2(7.5, 0), Vector2(9.5, 0)])
	SoldierSpatialHash.rebuild(pts, 1)
	assert_true(SoldierSpatialHash.query(pts[0]).has(1),
		"a neighbour just over the cell boundary is still a candidate")
	assert_true(SoldierSpatialHash.query(pts[1]).has(0), "and symmetrically")


func test_rebuild_is_idempotent_within_a_frame() -> void:
	SoldierSpatialHash.rebuild(PackedVector2Array([Vector2.ZERO]), 2)
	# A second rebuild on the same frame with different data is a no-op (mirrors
	# SpatialHash); the pass calls it once per physics frame.
	SoldierSpatialHash.rebuild(PackedVector2Array([Vector2(100, 100)]), 2)
	assert_true(SoldierSpatialHash.query(Vector2.ZERO).has(0),
		"the same-frame rebuild was skipped, so the original grid stands")


func test_reset_clears_the_grid() -> void:
	SoldierSpatialHash.rebuild(PackedVector2Array([Vector2.ZERO]), 3)
	SoldierSpatialHash.reset()
	assert_false(SoldierSpatialHash.is_current(3), "reset forgets the built frame")
	assert_eq(SoldierSpatialHash.query(Vector2.ZERO).size(), 0, "and empties the cells")
