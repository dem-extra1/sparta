extends GutTest
## Pure tick-list parsing for the scripted-input demo frame-capture path (tools/demo/
## DemoFrames.gd). A function of its string/array inputs only — no recorder/battle instance —
## so it's directly unit-testable like CameraKeyframes. The live capture (viewport -> PNG) needs
## a real renderer and is verified by rendering a demo, not headlessly here.


func test_parse_ticks_sorts_and_dedupes() -> void:
	assert_eq(DemoFrames.parse_ticks("120,10,60,10"), [10, 60, 120],
		"parses, sorts ascending, and drops the duplicate 10")


func test_parse_ticks_ignores_whitespace_and_empty_fields() -> void:
	assert_eq(DemoFrames.parse_ticks(" 10 , , 60 ,"), [10, 60],
		"whitespace trimmed and empty fields skipped")


func test_parse_ticks_empty_string_is_empty() -> void:
	assert_eq(DemoFrames.parse_ticks(""), [],
		"unset env var -> no capture, recorder runs as before")


func test_parse_ticks_drops_non_integer_and_negative_fields() -> void:
	assert_eq(DemoFrames.parse_ticks("10,abc,-5,60"), [10, 60],
		"non-integer 'abc' and negative -5 dropped; valid ticks kept")


func test_merge_ticks_unions_env_and_script_frames() -> void:
	assert_eq(DemoFrames.merge_ticks("10,60", [60, 120]), [10, 60, 120],
		"env and script frames merged, sorted, de-duplicated")


func test_merge_ticks_env_only() -> void:
	assert_eq(DemoFrames.merge_ticks("30,10", []), [10, 30],
		"env var alone captures frames from a script that names none")


func test_merge_ticks_script_only() -> void:
	assert_eq(DemoFrames.merge_ticks("", [90, 20]), [20, 90],
		"an empty env value falls back to the script 'frames' array")


func test_merge_ticks_drops_invalid_script_entries() -> void:
	# int("abc") is 0 in GDScript, so a stray non-integer must be rejected, not coerced to tick 0.
	assert_eq(DemoFrames.merge_ticks("", ["abc", -5, 60, 20.0]), [20, 60],
		"non-integer and negative script entries dropped; a float tick kept")


func test_merge_ticks_both_empty_is_empty() -> void:
	assert_eq(DemoFrames.merge_ticks("", []), [],
		"nothing armed -> capture stays off")


func test_frame_path_zero_pads_for_sortable_listing() -> void:
	assert_eq(DemoFrames.frame_path("/out", 20), "/out/frame_00020.png",
		"tick zero-padded to 5 digits so a listing sorts by tick")


func test_frame_path_trims_trailing_slash() -> void:
	assert_eq(DemoFrames.frame_path("/out/", 120), "/out/frame_00120.png",
		"a trailing slash on the dir doesn't double up")
