extends GutTest
## Tests for CameraController gesture input: two-finger pan and pinch zoom.

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
