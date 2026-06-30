extends GutTest
## Mark-glyph geometry (#400): the archer kite and the spearmen dart must be *directional*
## (reach further toward +X than back) so rotating each instance by its soldier's facing
## reads as an arrow, AND compact (no longer along the facing axis than the infantry
## pointer) so a rotated rank can't merge into a bar — the failure of the old elongated
## rect / symmetric diamond.

const R: float = 1.7


## Longest extent of a mesh along the +X / -X facing axis (front reach + rear reach).
func _facing_span(mesh: ArrayMesh) -> float:
	return _max_x(mesh) - _min_x(mesh)


func _verts(mesh: ArrayMesh) -> PackedVector2Array:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _max_x(mesh: ArrayMesh) -> float:
	var m: float = -INF
	for v in _verts(mesh):
		m = maxf(m, v.x)
	return m


func _min_x(mesh: ArrayMesh) -> float:
	var m: float = INF
	for v in _verts(mesh):
		m = minf(m, v.x)
	return m


func _max_abs_y(mesh: ArrayMesh) -> float:
	var m: float = 0.0
	for v in _verts(mesh):
		m = maxf(m, absf(v.y))
	return m


# --- archer kite -------------------------------------------------------------

func test_kite_points_forward_more_than_it_reaches_back() -> void:
	var kite := UnitMeshes.kite_mesh(R)
	assert_gt(_max_x(kite), absf(_min_x(kite)),
		"the front tip extends further along +X than the rear, so the kite reads directional")


func test_kite_front_reach_exceeds_its_half_width() -> void:
	# The cross-axis must stay shorter than the forward reach: a rank of these rotated to
	# ~90° can't merge into a flat horizontal bar the way the old symmetric diamond did.
	var kite := UnitMeshes.kite_mesh(R)
	assert_gt(_max_x(kite), _max_abs_y(kite),
		"forward reach is longer than half-width, so a rotated rank can't flatten into a stripe")


func test_kite_mesh_is_cached() -> void:
	assert_eq(UnitMeshes.kite_mesh(R), UnitMeshes.kite_mesh(R),
		"the same radius returns the shared cached mesh")


func test_kite_is_no_longer_along_facing_than_the_infantry_pointer() -> void:
	# Compactness guard: the kite's facing-axis span must not exceed the infantry pointer's,
	# so it can't stripe any worse than the glyph the issue calls clean at any angle.
	assert_lte(_facing_span(UnitMeshes.kite_mesh(R)), _facing_span(UnitMeshes.pointer_mesh(R)) + 0.01,
		"the kite stays at least as compact along facing as the infantry pointer")


# --- spearmen dart -----------------------------------------------------------

func test_dart_points_forward_more_than_it_reaches_back() -> void:
	var dart := UnitMeshes.dart_mesh(R)
	assert_gt(_max_x(dart), absf(_min_x(dart)),
		"the dart's tip extends further along +X than its flat rear, so it reads directional")


func test_dart_is_no_longer_along_facing_than_the_infantry_pointer() -> void:
	assert_lte(_facing_span(UnitMeshes.dart_mesh(R)), _facing_span(UnitMeshes.pointer_mesh(R)) + 0.01,
		"the dart stays at least as compact along facing as the infantry pointer")


func test_dart_mesh_is_cached() -> void:
	assert_eq(UnitMeshes.dart_mesh(R), UnitMeshes.dart_mesh(R),
		"the same radius returns the shared cached mesh")
