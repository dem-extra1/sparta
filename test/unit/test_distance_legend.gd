extends GutTest
## Pure scale-bar math (#364): metres-per-pixel from camera zoom, the round-number ladder
## pick, the resulting bar width, and the player-facing label. No node/camera needed --
## DistanceLegend is a function of (zoom, world_units_per_metre) only.

const WUPM: float = 20.0   # Battle.WORLD_UNITS_PER_METER


# --- metres_per_pixel --------------------------------------------------------

func test_metres_per_pixel_at_unit_zoom() -> void:
	# zoom=1, 20 world units/metre -> 1 world unit/px -> 0.05 m/px.
	assert_almost_eq(DistanceLegend.metres_per_pixel(1.0, WUPM), 0.05, 0.0001)


func test_metres_per_pixel_scales_inversely_with_zoom() -> void:
	# Zooming in (higher zoom) magnifies the world, so each pixel covers FEWER metres.
	var far := DistanceLegend.metres_per_pixel(0.5, WUPM)
	var near := DistanceLegend.metres_per_pixel(2.0, WUPM)
	assert_gt(far, near, "zooming in reduces metres-per-pixel")
	assert_almost_eq(near, far / 4.0, 0.0001, "zoom 0.5 -> 2.0 is a 4x change, so mpp quarters")


func test_metres_per_pixel_guards_nonpositive_input() -> void:
	assert_eq(DistanceLegend.metres_per_pixel(0.0, WUPM), 0.0, "zero zoom guarded")
	assert_eq(DistanceLegend.metres_per_pixel(-1.0, WUPM), 0.0, "negative zoom guarded")
	assert_eq(DistanceLegend.metres_per_pixel(1.0, 0.0), 0.0, "zero world-units-per-metre guarded")


# --- pick_round_metres --------------------------------------------------------

## True when `value` is some power of ten times 1, 2, or 5 (the 1-2-5 ladder rule) -- a
## property check, not a fixed list, so it stays valid at any rung the ladder might pick.
func _is_ladder_value(value: float) -> bool:
	if value <= 0.0:
		return false
	var mag: float = value
	while mag >= 10.0:
		mag /= 10.0
	while mag < 1.0:
		mag *= 10.0
	return is_equal_approx(mag, 1.0) or is_equal_approx(mag, 2.0) or is_equal_approx(mag, 5.0)


func test_pick_round_metres_is_a_ladder_value() -> void:
	var mpp: float = DistanceLegend.metres_per_pixel(1.0, WUPM)   # 0.05 m/px
	var picked: float = DistanceLegend.pick_round_metres(mpp)
	assert_true(_is_ladder_value(picked),
		"the result is a 1-2-5 ladder value (1/2/5 x a power of ten), got %s" % picked)


func test_pick_round_metres_width_never_exceeds_max_px() -> void:
	# Sweep a range of zooms; the chosen distance's bar must never overflow the band.
	for zoom in [0.45, 0.7, 1.0, 1.5, 2.2]:
		var mpp: float = DistanceLegend.metres_per_pixel(zoom, WUPM)
		var picked: float = DistanceLegend.pick_round_metres(mpp)
		var width: float = DistanceLegend.bar_width_px(picked, mpp)
		assert_lte(width, DistanceLegend.MAX_PX + 0.01,
			"zoom %s: width %s exceeds the max band" % [zoom, width])


func test_pick_round_metres_picks_the_largest_that_fits() -> void:
	# mpp such that 50m -> exactly 100px (under 150) but 100m -> 200px (over 150):
	# mpp = 0.5 -> pick should be 50, not 20 or 100.
	var picked: float = DistanceLegend.pick_round_metres(0.5)
	assert_eq(picked, 50.0, "picks the largest ladder value that still fits under max_px")


func test_pick_round_metres_guards_nonpositive_mpp() -> void:
	assert_eq(DistanceLegend.pick_round_metres(0.0), 0.0, "zero mpp guarded")
	assert_eq(DistanceLegend.pick_round_metres(-1.0), 0.0, "negative mpp guarded")


func test_pick_round_metres_falls_back_to_the_smallest_rung_when_even_that_overflows() -> void:
	# An extreme zoom-in where even 1m's bar would overflow max_px still returns a value
	# (the smallest rung), not 0 -- the bar just reads larger than the target band that frame.
	var picked: float = DistanceLegend.pick_round_metres(0.001, 0.5)
	assert_eq(picked, 1.0, "falls back to the ladder's smallest rung rather than nothing")


# --- bar_width_px --------------------------------------------------------

func test_bar_width_px_is_metres_over_mpp() -> void:
	assert_almost_eq(DistanceLegend.bar_width_px(50.0, 0.5), 100.0, 0.001)


func test_bar_width_px_guards_nonpositive_mpp() -> void:
	assert_eq(DistanceLegend.bar_width_px(50.0, 0.0), 0.0, "zero mpp guarded")


# --- label_text --------------------------------------------------------

func test_label_text_under_a_kilometre() -> void:
	assert_eq(DistanceLegend.label_text(50.0), "50 m")
	assert_eq(DistanceLegend.label_text(999.0), "999 m")


func test_label_text_at_and_above_a_kilometre() -> void:
	assert_eq(DistanceLegend.label_text(1000.0), "1 km", "a whole kilometre drops the .0")
	assert_eq(DistanceLegend.label_text(1500.0), "1.5 km")
	assert_eq(DistanceLegend.label_text(2000.0), "2 km")


# --- end-to-end sanity: the bar reads sensibly across the camera's real zoom range -------

func test_end_to_end_across_the_camera_zoom_range() -> void:
	# Mirrors CameraController's zoom_min/zoom_max (0.45 .. 2.2): at every zoom the battle
	# actually allows, the picked distance produces an in-band-or-smaller width and a
	# non-empty label.
	for zoom in [0.45, 1.0, 2.2]:
		var mpp: float = DistanceLegend.metres_per_pixel(zoom, WUPM)
		var metres: float = DistanceLegend.pick_round_metres(mpp)
		var width: float = DistanceLegend.bar_width_px(metres, mpp)
		assert_gt(metres, 0.0, "zoom %s yields a positive round distance" % zoom)
		assert_lte(width, DistanceLegend.MAX_PX + 0.01, "zoom %s stays within the max band" % zoom)
		assert_ne(DistanceLegend.label_text(metres), "", "zoom %s yields a non-empty label" % zoom)
