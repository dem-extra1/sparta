class_name BenchmarkStats
## Pure helpers for tools/benchmark/BenchmarkRunner.gd: aggregating a series of per-tick
## timing samples into summary statistics, and scaling a demos/README.md-style "scenario"
## unit list's soldier counts by a multiplier. No node/engine dependency -- both are plain
## functions of their inputs, so they're unit-testable headlessly (see
## test/unit/test_benchmark_stats.gd), unlike the live battle-driving part of the runner.


## Summarize a series of per-tick timings (microseconds) into mean/p95/min/max, in both
## microseconds and milliseconds, plus the implied fps if this is the bottleneck (1000 /
## mean_ms). Empty input returns all-zero stats with count 0 -- callers should check `count`
## before trusting the rest (e.g. a battle that ended during warmup, before any tick was
## sampled).
static func summarize(samples_usec: Array) -> Dictionary:
	var n: int = samples_usec.size()
	if n == 0:
		return {
			"count": 0, "mean_usec": 0.0, "p95_usec": 0.0, "min_usec": 0.0, "max_usec": 0.0,
			"mean_ms": 0.0, "p95_ms": 0.0, "min_ms": 0.0, "max_ms": 0.0, "implied_fps": 0.0,
		}
	var sorted_samples: Array = samples_usec.duplicate()
	sorted_samples.sort()
	var total: float = 0.0
	for s in sorted_samples:
		total += float(s)
	var mean_usec: float = total / n
	var p95_usec: float = float(sorted_samples[_p95_index(n)])
	var min_usec: float = float(sorted_samples[0])
	var max_usec: float = float(sorted_samples[n - 1])
	return {
		"count": n,
		"mean_usec": mean_usec, "p95_usec": p95_usec, "min_usec": min_usec, "max_usec": max_usec,
		"mean_ms": mean_usec / 1000.0, "p95_ms": p95_usec / 1000.0,
		"min_ms": min_usec / 1000.0, "max_ms": max_usec / 1000.0,
		# fps implied by the MEAN tick cost, if the physics step were the sole bottleneck
		# (no render cost, no vsync wait) -- see tools/benchmark/README.md for what this
		# does and doesn't capture.
		"implied_fps": (1000.0 / (mean_usec / 1000.0)) if mean_usec > 0.0 else 0.0,
	}


## Index of the 95th-percentile sample in a sorted, `n`-long series (nearest-rank method,
## 1-indexed rank ceil(0.95 * n), converted to a 0-indexed array position and clamped so a
## tiny sample count (n=1..3) still returns a valid index instead of running off the end).
static func _p95_index(n: int) -> int:
	var rank: int = int(ceil(0.95 * n))
	return clampi(rank - 1, 0, n - 1)


## Scale a demos/README.md-style "scenario" unit-spec list's soldier counts by `scale`
## (e.g. 2.0 doubles every unit's headcount), for the local scaling sweep described in
## tools/benchmark/README.md ("Finding the soldier-count ceiling"). Returns a NEW array of
## NEW dicts -- the input is never mutated, so the caller can scale the same loaded scenario
## multiple times. Each spec's "count" is rounded to the nearest int and floored at 1 (a
## scaled-down count can't hit zero soldiers). Specs without a "count" key pass through
## unchanged (BenchmarkRunner requires every benchmark scenario spec to set one explicitly;
## see benchmarks/scenarios/large-battle.json).
static func scale_scenario(specs: Array, scale: float) -> Array:
	var out: Array = []
	for spec in specs:
		if typeof(spec) != TYPE_DICTIONARY:
			out.append(spec)
			continue
		var d: Dictionary = (spec as Dictionary).duplicate()
		if d.has("count"):
			d["count"] = maxi(1, int(round(float(d["count"]) * scale)))
		out.append(d)
	return out


## Total soldier headcount across a scenario spec list (sum of each unit's "count"), for
## reporting how many bodies a run actually simulated. Specs missing "count" contribute 0
## (BenchmarkRunner's reference scenario always sets it explicitly).
static func total_soldiers(specs: Array) -> int:
	var total: int = 0
	for spec in specs:
		if typeof(spec) == TYPE_DICTIONARY and (spec as Dictionary).has("count"):
			total += int((spec as Dictionary)["count"])
	return total
