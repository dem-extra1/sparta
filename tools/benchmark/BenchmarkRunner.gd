extends Node
## Headless performance-benchmark entry point (see tools/benchmark/README.md). Set as the main
## scene under a plain `--headless` run (no Movie Maker, no rendering). It loads a
## demos/README.md-style "scenario" spec (a fixed large battle -- two armies already in
## contact so combat starts on tick 0, no scripted input needed), drives a LIVE Battle through
## it exactly like tools/demo/DemoInputRecorder.gd does for a custom demo matchup, and times
## the wall-clock cost of each physics tick with Time.get_ticks_usec(). After a warmup window
## (letting combat spin up -- an idle/marching tick is cheaper than an engaged one, so timing
## from tick 0 would understate the steady-state cost) it records N more ticks, aggregates them
## with BenchmarkStats, and writes a JSON report.
##
## Measures PHYSICS-STEP time only, not full frame/render time: this runner never opens a
## real renderer (plain --headless, no --rendering-driver), so there is nothing to measure on
## the render side anyway, and physics-step cost is what scales with soldier count / combat
## load -- the actual sim-hot-path this benchmark exists to catch regressions in. It also
## free-runs (Engine.max_fps = 0, no --fixed-fps lockstep) so each tick's measured cost is the
## real CPU time the step took, not a vsync-throttled/movie-recording-locked rate. This
## deliberately does NOT capture GPU/draw cost (sprite compositing, soldier mesh instancing),
## which is a real contributor to the actual 60fps target on the reference hardware -- see the
## README's "What this does and doesn't measure" section for the tradeoff and a suggested
## local-only windowed-mode follow-up.
##
## This is tooling: nothing in the live game references it, and it changes no simulation code.
## It is the performance-benchmark counterpart to tools/demo/DemoRunner.gd (which only records
## video) and tools/demo/DemoInputRecorder.gd (which drives scripted input) -- see those and
## demos/README.md for the sibling conventions this mirrors.

const BATTLE_SCENE := "res://scenes/Battle.tscn"
const DEFAULT_SCENARIO := "res://benchmarks/scenarios/large-battle.json"
const DEFAULT_WARMUP_TICKS := 120      # 2s at 60Hz: lets the lines close/clash before measuring.
const DEFAULT_MEASURE_TICKS := 600     # 10s at 60Hz: enough ticks for a stable mean/p95.
const DEFAULT_SCALE := 1.0
# Wall-clock backstop so a stalled run (e.g. the battle ends mid-warmup and physics_frame
# stops advancing the tick) can't hang the process forever. Generous: even a slow CI runner
# should clear warmup+measure well inside this.
const TIMEOUT_SEC := 300.0
# Consecutive physics_frame calls reporting the SAME battle tick before we conclude the sim
# has frozen (Battle._physics_process returns early once Battle._ended is true -- see
# tools/demo/DemoInputRecorder.gd's "the sim freezes its tick when a battle ends" comment) and
# stop early rather than waiting out the full TIMEOUT_SEC.
const STALL_LIMIT := 30

var _battle: Node = null
var _warmup_ticks: int = DEFAULT_WARMUP_TICKS
var _measure_ticks: int = DEFAULT_MEASURE_TICKS
var _scale: float = DEFAULT_SCALE
var _scenario_path: String = DEFAULT_SCENARIO
var _out_path: String = ""
var _seed_str: String = "0"
var _scaled_specs: Array = []
var _soldier_count: int = 0

var _frame_count: int = 0
var _last_time_usec: int = -1
var _samples_usec: Array = []
var _last_battle_tick: int = -1
var _stall_count: int = 0
var _finished: bool = false


func _ready() -> void:
	# Free-run physics as fast as the CPU allows -- see the class doc for why this matters:
	# a capped/vsynced rate would measure the cap, not the sim's real per-tick cost.
	Engine.max_fps = 0

	_scenario_path = _env_str("SPARTA_BENCHMARK_SCENARIO", DEFAULT_SCENARIO)
	_warmup_ticks = _env_int("SPARTA_BENCHMARK_WARMUP_TICKS", DEFAULT_WARMUP_TICKS)
	_measure_ticks = _env_int("SPARTA_BENCHMARK_TICKS", DEFAULT_MEASURE_TICKS)
	_scale = _env_float("SPARTA_BENCHMARK_SCALE", DEFAULT_SCALE)
	_out_path = OS.get_environment("SPARTA_BENCHMARK_OUT")
	if _out_path == "":
		_out_path = OS.get_temp_dir().path_join("sparta_benchmark_result.json")

	var script: Dictionary = _load_scenario(_scenario_path)
	_seed_str = str(script.get("seed", "0"))
	var specs: Array = script.get("scenario", [])
	if specs.is_empty():
		push_warning("[benchmark] scenario '%s' has no 'scenario' unit list; battle will be empty." % _scenario_path)
	_scaled_specs = BenchmarkStats.scale_scenario(specs, _scale)
	_soldier_count = BenchmarkStats.total_soldiers(_scaled_specs)

	print("[benchmark] scenario=%s scale=%.2f soldiers=%d warmup_ticks=%d measure_ticks=%d -> %s"
		% [_scenario_path, _scale, _soldier_count, _warmup_ticks, _measure_ticks, _out_path])

	get_tree().create_timer(TIMEOUT_SEC).timeout.connect(_on_timeout)
	_start_battle.call_deferred()


func _start_battle() -> void:
	Replay.forced_seed = int(_seed_str) if _seed_str.is_valid_int() else 0
	_battle = load(BATTLE_SCENE).instantiate()
	_battle.scenario = _scaled_specs   # set before add_child so Battle._ready reads it
	add_child(_battle)
	get_tree().physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	if _finished or _battle == null or not is_instance_valid(_battle):
		return

	var tick: int = _battle.current_tick()
	_stall_count = (_stall_count + 1) if tick == _last_battle_tick else 0
	_last_battle_tick = tick

	var now: int = Time.get_ticks_usec()
	if _last_time_usec >= 0 and _frame_count >= _warmup_ticks:
		_samples_usec.append(now - _last_time_usec)
	_last_time_usec = now
	_frame_count += 1

	if _stall_count >= STALL_LIMIT:
		push_warning("[benchmark] battle tick stopped advancing (ended early?) after %d samples; finishing with what was collected."
			% _samples_usec.size())
		_finish(true)
		return
	if _samples_usec.size() >= _measure_ticks:
		_finish(false)


func _on_timeout() -> void:
	if _finished:
		return
	push_warning("[benchmark] run timed out after %.0fs with %d/%d samples; writing partial results."
		% [TIMEOUT_SEC, _samples_usec.size(), _measure_ticks])
	_finish(true)


func _finish(early_stop: bool) -> void:
	if _finished:
		return
	_finished = true
	if get_tree().physics_frame.is_connected(_on_physics_frame):
		get_tree().physics_frame.disconnect(_on_physics_frame)

	var stats: Dictionary = BenchmarkStats.summarize(_samples_usec)
	var report: Dictionary = {
		"scenario": _scenario_path,
		"seed": _seed_str,
		"scale": _scale,
		"soldier_count": _soldier_count,
		"warmup_ticks": _warmup_ticks,
		"requested_measure_ticks": _measure_ticks,
		"samples_collected": stats["count"],
		"early_stop": early_stop,
		"stats": stats,
	}
	_write_report(report)

	print("[benchmark] done: %d/%d ticks sampled (%s), %d soldiers -- mean %.3fms p95 %.3fms max %.3fms (implied %.1f fps)"
		% [stats["count"], _measure_ticks, "early stop" if early_stop else "complete",
			_soldier_count, stats["mean_ms"], stats["p95_ms"], stats["max_ms"], stats["implied_fps"]])
	# push_error()/exit code does not reliably propagate from a headless Godot run (see
	# CLAUDE.md), so the wrapper script verifies the OUTPUT FILE, not this exit code, as the
	# authoritative success signal. Still return a best-effort nonzero code on an incomplete
	# run for anything that DOES check it (e.g. a human running the tool directly).
	get_tree().quit(1 if (early_stop or stats["count"] == 0) else 0)


func _write_report(report: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
	if f == null:
		push_warning("[benchmark] could not open %s for writing (err %d)" % [_out_path, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("[benchmark] wrote report -> %s" % _out_path)


func _load_scenario(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("[benchmark] scenario not found: %s" % path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[benchmark] scenario is not a JSON object: %s" % path)
		return {}
	return data


func _env_str(key: String, default_value: String) -> String:
	var v: String = OS.get_environment(key)
	return v if v != "" else default_value


func _env_int(key: String, default_value: int) -> int:
	var v: String = OS.get_environment(key)
	return int(v) if v.is_valid_int() else default_value


func _env_float(key: String, default_value: float) -> float:
	var v: String = OS.get_environment(key)
	return float(v) if v.is_valid_float() else default_value
