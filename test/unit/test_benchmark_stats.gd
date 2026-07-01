extends GutTest
## Pure stats/scaling helpers for the performance benchmark (tools/benchmark/BenchmarkStats.gd).
## Functions of their array/float inputs only — no node/battle/engine dependency — so they're
## directly unit-testable, unlike the live battle-driving part of BenchmarkRunner.gd (that part
## is verified by actually running the benchmark; see tools/benchmark/README.md).


func test_summarize_empty_is_all_zero_with_count_zero() -> void:
	var s: Dictionary = BenchmarkStats.summarize([])
	assert_eq(s["count"], 0, "no samples collected")
	assert_eq(s["mean_ms"], 0.0)
	assert_eq(s["p95_ms"], 0.0)
	assert_eq(s["max_ms"], 0.0)
	assert_eq(s["implied_fps"], 0.0, "no divide-by-zero on an empty run")


func test_summarize_single_sample() -> void:
	var s: Dictionary = BenchmarkStats.summarize([16000])   # 16ms in usec
	assert_eq(s["count"], 1)
	assert_almost_eq(s["mean_ms"], 16.0, 0.001)
	assert_almost_eq(s["p95_ms"], 16.0, 0.001)
	assert_almost_eq(s["min_ms"], 16.0, 0.001)
	assert_almost_eq(s["max_ms"], 16.0, 0.001)
	assert_almost_eq(s["implied_fps"], 62.5, 0.01, "1000 / 16ms")


func test_summarize_mean_and_extremes() -> void:
	# usec samples: 10ms, 20ms, 30ms.
	var s: Dictionary = BenchmarkStats.summarize([10000, 20000, 30000])
	assert_almost_eq(s["mean_ms"], 20.0, 0.001)
	assert_almost_eq(s["min_ms"], 10.0, 0.001)
	assert_almost_eq(s["max_ms"], 30.0, 0.001)


func test_summarize_p95_of_100_samples_is_the_95th_worst() -> void:
	# 100 samples: 1ms .. 100ms (as usec). Nearest-rank p95 of 100 values is the 95th
	# smallest -- 95.0ms here -- not an interpolated value between 95 and 96.
	var samples: Array = []
	for i in range(1, 101):
		samples.append(i * 1000)
	var s: Dictionary = BenchmarkStats.summarize(samples)
	assert_almost_eq(s["p95_ms"], 95.0, 0.001)


func test_summarize_p95_small_sample_count_does_not_overrun() -> void:
	# n=1..3: ceil(0.95*n) must clamp to a valid index, not run off the array end.
	assert_eq(BenchmarkStats.summarize([5000])["p95_ms"], 5.0)
	var s2: Dictionary = BenchmarkStats.summarize([5000, 10000])
	assert_almost_eq(s2["p95_ms"], 10.0, 0.001, "rank ceil(0.95*2)=2 -> the larger sample")


func test_summarize_does_not_require_pre_sorted_input() -> void:
	var s: Dictionary = BenchmarkStats.summarize([30000, 10000, 20000])
	assert_almost_eq(s["min_ms"], 10.0, 0.001)
	assert_almost_eq(s["max_ms"], 30.0, 0.001)


func test_scale_scenario_multiplies_count_and_rounds() -> void:
	var specs: Array = [{"team": 0, "type": "Infantry", "count": 120}]
	var scaled: Array = BenchmarkStats.scale_scenario(specs, 2.0)
	assert_eq(scaled[0]["count"], 240)
	# Unrelated fields pass through untouched.
	assert_eq(scaled[0]["type"], "Infantry")


func test_scale_scenario_floors_at_one_soldier() -> void:
	var specs: Array = [{"count": 1}]
	var scaled: Array = BenchmarkStats.scale_scenario(specs, 0.1)
	assert_eq(scaled[0]["count"], 1, "a scaled-down count never hits zero")


func test_scale_scenario_does_not_mutate_input() -> void:
	var specs: Array = [{"count": 100}]
	BenchmarkStats.scale_scenario(specs, 3.0)
	assert_eq(specs[0]["count"], 100, "the caller's original array/dicts are untouched")


func test_scale_scenario_leaves_specs_without_count_unchanged() -> void:
	var specs: Array = [{"team": 1, "type": "Cavalry"}]
	var scaled: Array = BenchmarkStats.scale_scenario(specs, 5.0)
	assert_false(scaled[0].has("count"))


func test_total_soldiers_sums_across_specs() -> void:
	var specs: Array = [{"count": 140}, {"count": 120}, {"count": 90}]
	assert_eq(BenchmarkStats.total_soldiers(specs), 350)


func test_total_soldiers_ignores_specs_without_count() -> void:
	var specs: Array = [{"count": 100}, {"team": 0}]
	assert_eq(BenchmarkStats.total_soldiers(specs), 100)
