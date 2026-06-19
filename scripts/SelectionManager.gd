extends Node2D
## Mouse control for the player's army (team 0):
##   Left click        — select one friendly unit
##   Left click + drag — box-select friendly units
##   Right click       — move there, or attack the enemy unit clicked

const UnitRef = preload("res://scripts/Unit.gd")  # avoid global-class-cache dependency
const BattleRef = preload("res://scripts/Battle.gd")  # for the waypoint-append sentinel (#34)

const CLICK_THRESHOLD: float = 6.0
const DOUBLE_CLICK_MS: int = 350

# Order-overlay colours (Total War convention: green = move, red = attack).
const ORDER_MOVE_COLOR: Color = Color(0.45, 0.95, 0.55, 0.9)
const ORDER_ATTACK_COLOR: Color = Color(0.96, 0.40, 0.32, 0.95)

var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_cur: Vector2 = Vector2.ZERO
var _selected: Array = []
# Tracks whether the order overlay was visible last frame (Space held to survey
# all orders), so it's redrawn one final time after Space is released — wiping
# the last frame's order lines.
var _was_showing_orders: bool = false

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
			# Shift+right-click appends a waypoint to the route instead of replacing
			# it, so a march can be plotted as a multi-leg path (#34).
			_issue_order(get_global_mouse_position(), event.shift_pressed)
	elif event is InputEventMouseMotion and _dragging:
		_drag_cur = get_global_mouse_position()
		queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			_issue_merge()   # merge the selected friendly regiments into one (#3)
		else:
			_handle_group_key(event)   # Ctrl+<0-9> bind / <0-9> recall (#11)


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


## Two units are the "same type" when their cavalry/anti-cavalry/ranged roles
## match (Infantry / Spearmen / Cavalry / Archers), regardless of name or stats.
func _same_type(a, b) -> bool:
	return a.is_cavalry == b.is_cavalry and a.anti_cavalry == b.anti_cavalry \
			and a.is_ranged == b.is_ranged


func _issue_order(world_pos: Vector2, append: bool = false) -> void:
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
		var friend: UnitRef = _unit_at(world_pos, 0)
		if friend != null and friend.state == UnitRef.State.FIGHTING and not _selected.has(friend):
			target_uid = friend.uid
		elif append:
			# Shift on plain ground queues a waypoint (#34); the sentinel rides the
			# target field so Battle appends instead of replacing the route. Append
			# is ignored when the click resolves to an attack or relief target.
			target_uid = BattleRef.ORDER_APPEND_WAYPOINT
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
		# A unit that died this frame is still valid and in the group until
		# queue_free() prunes it; skip it so a click on its last position can't
		# select/target a dead node — matching box-select, type-select and the
		# control-group recall guards.
		if unit == null or unit.state == UnitRef.State.DEAD:
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
	# Order overlays only render while Space is held (see _draw_orders), so redraw
	# while it's held to track marching units, plus one extra frame after release
	# to wipe the last frame's lines. Selection alone draws nothing here.
	var showing_orders := Input.is_key_pressed(KEY_SPACE)
	if showing_orders or _was_showing_orders:
		queue_redraw()
	_was_showing_orders = showing_orders


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
	_draw_orders()
	if not _dragging:
		return
	var rect := Rect2(_drag_start, _drag_cur - _drag_start).abs()
	draw_rect(rect, Color(0.4, 0.9, 0.4, 0.15))
	draw_rect(rect, Color(0.5, 1.0, 0.5, 0.9), false, 1.5)


## Draw units' current orders on the field (Total War style): a dashed line to
## each unit's destination or to the enemy it's attacking, with a marker at the
## far end. SelectionManager sits at the world origin with no parent transform —
## the same assumption the drag-box selection relies on — so unit world
## positions can be drawn directly in _draw()'s local space.
##
## Orders are a "hold to reveal" survey aid: shown for all of the player's units
## while Space is held (works paused too, since this node is PROCESS_MODE_ALWAYS;
## P or Shift+Space toggles pause). Enemy (team 1) orders are revealed only during
## replay playback — in live play the enemy's intentions stay hidden.
func _draw_orders() -> void:
	if not Input.is_key_pressed(KEY_SPACE):
		return
	var show_enemy: bool = Replay.mode == Replay.Mode.PLAYBACK
	for node in get_tree().get_nodes_in_group("units"):
		var u = node as UnitRef
		# A unit that dies mid-march stays valid (and keeps has_move_target) for a
		# frame before queue_free() prunes it; skip it so it doesn't flash a stale
		# order line — consistent with order_summary()'s DEAD skip.
		if u == null or not is_instance_valid(u) or u.state == UnitRef.State.DEAD:
			continue
		if u.team != 0 and not show_enemy:
			continue
		var origin: Vector2 = u.global_position
		# Only a player-issued attack (stored in target_enemy) draws a red line. A
		# unit auto-fighting its nearest foe has no stored target, so it draws no
		# line — matching order_summary() reporting "Engaged" with no destination.
		var tgt = u.target_enemy
		if tgt != null and is_instance_valid(tgt) \
				and tgt.state != UnitRef.State.DEAD and tgt.state != UnitRef.State.ROUTING:
			var tp: Vector2 = tgt.global_position
			draw_dashed_line(origin, tp, ORDER_ATTACK_COLOR, 2.0, 9.0)
			_draw_attack_marker(tp, ORDER_ATTACK_COLOR)
		elif u.has_move_target:
			_draw_move_path(origin, u.move_target, u.waypoints)


## Draw a unit's full move route (#34): a dashed line from the unit through its
## current move_target and each queued waypoint, a small dot at every intermediate
## stop, and the destination ring at the final point. With no waypoints this is the
## original single dashed segment to the destination.
func _draw_move_path(origin: Vector2, first: Vector2, waypoints: Array[Vector2]) -> void:
	var prev: Vector2 = origin
	var point: Vector2 = first
	for i in range(waypoints.size() + 1):
		draw_dashed_line(prev, point, ORDER_MOVE_COLOR, 2.0, 9.0)
		if i < waypoints.size():
			draw_circle(point, 3.0, ORDER_MOVE_COLOR)   # intermediate waypoint dot
			prev = point
			point = waypoints[i]
	_draw_move_marker(point, ORDER_MOVE_COLOR)           # final destination ring


## Destination marker: a small ring with a centre dot.
func _draw_move_marker(p: Vector2, color: Color) -> void:
	draw_arc(p, 8.0, 0.0, TAU, 18, color, 2.0)
	draw_circle(p, 2.5, color)


## Attack marker: a crosshair over the targeted enemy.
func _draw_attack_marker(p: Vector2, color: Color) -> void:
	var r := 11.0
	draw_arc(p, r, 0.0, TAU, 22, color, 2.0)
	draw_line(p + Vector2(-r - 3.0, 0.0), p + Vector2(r + 3.0, 0.0), color, 2.0)
	draw_line(p + Vector2(0.0, -r - 3.0), p + Vector2(0.0, r + 3.0), color, 2.0)
