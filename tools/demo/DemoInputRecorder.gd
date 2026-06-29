extends Node
## Headless **scripted-input** demo recorder (see demos/README.md). Set as the main scene
## under Godot's Movie Maker mode (`--write-movie`). It reads an input script named in the
## SPARTA_DEMO_INPUT environment variable — a deterministic list of mouse clicks/drags and
## keystrokes stamped with the physics tick they fire on — and drives a LIVE Battle by
## injecting those as real InputEvents through the SelectionManager's normal input path,
## while Movie Maker records what's drawn. So the clip is produced from the same code a
## player's mouse/keyboard would drive (a demo doubles as an input smoke test).
##
## This is tooling: nothing in the live game references it, and it changes no simulation
## code. It is the counterpart to DemoRunner.gd, which only plays back a saved replay.

const BATTLE_SCENE := "res://scenes/Battle.tscn"
# Ticks a press->release drag is spread over, so the live form-up / box-select preview
# visibly animates rather than snapping in a single frame.
const DRAG_TICKS := 16

var _sel: Node = null
var _battle: Node = null
var _cam: Camera2D = null
var _camera_kf: Dictionary = {}        # static framing {x,y,zoom}, or empty for the default camera
var _by_tick: Dictionary = {}          # tick -> Array of expanded input events


func _ready() -> void:
	# A recording carries the game's sound (SFX default off); session-only, like DemoRunner.
	Settings.set_sfx_enabled_session(true)
	var script: Dictionary = _load_script(OS.get_environment("SPARTA_DEMO_INPUT"))
	# Deterministic seed so the recorded battle is reproducible run to run.
	Replay.forced_seed = int(str(script.get("seed", "12345")))
	var cams: Array = script.get("camera", [])
	if not cams.is_empty():
		_camera_kf = cams[0]
	_schedule(script.get("steps", []))
	print("[demo-input] %d scripted input events over %d ticks" % [_count_events(), _max_tick()])
	# Defer so this bootstrap finishes _ready before the battle is added; Movie Maker keeps
	# recording across the change. The recorder stays the scene root (Battle is a child) so
	# it persists to inject events every tick.
	_start_battle.call_deferred()


func _start_battle() -> void:
	_battle = load(BATTLE_SCENE).instantiate()
	add_child(_battle)
	_sel = _battle.get_node("SelectionManager")
	_cam = _battle.get_node("Camera2D")
	_apply_camera()
	get_tree().physics_frame.connect(_on_physics_frame)


## Each physics frame, hold the camera framing and fire any input events due this tick.
func _on_physics_frame() -> void:
	if _sel == null or not is_instance_valid(_sel) \
			or _battle == null or not is_instance_valid(_battle):
		return
	_apply_camera()
	var tick: int = _battle.current_tick()
	for ev in _by_tick.get(tick, []):
		_fire(ev)


func _apply_camera() -> void:
	# CameraController only moves on real pan/zoom input, of which the recorder injects none,
	# so a directly-set position/zoom holds. Re-applied each tick to be safe.
	if _cam == null or _camera_kf.is_empty():
		return
	_cam.position = Vector2(_camera_kf["x"], _camera_kf["y"])
	var z: float = float(_camera_kf["zoom"])
	_cam.zoom = Vector2(z, z)


# --- input injection -------------------------------------------------------

## Drive one expanded event into the SelectionManager. Position comes via the cursor override
## (all selection/order logic reads _cursor_world()), so the synthesized events' own position
## fields don't need to be accurate — only the button/key and pressed state matter.
func _fire(ev: Dictionary) -> void:
	match ev["kind"]:
		"mb":
			_sel.set_cursor_override(ev["pos"])
			var mb := InputEventMouseButton.new()
			mb.button_index = int(ev["button"])
			mb.pressed = bool(ev["pressed"])
			mb.position = ev["pos"]
			mb.shift_pressed = bool(ev.get("shift", false))
			_sel._unhandled_input(mb)
		"motion":
			_sel.set_cursor_override(ev["pos"])
			var mm := InputEventMouseMotion.new()
			mm.position = ev["pos"]
			_sel._unhandled_input(mm)
		"key":
			var k := InputEventKey.new()
			k.keycode = int(ev["keycode"])
			k.physical_keycode = int(ev["keycode"])
			k.pressed = true
			_sel._unhandled_input(k)
		"hold_space":
			# Update hardware key state so Input.is_key_pressed(KEY_SPACE) returns true
			# for the rest of the recording — enabling the orders overlay draw path.
			var k := InputEventKey.new()
			k.keycode = KEY_SPACE
			k.physical_keycode = KEY_SPACE
			k.pressed = true
			Input.parse_input_event(k)


# --- script -> per-tick event schedule -------------------------------------

func _schedule(steps: Array) -> void:
	for step in steps:
		var tick: int = int(step.get("tick", 0))
		if step.has("click"):
			_click(tick, _vec(step["click"]), MOUSE_BUTTON_LEFT, false)
		elif step.has("shift_click"):
			_click(tick, _vec(step["shift_click"]), MOUSE_BUTTON_LEFT, true)
		elif step.has("rmb_click"):
			_click(tick, _vec(step["rmb_click"]), MOUSE_BUTTON_RIGHT, false)
		elif step.has("box"):
			_drag(tick, _vec(step["box"]["from"]), _vec(step["box"]["to"]), MOUSE_BUTTON_LEFT, false)
		elif step.has("rmb_drag"):
			var shift: bool = bool(step["rmb_drag"].get("shift", false))
			_drag(tick, _vec(step["rmb_drag"]["from"]), _vec(step["rmb_drag"]["to"]), MOUSE_BUTTON_RIGHT, shift)
		elif step.has("key"):
			_at(tick, {"kind": "key", "keycode": OS.find_keycode_from_string(str(step["key"]))})
		elif step.has("hold_space"):
			# Hold Space for the rest of the recording so the orders overlay is visible.
			# Uses Input.parse_input_event (not _unhandled_input) so Input.is_key_pressed()
			# reflects the held state — that's what _draw_orders() checks.
			_at(tick, {"kind": "hold_space"})


## A click = button press then release at one point, on the same tick.
func _click(tick: int, pos: Vector2, button: int, shift: bool) -> void:
	_at(tick, {"kind": "mb", "pos": pos, "button": button, "pressed": true, "shift": shift})
	_at(tick, {"kind": "mb", "pos": pos, "button": button, "pressed": false, "shift": shift})


## A drag = press at `from`, motions interpolating to `to` over DRAG_TICKS (so the preview
## animates and the drag passes the click threshold), then release at `to`.
func _drag(tick: int, from: Vector2, to: Vector2, button: int, shift: bool) -> void:
	_at(tick, {"kind": "mb", "pos": from, "button": button, "pressed": true, "shift": shift})
	for i in range(1, DRAG_TICKS):
		var pos: Vector2 = from.lerp(to, float(i) / float(DRAG_TICKS))
		_at(tick + i, {"kind": "motion", "pos": pos})
	_at(tick + DRAG_TICKS, {"kind": "mb", "pos": to, "button": button, "pressed": false, "shift": shift})


func _at(tick: int, ev: Dictionary) -> void:
	if not _by_tick.has(tick):
		_by_tick[tick] = []
	_by_tick[tick].append(ev)


# --- helpers ---------------------------------------------------------------

func _vec(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _load_script(path: String) -> Dictionary:
	if path == "":
		push_warning("[demo-input] SPARTA_DEMO_INPUT unset; recording a default battle.")
		return {}
	if not FileAccess.file_exists(path):
		push_warning("[demo-input] script not found: %s" % path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[demo-input] script is not a JSON object: %s" % path)
		return {}
	return data


func _max_tick() -> int:
	var m: int = 0
	for t in _by_tick:
		m = maxi(m, int(t))
	return m


func _count_events() -> int:
	var n: int = 0
	for t in _by_tick:
		n += (_by_tick[t] as Array).size()
	return n
