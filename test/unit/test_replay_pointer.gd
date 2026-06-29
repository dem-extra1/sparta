extends GutTest
## Tests for the Replay pointer track: recording the cursor / selection / drag-box /
## stance with dedup, playback stepping, order click-pulses, save/load round-trip, and
## back-compat with replays that have no pointer track.

const ReplayScript = preload("res://scripts/Replay.gd")


func _fresh() -> Node:
	var r: Node = ReplayScript.new()
	add_child_autofree(r)
	return r


func test_record_pointer_dedups_a_still_pointer() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_pointer(0, Vector2(100, 100), false, Vector2.ZERO, [], 0)
	r.record_pointer(1, Vector2(100, 100), false, Vector2.ZERO, [], 0)   # unchanged -> dropped
	r.record_pointer(2, Vector2(101, 100), false, Vector2.ZERO, [], 0)   # < EPS move -> dropped
	r.record_pointer(3, Vector2(140, 100), false, Vector2.ZERO, [], 0)   # real move -> kept
	assert_eq(r._pointer_track.size(), 2,
			"a still (or sub-EPS) pointer dedups; a real move adds a keyframe")
	assert_true(r.has_pointer_track(), "a recorded track reports present")


func test_record_pointer_is_noop_outside_record() -> void:
	var r := _fresh()   # IDLE
	r.record_pointer(0, Vector2(10, 10), false, Vector2.ZERO, [], 0)
	assert_eq(r._pointer_track.size(), 0, "no pointer captured outside RECORD")
	assert_false(r.has_pointer_track(), "no track without recording")


func test_record_pointer_keeps_keyframe_when_selection_changes() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_pointer(0, Vector2(50, 50), false, Vector2.ZERO, [1], 0)
	r.record_pointer(1, Vector2(50, 50), false, Vector2.ZERO, [1, 2], 0)   # selection grew
	assert_eq(r._pointer_track.size(), 2, "a selection change is a new keyframe even if the cursor is still")


func test_record_pointer_keeps_keyframe_when_mode_or_drag_changes() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_pointer(0, Vector2(50, 50), false, Vector2.ZERO, [], 0)
	r.record_pointer(1, Vector2(50, 50), false, Vector2.ZERO, [], 1)         # stance armed
	r.record_pointer(2, Vector2(50, 50), true, Vector2(50, 50), [], 1)       # drag opened
	assert_eq(r._pointer_track.size(), 3, "a stance change and a drag open each add a keyframe")


func test_record_pointer_stores_drag_corner_only_while_dragging() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_pointer(0, Vector2(10, 10), false, Vector2.ZERO, [], 0)
	r.record_pointer(1, Vector2(80, 80), true, Vector2(10, 10), [], 0)
	assert_false(r._pointer_track[0].has("sx"), "no drag -> no drag corner stored")
	assert_eq(r._pointer_track[1]["sx"], 10.0, "a drag stores its start corner")


func test_pointer_for_tick_holds_last_keyframe() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._pointer_track = [
		{"tick": 0, "x": 0.0, "y": 0.0, "drag": false, "sel": [], "mode": 0},
		{"tick": 10, "x": 100.0, "y": 0.0, "drag": false, "sel": [3], "mode": 2},
	]
	assert_eq(r.pointer_for_tick(0)["x"], 0.0, "tick 0 uses the first keyframe")
	assert_eq(r.pointer_for_tick(5)["x"], 0.0, "between keyframes it holds the earlier one")
	assert_eq(r.pointer_for_tick(10)["mode"], 2, "at the next keyframe's tick it switches")
	assert_eq(r.pointer_for_tick(99)["x"], 100.0, "past the last keyframe it holds the last")


func test_pointer_for_tick_rewinds_on_step_back() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._pointer_track = [
		{"tick": 0, "x": 0.0, "y": 0.0, "drag": false, "sel": [], "mode": 0},
		{"tick": 10, "x": 100.0, "y": 0.0, "drag": false, "sel": [], "mode": 0},
	]
	assert_eq(r.pointer_for_tick(10)["x"], 100.0, "advance the cursor")
	assert_eq(r.pointer_for_tick(0)["x"], 0.0, "a step back rewinds to the first keyframe")


func test_pointer_for_tick_empty_without_track_or_playback() -> void:
	var r := _fresh()   # IDLE, no track
	assert_eq(r.pointer_for_tick(0), {}, "no track / not playing back -> empty")


func test_cursor_interpolates_between_keyframes() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._pointer_track = [
		{"tick": 0, "x": 0.0, "y": 0.0, "drag": false, "sel": [], "mode": 0},
		{"tick": 10, "x": 100.0, "y": 0.0, "drag": false, "sel": [], "mode": 0},
	]
	assert_eq(r.pointer_cursor_for_tick(0), Vector2(0, 0), "at the first keyframe")
	assert_almost_eq(r.pointer_cursor_for_tick(5).x, 50.0, 0.001, "halfway glides to the midpoint")
	assert_almost_eq(r.pointer_cursor_for_tick(8).x, 80.0, 0.001, "four-fifths of the way")
	assert_eq(r.pointer_cursor_for_tick(10), Vector2(100, 0), "at the next keyframe")
	assert_eq(r.pointer_cursor_for_tick(20), Vector2(100, 0), "past the last keyframe it holds the last")


func test_cursor_is_zero_without_track_or_playback() -> void:
	var r := _fresh()   # IDLE
	assert_eq(r.pointer_cursor_for_tick(0), Vector2.ZERO, "no track / not playing back -> zero")


func test_cursor_for_tick_rewinds_on_step_back() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._pointer_track = [
		{"tick": 0, "x": 0.0, "y": 0.0, "drag": false, "sel": [], "mode": 0},
		{"tick": 10, "x": 100.0, "y": 0.0, "drag": false, "sel": [], "mode": 0},
	]
	assert_eq(r.pointer_cursor_for_tick(10), Vector2(100, 0), "advance the cursor to the later keyframe")
	assert_almost_eq(r.pointer_cursor_for_tick(5).x, 50.0, 0.001,
			"a step back rewinds and re-interpolates from the first keyframe")


func test_pulses_return_recent_orders_with_age() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._orders = [
		{"tick": 10, "x": 1.0, "y": 2.0},
		{"tick": 25, "x": 3.0, "y": 4.0},
		{"tick": 60, "x": 5.0, "y": 6.0},
	]
	var pulses: Array = r.pulses_for_tick(30, 30)   # window covers ticks 0..30
	assert_eq(pulses.size(), 2, "orders within the window (10, 25) pulse; the future one (60) does not")
	assert_eq(pulses[0]["age"], 20, "the tick-10 order is 20 ticks old at tick 30")
	assert_eq(pulses[1]["x"], 3.0, "the pulse carries the order's position")


func test_pulses_drop_orders_older_than_the_window() -> void:
	var r := _fresh()
	r.mode = ReplayScript.Mode.PLAYBACK
	r._orders = [{"tick": 5, "x": 1.0, "y": 1.0}]
	assert_eq(r.pulses_for_tick(100, 30).size(), 0, "an order beyond the window no longer pulses")


func test_save_load_round_trips_the_pointer_track() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_pointer(0, Vector2(10, 20), false, Vector2.ZERO, [7], 0)
	r.record_pointer(4, Vector2(80, 90), true, Vector2(10, 20), [7, 8], 3)
	var path: String = r.save("Test", 4)
	assert_ne(path, "", "the recording saves")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	assert_true(loaded.has_pointer_track(), "the pointer track survives save/load")
	var p: Dictionary = loaded.pointer_for_tick(4)
	assert_almost_eq(p["x"], 80.0, 0.0001, "cursor position round-trips")
	assert_eq(p["sel"], [7, 8], "selection uids round-trip")
	assert_eq(p["mode"], 3, "armed stance round-trips")
	assert_true(bool(p["drag"]), "drag flag round-trips")
	assert_almost_eq(p["sx"], 10.0, 0.0001, "drag start corner x round-trips")
	assert_almost_eq(p["sy"], 20.0, 0.0001, "drag start corner y round-trips")


func test_replay_without_pointer_has_no_track() -> void:
	var r := _fresh()
	r.start_recording()
	var path: String = r.save("Test", 0)
	assert_ne(path, "", "the recording saves even with no pointer track")

	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "it loads")
	assert_false(loaded.has_pointer_track(), "no pointer keyframes -> no track")
	assert_eq(loaded.pointer_for_tick(0), {}, "playback shows no cursor overlay")


# --- keystroke track (demo overlay) -----------------------

func test_record_keys_appends_only_when_pressed() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_keys(0, ["]"])
	r.record_keys(1, [])          # nothing pressed -> dropped
	r.record_keys(2, ["[", "T"])
	assert_eq(r._key_track.size(), 2, "only ticks with a keypress are recorded")
	assert_eq(r._key_track[1]["labels"], ["[", "T"], "all labels for a tick are kept")


func test_record_keys_is_noop_outside_record() -> void:
	var r := _fresh()   # IDLE
	r.record_keys(0, ["]"])
	assert_eq(r._key_track.size(), 0, "no keys captured outside RECORD")


func test_keys_for_tick_returns_recent_presses_with_age() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_keys(10, ["]"])
	r.record_keys(50, ["["])
	var path: String = r.save("Test", 60)
	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	# At tick 55 with a 42-tick window, only the tick-50 press is recent (age 5).
	var recent: Array = loaded.keys_for_tick(55, 42)
	assert_eq(recent.size(), 1, "the old keypress has aged out of the window")
	assert_eq(recent[0]["label"], "[", "the recent label is returned")
	assert_eq(recent[0]["age"], 5, "with its age in ticks")


func test_save_load_round_trips_the_keys_track() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_keys(3, ["]"])
	var path: String = r.save("Test", 3)
	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	assert_eq(loaded._key_track.size(), 1, "the keys track survives save/load")
	assert_eq(loaded._key_track[0]["labels"], ["]"], "labels round-trip")


func test_replay_without_keys_has_empty_track() -> void:
	var r := _fresh()
	r.start_recording()
	var path: String = r.save("Test", 0)
	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "it loads")
	assert_eq(loaded._key_track.size(), 0, "no keypresses -> no keys track")
	assert_eq(loaded.keys_for_tick(0, 42), [], "playback shows no key chips")


# --- form-up deploy facing in the order stream ----------

func test_record_order_round_trips_the_deploy_facing() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_order(5, [1], Vector2(300, 300), -1, 0, 0, 20, 1.5)   # form-up: frontage 20, face 1.5
	r.record_order(6, [1], Vector2(50, 0), -1)                     # plain move: no face
	var path: String = r.save("Test", 6)
	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var orders: Array = loaded._orders
	assert_almost_eq(float(orders[0]["face"]), 1.5, 0.0001, "a form-up order round-trips its facing")
	assert_eq(int(orders[0]["frontage"]), 20, "and its frontage")
	assert_false(orders[1].has("face"), "a plain move carries no facing")


func test_record_order_round_trips_group_attack_mode() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_order(5, [1, 2], Vector2(400, 400), 7, 0, 0, 0, INF, 1)   # distributed (1)
	r.record_order(6, [3], Vector2(50, 0), 8, 0, 0, 0, INF, 0)         # focused (0) -> omitted
	var path: String = r.save("Test", 6)
	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "the saved replay loads")
	var orders: Array = loaded._orders
	assert_eq(int(orders[0]["group_attack"]), 1, "a distributed attack order round-trips its mode")
	assert_false(orders[1].has("group_attack"), "a focused attack omits the field (back-compat)")


func test_form_ups_for_tick_returns_recent_deploys() -> void:
	var r := _fresh()
	r.start_recording()
	r.record_order(10, [1], Vector2(200, 300), -1, 0, 0, 18, 0.8)   # form-up
	r.record_order(12, [1], Vector2(50, 0), -1)                     # plain move (no face)
	var path: String = r.save("Test", 20)
	var loaded := _fresh()
	assert_true(loaded.start_playback(path), "loads")
	var due: Array = loaded.form_ups_for_tick(14, 30)
	assert_eq(due.size(), 1, "only the form-up order is a deploy gesture")
	assert_almost_eq(float(due[0]["face"]), 0.8, 0.0001, "carries its facing")
	assert_eq(int(due[0]["frontage"]), 18, "and its width")
	assert_eq(int(due[0]["age"]), 4, "with its age in ticks")
