extends GutTest
## Tests for CameraController gesture input: two-finger pan, pinch zoom, and wheel zoom.

func _make_camera() -> CameraController:
	var cam: CameraController = CameraController.new()
	add_child_autofree(cam)
	cam.bounds = Rect2(0, 0, 1600, 1000)
	cam.position = Vector2(800, 500)   # center of bounds
	return cam


func test_pan_gesture_moves_camera() -> void:
	var cam := _make_camera()
	var before := cam.position
	var event := InputEventPanGesture.new()
	event.delta = Vector2(10, 0)   # swipe right
	cam._unhandled_input(event)
	assert_gt(cam.position.x, before.x,
		"a rightward pan gesture moves the camera in +x")


func test_pan_gesture_is_zoom_adjusted() -> void:
	var cam := _make_camera()
	cam.zoom = Vector2(2.0, 2.0)   # zoomed in
	var before := cam.position
	var event := InputEventPanGesture.new()
	event.delta = Vector2(10, 0)
	cam._unhandled_input(event)
	var zoomed_move: float = cam.position.x - before.x

	cam.position = before
	cam.zoom = Vector2(1.0, 1.0)
	cam._unhandled_input(event)
	var normal_move: float = cam.position.x - before.x

	assert_lt(zoomed_move, normal_move,
		"the same gesture delta moves less world distance when zoomed in")


func test_magnify_gesture_zooms_in() -> void:
	var cam := _make_camera()
	var before_zoom := cam.zoom.x
	var event := InputEventMagnifyGesture.new()
	event.factor = 1.2   # spread = zoom in
	cam._unhandled_input(event)
	assert_gt(cam.zoom.x, before_zoom,
		"a magnify factor > 1 increases zoom")


func test_magnify_gesture_zooms_out() -> void:
	var cam := _make_camera()
	var before_zoom := cam.zoom.x
	var event := InputEventMagnifyGesture.new()
	event.factor = 0.8   # pinch = zoom out
	cam._unhandled_input(event)
	assert_lt(cam.zoom.x, before_zoom,
		"a magnify factor < 1 decreases zoom")


func test_zoom_clamped_at_max() -> void:
	var cam := _make_camera()
	var event := InputEventMagnifyGesture.new()
	event.factor = 100.0   # extreme spread
	cam._unhandled_input(event)
	# Camera2D stores zoom as float32 internally; allow a tiny rounding error.
	assert_almost_eq(cam.zoom.x, cam.zoom_max, 0.001,
		"zoom is clamped to zoom_max")


func test_zoom_clamped_at_min() -> void:
	var cam := _make_camera()
	var event := InputEventMagnifyGesture.new()
	event.factor = 0.001   # extreme pinch
	cam._unhandled_input(event)
	assert_almost_eq(cam.zoom.x, cam.zoom_min, 0.001,
		"zoom is clamped to zoom_min")


func test_pan_clamped_to_bounds() -> void:
	var cam := _make_camera()
	cam.position = Vector2(1590, 500)   # near right edge
	var event := InputEventPanGesture.new()
	event.delta = Vector2(1000, 0)   # huge rightward swipe
	cam._unhandled_input(event)
	assert_lte(cam.position.x, cam.bounds.position.x + cam.bounds.size.x,
		"pan cannot exceed the right bound")


func test_pan_clamped_to_bounds_y() -> void:
	var cam := _make_camera()
	cam.position = Vector2(800, 990)   # near bottom edge
	var event := InputEventPanGesture.new()
	event.delta = Vector2(0, 1000)   # huge downward swipe
	cam._unhandled_input(event)
	assert_lte(cam.position.y, cam.bounds.position.y + cam.bounds.size.y,
		"pan cannot exceed the bottom bound")


func test_pinch_anchors_on_gesture_position() -> void:
	var cam := _make_camera()
	cam.zoom = Vector2(1.0, 1.0)
	# Use a gesture position offset from center so the anchor matters.
	var gesture_pos := Vector2(200.0, 150.0)
	var vp_center: Vector2 = cam.get_viewport().get_visible_rect().size * 0.5
	var world_before: Vector2 = cam.position + (gesture_pos - vp_center) / cam.zoom.x
	var event := InputEventMagnifyGesture.new()
	event.position = gesture_pos
	event.factor = 2.0   # zoom in
	cam._unhandled_input(event)
	var world_after: Vector2 = cam.position + (gesture_pos - vp_center) / cam.zoom.x
	assert_almost_eq(world_after.x, world_before.x, 0.01,
		"pinch anchor keeps the X world coordinate fixed under the gesture")
	assert_almost_eq(world_after.y, world_before.y, 0.01,
		"pinch anchor keeps the Y world coordinate fixed under the gesture")


func test_wheel_zoom_anchors_on_cursor() -> void:
	var cam := _make_camera()
	cam.zoom = Vector2(1.0, 1.0)
	# Cursor offset from center so anchor drift would be visible.
	var cursor_pos := Vector2(300.0, 100.0)
	var vp_center: Vector2 = cam.get_viewport().get_visible_rect().size * 0.5
	var world_before: Vector2 = cam.position + (cursor_pos - vp_center) / cam.zoom.x
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	event.position = cursor_pos
	cam._unhandled_input(event)
	var world_after: Vector2 = cam.position + (cursor_pos - vp_center) / cam.zoom.x
	assert_almost_eq(world_after.x, world_before.x, 0.01,
		"wheel zoom anchors the world X coordinate under the cursor")
	assert_almost_eq(world_after.y, world_before.y, 0.01,
		"wheel zoom anchors the world Y coordinate under the cursor")


func test_wheel_zoom_down_anchors_on_cursor() -> void:
	var cam := _make_camera()
	cam.zoom = Vector2(1.0, 1.0)
	var cursor_pos := Vector2(300.0, 100.0)
	var vp_center: Vector2 = cam.get_viewport().get_visible_rect().size * 0.5
	var world_before: Vector2 = cam.position + (cursor_pos - vp_center) / cam.zoom.x
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	event.position = cursor_pos
	cam._unhandled_input(event)
	var world_after: Vector2 = cam.position + (cursor_pos - vp_center) / cam.zoom.x
	assert_almost_eq(world_after.x, world_before.x, 0.01,
		"wheel-down zoom anchors the world X coordinate under the cursor")
	assert_almost_eq(world_after.y, world_before.y, 0.01,
		"wheel-down zoom anchors the world Y coordinate under the cursor")


func test_input_yields_while_a_presentation_track_drives_the_camera() -> void:
	# During playback of a replay with a camera track, Battle drives the camera, so the
	# controller must ignore pan/zoom input rather than fight the recorded framing.
	var cam := _make_camera()
	var before := cam.position
	Replay.mode = Replay.Mode.PLAYBACK
	Replay.drive_camera = true
	Replay._camera_track = [{"tick": 0, "x": 0.0, "y": 0.0, "zoom": 1.0}]
	var event := InputEventPanGesture.new()
	event.delta = Vector2(50, 0)
	cam._unhandled_input(event)
	assert_eq(cam.position, before, "input is ignored while a presentation track drives the camera")
	# A plain replay (drive_camera off) keeps manual control even with a track loaded.
	Replay.drive_camera = false
	cam._unhandled_input(event)
	assert_gt(cam.position.x, before.x, "input still pans when the camera isn't presentation-driven")
	# Restore the shared Replay autoload so other tests see a clean state.
	Replay._camera_track = []
	Replay.reset()
