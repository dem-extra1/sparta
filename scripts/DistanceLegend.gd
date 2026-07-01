class_name DistanceLegend
## Pure math for the HUD map-scale bar (#364): how many real metres a screen pixel covers
## at the camera's current zoom, and which "nice" round-number distance to label the bar
## with so it stays both round and a sensible width on screen. No node state, no RNG, no
## wall-clock -- a function of (zoom, world_units_per_metre) only, so it's directly
## unit-testable; HUD just reads the camera and draws the rect + label these compute.

# Target on-screen width band for the bar (px): wide enough to read at a glance, narrow
# enough not to dominate the corner. pick_round_metres returns the largest "nice" distance
# that keeps the bar at or under MAX_PX (and -- for any normal zoom -- lands it in-band).
const MIN_PX: float = 60.0
const MAX_PX: float = 150.0


## World units a screen pixel spans at `zoom`, converted to metres via `world_units_per_metre`
## (Battle.WORLD_UNITS_PER_METER). Camera2D.zoom > 1 magnifies (fewer world units per pixel),
## so metres-per-pixel is the inverse of zoom. 0 for a non-positive input (caller's guard).
static func metres_per_pixel(zoom: float, world_units_per_metre: float) -> float:
	if zoom <= 0.0 or world_units_per_metre <= 0.0:
		return 0.0
	return 1.0 / (zoom * world_units_per_metre)


## Real metres spanned by a `world_units` world-space distance, via `world_units_per_metre`
## (Battle.WORLD_UNITS_PER_METER). The inverse of the metres->world conversion the loadouts
## use. 0 for a non-positive scale. Lets the order overlay label a route in the same metric
## units the scale bar uses.
static func metres_for_world(world_units: float, world_units_per_metre: float) -> float:
	if world_units_per_metre <= 0.0:
		return 0.0
	return world_units / world_units_per_metre


## Real metres/second for a `world_speed` (world units/second), via `world_units_per_metre`
## (Battle.WORLD_UNITS_PER_METER) and the global `speed_scale` (Battle.SPEED_SCALE) the
## loadouts multiply their authored m/s by. Undoes that same product so a unit's live
## `_current_speed` reads back in the metres/second the loadout declared. 0 for a
## non-positive scale.
static func mps_for_world_speed(world_speed: float, world_units_per_metre: float, speed_scale: float = 1.0) -> float:
	var factor: float = world_units_per_metre * speed_scale
	if factor <= 0.0:
		return 0.0
	return world_speed / factor


## Player-facing label for a speed in metres/second: one decimal place, e.g. "2.6 m/s".
## Negative inputs clamp to 0 (a magnitude, never below zero).
static func speed_label_text(mps: float) -> String:
	return "%.1f m/s" % maxf(mps, 0.0)


## The "nice" round distance (the classic 1-2-5 ladder: 1, 2, 5, 10, 20, 50, 100, 200, …,
## scaled by powers of ten in both directions) whose on-screen width is the largest that
## still fits at or under `max_px`. Width grows monotonically with the ladder, so the first
## candidate to exceed max_px stops the scan and the previous one is the answer. 0 for a
## non-positive metres_per_pixel (camera not ready / degenerate zoom).
static func pick_round_metres(mpp: float, max_px: float = MAX_PX) -> float:
	if mpp <= 0.0:
		return 0.0
	var ladder: Array[float] = _ladder()
	var best: float = 0.0
	for c in ladder:
		if c / mpp > max_px:
			break
		best = c
	return best if best > 0.0 else ladder[0]


## On-screen width (px) of a bar spanning `metres` at `mpp` metres-per-pixel.
static func bar_width_px(metres: float, mpp: float) -> float:
	if mpp <= 0.0:
		return 0.0
	return metres / mpp


## Player-facing label for a round distance: "750 m" below 1 km, "1.5 km" / "2 km" at or
## above -- trims a trailing ".0" so whole kilometres read clean.
static func label_text(metres: float) -> String:
	if metres < 1000.0:
		return "%d m" % int(round(metres))
	var km: float = metres / 1000.0
	var s: String = "%.1f" % km
	if s.ends_with(".0"):
		s = s.substr(0, s.length() - 2)
	return "%s km" % s


## The 1-2-5 ladder from 1 m up to 1e7 m (10,000 km -- far past any battlefield), so
## pick_round_metres always has a candidate at any sane zoom. Generated, not hand-listed,
## so it never runs out at an extreme zoom.
static func _ladder() -> Array[float]:
	var out: Array[float] = []
	var mag: float = 1.0
	for _decade in range(8):
		out.append(mag)
		out.append(mag * 2.0)
		out.append(mag * 5.0)
		mag *= 10.0
	return out
