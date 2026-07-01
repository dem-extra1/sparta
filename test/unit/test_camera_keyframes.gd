extends GutTest
## Pure camera-track interpolation for scripted-input demos (#412): CameraKeyframes.sample()
## eases the recorder's framing between keyframes by tick. A function of (track, tick) only,
## so no recorder/battle instance is needed (mirrors test_distance_legend).

func _kf(tick: int, x: float, y: float, zoom: float) -> Dictionary:
	return {"tick": tick, "x": x, "y": y, "zoom": zoom}


func test_empty_track_returns_empty() -> void:
	assert_true(CameraKeyframes.sample([], 5).is_empty(),
		"no keyframes -> no framing (recorder leaves the default camera alone)")


func test_single_keyframe_holds_its_framing_at_every_tick() -> void:
	var track: Array = [_kf(0, 500.0, 300.0, 1.5)]
	for tick in [0, 50, 999]:
		var f: Dictionary = CameraKeyframes.sample(track, tick)
		assert_eq(f["x"], 500.0, "x held at tick %d" % tick)
		assert_eq(f["y"], 300.0, "y held at tick %d" % tick)
		assert_eq(f["zoom"], 1.5, "zoom held at tick %d" % tick)


func test_midpoint_tick_interpolates_linearly() -> void:
	var track: Array = [_kf(0, 0.0, 0.0, 1.0), _kf(100, 200.0, 400.0, 2.0)]
	var f: Dictionary = CameraKeyframes.sample(track, 50)
	assert_almost_eq(f["x"], 100.0, 0.0001, "halfway in tick -> halfway in x")
	assert_almost_eq(f["y"], 200.0, 0.0001, "halfway in y")
	assert_almost_eq(f["zoom"], 1.5, 0.0001, "halfway in zoom")


func test_quarter_tick_interpolates_proportionally() -> void:
	var track: Array = [_kf(0, 0.0, 0.0, 1.0), _kf(100, 200.0, 0.0, 3.0)]
	var f: Dictionary = CameraKeyframes.sample(track, 25)
	assert_almost_eq(f["x"], 50.0, 0.0001, "a quarter of the way through is a quarter of the span")
	assert_almost_eq(f["zoom"], 1.5, 0.0001, "zoom eases the same quarter")


func test_lands_on_each_keyframe_exactly_at_its_tick() -> void:
	var track: Array = [_kf(0, 0.0, 0.0, 1.0), _kf(60, 90.0, 0.0, 2.0), _kf(120, 300.0, 0.0, 0.5)]
	assert_almost_eq(CameraKeyframes.sample(track, 60)["x"], 90.0, 0.0001, "exact hit on the middle keyframe")
	assert_almost_eq(CameraKeyframes.sample(track, 60)["zoom"], 2.0, 0.0001, "exact zoom on the middle keyframe")


func test_interpolates_within_the_correct_segment_of_a_multi_keyframe_track() -> void:
	# Tick 90 sits in the second segment (60->120), 50% through it.
	var track: Array = [_kf(0, 0.0, 0.0, 1.0), _kf(60, 100.0, 0.0, 2.0), _kf(120, 300.0, 0.0, 4.0)]
	var f: Dictionary = CameraKeyframes.sample(track, 90)
	assert_almost_eq(f["x"], 200.0, 0.0001, "halfway between the 2nd and 3rd keyframes in x")
	assert_almost_eq(f["zoom"], 3.0, 0.0001, "halfway between in zoom")


func test_clamps_before_first_and_after_last() -> void:
	var track: Array = [_kf(10, 50.0, 0.0, 1.0), _kf(100, 250.0, 0.0, 2.0)]
	assert_eq(CameraKeyframes.sample(track, 0)["x"], 50.0, "before the first tick holds the first frame's x")
	assert_eq(CameraKeyframes.sample(track, 0)["zoom"], 1.0, "...and its zoom")
	assert_eq(CameraKeyframes.sample(track, 999)["x"], 250.0, "after the last tick holds the last frame's x")
	assert_eq(CameraKeyframes.sample(track, 999)["zoom"], 2.0, "...and its zoom")


func test_is_sorted_accepts_a_non_decreasing_track() -> void:
	# Includes a tie (30, 30) so the "non-decreasing, not strictly increasing" case is covered.
	var track: Array = [_kf(0, 0.0, 0.0, 1.0), _kf(30, 0.0, 0.0, 1.0), _kf(30, 0.0, 0.0, 1.0), _kf(90, 0.0, 0.0, 1.0)]
	assert_true(CameraKeyframes.is_sorted(track), "non-decreasing ticks (including a tie) are sorted")


func test_is_sorted_rejects_an_out_of_order_track() -> void:
	var track: Array = [_kf(0, 0.0, 0.0, 1.0), _kf(90, 0.0, 0.0, 1.0), _kf(30, 0.0, 0.0, 1.0)]
	assert_false(CameraKeyframes.is_sorted(track), "a tick that drops back is not sorted")


func test_is_sorted_is_true_for_empty_and_single() -> void:
	assert_true(CameraKeyframes.is_sorted([]), "empty track is trivially sorted")
	assert_true(CameraKeyframes.is_sorted([_kf(5, 0.0, 0.0, 1.0)]), "single keyframe is trivially sorted")


func test_duplicate_tick_keyframes_do_not_divide_by_zero() -> void:
	# Degenerate authoring: two keyframes on the same mid-track tick. The exact-hit lands via
	# the first segment ending at tick 30 (fraction clamps to 1.0 -> its end frame), so the
	# first keyframe at 30 wins and the zero-span pair is never divided through.
	var track: Array = [_kf(0, 0.0, 0.0, 1.0), _kf(30, 100.0, 0.0, 1.0),
			_kf(30, 999.0, 0.0, 5.0), _kf(60, 300.0, 0.0, 2.0)]
	var f: Dictionary = CameraKeyframes.sample(track, 30)
	assert_eq(f["x"], 100.0, "the first keyframe at tick 30 wins on an exact hit (no divide-by-zero)")
	assert_eq(f["zoom"], 1.0, "...with its zoom, not the duplicate's")
