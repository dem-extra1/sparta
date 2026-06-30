class_name CameraKeyframes
## Pure interpolation of a scripted-input demo's camera track (#412). Given a list of
## keyframes [{tick, x, y, zoom}, ...] sorted by tick, and the current physics tick, return
## the interpolated framing {x, y, zoom}. Linear by tick fraction between the two surrounding
## keyframes; clamps to the first/last frame outside the track's range, so a single-keyframe
## track (the old behaviour) just holds that framing for the whole clip. No node/engine state
## — a deterministic function of (track, tick) only, so it's directly unit-testable like
## DistanceLegend; DemoInputRecorder samples it each tick and sets the camera.
static func sample(track: Array, tick: int) -> Dictionary:
	if track.is_empty():
		return {}
	# Before (or at) the first keyframe, and for a lone keyframe: hold the first framing.
	if track.size() == 1 or tick <= int(track[0]["tick"]):
		return _frame(track[0])
	var last: Dictionary = track[track.size() - 1]
	if tick >= int(last["tick"]):
		return _frame(last)
	for i in range(track.size() - 1):
		var a: Dictionary = track[i]
		var b: Dictionary = track[i + 1]
		var ta: int = int(a["tick"])
		var tb: int = int(b["tick"])
		if tick >= ta and tick <= tb:
			# span == 0 means duplicate ticks; snap to the later frame rather than divide by zero.
			var span: int = tb - ta
			var f: float = 1.0 if span <= 0 else float(tick - ta) / float(span)
			return {
				"x": lerpf(float(a["x"]), float(b["x"]), f),
				"y": lerpf(float(a["y"]), float(b["y"]), f),
				"zoom": lerpf(float(a["zoom"]), float(b["zoom"]), f),
			}
	# Unreachable given the clamps above, but keeps the function total.
	return _frame(last)


## True if the track's keyframe ticks are non-decreasing — sample() assumes this (it scans
## segments front-to-back). The recorder checks it once at load and warns if violated, since
## an out-of-order track would silently interpolate the wrong segments.
static func is_sorted(track: Array) -> bool:
	for i in range(track.size() - 1):
		if int(track[i + 1]["tick"]) < int(track[i]["tick"]):
			return false
	return true


## Normalize a keyframe to a bare {x, y, zoom} float framing (drops the tick).
static func _frame(kf: Dictionary) -> Dictionary:
	return {"x": float(kf["x"]), "y": float(kf["y"]), "zoom": float(kf["zoom"])}
