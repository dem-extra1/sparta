extends GutHookScript

# GUT post-run hook: turn the coverage collected by test/pre_run_hook.gd into an
# lcov report (lcov.info) that Codecov ingests directly. The coverage tool
# itself only emits JSON, so we walk its per-script, per-line hit data and write
# lcov ourselves.

const Coverage = preload("res://addons/coverage/Coverage.gd")

# Where the report is written. CI overrides this via the environment so the
# path can differ from the local default; see .github/workflows/test-coverage.yml.
const DEFAULT_LCOV_PATH := "res://coverage/lcov.info"

func run():
	var coverage = Coverage.get_instance()
	var lcov_path := OS.get_environment("COVERAGE_LCOV_FILE")
	if lcov_path == "":
		lcov_path = DEFAULT_LCOV_PATH
	_write_lcov(coverage, lcov_path)
	# Print a one-line-per-file summary and clear the singleton, which reverts
	# the instrumented scripts to their original source. Read coverage data
	# BEFORE this call -- finalize() replaces the instance with a no-op.
	Coverage.finalize(Coverage.Verbosity.Filenames)

# Write lcov "tracefile" records for every instrumented script.
func _write_lcov(coverage, lcov_path: String) -> void:
	var out := PackedStringArray()
	var collectors: Dictionary = coverage.coverage_collectors
	var script_paths := collectors.keys()
	script_paths.sort()
	for script_path in script_paths:
		var collector = collectors[script_path]
		var lines: Dictionary = collector.get_coverage_json()
		out.append("SF:%s" % _res_to_relative(script_path))
		var line_numbers := lines.keys()
		line_numbers.sort()
		var hit := 0
		for line_number in line_numbers:
			var count := int(lines[line_number])
			# Godot line indices are 0-based; lcov DA lines are 1-based.
			out.append("DA:%d,%d" % [int(line_number) + 1, count])
			if count > 0:
				hit += 1
		out.append("LF:%d" % line_numbers.size())
		out.append("LH:%d" % hit)
		out.append("end_of_record")
	var text := "\n".join(out)
	if text != "":
		text += "\n"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(lcov_path.get_base_dir()))
	var f := FileAccess.open(lcov_path, FileAccess.WRITE)
	if f == null:
		push_error("Unable to open %s for writing lcov coverage" % lcov_path)
		return
	f.store_string(text)
	f.close()
	print("Wrote lcov coverage for %d files to %s" % [script_paths.size(), lcov_path])

# Codecov maps coverage to files by repo-relative path, so drop the res:// prefix.
func _res_to_relative(res_path: String) -> String:
	return res_path.trim_prefix("res://")
