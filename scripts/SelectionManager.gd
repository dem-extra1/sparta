extends Node2D
## Mouse control for the player's army (team 0):
##   Left click        — select one friendly unit
##   Left click + drag — box-select friendly units
##   Right click       — move there, or attack the enemy unit clicked

const UnitRef = preload("res://scripts/Unit.gd")  # avoid global-class-cache dependency

const CLICK_THRESHOLD: float = 6.0

# Order-overlay colours (Total War convention: green = move, red = attack).
const ORDER_MOVE_COLOR: Color = Color(0.45, 0.95, 0.55, 0.9)
const ORDER_ATTACK_COLOR: Color = Color(0.96, 0.40, 0.32, 0.95)

var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_cur: Vector2 = Vector2.ZERO
var _selected: Array = []
# Tracks the overlay-visible state last frame (anything selected, or Space held
# to survey all orders), so the overlay is redrawn one final time after that
# clears — wiping the last frame's order lines.
var _had_selection: bool = false
var _was_showing_orders: bool = false

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
	# Order overlays track units as they march, so redraw while anything is
	# selected or while the player holds Space to survey all orders; one extra
	# redraw the frame after either clears wipes the stale lines.
	var has_selection := not _selected.is_empty()
	var showing_orders := Input.is_key_pressed(KEY_SPACE)
	if has_selection or showing_orders or _had_selection or _was_showing_orders:
		queue_redraw()
	_had_selection = has_selection
	_was_showing_orders = showing_orders


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
## P or Ctrl+Space toggles pause). Enemy (team 1) orders are revealed only during
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
			var mp: Vector2 = u.move_target
			draw_dashed_line(origin, mp, ORDER_MOVE_COLOR, 2.0, 9.0)
			_draw_move_marker(mp, ORDER_MOVE_COLOR)


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
