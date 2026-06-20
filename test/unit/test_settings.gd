extends GutTest
## Settings: order-mode keybindings (#87) — defaults, lookup, rebind, reset, and the
## save/load round-trip. The keybindings dialog UI itself is verified manually (#12);
## here we pin the persistence + query logic the dialog and selector rely on.

const SettingsScript = preload("res://scripts/Settings.gd")
const BattleScript = preload("res://scripts/Battle.gd")
const TEST_PATH := "user://test_settings_87.cfg"


# A standalone Settings instance with disk writes / signals suppressed, for the
# in-memory assertions (so they never touch the real user://settings.cfg).
func _settings() -> Node:
	var s = SettingsScript.new()
	s._loading = true
	autofree(s)
	return s


func test_default_bindings_are_the_documented_keys() -> void:
	var s := _settings()
	assert_eq(s.order_binding("hold"), KEY_H, "Hold defaults to H")
	assert_eq(s.order_binding("attack_flank"), KEY_F, "Attack flank defaults to F")
	assert_eq(s.order_binding("attack_rear"), KEY_R, "Attack rear defaults to R")
	assert_eq(s.order_binding("skirmish"), KEY_K, "Skirmish defaults to K")
	assert_eq(s.order_binding("support"), KEY_G, "Support defaults to G")


func test_slug_for_keycode_resolves_back() -> void:
	var s := _settings()
	assert_eq(s.slug_for_keycode(KEY_H), "hold", "the default H maps back to hold")
	assert_eq(s.slug_for_keycode(KEY_Z), "", "an unbound key maps to nothing")


func test_set_order_binding_updates_both_directions() -> void:
	var s := _settings()
	s.set_order_binding("hold", KEY_Z)
	assert_eq(s.order_binding("hold"), KEY_Z, "the new key is stored")
	assert_eq(s.slug_for_keycode(KEY_Z), "hold", "...and resolves back to the slug")


func test_set_order_binding_ignores_unknown_slug() -> void:
	var s := _settings()
	s.set_order_binding("not_a_mode", KEY_Z)
	assert_eq(s.slug_for_keycode(KEY_Z), "", "an unknown slug is never stored")


func test_reset_restores_defaults() -> void:
	var s := _settings()
	s.set_order_binding("hold", KEY_Z)
	s.set_order_binding("support", KEY_X)
	s.reset_order_bindings()
	assert_eq(s.order_binding("hold"), KEY_H, "hold is back to default")
	assert_eq(s.order_binding("support"), KEY_G, "support is back to default")


func test_bindings_round_trip_through_disk() -> void:
	var a = SettingsScript.new()
	autofree(a)
	a._loading = true
	a.order_bindings["hold"] = KEY_Z
	a.order_bindings["support"] = KEY_X
	a._save(TEST_PATH)

	var b = SettingsScript.new()
	autofree(b)
	b._load(TEST_PATH)
	assert_eq(b.order_binding("hold"), KEY_Z, "a rebound key survives save + load")
	assert_eq(b.order_binding("support"), KEY_X, "...for each rebound slug")
	assert_eq(b.order_binding("attack_flank"), KEY_F, "untouched slugs keep their default")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func test_set_sfx_enabled_session_flips_value_without_persisting() -> void:
	# The demo recorder turns SFX on so recordings carry sound, but must not rewrite a
	# developer's saved preference: the session setter flips the in-memory flag while
	# suppressing both the disk write and the `changed` signal. A partial double (real
	# code, but calls recorded) lets us assert _save() is never called — pinning the
	# persistence guarantee directly, not just via the coupled signal, and without
	# touching the real settings.cfg. A fresh, NOT-loading instance proves the
	# suppression is the method's own doing (not the test harness's _loading=true).
	var s = partial_double(SettingsScript).new()
	autofree(s)
	watch_signals(s)
	assert_false(s.sfx_enabled, "sfx default off")
	s.set_sfx_enabled_session(true)
	assert_true(s.sfx_enabled, "session setter flips the in-memory value")
	assert_not_called(s, "_save")
	assert_signal_not_emitted(s, "changed", "...and emits no `changed`")
	assert_false(s._loading, "_loading restored to its prior value (false) after the call")


func test_set_sfx_enabled_session_restores_an_in_progress_load_guard() -> void:
	# fe7d166 made the setter save/restore _loading instead of hard-clearing it to
	# false, so a nested call (while a load is already in progress) doesn't drop the
	# guard. Pin that directly: with _loading already true, it must still be true
	# afterward — an assertion that fails against the old hard `_loading = false`.
	var s = SettingsScript.new()
	autofree(s)
	s._loading = true
	s.set_sfx_enabled_session(true)
	assert_true(s.sfx_enabled, "the value still flips while a load is in progress")
	assert_true(s._loading, "_loading restored to its prior (true) value, not hard-cleared")


func test_default_bindings_cover_exactly_battles_hotkey_slugs() -> void:
	# Settings.DEFAULT_ORDER_BINDINGS and Battle.ORDER_MODE_HOTKEYS must agree on the
	# slug set, or a mode would be unbindable (or a default binding orphaned).
	var battle_slugs: Array = []
	for entry in BattleScript.ORDER_MODE_HOTKEYS:
		battle_slugs.append(entry["slug"])
	battle_slugs.sort()
	var setting_slugs: Array = SettingsScript.DEFAULT_ORDER_BINDINGS.keys()
	setting_slugs.sort()
	assert_eq(setting_slugs, battle_slugs,
		"every rebindable mode has a default binding and vice-versa")
