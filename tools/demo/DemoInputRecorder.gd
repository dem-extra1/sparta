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
# Wall-clock cap for a frame-capture run, so it can't hang if a frame is armed past a battle's
# end (the sim freezes its tick then). Generous — a normal capture finishes in a few seconds.
const CAPTURE_TIMEOUT_SEC := 60.0

var _sel: Node = null
var _battle: Node = null
var _cam: Camera2D = null
var _camera_track: Array = []          # keyframes [{tick,x,y,zoom}], interpolated per tick; empty = default camera
var _by_tick: Dictionary = {}          # tick -> Array of expanded input events
var _drill: bool = false               # solo/no-opponent rehearsal (input script "drill" field)
var _scenario: Array = []              # custom unit matchup (input script "scenario" field)
var _frame_ticks: Array = []           # ticks to save a viewport PNG at (frame capture; empty = off)
var _frame_dir: String = ""            # output dir for captured frames
var _captured: Dictionary = {}         # tick -> true, so each frame is saved at most once
var _state_ticks: Array = []           # ticks to dump a JSON game-state snapshot at (empty = off)
var _state_dir: String = ""            # output dir for state snapshots
var _state_full: bool = false          # also dump the raw per-soldier arrays (deep debugging)
var _state_dumped: Dictionary = {}     # tick -> true, so each snapshot is written at most once


func _ready() -> void:
	# A recording carries the game's sound (SFX default off); session-only, like DemoRunner.
	Settings.set_sfx_enabled_session(true)
	var script: Dictionary = _load_script(OS.get_environment("SPARTA_DEMO_INPUT"))
	# Deterministic seed so the recorded battle is reproducible run to run.
	Replay.forced_seed = int(str(script.get("seed", "12345")))
	_camera_track = script.get("camera", [])
	if not CameraKeyframes.is_sorted(_camera_track):
		push_warning("[demo-input] camera keyframes are not sorted by tick; interpolation will be wrong.")
	_schedule(script.get("steps", []))
	_drill = bool(script.get("drill", false))
	_scenario = script.get("scenario", [])
	_arm_frame_capture(script.get("frames", []))
	_arm_state_dump(script.get("state", []))
	print("[demo-input] %d scripted input events over %d ticks%s%s" % [
		_count_events(), _max_tick(), " (drill mode)" if _drill else "",
		" (scenario: %d units)" % _scenario.size() if not _scenario.is_empty() else ""])
	# Defer so this bootstrap finishes _ready before the battle is added; Movie Maker keeps
	# recording across the change. The recorder stays the scene root (Battle is a child) so
	# it persists to inject events every tick.
	_start_battle.call_deferred()


func _start_battle() -> void:
	_battle = load(BATTLE_SCENE).instantiate()
	_battle.drill_mode = _drill   # set before add_child so Battle._ready reads it (no team-1 spawn)
	_battle.scenario = _scenario  # likewise: a custom matchup replaces the default line spawn
	add_child(_battle)
	_sel = _battle.get_node("SelectionManager")
	_cam = _battle.get_node("Camera2D")
	_apply_camera(0)
	get_tree().physics_frame.connect(_on_physics_frame)


## Each physics frame, hold the camera framing and fire any input events due this tick.
func _on_physics_frame() -> void:
	if _sel == null or not is_instance_valid(_sel) \
			or _battle == null or not is_instance_valid(_battle):
		return
	var tick: int = _battle.current_tick()
	_apply_camera(tick)
	for ev in _by_tick.get(tick, []):
		_fire(ev)
	if _state_ticks.has(tick) and not _state_dumped.has(tick):
		_state_dumped[tick] = true
		_dump_state(tick)
	if _frame_ticks.has(tick) and not _captured.has(tick):
		_captured[tick] = true
		_capture_frame(tick)
	# In capture / dump mode (not a movie recording), quit once every armed frame AND state
	# snapshot is done so the tool returns promptly, without a fragile --quit-after frame count.
	# _all_artifacts_done() guards on at least one list being armed, so a movie recording (neither
	# armed) never quits here — it runs to Movie Maker's own --quit-after.
	if _all_artifacts_done():
		_quit_after_captures()


## Set the camera to the track's framing for `tick`, interpolating between keyframes. The
## CameraController only moves on real pan/zoom input (the recorder injects none), so a
## directly-set position/zoom holds; we re-apply each tick to animate along the track.
func _apply_camera(tick: int) -> void:
	if _cam == null:
		return
	var kf: Dictionary = CameraKeyframes.sample(_camera_track, tick)
	if kf.is_empty():
		return
	_cam.position = Vector2(kf["x"], kf["y"])
	var z: float = kf["zoom"]   # sample() already returns floats
	_cam.zoom = Vector2(z, z)


# --- frame capture ---------------------------------------------------------

## Arm PNG frame capture from SPARTA_DEMO_FRAMES (a comma-separated tick list) merged with the
## input script's optional `frames` array. When the resulting set is empty (both unset — the
## normal case), capture is off and the recorder behaves exactly as before. Otherwise each
## listed tick saves the drawn viewport to SPARTA_DEMO_FRAME_DIR (default: a temp dir), so a
## demo can be rendered to a handful of PNGs and eyeballed to confirm the behaviour is on-screen.
func _arm_frame_capture(script_frames: Array) -> void:
	# Capture is env-gated: it arms only when SPARTA_DEMO_FRAMES is set. A movie recording (CI)
	# leaves it unset, so a demo's own `frames` array never truncates the recording — that array
	# just supplies default ticks for a capture run. Set SPARTA_DEMO_FRAMES to a tick list to
	# override those defaults, or to any value (even empty, via the wrapper) to arm with them.
	if not OS.has_environment("SPARTA_DEMO_FRAMES"):
		return
	_frame_ticks = DemoFrames.merge_ticks(OS.get_environment("SPARTA_DEMO_FRAMES"), script_frames)
	if _frame_ticks.is_empty():
		return
	_frame_dir = OS.get_environment("SPARTA_DEMO_FRAME_DIR")
	if _frame_dir == "":
		_frame_dir = OS.get_temp_dir().path_join("sparta_demo_frames")
	# Create the output dir (recursively) so save_png doesn't silently fail on a missing path.
	DirAccess.make_dir_recursive_absolute(_frame_dir)
	print("[demo-input] frame capture armed at ticks %s -> %s" % [str(_frame_ticks), _frame_dir])
	# Safety net: the sim freezes its tick when a battle ends (Battle._ended), so a frame armed
	# past the battle's end would never fire and the run would hang. Quit after a generous wall
	# time regardless, saving whatever was captured. Timer runs on real time (not process time),
	# so it fires even if physics is throttled while the window is unfocused.
	get_tree().create_timer(CAPTURE_TIMEOUT_SEC).timeout.connect(_on_capture_timeout)


## Save the drawn viewport to a PNG for `tick`. The viewport texture is only valid after the
## frame is drawn, so wait for RenderingServer.frame_post_draw before reading it — reading in
## the physics frame (before the draw) yields a stale or blank image. A real renderer is
## required: --headless uses the dummy renderer and produces a null/blank texture, so this
## must run with e.g. --rendering-driver opengl3 (see demos/README.md).
func _capture_frame(tick: int) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_warning("[demo-input] frame %d: null viewport image (dummy renderer? run with a real --rendering-driver)." % tick)
		return
	var path: String = DemoFrames.frame_path(_frame_dir, tick)
	var err: int = img.save_png(path)
	if err != OK:
		push_warning("[demo-input] frame %d: save_png failed (%d) at %s" % [tick, err, path])
	else:
		print("[demo-input] captured frame at tick %d -> %s (%dx%d)" % [tick, path, img.get_width(), img.get_height()])


## True once every armed frame is captured and every armed state snapshot is written — the
## signal to quit a capture/dump run. The leading `> 0` guard is load-bearing: without it, a
## normal movie recording (neither list armed, both sizes 0) would satisfy `0 == 0 and 0 == 0`
## and quit after the first physics tick. The guard keeps this false unless at least one
## artifact type is armed, so an unarmed recording runs to Movie Maker's own --quit-after.
func _all_artifacts_done() -> bool:
	return (_frame_ticks.size() + _state_ticks.size()) > 0 \
		and _captured.size() == _frame_ticks.size() \
		and _state_dumped.size() == _state_ticks.size()


## Quit the tree once every armed frame is captured, after the pending save_png awaits finish.
## Only reached in frame-capture / state-dump mode; a normal movie recording never arms either
## and runs to Movie Maker's own --quit-after, so this never fires there.
##
## The frame_post_draw await lets any in-flight _capture_frame() save_png finish before we quit.
## It is ONLY needed when frames were captured: under --headless (the state-dump path) the dummy
## renderer may never emit frame_post_draw, so awaiting it there hangs the run until the caller's
## wall-clock timeout. A state-only dump reads sim state, never the drawn frame, so it quits
## straight away.
func _quit_after_captures() -> void:
	if not _frame_ticks.is_empty():
		await RenderingServer.frame_post_draw
	print("[demo-input] all artifacts done (%d frames, %d state snapshots); quitting."
		% [_frame_ticks.size(), _state_ticks.size()])
	get_tree().quit()


## Fired if a capture/dump run runs long. Quit anyway so the tool never hangs; whatever was
## captured/dumped is already on disk. Two cases reach here: a tick armed past the battle's end
## never fired (the sim freezes its tick then), so artifacts are incomplete; or every artifact
## landed but the quit-after path stalled. Either way we are done waiting — quit unconditionally,
## warning only when something is actually missing.
func _on_capture_timeout() -> void:
	if not _all_artifacts_done():
		push_warning("[demo-input] run timed out: %d/%d frames, %d/%d state snapshots (a tick may be past the battle's end)."
			% [_captured.size(), _frame_ticks.size(), _state_dumped.size(), _state_ticks.size()])
	get_tree().quit()


# --- state dump ------------------------------------------------------------

## Arm JSON game-state dumping from SPARTA_DEMO_STATE (a comma-separated tick list) merged with
## the input script's optional `state` array. When the resulting set is empty (both unset — the
## normal case), dumping is off and the recorder behaves exactly as before. Otherwise each listed
## tick writes a readable snapshot of the authoritative unit state to
## SPARTA_DEMO_STATE_DIR/state_<tick>.json (default: a temp dir), so a demo can be verified by
## reading exact values rather than interpreting a rendered frame. SPARTA_DEMO_STATE_FULL=1 also
## dumps the raw per-soldier arrays for deep debugging.
func _arm_state_dump(script_state: Array) -> void:
	# Env-gated, exactly like frame capture: arms only when SPARTA_DEMO_STATE is set. A movie
	# recording (CI) leaves it unset, so a demo's own `state` array never affects the recording —
	# that array just supplies default ticks for a dump run. Reuses DemoFrames' tick parse/merge.
	if not OS.has_environment("SPARTA_DEMO_STATE"):
		return
	_state_ticks = DemoFrames.merge_ticks(OS.get_environment("SPARTA_DEMO_STATE"), script_state)
	if _state_ticks.is_empty():
		return
	_state_full = OS.get_environment("SPARTA_DEMO_STATE_FULL") == "1"
	_state_dir = OS.get_environment("SPARTA_DEMO_STATE_DIR")
	if _state_dir == "":
		_state_dir = OS.get_temp_dir().path_join("sparta_demo_state")
	DirAccess.make_dir_recursive_absolute(_state_dir)
	print("[demo-input] state dump armed at ticks %s -> %s%s" % [
		str(_state_ticks), _state_dir, " (full per-soldier arrays)" if _state_full else ""])
	# Same safety net as capture: quit after a generous wall time so a tick past the battle's
	# end can't hang the run. Guarded so two arms don't stack two timers unnecessarily is not
	# needed — a duplicate timer just fires a redundant already-done check.
	get_tree().create_timer(CAPTURE_TIMEOUT_SEC).timeout.connect(_on_capture_timeout)


## Write a readable JSON snapshot of the authoritative game state at `tick`. Walks the live units
## (the "units" group), pulls each unit's fields, and hands the per-soldier arrays to
## DemoState.soldier_summary for a compact summary. No await / renderer needed — this reads sim
## state, not the drawn frame, so it works even under --headless.
func _dump_state(tick: int) -> void:
	var snapshot: Dictionary = _build_snapshot(tick)
	var path: String = "%s/state_%05d.json" % [_state_dir.trim_suffix("/"), tick]
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[demo-input] state %d: could not open %s (err %d)" % [tick, path, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(snapshot, "  "))
	f.close()
	print("[demo-input] dumped state at tick %d -> %s (%d units)" % [tick, path, snapshot["units"].size()])


## Build the snapshot Dictionary for `tick`: battle-level tick plus a per-unit record. Separated
## from the file write so it's directly inspectable; the recorder is the only caller.
func _build_snapshot(tick: int) -> Dictionary:
	var units_out: Array = []
	for u in get_tree().get_nodes_in_group("units"):
		units_out.append(_unit_record(u))
	return {"tick": tick, "units": units_out}


## One unit's readable record. Reads Unit fields directly and maps the enum ints to names via
## DemoState (State/formation) and Battle.ORDER_MODE_NAMES (order_mode). target_enemy is dumped
## as its uid (or null) so a snapshot references units by the same stable id, not a node path.
func _unit_record(u: Node) -> Dictionary:
	var target_uid = u.target_enemy.uid if u.target_enemy != null and is_instance_valid(u.target_enemy) else null
	var rec: Dictionary = {
		"uid": u.uid,
		"name": u.unit_name,
		"team": u.team,
		"position": DemoState.vec2_pair(u.position),
		"facing": DemoState.vec2_pair(u.facing),
		"morale": DemoState.round_to(u.morale, 1),
		"state": DemoState.state_name(u.state),
		"formation": DemoState.formation_name(u.formation_mode),
		"soldiers": u.soldiers,
		"current_speed": DemoState.round_to(u._current_speed, 1),
		"order_mode": DemoState.order_mode_name(_battle.ORDER_MODE_NAMES, u.order_mode),
		"target_enemy_uid": target_uid,
		"engaged": u.is_engaged(),
		# Phase 1 of the unified orders-queue design (#516): the head of the orders queue -- the
		# single, transcript-visible source of truth for "what is this unit doing right now,"
		# including its active phase for a phased order (e.g. a move-to-rear about-face vs its
		# march). null when the unit is idle (no current order).
		"current_order": Order.type_name(u.current_order.type) if u.current_order != null else null,
		"order_phase": Order.phase_name(u.current_order.phase) if u.current_order != null else null,
		"soldier_summary": DemoState.soldier_summary(u._sim_soldier_pos, u._sim_prone),
	}
	if _state_full:
		rec["soldiers_full"] = _soldier_arrays(u)
	return rec


## The raw per-soldier arrays for one unit, for --full deep debugging. Positions and facings are
## world-space Vector2s flattened to [x, y] pairs; hp/prone/stamina are index-aligned floats.
func _soldier_arrays(u: Node) -> Dictionary:
	var positions: Array = []
	for p in u._sim_soldier_pos:
		positions.append(DemoState.vec2_pair(p))
	var facings: Array = []
	for fdir in u._sim_soldier_facing:
		facings.append(DemoState.vec2_pair(fdir))
	return {
		"pos": positions,
		"facing": facings,
		"hp": _floats(u._sim_soldier_hp),
		"prone": _floats(u._sim_prone),
		"stamina": _floats(u._sim_soldier_stamina),
	}


## A PackedFloat32Array -> a plain Array of rounded floats, for JSON.
func _floats(arr: PackedFloat32Array) -> Array:
	var out: Array = []
	for v in arr:
		out.append(DemoState.round_to(v, 2))
	return out


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
