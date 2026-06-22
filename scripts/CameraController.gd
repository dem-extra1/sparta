extends Camera2D
class_name CameraController
## RTS camera: WASD / arrow-keys or screen-edge to pan, mouse wheel to zoom.
## Two-finger swipe pans and pinch-to-zoom scales on trackpads.
## Bounds are clamped to the battlefield set by Battle.gd.

@export var pan_speed: float = 700.0
@export var edge_margin: float = 18.0
@export var zoom_min: float = 0.45
@export var zoom_max: float = 2.2
# Two-finger swipe sensitivity: world units per pixel of trackpad delta.
# Divided by zoom.x so the pan speed stays consistent across zoom levels.
const PAN_GESTURE_SENSITIVITY := 1.5

# Battlefield extents (world coords); Battle.gd overrides these.
var bounds: Rect2 = Rect2(0, 0, 1600, 1000)


func _ready() -> void:
	make_current()
	position = bounds.position + bounds.size * 0.5
	# Keep panning/zooming during active pause so the field can be surveyed
	# while issuing orders.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	var dir := Vector2.ZERO

	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1

	if Settings.edge_scroll:
		var m: Vector2 = get_viewport().get_mouse_position()
		var vp: Vector2 = get_viewport().get_visible_rect().size
		if m.x < edge_margin:
			dir.x -= 1
		elif m.x > vp.x - edge_margin:
			dir.x += 1
		if m.y < edge_margin:
			dir.y -= 1
		elif m.y > vp.y - edge_margin:
			dir.y += 1

	if dir != Vector2.ZERO:
		# Pan faster when zoomed out so it feels consistent.
		position += dir.normalized() * pan_speed * delta / zoom.x
		_clamp_position()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / 1.1)
	elif event is InputEventPanGesture:
		position += event.delta * PAN_GESTURE_SENSITIVITY / zoom.x
		_clamp_position()
	elif event is InputEventMagnifyGesture:
		var old_z: float = zoom.x
		_zoom_by(event.factor)
		# Anchor the zoom on the pinch midpoint: the world point under the
		# gesture stays fixed as zoom changes.
		var vp_center: Vector2 = get_viewport().get_visible_rect().size * 0.5
		var screen_offset: Vector2 = event.position - vp_center
		position += screen_offset / old_z - screen_offset / zoom.x
		_clamp_position()


func _zoom_by(factor: float) -> void:
	var z: float = clampf(zoom.x * factor, zoom_min, zoom_max)
	zoom = Vector2(z, z)


func _clamp_position() -> void:
	position.x = clampf(position.x, bounds.position.x, bounds.position.x + bounds.size.x)
	position.y = clampf(position.y, bounds.position.y, bounds.position.y + bounds.size.y)
