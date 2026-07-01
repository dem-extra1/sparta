class_name DemoFrames
## Pure parsing for the scripted-input demo frame-capture path (see demos/README.md).
## Given the SPARTA_DEMO_FRAMES value (a comma-separated tick list like "10,60,120") and
## an optional `frames` array from the input script, produce the sorted, de-duplicated set
## of physics ticks at which DemoInputRecorder should save a viewport PNG. No node/engine
## state — a deterministic function of its inputs only, so it's directly unit-testable like
## CameraKeyframes; the recorder calls it once at load and captures on the returned ticks.

## Parse a comma-separated tick list into a sorted, de-duplicated Array[int]. Whitespace and
## empty fields are ignored; non-integer or negative fields are dropped (a frame at a negative
## tick can never fire). "" -> []. So an unset env var yields no capture and the recorder runs
## exactly as before.
static func parse_ticks(spec: String) -> Array:
	var ticks: Array = []
	for field in spec.split(",", false):
		var trimmed: String = field.strip_edges()
		if trimmed == "" or not trimmed.is_valid_int():
			continue
		var tick: int = trimmed.to_int()
		if tick >= 0 and not ticks.has(tick):
			ticks.append(tick)
	ticks.sort()
	return ticks


## Merge the env-var tick list (SPARTA_DEMO_FRAMES) with a `frames` array from the input
## script into one sorted, de-duplicated tick set. Either source may be empty; the env var
## lets a reviewer capture frames from a demo whose script names none. Script `frames` entries
## are cast through int(); negatives are dropped, matching parse_ticks.
static func merge_ticks(spec: String, script_frames: Array) -> Array:
	var ticks: Array = parse_ticks(spec)
	for f in script_frames:
		var tick: int = int(f)
		if tick >= 0 and not ticks.has(tick):
			ticks.append(tick)
	ticks.sort()
	return ticks


## The PNG path for a capture at `tick` inside `dir`. Zero-pads the tick to 5 digits so a
## directory listing sorts frames in tick order (frame_00010.png before frame_00120.png).
static func frame_path(dir: String, tick: int) -> String:
	return "%s/frame_%05d.png" % [dir.trim_suffix("/"), tick]
