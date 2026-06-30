class_name UnitMeshes
## Cosmetic soldier-mark mesh geometry, extracted from Unit.gd. Pure, cached mesh
## builders for the two render LODs: the flat geometric marks (disc / rect / diamond,
## zoomed out) and the detailed figure silhouettes (foot soldier or mounted rider,
## zoomed in). Render-time only — none of this writes back into the simulation, and
## every function is a deterministic function of its size/type arguments. Meshes are
## shared and cached across all units (keyed by shape + size), so the thousands of
## marks reuse a handful of meshes.

# The figure outline is a slightly larger copy of the body silhouette, drawn behind it.
const FIGURE_OUTLINE_SCALE: float = 1.22

# Foot-figure render kinds — the per-type held item that keeps foot soldiers distinct
# up close (and matches each type's flat mark shape). Cavalry ignores it. `Unit._foot_kind`
# maps a unit's type flags onto one of these.
const FOOT_INFANTRY: int = 0
const FOOT_SPEAR: int = 1
const FOOT_ARCHER: int = 2

static var _mesh_cache: Dictionary = {}


## Facing-indicator mark: a left-side semicircle (rear) joined to an isosceles triangle
## (front), pointed along +X. Rotate the instance transform to face any direction.
## tip_factor controls how far the tip extends past the radius; 1.5 gives a clear point.
static func pointer_mesh(radius: float, tip_factor: float = 1.5) -> ArrayMesh:
	var key: String = "ptr%.2f_%.2f" % [radius, tip_factor]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var segments: int = 8   # semicircle resolution
	var verts := PackedVector2Array()
	verts.push_back(Vector2.ZERO)   # fan centre
	# Semicircle from (0, +radius) going left to (0, -radius)
	for i in range(segments + 1):
		var a: float = PI * 0.5 + PI * float(i) / float(segments)
		verts.push_back(Vector2(cos(a), sin(a)) * radius)
	# Triangle tip along +X
	verts.push_back(Vector2(radius * tip_factor, 0.0))
	var n: int = verts.size()
	var idx := PackedInt32Array()
	for i in range(1, n - 1):
		idx.append(0)
		idx.append(i)
		idx.append(i + 1)
	idx.append(0)   # close: tip back to top of semicircle
	idx.append(n - 1)
	idx.append(1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_cache[key] = mesh
	return mesh


## Disc mesh at the given radius, shared across all units. Built once and cached.
static func disc_mesh(radius: float) -> ArrayMesh:
	var key: float = snappedf(radius, 0.01)
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var segments: int = 10
	var verts := PackedVector2Array()
	verts.push_back(Vector2.ZERO)   # fan centre
	for i in range(segments + 1):
		var a: float = TAU * float(i) / float(segments)
		verts.push_back(Vector2(cos(a), sin(a)) * radius)
	var idx := PackedInt32Array()
	for i in range(segments):
		idx.append(0)
		idx.append(1 + i)
		idx.append(2 + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_cache[key] = mesh
	return mesh


static func rect_mesh(w: float, h: float) -> ArrayMesh:
	var key: String = "r%.2f_%.2f" % [w, h]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var hw := w * 0.5
	var hh := h * 0.5
	var verts := PackedVector2Array([
		Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh),
	])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_cache[key] = mesh
	return mesh


static func diamond_mesh(radius: float) -> ArrayMesh:
	var key: String = "d%.2f" % [radius]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var verts := PackedVector2Array([
		Vector2(0.0, -radius), Vector2(radius, 0.0),
		Vector2(0.0, radius),  Vector2(-radius, 0.0),
	])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_cache[key] = mesh
	return mesh


## A unit-length melee-weapon blade pointing along +X: a slim leaf shape, half-width 1
## at the hilt (x=0) tapering to a point at the tip (x=1). Built unit-sized so the render
## sets the actual length and thickness through the per-instance transform basis (length
## encodes the unit's reach; see SoldierFlock.weapon_stroke). Shared/cached. Cosmetic only.
static func weapon_mesh() -> ArrayMesh:
	var key := "weapon"
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var blade := PackedVector2Array([
		Vector2(0.0, -1.0), Vector2(0.65, -0.55), Vector2(1.0, 0.0),
		Vector2(0.65, 0.55), Vector2(0.0, 1.0),
	])
	var mesh := _mesh_from_polys([blade])
	_mesh_cache[key] = mesh
	return mesh


## A detailed figure silhouette (zoomed-in LOD), shared/cached across units. `is_cav`
## picks a mounted rider over a standing soldier; for foot, `foot_kind` selects the
## per-type held item (FOOT_INFANTRY / FOOT_SPEAR / FOOT_ARCHER). `outline` returns the
## scaled-up rim copy; `flip` mirrors it left-right so the figure faces the unit's march
## direction (MultiMesh 2D can't store a reflected instance transform, so we bake two
## meshes and swap). Built by fan-triangulating the figure's convex polygon parts.
static func figure_mesh(is_cav: bool, foot_kind: int, mark_r: float, outline: bool, flip: bool) -> ArrayMesh:
	var who: String = "cav" if is_cav else "foot%d" % foot_kind
	var key: String = "fig_%s_%s%s_%.2f" % [who, "o" if outline else "b", "f" if flip else "", mark_r]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var polys: Array = _horse_figure_polys(mark_r) if is_cav else _foot_figure_polys(foot_kind, mark_r)
	if outline:
		polys = _scale_polys(polys, FIGURE_OUTLINE_SCALE)
	if flip:
		polys = _mirror_polys_x(polys)
	var mesh := _mesh_from_polys(polys)
	_mesh_cache[key] = mesh
	return mesh


## Combine a list of convex polygons (each a PackedVector2Array) into one ArrayMesh
## surface, fan-triangulating each from its first vertex.
static func _mesh_from_polys(polys: Array) -> ArrayMesh:
	var verts := PackedVector2Array()
	var idx := PackedInt32Array()
	for poly in polys:
		var base: int = verts.size()
		for v in poly:
			verts.push_back(v)
		for i in range(1, poly.size() - 1):
			idx.push_back(base)
			idx.push_back(base + i)
			idx.push_back(base + i + 1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Scale every vertex of every polygon about the origin (the figure's centre) to
## produce the slightly larger outline silhouette.
static func _scale_polys(polys: Array, s: float) -> Array:
	var out: Array = []
	for poly in polys:
		var scaled := PackedVector2Array()
		for v in poly:
			scaled.push_back(v * s)
		out.push_back(scaled)
	return out


## Mirror every vertex left-right about the figure's centre (negate x), producing the
## opposite-facing figure. Reverses polygon winding, but 2D canvas meshes aren't
## backface-culled, so the silhouette renders the same.
static func _mirror_polys_x(polys: Array) -> Array:
	var out: Array = []
	for poly in polys:
		var mirrored := PackedVector2Array()
		for v in poly:
			mirrored.push_back(Vector2(-v.x, v.y))
		out.push_back(mirrored)
	return out


## A convex polygon approximating a circle of `radius` centred at `c`, for figure
## heads (a coarse disc — these are a few px across on screen).
static func _disc_poly(c: Vector2, radius: float, segments: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a: float = TAU * float(i) / float(segments)
		pts.push_back(c + Vector2(cos(a), sin(a)) * radius)
	return pts


## Convex-polygon parts of a standing foot soldier, centred on the origin
## (screen-up = -y): a head, a tapering torso and two legs, plus a per-type held
## item (`kind`) on one flank so spearmen / archers / infantry stay distinct up
## close. Sizes scale with the mark radius so the figure tracks the mark it replaces.
static func _foot_figure_polys(kind: int, r: float) -> Array:
	var parts: Array = _foot_body_polys(r)
	match kind:
		FOOT_SPEAR:
			parts.append_array(_spear_polys(r))
		FOOT_ARCHER:
			parts.append_array(_bow_polys(r))
		_:
			parts.append_array(_shield_polys(r))
	return parts


## The bare standing-soldier silhouette (head, torso, two legs), shared by every
## foot type before its held item is added.
static func _foot_body_polys(r: float) -> Array:
	var head := _disc_poly(Vector2(0.0, -1.35 * r), 0.5 * r)
	var torso := PackedVector2Array([
		Vector2(-0.85 * r, -0.85 * r), Vector2(0.85 * r, -0.85 * r),
		Vector2(0.5 * r, 0.45 * r), Vector2(-0.5 * r, 0.45 * r),
	])
	var leg_l := PackedVector2Array([
		Vector2(-0.5 * r, 0.45 * r), Vector2(-0.1 * r, 0.45 * r),
		Vector2(-0.1 * r, 1.75 * r), Vector2(-0.5 * r, 1.75 * r),
	])
	var leg_r := PackedVector2Array([
		Vector2(0.1 * r, 0.45 * r), Vector2(0.5 * r, 0.45 * r),
		Vector2(0.5 * r, 1.75 * r), Vector2(0.1 * r, 1.75 * r),
	])
	return [torso, leg_l, leg_r, head]


## A spear held upright on the figure's right: a thin shaft rising above the head
## with a small triangular head, protruding past the body silhouette.
static func _spear_polys(r: float) -> Array:
	var shaft := PackedVector2Array([
		Vector2(0.78 * r, -2.0 * r), Vector2(1.0 * r, -2.0 * r),
		Vector2(1.0 * r, 1.55 * r), Vector2(0.78 * r, 1.55 * r),
	])
	var head := PackedVector2Array([
		Vector2(0.89 * r, -2.6 * r), Vector2(1.22 * r, -1.9 * r),
		Vector2(0.56 * r, -1.9 * r),
	])
	return [shaft, head]


## A bow held on the figure's right: a curved limb (an arc strip) with a straight
## bowstring across its tips, reaching past the body silhouette.
static func _bow_polys(r: float) -> Array:
	var c := Vector2(0.25 * r, -0.2 * r)
	var rad: float = 1.15 * r
	var a0: float = -0.95
	var a1: float = 0.95
	var parts: Array = _arc_strip(c, rad, a0, a1, 0.2 * r)
	var tip0: Vector2 = c + Vector2(cos(a0), sin(a0)) * rad
	var tip1: Vector2 = c + Vector2(cos(a1), sin(a1)) * rad
	parts.push_back(_line_quad(tip0, tip1, 0.07 * r))
	return parts


## A heater shield held on the figure's left: a convex pentagon protruding past
## the torso so the silhouette reads as a shield-bearer.
static func _shield_polys(r: float) -> Array:
	var shield := PackedVector2Array([
		Vector2(-1.3 * r, -0.7 * r), Vector2(-0.5 * r, -0.7 * r),
		Vector2(-0.5 * r, 0.25 * r), Vector2(-0.9 * r, 0.7 * r),
		Vector2(-1.3 * r, 0.25 * r),
	])
	return [shield]


## A curved strip — an arc of `radius` about `c` from angle `a0` to `a1`, `thickness`
## wide — as a list of convex trapezoid quads (each fan-triangulable). Used for the
## archer's bow limb, which a single convex polygon can't represent.
static func _arc_strip(c: Vector2, radius: float, a0: float, a1: float,
		thickness: float, segments: int = 6) -> Array:
	var quads: Array = []
	var inner: float = radius - thickness * 0.5
	var outer: float = radius + thickness * 0.5
	for i in range(segments):
		var t0: float = a0 + (a1 - a0) * float(i) / float(segments)
		var t1: float = a0 + (a1 - a0) * float(i + 1) / float(segments)
		var d0 := Vector2(cos(t0), sin(t0))
		var d1 := Vector2(cos(t1), sin(t1))
		quads.push_back(PackedVector2Array([
			c + d0 * inner, c + d0 * outer, c + d1 * outer, c + d1 * inner,
		]))
	return quads


## A thin rectangle (a line of half-width `hw`) from `a` to `b`, as one convex quad.
static func _line_quad(a: Vector2, b: Vector2, hw: float) -> PackedVector2Array:
	var dir: Vector2 = b - a
	dir = dir.normalized() if dir.length() > 0.0001 else Vector2.RIGHT
	var n := Vector2(-dir.y, dir.x) * hw
	return PackedVector2Array([a + n, b + n, b - n, a - n])


## Convex-polygon parts of a mounted rider, centred on the origin, facing screen-right
## (+x) by default: a mount body with a neck and head reaching forward, a tail at the
## rear, four legs, and an upright rider. The render flips it horizontally from the
## unit's facing.x so the regiment's horses face its march/charge direction.
static func _horse_figure_polys(r: float) -> Array:
	var body := PackedVector2Array([
		Vector2(-1.25 * r, 0.18 * r), Vector2(-0.9 * r, -0.15 * r),
		Vector2(0.85 * r, -0.15 * r), Vector2(1.2 * r, 0.12 * r),
		Vector2(0.85 * r, 0.6 * r), Vector2(-0.9 * r, 0.6 * r),
	])
	var parts: Array = [body]
	# Neck rising forward from the chest, with a muzzle reaching ahead (+x).
	var neck := PackedVector2Array([
		Vector2(0.95 * r, -0.05 * r), Vector2(1.55 * r, -0.95 * r),
		Vector2(1.8 * r, -0.7 * r), Vector2(1.25 * r, 0.12 * r),
	])
	parts.push_back(neck)
	var head := PackedVector2Array([
		Vector2(1.55 * r, -1.05 * r), Vector2(2.0 * r, -0.92 * r),
		Vector2(1.88 * r, -0.58 * r), Vector2(1.5 * r, -0.68 * r),
	])
	parts.push_back(head)
	# Tail trailing down off the hindquarters (-x).
	var tail := PackedVector2Array([
		Vector2(-1.2 * r, -0.05 * r), Vector2(-1.0 * r, 0.05 * r),
		Vector2(-1.4 * r, 0.95 * r), Vector2(-1.62 * r, 0.8 * r),
	])
	parts.push_back(tail)
	for cx in [-0.95 * r, -0.4 * r, 0.4 * r, 0.85 * r]:
		parts.push_back(PackedVector2Array([
			Vector2(cx - 0.11 * r, 0.6 * r), Vector2(cx + 0.11 * r, 0.6 * r),
			Vector2(cx + 0.11 * r, 1.55 * r), Vector2(cx - 0.11 * r, 1.55 * r),
		]))
	# Rider seated just behind the mount's centre.
	var rider_torso := PackedVector2Array([
		Vector2(-0.5 * r, -0.9 * r), Vector2(0.45 * r, -0.9 * r),
		Vector2(0.3 * r, -0.15 * r), Vector2(-0.4 * r, -0.15 * r),
	])
	parts.push_back(rider_torso)
	parts.push_back(_disc_poly(Vector2(-0.05 * r, -1.3 * r), 0.42 * r))
	return parts
