extends Node2D
## Mouse control for the player's army (team 0):
##   Left click        — select one friendly unit
##   Left click + drag — box-select friendly units
##   Right click       — move there, or attack the enemy unit clicked

const CLICK_THRESHOLD: float = 6.0

var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_cur: Vector2 = Vector2.ZERO
var _selected: Array[Unit] = []

@onready var _hud = get_node_or_null("../HUD")


func _ready() -> void:
	z_index = 100   # draw the selection box over the units


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
			_issue_order(get_global_mouse_position())
	elif event is InputEventMouseMotion and _dragging:
		_drag_cur = get_global_mouse_position()
		queue_redraw()


func _finish_selection() -> void:
	_clear_selection()
	var rect := Rect2(_drag_start, _drag_cur - _drag_start).abs()

	if rect.size.length() < CLICK_THRESHOLD:
		var u := _unit_at(_drag_start, 0, true)
		if u != null:
			_select(u)
	else:
		for node in get_tree().get_nodes_in_group("units"):
			var unit: Unit = node as Unit
			if unit != null and unit.team == 0 and rect.has_point(unit.position):
				_select(unit)

	_refresh_hud()


func _issue_order(world_pos: Vector2) -> void:
	if _selected.is_empty():
		return
	var enemy := _unit_at(world_pos, 1, false)
	var i: int = 0
	for unit in _selected:
		if not is_instance_valid(unit):
			continue
		if enemy != null:
			unit.target_enemy = enemy
			unit.has_move_target = false
		else:
			# Spread the destination so units don't pile onto one point.
			var cols: int = 4
			var off := Vector2((i % cols) * 42 - 63, (i / cols) * 42)
			unit.move_target = world_pos + off
			unit.has_move_target = true
			unit.target_enemy = null
		i += 1


# --- helpers ---------------------------------------------------------------

func _unit_at(world_pos: Vector2, team_filter: int, friendly: bool) -> Unit:
	# friendly=true matches team_filter; friendly=false matches that enemy team.
	var best: Unit = null
	var best_d: float = Unit.RADIUS + 6.0
	for node in get_tree().get_nodes_in_group("units"):
		var unit: Unit = node as Unit
		if unit == null:
			continue
		if friendly and unit.team != team_filter:
			continue
		if not friendly and unit.team != team_filter:
			continue
		var d: float = unit.position.distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = unit
	return best


func _select(u: Unit) -> void:
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
	# Drop any units that died/routed out of the selection.
	var live: Array[Unit] = []
	for u in _selected:
		if is_instance_valid(u):
			live.append(u)
	_selected = live
	if _selected.is_empty():
		_hud.clear_unit()
	else:
		_hud.show_unit(_selected[0], _selected.size())


func _process(_delta: float) -> void:
	# Keep the panel current as the shown unit takes casualties.
	_refresh_hud()


func _draw() -> void:
	if not _dragging:
		return
	var rect := Rect2(_drag_start, _drag_cur - _drag_start).abs()
	draw_rect(rect, Color(0.4, 0.9, 0.4, 0.15))
	draw_rect(rect, Color(0.5, 1.0, 0.5, 0.9), false, 1.5)
