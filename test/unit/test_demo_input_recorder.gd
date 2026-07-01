extends GutTest
## The scripted-input demo recorder's step → per-tick event expansion (tools/demo/
## DemoInputRecorder.gd). The live recording itself is integration-only, but the schedule
## that turns a demo input script into timed InputEvents is pure logic and worth pinning.

const RecorderScript = preload("res://tools/demo/DemoInputRecorder.gd")


func _rec():
	# new() (not add_child) so _ready — which would load the Battle scene — doesn't run; we
	# only exercise _schedule(), which populates _by_tick from the steps.
	var r = RecorderScript.new()
	autofree(r)
	return r


func test_click_expands_to_a_press_then_release_on_one_tick() -> void:
	var r = _rec()
	r._schedule([{"tick": 8, "click": [500, 300]}])
	var evs: Array = r._by_tick.get(8, [])
	assert_eq(evs.size(), 2, "a click is a press + a release")
	assert_eq(evs[0]["button"], MOUSE_BUTTON_LEFT, "left button")
	assert_true(evs[0]["pressed"], "press first")
	assert_false(evs[1]["pressed"], "then release")


func test_shift_click_sets_the_shift_modifier() -> void:
	var r = _rec()
	r._schedule([{"tick": 3, "shift_click": [500, 300]}])
	assert_true(r._by_tick[3][0]["shift"], "shift_click marks the event shifted")


func test_rmb_drag_expands_to_press_motions_release_across_ticks() -> void:
	var r = _rec()
	r._schedule([{"tick": 24, "rmb_drag": {"from": [800, 470], "to": [300, 470]}}])
	var span: int = RecorderScript.DRAG_TICKS
	# Press on the start tick.
	assert_eq(r._by_tick[24][0]["kind"], "mb", "press at the drag start tick")
	assert_eq(r._by_tick[24][0]["button"], MOUSE_BUTTON_RIGHT, "right button")
	assert_true(r._by_tick[24][0]["pressed"], "pressed")
	# A motion on an intermediate tick (so the drag passes the click threshold + animates).
	assert_eq(r._by_tick[25][0]["kind"], "motion", "motion follows the press")
	# Release on the final tick.
	var rel: Array = r._by_tick[24 + span]
	assert_eq(rel[0]["kind"], "mb", "release at start + DRAG_TICKS")
	assert_false(rel[0]["pressed"], "released")
	assert_eq(rel[0]["pos"], Vector2(300, 470), "release lands at the drag's end point")


func test_rmb_drag_shift_propagates_to_press_and_release() -> void:
	var r = _rec()
	r._schedule([{"tick": 5, "rmb_drag": {"from": [800, 470], "to": [300, 470], "shift": true}}])
	assert_true(r._by_tick[5][0]["shift"], "shift on the press")
	assert_true(r._by_tick[5 + RecorderScript.DRAG_TICKS][0]["shift"], "shift on the release")


func test_key_step_maps_to_a_keycode() -> void:
	var r = _rec()
	r._schedule([{"tick": 10, "key": "Y"}])
	assert_eq(r._by_tick[10][0]["kind"], "key", "a key step is a key event")
	assert_eq(r._by_tick[10][0]["keycode"], KEY_Y, "the key string resolves to its keycode")


func test_box_expands_to_a_left_drag() -> void:
	var r = _rec()
	r._schedule([{"tick": 5, "box": {"from": [100, 200], "to": [400, 500]}}])
	assert_eq(r._by_tick[5][0]["button"], MOUSE_BUTTON_LEFT, "box-select uses the left button")
	assert_true(r._by_tick[5][0]["pressed"], "press at the start tick")
	var rel: Array = r._by_tick[5 + RecorderScript.DRAG_TICKS]
	assert_false(rel[0]["pressed"], "release after DRAG_TICKS")
	assert_eq(rel[0]["pos"], Vector2(400, 500), "release lands at the box's end corner")


# --- capture/dump completion gate ------------------------------------------
# _all_artifacts_done() drives the quit of a capture/dump run; a state-only dump
# (no frames armed) must report done once every state tick is written, so the run
# quits instead of stalling. (The quit path itself skips the frame_post_draw await
# when no frames were captured, so a --headless state dump never hangs on it.)

func test_all_artifacts_done_false_when_nothing_is_armed() -> void:
	var r = _rec()
	assert_false(r._all_artifacts_done(),
		"a movie recording arms neither list, so it must not report done (or it would quit at once)")


func test_state_only_dump_is_done_when_every_state_tick_is_written() -> void:
	var r = _rec()
	r._state_ticks = [0, 60, 120]
	r._state_dumped = {}
	assert_false(r._all_artifacts_done(), "not done until every armed state tick is dumped")
	r._state_dumped = {0: true, 60: true, 120: true}
	assert_true(r._all_artifacts_done(),
		"a state-only dump reports done once all snapshots land, with no frames armed")
