extends GutTest
## SpatialHash: the per-frame grid query must return a SUPERSET of the
## units within separation distance, so Unit._separate() resolves the same set of
## overlaps a brute-force all-pairs scan would, just faster.

func before_each() -> void:
	# Start from a clean grid even if another test script left static state behind.
	SpatialHash.reset()


func after_each() -> void:
	# Isolate the static grid between tests (and from other test scripts).
	SpatialHash.reset()


func _grid_node(pos: Vector2) -> Node2D:
	var n := Node2D.new()
	add_child_autofree(n)
	n.add_to_group("units")
	n.position = pos
	return n


func test_is_current_tracks_the_built_frame() -> void:
	assert_false(SpatialHash.is_current(7), "no grid is current before a rebuild")
	SpatialHash.rebuild(get_tree(), 7)
	assert_true(SpatialHash.is_current(7), "the grid is current for the frame it built")
	assert_false(SpatialHash.is_current(8), "a later frame needs its own rebuild")


func test_query_includes_nearby_and_excludes_far_units() -> void:
	var a := _grid_node(Vector2(10, 10))
	var b := _grid_node(Vector2(40, 10))            # same cell block as a
	var far := _grid_node(Vector2(2000, 2000))      # far-off cell block
	SpatialHash.rebuild(get_tree(), 1)
	var near := SpatialHash.query(a.position)
	assert_true(near.has(b), "a unit within separation distance is a candidate")
	assert_false(near.has(far), "a far unit in another cell block is excluded")


func test_query_spans_the_three_by_three_block_across_a_cell_boundary() -> void:
	# Two units straddling a cell boundary (x≈128) are within ~20px of each other,
	# so the query around one must still surface the other from the next cell.
	var a := _grid_node(Vector2(120, 50))
	var b := _grid_node(Vector2(140, 50))
	SpatialHash.rebuild(get_tree(), 1)
	assert_true(SpatialHash.query(a.position).has(b),
		"a neighbour in the adjacent cell is still a candidate")
