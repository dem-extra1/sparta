class_name SoldierFlock
## Render-support helpers for the soldier mark layer. The cosmetic spring and all
## render-only animation offsets (lunge, weapon stroke, rank-cycle widen, relief
## spread) have been removed; marks now render directly from _sim_soldier_pos.
## Only the LOD threshold logic and block-extent computation remain here.


## Whether the zoomed-in figure LOD should be active, with hysteresis: switch ON at or past
## LOD_ZOOM_IN, OFF at or below LOD_ZOOM_OUT, and HOLD the current level in the band between
## (so the figures don't flicker on and off at the threshold).
static func lod_should_detail(currently_detailed: bool, zoom: float) -> bool:
	if zoom >= Unit.LOD_ZOOM_IN:
		return true
	if zoom <= Unit.LOD_ZOOM_OUT:
		return false
	return currently_detailed


## Block half-size: the farthest slot plus a mark radius, floored at the collision RADIUS.
## Sizes the state ring, selection halo, stat bars (in _draw) and the ground shadow.
static func compute_extent(unit: Unit, slots: PackedVector2Array) -> float:
	var mark_r: float = Unit.CAV_MARK_RADIUS if unit.is_cavalry else Unit.MARK_RADIUS
	var extent: float = Unit.RADIUS
	for s in slots:
		extent = maxf(extent, s.length())
	return extent + mark_r + 2.0
