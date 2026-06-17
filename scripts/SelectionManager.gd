extends Node2D
## Mouse control for the player's army (team 0):
##   Left click        — select one friendly unit
##   Left click + drag — box-select friendly units
##   Right click       — move there, or attack the enemy unit clicked

const UnitRef = preload("res://scripts/Unit.gd")  # avoid global-class-cache dependency

const CLICK_THRESHOLD: float = 6.0

var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_cur: Vector2 = Vector2.ZERO
var _selected: Array = []

@onready var _hud = get_node_or_null("../HUD")
@onready var _battle = get_parent()


func _ready() -> void:
	z_index = 100   # draw the selection box over the units
	# Stay responsive during active pause: the player can survey, select, and
	# queue orders while the simulation is frozen (orders apply on resume).
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
			_issue_order(get_global_mouse_position())
	elif event is InputEventMouseMotion and _dragging:
		_drag_cur = get_global_mouse_position()
		queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		_issue_merge()   # merge the selected friendly regiments into one (#3)


func _finish_selection() -> void:
	_clear_selection()
	var rect := Rect2(_drag_start, _drag_cur - _drag_start).abs()

	if rect.size.length() < CLICK_THRESHOLD:
		var u = _unit_at(_drag_start, 0)
		if u != null:
			_select(u)
	else:
		for node in get_tree().get_nodes_in_group("units"):
			var unit = node as UnitRef
			if unit != null and unit.team == 0 and rect.has_point(unit.global_position):
				_select(unit)

	_refresh_hud()


func _issue_order(world_pos: Vector2) -> void:
	# Orders are replayed, so the player can't steer a playback.
	if Replay.mode == Replay.Mode.PLAYBACK:
		return
	if _selected.is_empty():
		return
	# Gather the selection as stable uids and hand the order to Battle, which
	# records it and applies it on the next physics tick (so live and replayed
	# orders take exactly the same code path). Selection and camera stay live —
	# only the simulation-affecting order is routed through the recorder.
	var enemy = _unit_at(world_pos, 1)
	var target_uid: int = -1
	if enemy != null:
		target_uid = enemy.uid
	else:
		# Right-clicking an engaged friendly that isn't part of the selection is a
		# line-relief order (#4): the selected unit swaps into its fight. Plain
		# ground stays an ordinary move.
		var friend = _unit_at(world_pos, 0)
		if friend != null and friend.state == UnitRef.State.FIGHTING and not _selected.has(friend):
			target_uid = friend.uid
	var uids: Array = []
	for unit in _selected:
		if is_instance_valid(unit):
			uids.append(unit.uid)
	if uids.is_empty():
		return
	_battle.enqueue_order(uids, world_pos, target_uid)


## Merge the selected friendly regiments into the first-selected one (#3). Encoded
## as an order whose target is the primary uid — which IS in `units`, so Battle
## tells it apart from a relief (whose target is a friendly outside the selection).
func _issue_merge() -> void:
	if Replay.mode == Replay.Mode.PLAYBACK:
		return
	var uids: Array = []
	for unit in _selected:
		if is_instance_valid(unit):
			uids.append(unit.uid)
	if uids.size() < 2:
		return   # need at least two regiments to merge
	_battle.enqueue_order(uids, Vector2.ZERO, uids[0])


# --- helpers ---------------------------------------------------------------

func _unit_at(world_pos: Vector2, team: int) -> UnitRef:
	# Nearest unit on `team` under the cursor (callers pass whichever team they
	# want — the player's own for selection, the enemy's for attack orders).
	var best = null
	var best_d: float = UnitRef.RADIUS + 6.0
	for node in get_tree().get_nodes_in_group("units"):
		var unit = node as UnitRef
		if unit == null:
			continue
		if unit.team != team:
			continue
		var d: float = unit.global_position.distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = unit
	return best


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
	# Drop any units that died/routed out of the selection.
	var live: Array = []
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
