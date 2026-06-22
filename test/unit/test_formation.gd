extends GutTest
## Formation cohesion: a group move translates the regiment as a rigid
## block from its centroid (move_target = dest + (pos - centroid)), so the shape
## is preserved. These test the math used in Battle._apply_order_cmd.

const BattleScript = preload("res://scripts/Battle.gd")


func test_centroid_is_the_average_position() -> void:
	var ps: Array[Vector2] = [Vector2(0, 0), Vector2(40, 0), Vector2(80, 0)]
	var c := BattleScript.formation_centroid(ps)
	assert_almost_eq(c.x, 40.0, 0.001, "centroid x is the mean")
	assert_almost_eq(c.y, 0.0, 0.001, "centroid y is the mean")


func test_empty_set_centroid_is_zero() -> void:
	var empty: Array[Vector2] = []
	assert_eq(BattleScript.formation_centroid(empty), Vector2.ZERO)


func test_block_translation_preserves_spacing_and_lands_on_destination() -> void:
	var positions: Array[Vector2] = [Vector2(0, 0), Vector2(40, 0), Vector2(80, 0)]   # a line
	var dest := Vector2(500, 500)
	var centroid := BattleScript.formation_centroid(positions)
	var targets: Array[Vector2] = []
	for p in positions:
		targets.append(dest + (p - centroid))
	# Rigid translation keeps every pairwise gap identical (shape held).
	assert_almost_eq(targets[0].distance_to(targets[1]), 40.0, 0.001, "left gap held")
	assert_almost_eq(targets[1].distance_to(targets[2]), 40.0, 0.001, "right gap held")
	# The formation's centroid lands exactly on the ordered destination.
	var tc := BattleScript.formation_centroid(targets)
	assert_almost_eq(tc.x, 500.0, 0.001, "formation recenters on the destination")
	assert_almost_eq(tc.y, 500.0, 0.001)


func test_2d_block_translation_preserves_shape() -> void:
	# A 2x2 grid exercises both axes (the prior tests are all collinear at y=0).
	var positions: Array[Vector2] = [
		Vector2(0, 0), Vector2(40, 0), Vector2(0, 40), Vector2(40, 40),
	]
	var dest := Vector2(300, 200)
	var centroid := BattleScript.formation_centroid(positions)
	var targets: Array[Vector2] = []
	for p in positions:
		targets.append(dest + (p - centroid))
	# Every pairwise gap is preserved on both axes.
	assert_almost_eq(targets[0].distance_to(targets[1]), 40.0, 0.001, "top edge held")
	assert_almost_eq(targets[0].distance_to(targets[2]), 40.0, 0.001, "left edge held")
	assert_almost_eq(targets[0].distance_to(targets[3]), positions[0].distance_to(positions[3]),
		0.001, "diagonal held")
	var tc := BattleScript.formation_centroid(targets)
	assert_almost_eq(tc.x, 300.0, 0.001, "2D formation recenters on the destination x")
	assert_almost_eq(tc.y, 200.0, 0.001, "2D formation recenters on the destination y")
