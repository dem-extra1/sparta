extends Node2D
## Mouse control for team 0: click/drag to select, RMB to move or attack.

const SelectionUtils := preload("res://scripts/SelectionUtils.gd")
const CLICK_THRESHOLD: float = 6.0

var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_cur: Vector2 = Vector2.ZERO
var _selected: Array = []

@onready var _hud = get_node_or_null("../HUD")


func _ready() -> void:
	z_index = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_start = get_global_mouse_position()
				_drag_cur = _drag_start
			else:
				_dragging = false
				_finish_selection()
				queue_redraw()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			SelectionUtils.issue_order(_selected, get_global_mouse_position(), get_tree())
	elif event is InputEventMouseMotion and _dragging:
		_drag_cur = get_global_mouse_position()
		queue_redraw()

func _finish_selection() -> void:
	_clear_selection()
	var rect := Rect2(_drag_start, _drag_cur - _drag_start).abs()
	if rect.size.length_squared() < CLICK_THRESHOLD * CLICK_THRESHOLD:
		var u = SelectionUtils.unit_at(_drag_start, 0, get_tree())
		if u != null:
			_select(u)
	else:
		for u in SelectionUtils.box_select(rect, get_tree()):
			_select(u)
	_refresh_hud()

func _select(u) -> void:
	u.selected = true
	u.queue_redraw()
	_selected.append(u)

func _clear_selection() -> void:
	for u in _selected:
		if is_instance_valid(u):
			u.selected = false
			u.queue_redraw()
	_selected.clear()

func _refresh_hud() -> void:
	if _hud == null:
		return
	_selected = _selected.filter(func(u): return is_instance_valid(u))
	if _selected.is_empty():
		_hud.clear_unit()
	else:
		_hud.show_unit(_selected[0], _selected.size())

func _process(_delta: float) -> void:
	_refresh_hud()

func _draw() -> void:
	if not _dragging:
		return
	var rect := Rect2(_drag_start, _drag_cur - _drag_start).abs()
	draw_rect(rect, Color(0.4, 0.9, 0.4, 0.15))
	draw_rect(rect, Color(0.5, 1.0, 0.5, 0.9), false, 1.5)
