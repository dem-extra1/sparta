class_name SoldierSpatialHash
extends RefCounted
## Per-physics-frame spatial hash for the individual-SOLDIER steering pass — the
## soldier-scale sibling of SpatialHash (which buckets whole regiments).
##
## The global engaged-soldier steering pass (SoldierSteering.accumulate) gathers every
## engaged soldier across all regiments into one flat, id-sorted array, rebuilds
## this grid from those world positions, then queries the 3x3 cell block around
## each soldier to get a small superset of possible neighbours — replacing an
## O(n^2) all-pairs scan over ~1,500 engaged bodies with O(n) bucketing + local
## neighbourhoods. It stores RECORD INDICES into that flat array (not nodes), so
## the caller can map a candidate back to its owning regiment and id.
##
## Determinism: the array is sorted by global soldier id before rebuild, so cell
## insertion order is id order, and query()'s fixed 3x3 traversal then visits
## candidates in a reproducible order — the property replays rely on.

# Cell size must exceed the widest soldier separation floor (two cavalry bodies,
# 2 * CAV_MARK_RADIUS = 5.2) so the 3x3 block around a soldier is a guaranteed
# superset of every soldier within separation distance. The grid is rebuilt from
# the exact positions the pass then separates (no movement between rebuild and
# query), so that one bound is all that's required; 8.0 clears 5.2 while keeping
# per-cell candidate counts low.
const CELL_SIZE := 8.0

static var _frame: int = -1
static var _cells: Dictionary = {}


static func _key(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL_SIZE)), int(floor(p.y / CELL_SIZE)))


## True when the grid has been rebuilt for `frame` and can be queried.
static func is_current(frame: int) -> bool:
	return frame == _frame


## Rebuild the grid by bucketing each position's INDEX into its cell. `positions`
## is the flat, id-sorted engaged-soldier array; the returned candidate indices
## point back into it. Idempotent within a frame.
static func rebuild(positions: PackedVector2Array, frame: int) -> void:
	if frame == _frame:
		return
	_frame = frame
	_cells.clear()
	for i in range(positions.size()):
		var key := _key(positions[i])
		if not _cells.has(key):
			_cells[key] = PackedInt32Array()
		_cells[key].append(i)


## Candidate record indices in the 3x3 cell block around `pos` — a superset of
## every soldier within CELL_SIZE. Traversal order is deterministic (fixed dx/dy
## loop, then each cell's insertion = id order), so separation is reproducible.
static func query(pos: Vector2) -> PackedInt32Array:
	var out := PackedInt32Array()
	var c := _key(pos)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cell: Variant = _cells.get(Vector2i(c.x + dx, c.y + dy))
			if cell != null:
				out.append_array(cell)
	return out


## Forget any built grid so the next rebuild() runs. Used by tests for isolation.
static func reset() -> void:
	_frame = -1
	_cells.clear()
