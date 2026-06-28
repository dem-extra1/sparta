extends Node2D
class_name SelectionManager
## Mouse control for the player's army (team 0):
##   Left click        — select one friendly unit
##   Left click + drag — box-select friendly units
##   Right click       — move there, or attack the enemy unit clicked
##   Drag a flank grip — resize a single selected unit's frontage (line width)
##   [ / ]             — narrow / widen the selected units by one file

const UnitRef = preload("res://scripts/Unit.gd")  # avoid global-class-cache dependency
const BattleRef = preload("res://scripts/Battle.gd")  # for the waypoint-append sentinel

const CLICK_THRESHOLD: float = 6.0
const DOUBLE_CLICK_MS: int = 350
const CURSOR_SIZE: int = 24   # generated order-mode cursor

# Frontage resize grips: small squares on a singly-selected unit's flanks. Drag one
# to widen/narrow the line; the bracket keys do the same in single-file steps.
const RESIZE_HANDLE_GAP: float = 10.0     # px the grip sits outside the block extent
const RESIZE_HANDLE_SIZE: float = 6.0     # grip half-size (px)
const RESIZE_HANDLE_HIT: float = 13.0     # cursor radius that grabs a grip (px)
const RESIZE_HANDLE_COLOR: Color = Color(0.95, 0.95, 0.3, 0.9)   # match selection yellow

# Order-overlay colours (common RTS convention: green = move, red = attack). Teal marks
# a SUPPORT link — same hue as the SUPPORT order cursor (_order_mode_color).
const ORDER_MOVE_COLOR: Color = Color(0.45, 0.95, 0.55, 0.9)
const ORDER_ATTACK_COLOR: Color = Color(0.96, 0.40, 0.32, 0.95)
const ORDER_SUPPORT_COLOR: Color = Color(0.4, 0.95, 0.7, 0.9)

# Demo-pointer overlay (#247): a replay reproduces what the player did with the mouse.
const DEMO_CURSOR_COLOR: Color = Color(1.0, 1.0, 1.0, 0.95)
const DEMO_SELECT_COLOR: Color = Color(0.95, 0.95, 0.3, 0.9)   # match the live selection ring
const DEMO_PULSE_WINDOW: int = 30        # ticks an order's click-pulse lingers (~0.5 s at 60 Hz)
const DEMO_PULSE_BASE_R: float = 6.0     # pulse ring's starting radius (px)
const DEMO_PULSE_GROWTH: float = 0.9     # px the pulse ring expands per tick of age
const DEMO_KEY_WINDOW: int = 42          # ticks a pressed-key chip lingers (~0.7 s at 60 Hz)
const DEMO_KEY_COLOR: Color = Color(1.0, 1.0, 1.0, 0.95)   # key-chip text/border

var _cursor_canvas: CanvasLayer
var _cursor_sprite: Sprite2D
var _cursor_textures: Dictionary = {}   # mode int -> ImageTexture; cached to avoid redundant image allocs

var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_cur: Vector2 = Vector2.ZERO
# Frontage drag-resize: active while a flank grip of a single selected unit is held.
# _resize_files is the live target file count (drives the preview and the commit).
var _resizing: bool = false
var _resize_unit = null
var _resize_files: int = 0
# Gameplay-hotkey labels pressed since the last sim tick; Battle drains this each tick
# (take_keys_this_tick) into the replay's keystroke track for the demo overlay.
var _keys_this_tick: Array = []
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
# Armed order mode: the next right-click issues an order in this stance.
# Selected by hotkey (rebindable via ☰ Menu → Keybindings) and shown by the
# cursor + a HUD indicator. Stays armed (sticky) until changed or cleared (Esc).
var _armed_mode: int = BattleRef.OrderMode.NORMAL

# Deterministic cursor injection. Normally null (the cursor follows the live OS mouse). A
# demo-recording tool or a test sets a world position here so the selection/order logic and
# the recorded pointer track use that exact cursor instead of the hardware mouse -- which
# can't be driven headlessly (warp_mouse is ignored) without hijacking the shared system
# cursor. Cleared back to null to return to the real mouse. See _cursor_world().
var _cursor_override = null   # Variant: Vector2 when injected, else null

@onready var _hud = get_node_or_null("../HUD")
@onready var _battle = get_parent()


func _ready() -> void:
	z_index = 100   # draw the selection box over the units
	# Stay responsive during active pause: the player can survey, select, and
	# queue orders while the simulation is frozen (orders apply on resume).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cursor_canvas = CanvasLayer.new()
	_cursor_canvas.layer = 127
	add_child(_cursor_canvas)
	_cursor_sprite = Sprite2D.new()
	_cursor_sprite.centered = true
	_cursor_sprite.visible = false
	_cursor_canvas.add_child(_cursor_sprite)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# A press on a selected unit's flank grip starts a frontage resize;
				# anywhere else begins the usual box-select drag.
				var grip = _resize_handle_at(_cursor_world())
				if grip != null:
					_begin_resize(grip)
				else:
					_dragging = true
					_drag_start = _cursor_world()
					_drag_cur = _drag_start
			elif _resizing:
				_finish_resize()
				queue_redraw()
			else:
				_dragging = false
				_finish_selection()
				queue_redraw()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Shift+right-click appends a waypoint to the route instead of replacing
			# it, so a march can be plotted as a multi-leg path.
			_issue_order(_cursor_world(), event.shift_pressed)
	elif event is InputEventMouseMotion:
		if _resizing:
			_update_resize(_cursor_world())
			queue_redraw()
		elif _dragging:
			_drag_cur = _cursor_world()
			queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		# Dispatch the hotkey; if it did something, note its label for the demo overlay.
		if _dispatch_key(event):
			_note_key(_key_label(event))


## Route a gameplay hotkey to its action. Returns true if a known action fired (so the
## caller records the keystroke for the demo overlay), false for an unhandled key.
func _dispatch_key(event: InputEventKey) -> bool:
	var mode: int = _order_mode_for_keycode(event.physical_keycode)
	if mode >= 0:
		_set_armed_mode(mode)   # arm a smart-order stance
		return true
	elif event.keycode == KEY_M:
		_issue_merge()   # merge the selected friendly regiments into one
		return true
	elif event.keycode == KEY_T:
		_cycle_formation()   # cycle tight → normal → loose for selected units
		return true
	elif event.keycode == KEY_BRACKETRIGHT:
		_resize_frontage(1)    # ] widens the line by one file
		return true
	elif event.keycode == KEY_BRACKETLEFT:
		_resize_frontage(-1)   # [ narrows the line by one file
		return true
	return _handle_group_key(event)   # Ctrl+<0-9> bind / <0-9> recall


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

	if not _selected.is_empty():
		Sfx.play(&"select")
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
		# Right-clicking a friendly that isn't part of the selection targets it: a
		# line-relief order on an engaged friendly, or — when SUPPORT is armed
		# — a guard order on any friendly, engaged or not. Plain ground stays
		# an ordinary move.
		var friend: UnitRef = _unit_at(world_pos, 0)
		var supporting: bool = _armed_mode == BattleRef.OrderMode.SUPPORT
		if friend != null and not _selected.has(friend) \
				and (supporting or friend.state == UnitRef.State.FIGHTING):
			target_uid = friend.uid
		elif append:
			# Shift on plain ground queues a waypoint; the sentinel rides the
			# target field so Battle appends instead of replacing the route. Append
			# is ignored when the click resolves to an attack or relief target.
			target_uid = BattleRef.ORDER_APPEND_WAYPOINT
	var uids: Array = []
	for unit in _selected:
		if is_instance_valid(unit):
			uids.append(unit.uid)
	if uids.is_empty():
		return
	_battle.enqueue_order(uids, world_pos, target_uid, _armed_mode)
	Sfx.play(&"order")


## Merge the selected friendly regiments into the first-selected one. Encoded
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
	Sfx.play(&"order")


## Cycle the formation of all selected friendly units: Normal → Tight → Loose → Normal.
func _cycle_formation() -> void:
	if Replay.mode == Replay.Mode.PLAYBACK:
		return
	if _selected.is_empty() or not is_instance_valid(_selected[0]):
		return
	var current: int = _selected[0].formation_mode
	var next: int = (current + 1) % 3
	var uids: Array = []
	for unit in _selected:
		if is_instance_valid(unit):
			uids.append(unit.uid)
	_battle.enqueue_formation(uids, next)
	_refresh_hud()
	Sfx.play(&"order")


# --- frontage resize -------------------------------------------------------

## Widen (delta > 0) or narrow (delta < 0) every selected unit's frontage by `delta`
## files. Routed through Battle so the resize is recorded and replays exactly. Each
## unit steps from its own current width, so a mixed selection keeps its proportions.
func _resize_frontage(delta: int) -> void:
	if Replay.mode == Replay.Mode.PLAYBACK:
		return
	var uids: Array = _selected_uids()
	if uids.is_empty():
		return
	_battle.enqueue_frontage(uids, delta)
	_refresh_hud()
	Sfx.play(&"order")


## Begin a drag-resize from a flank grip: seed the live target with the unit's
## current frontage so a click without movement is a no-op.
func _begin_resize(u) -> void:
	_resizing = true
	_resize_unit = u
	_resize_files = UnitFormation.frontage(u)
	queue_redraw()


## Update the live resize target as the cursor drags: project the cursor onto the
## unit's file axis for a half-width, then map it to a file count (shared helper).
func _update_resize(world_pos: Vector2) -> void:
	if not is_instance_valid(_resize_unit):
		_resizing = false
		return
	var offset: Vector2 = world_pos - _resize_unit.global_position
	var half_width: float = absf(offset.dot(_file_axis(_resize_unit)))
	_resize_files = UnitFormation.files_for_halfwidth(half_width, _resize_unit.max_soldiers)


## Commit a drag-resize on release: enqueue the delta from the unit's current
## frontage to the previewed target, sharing the recorded path with the keyboard
## resize. A zero delta (no real change) issues nothing.
func _finish_resize() -> void:
	var u = _resize_unit
	_resizing = false
	_resize_unit = null
	if not is_instance_valid(u) or Replay.mode == Replay.Mode.PLAYBACK:
		return
	var delta: int = _resize_files - UnitFormation.frontage(u)
	if delta != 0:
		_battle.enqueue_frontage([u.uid], delta)
		Sfx.play(&"order")
	_refresh_hud()


## The selected unit whose flank resize-grip is under `world_pos`, or null.
func _resize_handle_at(world_pos: Vector2):
	var u = _single_selected_unit()
	if u == null:
		return null
	for hp in _resize_handle_positions(u):
		if world_pos.distance_to(hp) <= RESIZE_HANDLE_HIT:
			return u
	return null


## The sole live selected unit, or null when the selection isn't exactly one (or a
## replay is playing) -- the precondition for showing and grabbing resize grips.
func _single_selected_unit():
	if Replay.mode == Replay.Mode.PLAYBACK or _selected.size() != 1:
		return null
	var u = _selected[0]
	if not is_instance_valid(u) or u.state == UnitRef.State.DEAD:
		return null
	return u


## World positions of a unit's two flank resize grips: out along its file axis, just
## past the block extent, on each side.
func _resize_handle_positions(u) -> Array:
	var right: Vector2 = _file_axis(u)
	var reach: float = u.render_block_extent() + RESIZE_HANDLE_GAP
	return [u.global_position + right * reach, u.global_position - right * reach]


## Unit vector along a regiment's file (width) axis in world space: its facing turned
## 90 degrees, matching UnitFormation.slots' local-X spread (local forward is -Y).
func _file_axis(u) -> Vector2:
	return Vector2.RIGHT.rotated(u.facing.angle() + PI * 0.5)


## Stable uids of the live (alive) units in the current selection.
func _selected_uids() -> Array:
	var uids: Array = []
	for unit in _selected:
		if is_instance_valid(unit) and unit.state != UnitRef.State.DEAD:
			uids.append(unit.uid)
	return uids


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
	# Order overlays render while Space is held (see _draw_orders) or, in a demo
	# recording, continuously — so redraw to track marching units, plus one extra
	# frame after it turns off to wipe the last frame's lines. Selection alone
	# draws nothing here.
	var showing_orders := Input.is_key_pressed(KEY_SPACE) or _demo_orders_active()
	if showing_orders or _was_showing_orders:
		queue_redraw()
	_was_showing_orders = showing_orders
	if _cursor_sprite.visible:
		_cursor_sprite.position = get_viewport().get_mouse_position()


# --- control groups --------------------------------------------------------

## Ctrl+<0-9> binds the current selection to that group; <0-9> alone recalls it.
## Returns true if the key was a control-group digit (handled), false otherwise.
func _handle_group_key(event: InputEventKey) -> bool:
	var n: int = _digit_for_keycode(event.keycode)
	if n < 0:
		return false
	if event.ctrl_pressed:
		_bind_group(n)
	else:
		_recall_group(n)
	return true


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
	if not _selected.is_empty():
		Sfx.play(&"select")   # parity with click / box / type-select feedback
	_refresh_hud()


# --- order modes -----------------------------------------------------

func _exit_tree() -> void:
	# Hide the sprite and restore the OS cursor so armed mode doesn't leak
	# across scenes (e.g. after reload_current_scene).
	_cursor_sprite.visible = false
	DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_VISIBLE)


## Order-mode hotkeys: keyed on the PHYSICAL keycode (layout-independent, like
## the camera/pause keys) and now read from the Settings autoload so they're
## rebindable. Esc -> NORMAL ("clear stance") stays fixed. -1 = not a mode key.
func _order_mode_for_keycode(physical_keycode: Key) -> int:
	if physical_keycode == KEY_ESCAPE:
		return BattleRef.OrderMode.NORMAL
	var slug := Settings.slug_for_keycode(physical_keycode)
	if slug == "":
		return -1
	for entry in BattleRef.ORDER_MODE_HOTKEYS:
		if entry["slug"] == slug:
			return entry["mode"]
	return -1


func _set_armed_mode(mode: int) -> void:
	if mode == _armed_mode:
		return
	_armed_mode = mode
	_update_order_cursor()
	if _hud != null:
		# Empty label hides the indicator for the default stance.
		var label: String = "" if mode == BattleRef.OrderMode.NORMAL \
				else str(BattleRef.ORDER_MODE_NAMES.get(mode, ""))
		_hud.set_order_mode(label)


## Reflect the armed mode in the mouse cursor: a coloured disc (in-scene Sprite2D)
## per smart mode, or the system arrow for NORMAL. Bypasses Input.set_custom_mouse_cursor
## to avoid the macOS imgrep null-conversion crash.
func _update_order_cursor() -> void:
	if _armed_mode == BattleRef.OrderMode.NORMAL:
		_cursor_sprite.visible = false
		DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_VISIBLE)
		return
	if not _cursor_textures.has(_armed_mode):
		_cursor_textures[_armed_mode] = _order_cursor_texture(_order_mode_color(_armed_mode))
	_cursor_sprite.texture = _cursor_textures[_armed_mode]
	_cursor_sprite.visible = true
	DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_HIDDEN)


func _order_mode_color(mode: int) -> Color:
	match mode:
		BattleRef.OrderMode.HOLD: return Color(0.45, 0.6, 1.0)
		BattleRef.OrderMode.ATTACK_FLANK: return Color(1.0, 0.65, 0.2)
		BattleRef.OrderMode.ATTACK_REAR: return Color(1.0, 0.3, 0.25)
		BattleRef.OrderMode.SKIRMISH: return Color(1.0, 0.9, 0.3)
		BattleRef.OrderMode.SUPPORT: return Color(0.4, 0.95, 0.7)
		_: return Color.WHITE


## A filled disc in `color` with a white rim, centre-hotspot, for the cursor.
func _order_cursor_texture(color: Color) -> ImageTexture:
	var img := Image.create(CURSOR_SIZE, CURSOR_SIZE, false, Image.FORMAT_RGBA8)
	var c := Vector2(CURSOR_SIZE / 2.0, CURSOR_SIZE / 2.0)
	var r: float = CURSOR_SIZE / 2.0 - 1.0
	for y in CURSOR_SIZE:
		for x in CURSOR_SIZE:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= r - 3.0:
				img.set_pixel(x, y, color)
			elif d <= r:
				img.set_pixel(x, y, Color.WHITE)   # rim for contrast on any background
	return ImageTexture.create_from_image(img)


func _draw() -> void:
	_draw_orders()
	# During a demo replay with a recorded pointer track, redraw the player's mouse:
	# selection halos, the drag-box, click pulses and the cursor with its armed stance.
	if _demo_orders_active() and Replay.has_pointer_track():
		_draw_demo_pointer()
	_draw_resize_handles()
	if not _dragging:
		return
	var rect := Rect2(_drag_start, _drag_cur - _drag_start).abs()
	draw_rect(rect, Color(0.4, 0.9, 0.4, 0.15))
	draw_rect(rect, Color(0.5, 1.0, 0.5, 0.9), false, 1.5)


## Flank resize grips on a singly-selected unit, plus -- while a grip is held -- a
## preview line across the target width with its file count.
func _draw_resize_handles() -> void:
	var u = _single_selected_unit()
	if u == null:
		return
	for hp in _resize_handle_positions(u):
		var box := Rect2(hp - Vector2.ONE * RESIZE_HANDLE_SIZE, Vector2.ONE * RESIZE_HANDLE_SIZE * 2.0)
		draw_rect(box, RESIZE_HANDLE_COLOR)
		draw_rect(box, Color.BLACK, false, 1.0)   # rim for contrast on any background
	if _resizing and is_instance_valid(_resize_unit):
		_draw_resize_preview(_resize_unit)


## Preview the dragged frontage: a line spanning the target width and the file count
## as text, so the player sees the new line before releasing.
func _draw_resize_preview(u) -> void:
	var right: Vector2 = _file_axis(u)
	var half: float = float(_resize_files - 1) * 0.5 * UnitRef.FORMATION_SPACING
	var a: Vector2 = u.global_position - right * half
	var b: Vector2 = u.global_position + right * half
	draw_line(a, b, RESIZE_HANDLE_COLOR, 2.0)
	draw_string(ThemeDB.fallback_font, b + Vector2(8.0, -6.0), UnitFormation.files_label(_resize_files),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, RESIZE_HANDLE_COLOR)


## The cursor's world position: the injected position when one is set (deterministic
## recording / tests), otherwise the live OS mouse. All selection, order and pointer-capture
## logic reads the cursor through here so an injected cursor behaves exactly like the mouse.
func _cursor_world() -> Vector2:
	return _cursor_override if _cursor_override != null else get_global_mouse_position()


## Inject a cursor world position (deterministic input), or pass null to resume the live
## mouse. Used by the demo recorder and tests; never called in normal play.
func set_cursor_override(world_pos: Variant) -> void:
	_cursor_override = world_pos


## The player's live pointer state, sampled by Battle each tick during a live recording
## (#247): the cursor world position, whether a multi-select drag-box is open and its start
## corner, the selected unit uids, and the armed order stance. Render-only — never read by
## the simulation.
func pointer_state() -> Dictionary:
	var sel: Array = []
	for u in _selected:
		if is_instance_valid(u) and u.state != UnitRef.State.DEAD:
			sel.append(u.uid)
	return {
		"cursor": _cursor_world(),
		"dragging": _dragging,
		"drag_start": _drag_start,
		"selection": sel,
		"mode": _armed_mode,
	}


## Drain and return the gameplay-hotkey labels pressed since the previous tick. Battle
## calls this once per tick during a live recording, feeding the replay's keystroke track.
func take_keys_this_tick() -> Array:
	var k: Array = _keys_this_tick
	_keys_this_tick = []
	return k


## Buffer a pressed-key label for this tick's keystroke recording.
func _note_key(label: String) -> void:
	if label != "":
		_keys_this_tick.append(label)


## Short on-screen label for a pressed hotkey: a glyph for the brackets, "Esc" for escape,
## the bare letter/digit otherwise (prefixed "Ctrl+" when chorded).
func _key_label(event: InputEventKey) -> String:
	if event.keycode == KEY_BRACKETLEFT:
		return "["
	if event.keycode == KEY_BRACKETRIGHT:
		return "]"
	if event.keycode == KEY_ESCAPE:
		return "Esc"
	var s: String = OS.get_keycode_string(event.keycode)
	if s.length() == 1 and event.ctrl_pressed:
		return "Ctrl+" + s
	return s


## Replay-only: draw the recorded pointer for the current tick — selection halos on the
## still-living selected units, the multi-select drag-box, an expanding pulse at each
## recently-issued order, and the cursor reticle tinted by the armed stance (with a stance
## label). Reads the pointer track via Replay; touches no simulation state.
func _draw_demo_pointer() -> void:
	var tick: int = _battle.current_tick()
	var p: Dictionary = Replay.pointer_for_tick(tick)
	if p.is_empty():
		return
	# Discrete state (selection, drag, stance) snaps at keyframes via `p`; the cursor itself
	# interpolates between keyframes so it visibly glides rather than teleporting.
	var cursor: Vector2 = Replay.pointer_cursor_for_tick(tick)

	# Selection halos: a yellow ring around each still-living selected unit, matching the
	# live selection ring (units aren't flagged `selected` during playback, so draw it here).
	for uid in p["sel"]:
		var u: UnitRef = _battle.unit_by_uid(int(uid))
		if u != null and u.state != UnitRef.State.DEAD:
			draw_arc(u.global_position, u.render_block_extent() + 4.0, 0.0, TAU, 36, DEMO_SELECT_COLOR, 2.0)

	# Drag-box: the marquee from its recorded start corner to the (gliding) cursor.
	if bool(p["drag"]):
		var rect := Rect2(Vector2(p["sx"], p["sy"]), cursor - Vector2(p["sx"], p["sy"])).abs()
		draw_rect(rect, Color(0.4, 0.9, 0.4, 0.15))
		draw_rect(rect, Color(0.5, 1.0, 0.5, 0.9), false, 1.5)

	# Click pulses: an expanding, fading ring where each recent order was issued.
	for pulse in Replay.pulses_for_tick(tick, DEMO_PULSE_WINDOW):
		var age: int = int(pulse["age"])
		var t: float = float(age) / float(DEMO_PULSE_WINDOW)
		var r: float = DEMO_PULSE_BASE_R + float(age) * DEMO_PULSE_GROWTH
		draw_arc(Vector2(pulse["x"], pulse["y"]), r, 0.0, TAU, 24,
				Color(DEMO_CURSOR_COLOR, (1.0 - t) * 0.8), 2.0)

	# Cursor reticle, tinted by the armed stance (NORMAL = white), with a stance label.
	var mode: int = int(p["mode"])
	var cursor_color: Color = DEMO_CURSOR_COLOR if mode == BattleRef.OrderMode.NORMAL \
			else Color(_order_mode_color(mode), 0.95)
	draw_arc(cursor, 5.0, 0.0, TAU, 16, cursor_color, 2.0)
	draw_circle(cursor, 1.5, cursor_color)
	if mode != BattleRef.OrderMode.NORMAL:
		var label: String = str(BattleRef.ORDER_MODE_NAMES.get(mode, ""))
		draw_string(ThemeDB.fallback_font, cursor + Vector2(9.0, -6.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, cursor_color)

	# Pressed-key chips, stacked by the cursor so the clip shows which keys drove the action.
	_draw_demo_keys(tick, cursor)


## Replay-only: draw labelled chips for the recently pressed hotkeys, stacked below the
## cursor and fading with age, so a demo clip shows the keystrokes (the keyboard
## counterpart to the cursor/click overlay). Newest sits nearest the cursor; capped to a
## few so a flurry of presses can't tower.
func _draw_demo_keys(tick: int, anchor: Vector2) -> void:
	var keys: Array = Replay.keys_for_tick(tick, DEMO_KEY_WINDOW)
	if keys.is_empty():
		return
	var font := ThemeDB.fallback_font
	var fsize := 15
	var pad := 5.0
	var shown: int = mini(keys.size(), 4)
	for i in range(shown):
		var k: Dictionary = keys[keys.size() - 1 - i]   # newest first
		var fade: float = 1.0 - float(int(k["age"])) / float(DEMO_KEY_WINDOW)
		var label: String = str(k["label"])
		var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		var box := Rect2(anchor + Vector2(12.0, 10.0 + float(i) * (float(fsize) + pad + 4.0)),
				Vector2(tw + pad * 2.0, float(fsize) + pad))
		draw_rect(box, Color(0.0, 0.0, 0.0, 0.55 * fade))
		draw_rect(box, Color(DEMO_KEY_COLOR, 0.9 * fade), false, 1.5)
		draw_string(font, box.position + Vector2(pad, float(fsize)), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(DEMO_KEY_COLOR, fade))


## Draw units' current orders on the field (RTS style): a dashed line to
## each unit's destination or to the enemy it's attacking, with a marker at the
## far end. SelectionManager sits at the world origin with no parent transform —
## the same assumption the drag-box selection relies on — so unit world
## positions can be drawn directly in _draw()'s local space.
##
## Orders are a "hold to reveal" survey aid: shown for all of the player's units
## while Space is held (works paused too, since this node is PROCESS_MODE_ALWAYS;
## P or Shift+Space toggles pause). Enemy (team 1) orders are revealed only during
## replay playback — in live play the enemy's intentions stay hidden.
## True while a demo recording is replaying with the order overlay enabled — the
## DemoRunner sets Replay.show_demo_orders, so markers show without a held key.
## In-app Watch Replay leaves the flag off, keeping the Space-held survey behaviour.
func _demo_orders_active() -> bool:
	return Replay.mode == Replay.Mode.PLAYBACK and Replay.show_demo_orders


func _draw_orders() -> void:
	# Normally a hold-Space survey; during a demo recording the order overlay is
	# always on (Replay.show_demo_orders), so the clip reveals what was commanded.
	if not (Input.is_key_pressed(KEY_SPACE) or _demo_orders_active()):
		return
	# The hold-Space survey reveals enemy orders during playback (inspection); the
	# demo overlay shows only the player's own orders — #223 is about surfacing what
	# *you* commanded, and drawing every AI unit's target just clutters the clip.
	var show_enemy: bool = Replay.mode == Replay.Mode.PLAYBACK and not _demo_orders_active()
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
		# Resolve the SUPPORT ward once (only when supporting) so the elif and its body
		# share a single lookup. Binding it before the chain — rather than inside the
		# elif — keeps the move-route else reachable when a SUPPORT unit has no valid
		# ward (e.g. a SUPPORT order on empty ground, which leaves a move target).
		var ward: UnitRef = _support_ward_of(u) if u.order_mode == UnitRef.ORDER_SUPPORT else null
		if tgt != null and is_instance_valid(tgt) \
				and tgt.state != UnitRef.State.DEAD and tgt.state != UnitRef.State.ROUTING:
			var tp: Vector2 = tgt.global_position
			draw_dashed_line(origin, tp, ORDER_ATTACK_COLOR, 2.0, 9.0)
			_draw_attack_marker(tp, ORDER_ATTACK_COLOR)
		elif ward != null:
			# A SUPPORT unit holds no target_enemy/move_target of its own, so draw
			# its guard duty instead: a teal link to the ward it's shadowing.
			var wp: Vector2 = ward.global_position
			draw_dashed_line(origin, wp, ORDER_SUPPORT_COLOR, 2.0, 9.0)
			_draw_support_marker(wp, ORDER_SUPPORT_COLOR)
		else:
			var route := _move_route_for(u)
			if not route.is_empty():
				_draw_move_path(origin, route[0], route.slice(1))


## The friendly a SUPPORT unit is guarding, if it's still a valid overlay
## target; else null. Extracted so the overlay branch reads cleanly and the guard is
## unit-testable. Fully mirrors the ward checks in UnitTargeting.support_valid — alive, not
## routing, and not the unit itself (the order_mode == SUPPORT test stays at the call site).
func _support_ward_of(u: UnitRef) -> UnitRef:
	var ward = u.support_target
	if ward != null and is_instance_valid(ward) and ward != u \
			and ward.state != UnitRef.State.DEAD and ward.state != UnitRef.State.ROUTING:
		return ward
	return null


## A unit's full move route for the overlay: its committed destination and queued
## waypoints, plus any waypoint appends still pending in Battle. While the
## sim is paused the physics tick that drains those appends into u.waypoints isn't
## running, so without this the overlay wouldn't preview a just-queued leg until
## the player unpaused. Returns [] when the unit has no move order and nothing
## pending. The pending points are read-only — no authoritative state is mutated.
func _move_route_for(u: UnitRef) -> Array[Vector2]:
	var route: Array[Vector2] = []
	if u.has_move_target:
		route.append(u.move_target)
		route.append_array(u.waypoints)
	route.append_array(_battle.pending_append_points_for(u))
	return route


## Draw a unit's full move route: a dashed line from the unit through its
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


## Support marker: a double "shielding" ring over the guarded ward, distinct from the
## move ring and the attack crosshair.
func _draw_support_marker(p: Vector2, color: Color) -> void:
	draw_arc(p, 10.0, 0.0, TAU, 20, color, 2.0)
	draw_arc(p, 5.0, 0.0, TAU, 12, color, 1.5)


## Attack marker: a crosshair over the targeted enemy.
func _draw_attack_marker(p: Vector2, color: Color) -> void:
	var r := 11.0
	draw_arc(p, r, 0.0, TAU, 22, color, 2.0)
	draw_line(p + Vector2(-r - 3.0, 0.0), p + Vector2(r + 3.0, 0.0), color, 2.0)
	draw_line(p + Vector2(0.0, -r - 3.0), p + Vector2(0.0, r + 3.0), color, 2.0)
