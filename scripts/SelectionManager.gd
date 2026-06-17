extends Node2D
## Mouse control for the player's army (team 0):
##   Left click        — select one friendly unit
##   Left click + drag — box-select friendly units
##   Right click       — move there, or attack the enemy unit clicked

const UnitRef = preload("res://scripts/Unit.gd")  # avoid global-class-cache dependency

const CLICK_THRESHOLD: float = 6.0
const DOUBLE_CLICK_MS: int = 350

var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_cur: Vector2 = Vector2.ZERO
var _selected: Array = []

# Double-click type-select: the last clicked unit and when (ms).
var _last_click_unit = null
var _last_click_ms: int = -100000
# Control groups: number-key digit -> bound Array of units.
var _groups: Dictionary = {}

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
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_group_key(event)


func _finish_selection() -> void:
	_clear_selection()
	var rect := Rect2(_drag_start, _drag_cur - _drag_start).abs()

	if rect.size.length() < CLICK_THRESHOLD:
		_finish_click(_unit_at(_drag_start, 0))
	else:
		for node in get_tree().get_nodes_in_group("units"):
			var unit = node as UnitRef
			if unit == null or unit.team != 0 or unit.state == UnitRef.State.DEAD:
				continue
			if rect.has_point(unit.global_position):
				_select(unit)
		_last_click_unit = null   # a box-select breaks any double-click streak

	_refresh_hud()


## Resolve a single left-click: a second click on the same unit within the
## double-click window selects every visible friendly of that type; otherwise it
## is an ordinary single select.
func _finish_click(u) -> void:
	var now: int = Time.get_ticks_msec()
	if u != null and u == _last_click_unit and now - _last_click_ms <= DOUBLE_CLICK_MS:
		_select_same_type(u)
		_last_click_unit = null   # consume, so a third click starts a fresh streak
		return
	if u == null:
		_last_click_unit = null   # click on empty space ends any streak
		return
	_select(u)
	_last_click_unit = u
	_last_click_ms = now


## Select every alive friendly (team 0) unit sharing the prototype's type.
func _select_same_type(proto) -> void:
	for node in get_tree().get_nodes_in_group("units"):
		var unit = node as UnitRef
		if unit == null or unit.team != 0 or unit.state == UnitRef.State.DEAD:
			continue
		if _same_type(unit, proto):
			_select(unit)


## Two units are the "same type" when their cavalry/anti-cavalry roles match
## (Infantry / Spearmen / Cavalry), regardless of name or stats.
func _same_type(a, b) -> bool:
	return a.is_cavalry == b.is_cavalry and a.anti_cavalry == b.anti_cavalry


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
	var uids: Array = []
	for unit in _selected:
		if is_instance_valid(unit):
			uids.append(unit.uid)
	if uids.is_empty():
		return
	_battle.enqueue_order(uids, world_pos, enemy.uid if enemy != null else -1)


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


# --- control groups --------------------------------------------------------

## Ctrl+<0-9> binds the current selection to that group; <0-9> alone recalls it.
func _handle_group_key(event: InputEventKey) -> void:
	var n: int = _digit_for_keycode(event.keycode)
	if n < 0:
		return
	if event.ctrl_pressed:
		_bind_group(n)
	else:
		_recall_group(n)


## Map the number-row keycodes KEY_0..KEY_9 to 0..9; -1 for anything else.
func _digit_for_keycode(keycode: Key) -> int:
	if keycode >= KEY_0 and keycode <= KEY_9:
		return keycode - KEY_0
	return -1


## Bind the current selection to a control group (a snapshot of live members).
func _bind_group(n: int) -> void:
	var members: Array = []
	for u in _selected:
		if is_instance_valid(u) and u.state != UnitRef.State.DEAD:
			members.append(u)
	_groups[n] = members


## Replace the selection with a control group's still-alive members.
func _recall_group(n: int) -> void:
	if not _groups.has(n):
		return
	_clear_selection()
	for u in _groups[n]:
		if is_instance_valid(u) and u.state != UnitRef.State.DEAD:
			_select(u)
	_refresh_hud()


func _draw() -> void:
	if not _dragging:
		return
	var rect := Rect2(_drag_start, _drag_cur - _drag_start).abs()
	draw_rect(rect, Color(0.4, 0.9, 0.4, 0.15))
	draw_rect(rect, Color(0.5, 1.0, 0.5, 0.9), false, 1.5)
