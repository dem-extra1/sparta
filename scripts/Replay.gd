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

# Orders for the battle being recorded or played back.
# Each entry: { "tick": int, "units": Array[int] (uids), "x": float, "y": float,
#               "target": int (enemy uid, -1 move, -3 formation-only),
#               "mode": int (Battle.OrderMode; 0 = NORMAL),
#               "formation"?: int (Unit.FORMATION_*; omitted when 0 = NORMAL) }.
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

# Whether playback should drive the camera from the presentation track. Off by default,
# so in-app "Watch Replay" keeps free pan/zoom for inspection; the demo recorder
# (DemoRunner) turns it on so CI clips reproduce the recorded framing.
var drive_camera: bool = false
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
	var picker := RandomNumberGenerator.new()
	picker.randomize()
	seed_value = picker.seed
	rng.seed = seed_value
	_orders.clear()
	_camera_track.clear()
	_camera_index = 0
	drive_camera = false
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
	loaded_path = path
	mode = Mode.PLAYBACK
	return true


## Return to IDLE for a fresh battle (so the next Battle._ready re-records).
## Keeps the state transition in one place instead of having callers poke `mode`.
func reset() -> void:
	mode = Mode.IDLE
	drive_camera = false


## The folder replays are saved to (created if needed). For a file picker.
func replays_dir() -> String:
	_ensure_dir()
	return DIR


## RECORD: append an order at the current tick. No-op otherwise.
func record_order(tick: int, uids: Array, pos: Vector2, target_uid: int,
		order_mode: int = 0, formation: int = 0) -> void:
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
