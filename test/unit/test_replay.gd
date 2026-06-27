extends GutTest
## Tests for the Replay presentation (camera) track: recording with dedup, playback
## stepping, save/load round-trip, and back-compat with replays that have no track.

const ReplayScript = preload("res://scripts/Replay.gd")


## A fresh, isolated Replay instance so tests never touch the live autoload's state.
func _fresh() -> Node:
	var r: Node = ReplayScript.new()
	add_child_autofree(r)
	return r


func test_record_camera_dedups_static_frames() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_camera(0, Vector2(100, 100), 1.0)
	r.record_camera(1, Vector2(100, 100), 1.0)   # unchanged -> dropped
	r.record_camera(2, Vector2(150, 100), 1.5)   # moved -> kept
	assert_eq(r._camera_track.size(), 2,
			"a still camera dedups to one keyframe; a move adds another")
	assert_true(r.has_camera_track(), "a recorded track reports present")


func test_record_camera_is_noop_outside_record() -> void:
	var r := _fresh()   # mode IDLE
	r.record_camera(0, Vector2(10, 10), 1.0)
	assert_eq(r._camera_track.size(), 0, "no camera is captured outside RECORD")
	assert_false(r.has_camera_track(), "no track without recording")


func test_camera_for_tick_holds_last_keyframe() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._camera_track = [
		{"tick": 0, "x": 0.0, "y": 0.0, "zoom": 1.0},
		{"tick": 10, "x": 100.0, "y": 0.0, "zoom": 2.0},
	]
	assert_eq(r.camera_for_tick(0)["zoom"], 1.0, "tick 0 uses the first keyframe")
	assert_eq(r.camera_for_tick(5)["zoom"], 1.0, "between keyframes it holds the earlier one")
	assert_eq(r.camera_for_tick(10)["x"], 100.0, "at the next keyframe's tick it switches")
	assert_eq(r.camera_for_tick(99)["x"], 100.0, "past the last keyframe it holds the last")


func test_camera_for_tick_before_first_keyframe_holds_first() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._camera_track = [{"tick": 5, "x": 7.0, "y": 8.0, "zoom": 1.5}]
	assert_eq(r.camera_for_tick(0)["x"], 7.0,
			"a tick before the first keyframe holds the first framing")


func test_camera_for_tick_rewinds_on_step_back() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._camera_track = [
		{"tick": 0, "x": 0.0, "y": 0.0, "zoom": 1.0},
		{"tick": 10, "x": 100.0, "y": 0.0, "zoom": 2.0},
	]
	assert_eq(r.camera_for_tick(10)["x"], 100.0, "advance the cursor to the later keyframe")
	assert_eq(r.camera_for_tick(0)["x"], 0.0, "a step back to tick 0 rewinds to the first keyframe")


func test_camera_for_tick_empty_without_track_or_playback() -> void:
	var r := _fresh()   # IDLE, no track
	assert_eq(r.camera_for_tick(0), {}, "no track / not playing back -> empty")


func test_save_load_round_trips_the_camera_track() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_camera(0, Vector2(10.0, 20.0), 0.8)
	r.record_camera(3, Vector2(40.0, 20.0), 1.2)
	var path: String = r.save("Test", 3)
	assert_ne(path, "", "the recording saves to a path")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	assert_true(loaded.has_camera_track(), "the camera track survives save/load")
	assert_almost_eq(loaded.camera_for_tick(0)["zoom"], 0.8, 0.0001, "zoom round-trips")
	assert_almost_eq(loaded.camera_for_tick(3)["x"], 40.0, 0.0001, "position round-trips")


func test_replay_without_camera_moves_has_no_track() -> void:
	# A recording that never moves (records) the camera omits the track entirely, so it
	# loads exactly like a pre-camera replay: no track, default static camera on playback.
	var r := _fresh()
	r.start_recording()
	var path: String = r.save("Test", 0)
	assert_ne(path, "", "the recording saves even with no camera track")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "it loads")
	assert_false(loaded.has_camera_track(), "no camera keyframes -> no presentation track")
	assert_eq(loaded.camera_for_tick(0), {}, "playback drives nothing -> static camera")
