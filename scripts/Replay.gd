extends Node
## Reproducible battle replays (autoload singleton: "Replay").
##
## Approach: *deterministic simulation + input log* — the same model many
## strategy games use. We do NOT record the state of every unit each frame. Instead we record
## just two things:
##   1. the RNG seed, and
##   2. the player's orders, each stamped with the physics tick it took effect.
## Replaying re-runs the *actual* battle simulation from the seed and re-injects
## the recorded orders on the same ticks, so the battle unfolds identically.
##
## This keeps logs tiny and — because it re-runs the real game logic — makes it
## genuinely useful for debugging (a bug that showed up in a battle reproduces
## exactly on replay).
##
## Determinism requirements (already satisfied by this project, noted so they
## stay true as the game grows):
##   - All gameplay randomness goes through `Replay.rng` (one seeded stream),
##     drawn in a stable order. Today that's the single `randf_range` in
##     Unit._strike, drawn once per striking unit in tree order each tick.
##   - The simulation advances on the fixed-rate physics tick (60 Hz), never on
##     a wall-clock / variable-framerate timer.
##   - Note: floating-point results are reproducible on the *same build and
##     platform*; bit-exact cross-platform replay is out of scope.

enum Mode { IDLE, RECORD, PLAYBACK }

const DIR := "user://replays"
const FORMAT_VERSION := 1
# The per-order "mode" field (smart orders) is additive and back-compatible:
# old replays omit it and load with mode 0 (OrderMode.NORMAL = current behaviour),
# so no version bump is needed and existing v1 replays still play.
const PHYSICS_TPS := 60

# IDLE before a battle is set up; RECORD while capturing a live battle;
# PLAYBACK while re-running a saved one.
var mode: int = Mode.IDLE

# The one seeded RNG the whole simulation draws from. Its seed is set once per
# battle by start_recording()/start_playback(); never call .randomize() or set
# .seed on it elsewhere, or replays will silently desync.
var rng := RandomNumberGenerator.new()
var seed_value: int = 0

# When >= 0, start_recording() uses this exact seed instead of a random one. The scripted-
# input demo recorder (tools/demo/DemoInputRecorder.gd) sets it so a live recording is
# reproducible. Never set in normal play (a fresh battle stays randomly seeded).
var forced_seed: int = -1

# Orders for the battle being recorded or played back.
# Each entry: { "tick": int, "units": Array[int] (uids), "x": float, "y": float,
#               "target": int (enemy uid, -1 move, -3 formation-only, -4 frontage-only),
#               "mode": int (Battle.OrderMode; 0 = NORMAL),
#               "formation"?: int (Unit.FORMATION_*; omitted when 0 = NORMAL),
#               "frontage"?: int (absolute file count for a -4 resize or a form-up move),
#               "face"?: float (deploy facing in radians for a drag-to-form-up move) }.
var _orders: Array = []
var _play_index: int = 0

# Presentation track (cosmetic): camera keyframes captured during live play so a
# replay reproduces what the player *saw* (zoom/pan), not just the sim. Each entry:
# { "tick": int, "x": float, "y": float, "zoom": float }. Recorded once per tick
# during RECORD, with consecutive-identical samples dropped (a static camera stores
# one keyframe). Never feeds the sim — purely how the recorded battle is framed on
# playback. Additive and back-compatible: replays without a camera track play with
# the default static camera, exactly as before (no version bump, like the per-order
# "mode" field above).
var _camera_track: Array = []
var _camera_index: int = 0

# Pointer track (cosmetic): the player's live mouse cursor, selection and multi-select
# drag-box captured during live play, so a demo replay reproduces what the player *did*
# with the mouse (not just the orders that resulted). Each entry:
# { "tick": int, "x": float, "y": float (cursor, world space), "drag": bool,
#   "sx": float, "sy": float (drag-box start corner, present only while dragging),
#   "sel": Array[int] (selected unit uids), "mode": int (armed Battle.OrderMode) }.
# Recorded once per tick during RECORD, dropping samples that don't differ from the last
# (cursor within POINTER_EPS, same drag/selection/mode) so a still pointer costs one
# keyframe. Never feeds the sim. Additive and back-compatible: replays without a pointer
# track play with no cursor overlay, exactly as before (no version bump).
var _pointer_track: Array = []
var _pointer_index: int = 0

# Keystroke track (cosmetic): the gameplay hotkeys the player pressed each tick, so a demo
# replay can flash the keys on screen (the keyboard counterpart to the pointer overlay).
# Each entry: { "tick": int, "labels": Array[String] (e.g. ["]"], ["T"]) }. Recorded only
# on ticks where a recognised hotkey fired. Never feeds the sim. Additive and
# back-compatible: replays without a keys track simply show no key chips (no version bump,
# like the camera/pointer tracks).
var _key_track: Array = []

# Cursor moves smaller than this (world px) don't add a keyframe — drops sub-pixel jitter
# while keeping deliberate motion. Larger than the camera track's exact dedup because the
# cursor is a continuous signal, not the camera's occasional pan.
const POINTER_EPS := 1.5

# Whether playback should drive the camera from the presentation track. Off by default,
# so in-app "Watch Replay" keeps free pan/zoom for inspection; the demo recorder
# (DemoRunner) turns it on so CI clips reproduce the recorded framing.
var drive_camera: bool = false
# Whether playback should render the order overlay (move/attack/waypoint markers) over
# the units, so a demo clip shows *what was commanded*, not just the resulting moves.
# Off by default — in-app Watch Replay keeps the orders on the Space-held survey only;
# the demo recorder (DemoRunner) turns it on. Cosmetic, never touches the sim.
var show_demo_orders: bool = false
# Bumped per save so two battles finishing in the same wall-clock second don't
# overwrite each other (the timestamp only has second precision).
var _save_counter: int = 0

# Metadata about the source file, for the HUD.
var loaded_path: String = ""
# Path of the most recent successful save() this session. Preferred over a fresh
# directory scan so a failed save can't silently replay a previous battle.
var last_saved_path: String = ""


## Begin capturing a fresh live battle. Picks a random seed and clears history.
func start_recording() -> void:
	mode = Mode.RECORD
	if forced_seed >= 0:
		# Deterministic seed for a scripted demo recording (see `forced_seed`).
		seed_value = forced_seed
		forced_seed = -1   # consumed; a later start_recording() randomises normally
	else:
		var picker := RandomNumberGenerator.new()
		picker.randomize()
		seed_value = picker.seed
	rng.seed = seed_value
	_orders.clear()
	_camera_track.clear()
	_camera_index = 0
	_pointer_track.clear()
	_pointer_index = 0
	_key_track.clear()
	drive_camera = false
	show_demo_orders = false
	_play_index = 0
	loaded_path = ""
	# Drop the previous battle's save path so a failed save() this battle can't
	# fall back to replaying the wrong one.
	last_saved_path = ""


## Load a saved replay and arm playback. Returns false if the file is unusable.
## The caller is expected to reload the battle scene afterwards; Battle._ready
## will see `mode == PLAYBACK` and re-run from the loaded seed instead of
## starting a new recording.
func start_playback(path: String) -> bool:
	var data := _read_file(path)
	if data.is_empty():
		return false
	if int(data.get("version", 0)) != FORMAT_VERSION:
		push_warning("Replay format mismatch in %s; skipping." % path)
		return false
	# Replays are only valid at the tick rate they were recorded at: orders are
	# stamped with physics ticks, so a different rate would replay them at the
	# wrong wall-clock moments and desync the battle.
	if int(data.get("physics_tps", 0)) != PHYSICS_TPS:
		push_warning("Replay physics tick rate mismatch in %s; skipping." % path)
		return false

	# Seed is stored as a string: JSON numbers are float64 and would lose
	# precision on a full 64-bit seed, silently desyncing the replay.
	seed_value = int(str(data.get("seed", "0")))
	rng.seed = seed_value
	_orders.clear()
	for o in data.get("orders", []):
		var uids: Array = []
		for u in o.get("units", []):
			uids.append(int(u))
		var entry := {
			"tick": int(o.get("tick", 0)),
			"units": uids,
			"x": float(o.get("x", 0.0)),
			"y": float(o.get("y", 0.0)),
			"target": int(o.get("target", -1)),
			"mode": int(o.get("mode", 0)),   # 0 = OrderMode.NORMAL
		}
		if o.has("formation"):
			entry["formation"] = int(o["formation"])
		if o.has("frontage"):
			entry["frontage"] = int(o["frontage"])
		if o.has("face"):
			entry["face"] = float(o["face"])
		_orders.append(entry)
	_play_index = 0
	# Load the optional presentation (camera) track. Absent in pre-camera replays,
	# which then play with the default static camera.
	_camera_track.clear()
	_camera_index = 0
	for c in data.get("camera", []):
		_camera_track.append({
			"tick": int(c.get("tick", 0)),
			"x": float(c.get("x", 0.0)),
			"y": float(c.get("y", 0.0)),
			"zoom": float(c.get("zoom", 1.0)),
		})
	# Load the optional pointer (cursor/selection/drag-box) track. Absent in replays
	# recorded before this track existed, which then play with no cursor overlay.
	_pointer_track.clear()
	_pointer_index = 0
	for p in data.get("pointer", []):
		var sel: Array = []
		for u in p.get("sel", []):
			sel.append(int(u))
		var entry := {
			"tick": int(p.get("tick", 0)),
			"x": float(p.get("x", 0.0)),
			"y": float(p.get("y", 0.0)),
			"drag": bool(p.get("drag", false)),
			"sel": sel,
			"mode": int(p.get("mode", 0)),
		}
		if entry["drag"]:
			entry["sx"] = float(p.get("sx", entry["x"]))
			entry["sy"] = float(p.get("sy", entry["y"]))
		_pointer_track.append(entry)
	# Load the optional keystroke track. Absent in replays recorded before it existed,
	# which then play with no key chips.
	_key_track.clear()
	for k in data.get("keys", []):
		var labels: Array = []
		for s in k.get("labels", []):
			labels.append(str(s))
		_key_track.append({"tick": int(k.get("tick", 0)), "labels": labels})
	loaded_path = path
	mode = Mode.PLAYBACK
	return true


## Return to IDLE for a fresh battle (so the next Battle._ready re-records).
## Keeps the state transition in one place instead of having callers poke `mode`.
func reset() -> void:
	mode = Mode.IDLE
	drive_camera = false
	show_demo_orders = false


## The folder replays are saved to (created if needed). For a file picker.
func replays_dir() -> String:
	_ensure_dir()
	return DIR


## RECORD: append an order at the current tick. No-op otherwise.
func record_order(tick: int, uids: Array, pos: Vector2, target_uid: int,
		order_mode: int = 0, formation: int = 0, frontage: int = 0, face: float = INF) -> void:
	if mode != Mode.RECORD:
		return
	var entry := {
		"tick": tick,
		"units": uids.duplicate(),
		"x": pos.x,
		"y": pos.y,
		"target": target_uid,
		"mode": order_mode,   # 0 = OrderMode.NORMAL
	}
	if formation != 0:
		entry["formation"] = formation
	if frontage != 0:
		entry["frontage"] = frontage
	# A drag-to-form-up order carries a deploy facing (radians); INF means "none"
	# (a plain move), so any real angle -- including 0 -- is recorded.
	if not is_inf(face):
		entry["face"] = face
	_orders.append(entry)


## PLAYBACK: return all orders scheduled for `tick` (in record order), advancing
## the read cursor. Returns an empty array when not in playback.
func orders_for_tick(tick: int) -> Array:
	if mode != Mode.PLAYBACK:
		return []
	var due: Array = []
	while _play_index < _orders.size() and int(_orders[_play_index]["tick"]) == tick:
		due.append(_orders[_play_index])
		_play_index += 1
	# Skip any (shouldn't happen) orders whose tick we've already passed.
	while _play_index < _orders.size() and int(_orders[_play_index]["tick"]) < tick:
		_play_index += 1
	return due


## RECORD: capture the camera at `tick`. No-op otherwise. A sample equal to the last
## stored keyframe (same position and zoom) is dropped, so a still camera costs one
## keyframe and only real moves add entries. Cosmetic — never read by the simulation.
func record_camera(tick: int, pos: Vector2, zoom: float) -> void:
	if mode != Mode.RECORD:
		return
	if not _camera_track.is_empty():
		var last: Dictionary = _camera_track[_camera_track.size() - 1]
		if is_equal_approx(last["x"], pos.x) and is_equal_approx(last["y"], pos.y) \
				and is_equal_approx(last["zoom"], zoom):
			return
	_camera_track.append({"tick": tick, "x": pos.x, "y": pos.y, "zoom": zoom})


## Whether a presentation (camera) track is loaded — true only for replays recorded
## with one. Callers use it to decide whether to drive the camera from the track.
func has_camera_track() -> bool:
	return not _camera_track.is_empty()


## PLAYBACK: the camera state to apply at `tick` — the latest keyframe at or before it
## (the camera holds its last framing until the next recorded move; before the first
## keyframe it holds the first). Returns {} when not in playback or no track is loaded.
## Advances an internal cursor, so call it with non-decreasing ticks (as the tick loop
## does); it also tolerates a step back to an earlier tick.
func camera_for_tick(tick: int) -> Dictionary:
	if mode != Mode.PLAYBACK or _camera_track.is_empty():
		return {}
	# A replay that steps backward (e.g. a restarted playback) rewinds the cursor.
	if _camera_index > 0 and int(_camera_track[_camera_index]["tick"]) > tick:
		_camera_index = 0
	while _camera_index + 1 < _camera_track.size() \
			and int(_camera_track[_camera_index + 1]["tick"]) <= tick:
		_camera_index += 1
	return _camera_track[_camera_index]


## RECORD: capture the pointer (cursor world pos, drag-box, selection, armed mode) at
## `tick`. No-op otherwise. A sample that matches the last keyframe — cursor within
## POINTER_EPS, same drag corner, same selection set and mode — is dropped, so a still
## pointer costs one keyframe. Cosmetic — never read by the simulation.
func record_pointer(tick: int, cursor: Vector2, dragging: bool, drag_start: Vector2,
		selection: Array, armed_mode: int) -> void:
	# `mode` here is the Replay member (RECORD/PLAYBACK); the stance is `armed_mode`.
	if mode != Mode.RECORD:
		return
	if not _pointer_track.is_empty():
		var last: Dictionary = _pointer_track[_pointer_track.size() - 1]
		var still: bool = bool(last["drag"]) == dragging \
				and int(last["mode"]) == armed_mode \
				and last["sel"] == selection \
				and Vector2(last["x"], last["y"]).distance_to(cursor) <= POINTER_EPS
		if still and dragging:
			still = Vector2(last.get("sx", 0.0), last.get("sy", 0.0)).distance_to(drag_start) <= POINTER_EPS
		if still:
			return
	var entry := {
		"tick": tick,
		"x": cursor.x,
		"y": cursor.y,
		"drag": dragging,
		"sel": selection.duplicate(),
		"mode": armed_mode,
	}
	if dragging:
		entry["sx"] = drag_start.x
		entry["sy"] = drag_start.y
	_pointer_track.append(entry)


## Whether a pointer track is loaded — true only for replays recorded with one.
func has_pointer_track() -> bool:
	return not _pointer_track.is_empty()


## Advance _pointer_index to the latest keyframe at or before `tick`, rewinding if the
## caller stepped back to an earlier tick. Shared by pointer_for_tick and
## pointer_cursor_for_tick so they always agree on the current keyframe. Assumes a
## non-empty track (callers check) and non-decreasing ticks in the common case.
func _advance_pointer_index(tick: int) -> void:
	if _pointer_index > 0 and int(_pointer_track[_pointer_index]["tick"]) > tick:
		_pointer_index = 0
	while _pointer_index + 1 < _pointer_track.size() \
			and int(_pointer_track[_pointer_index + 1]["tick"]) <= tick:
		_pointer_index += 1


## PLAYBACK: the pointer state to apply at `tick` — the latest keyframe at or before it
## (holds its last state until the next recorded change), mirroring camera_for_tick.
## Returns {} when not in playback or no track is loaded. Advances an internal cursor, so
## call with non-decreasing ticks; tolerates a step back to an earlier tick.
func pointer_for_tick(tick: int) -> Dictionary:
	if mode != Mode.PLAYBACK or _pointer_track.is_empty():
		return {}
	_advance_pointer_index(tick)
	return _pointer_track[_pointer_index]


## PLAYBACK: the cursor position at `tick`, linearly interpolated between the surrounding
## pointer keyframes so the cursor visibly GLIDES between samples instead of snapping --
## the discrete state (selection, drag, stance from pointer_for_tick) still changes at
## keyframe boundaries, only the cursor moves continuously. Holds the first/last position
## outside the track's range. Returns ZERO when not in playback or no track is loaded
## (callers gate on has_pointer_track). Walks the same _pointer_index as pointer_for_tick.
func pointer_cursor_for_tick(tick: int) -> Vector2:
	if mode != Mode.PLAYBACK or _pointer_track.is_empty():
		return Vector2.ZERO
	_advance_pointer_index(tick)
	var cur: Dictionary = _pointer_track[_pointer_index]
	var cur_pos := Vector2(cur["x"], cur["y"])
	if _pointer_index + 1 >= _pointer_track.size():
		return cur_pos
	var nxt: Dictionary = _pointer_track[_pointer_index + 1]
	var span: float = float(int(nxt["tick"]) - int(cur["tick"]))
	if span <= 0.0:
		return cur_pos
	var f: float = clampf(float(tick - int(cur["tick"])) / span, 0.0, 1.0)
	return cur_pos.lerp(Vector2(nxt["x"], nxt["y"]), f)


## PLAYBACK: positions of orders issued within `window` ticks before `tick`, each with its
## age in ticks, so the overlay can pulse a ring where each order was just commanded. All
## recorded orders are the player's own. Read-only — does not disturb the orders_for_tick
## read cursor. Returns [] outside playback. Orders are tick-sorted, so the scan stops at the
## first future order (no need to walk past `tick`).
func pulses_for_tick(tick: int, window: int) -> Array:
	if mode != Mode.PLAYBACK:
		return []
	var out: Array = []
	for o in _orders:
		var ot: int = int(o["tick"])
		if ot > tick:
			break
		if tick - ot <= window:
			out.append({"x": float(o["x"]), "y": float(o["y"]), "age": tick - ot})
	return out


## RECORD: capture the gameplay-hotkey labels pressed at `tick`. No-op otherwise or when
## nothing was pressed. Cosmetic — never read by the simulation.
func record_keys(tick: int, labels: Array) -> void:
	if mode != Mode.RECORD or labels.is_empty():
		return
	_key_track.append({"tick": tick, "labels": labels.duplicate()})


## PLAYBACK: hotkey labels pressed within `window` ticks before `tick`, each with its age in
## ticks, so the overlay can flash a chip for each recent keypress. Read-only; returns []
## outside playback. The track is tick-sorted, so the scan stops at the first future entry.
func keys_for_tick(tick: int, window: int) -> Array:
	if mode != Mode.PLAYBACK:
		return []
	var out: Array = []
	for k in _key_track:
		var kt: int = int(k["tick"])
		if kt > tick:
			break
		if tick - kt <= window:
			for label in k["labels"]:
				out.append({"label": str(label), "age": tick - kt})
	return out


## PLAYBACK: form-up (drag-deploy) orders issued within `window` ticks before `tick`,
## each as {x, y (centre), face (radians), frontage, age}, so the overlay can replay the
## dragged flank line. Read-only; [] outside playback. Tick-sorted, so the scan stops at
## the first future order.
func form_ups_for_tick(tick: int, window: int) -> Array:
	if mode != Mode.PLAYBACK:
		return []
	var out: Array = []
	for o in _orders:
		var ot: int = int(o["tick"])
		if ot > tick:
			break
		if o.has("face") and tick - ot <= window:
			out.append({"x": float(o["x"]), "y": float(o["y"]), "face": float(o["face"]),
					"frontage": int(o.get("frontage", 1)), "age": tick - ot})
	return out


## Persist the recorded battle. Returns the file path, or "" if nothing/failed.
func save(result: String, duration_ticks: int) -> String:
	if mode != Mode.RECORD:
		return ""
	if not _ensure_dir():
		return ""
	# ISO 8601-style with the 'T' kept (no space) and colons swapped for '-', so
	# the filename is conventional and shell-friendly. A counter suffix keeps it
	# unique even when two battles end in the same second.
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-")
	var path := "%s/battle_%s_%02d.json" % [DIR, stamp, _save_counter]
	_save_counter += 1
	var payload := {
		"version": FORMAT_VERSION,
		"seed": str(seed_value),   # string to preserve full 64-bit precision
		"physics_tps": PHYSICS_TPS,
		"created": Time.get_unix_time_from_system(),
		"result": result,
		"duration_ticks": duration_ticks,
		"orders": _orders,
	}
	# Only emit the presentation track when one was captured, so pre-camera-style
	# recordings (and tooling that never moves the camera) stay byte-for-byte simple.
	if not _camera_track.is_empty():
		payload["camera"] = _camera_track
	# Likewise emit the pointer track only when one was captured, so recordings without
	# mouse activity (and pre-pointer-track tooling) stay simple.
	if not _pointer_track.is_empty():
		payload["pointer"] = _pointer_track
	# Likewise emit the keystroke track only when keys were pressed.
	if not _key_track.is_empty():
		payload["keys"] = _key_track
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write replay to %s" % path)
		return ""
	f.store_string(JSON.stringify(payload, "  "))
	f.close()
	last_saved_path = path
	return path


# --- internals -------------------------------------------------------------

func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(DIR):
		return true
	return DirAccess.make_dir_recursive_absolute(DIR) == OK
