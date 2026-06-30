extends GutTest
## HUD control-bar stance dropup: pins the single source of truth (_STANCE_ENTRIES)
## and the helpers the three stance sites now share — the menu builder, the rebind
## refresh, and the button caption. The coverage test guards the desync the
## consolidation prevents: a new OrderMode that never reaches the dropup.

const HUDScript = preload("res://scripts/HUD.gd")
const BattleScript = preload("res://scripts/Battle.gd")


func _hud() -> HUDScript:
	var h := HUDScript.new()
	autofree(h)
	return h


func test_stance_entries_cover_every_order_mode() -> void:
	var h := _hud()
	var entry_modes := {}
	for entry in h._STANCE_ENTRIES:
		entry_modes[entry["mode"]] = true
	for mode: int in BattleScript.OrderMode.values():
		assert_true(entry_modes.has(mode),
			"OrderMode %d must have a _STANCE_ENTRIES row" % mode)
	assert_eq(h._STANCE_ENTRIES.size(), BattleScript.OrderMode.values().size(),
		"one stance entry per OrderMode, no extras")


func test_stance_entry_ids_are_sequential_and_unique() -> void:
	var h := _hud()
	var ids := []
	for entry in h._STANCE_ENTRIES:
		ids.append(entry["id"])
	assert_eq(ids, range(h._STANCE_ENTRIES.size()),
		"popup item ids are 0..N-1 in order; refresh/build index by id")


func test_label_for_mode_matches_each_entry() -> void:
	var h := _hud()
	for entry in h._STANCE_ENTRIES:
		assert_eq(h._stance_label_for_mode(entry["mode"]), entry["label"],
			"caption label round-trips through the mode lookup")


func test_label_for_unknown_mode_falls_back_to_normal() -> void:
	var h := _hud()
	assert_eq(h._stance_label_for_mode(999), "Normal",
		"an unmapped mode falls back to Normal, as before")


func test_normal_entry_is_fixed_to_esc() -> void:
	var h := _hud()
	var normal: Dictionary = h._STANCE_ENTRIES[0]
	assert_eq(normal["mode"], BattleScript.OrderMode.NORMAL, "first entry is NORMAL")
	assert_eq(normal["slug"], "", "NORMAL has no rebindable slug")
	assert_eq(h._stance_key_str(normal), "Esc", "NORMAL shows the fixed Esc key")
	assert_eq(h._stance_item_text(normal), "Normal  (Esc)",
		"NORMAL menu text is the fixed caption")


func test_rebindable_entry_text_shows_label_and_a_key() -> void:
	var h := _hud()
	var hold: Dictionary = h._STANCE_ENTRIES[1]
	assert_ne(hold["slug"], "", "rebindable entries carry a slug")
	var text := h._stance_item_text(hold)
	assert_string_starts_with(text, hold["label"] + "  (",
		"menu text leads with the label then the bound key in parens")
	assert_string_ends_with(text, ")", "the hotkey hint is parenthesized")
