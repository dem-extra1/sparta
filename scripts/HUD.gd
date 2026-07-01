extends CanvasLayer
## On-screen UI, built in code (no .tscn needed):
##   - top hint bar
##   - top-right Menu button: restart the battle plus global options
##   - selected-unit info panel (bottom-left)
##   - victory/defeat overlay with a restart button

const BattleRef = preload("res://scripts/Battle.gd")
const CampaignBattleRef = preload("res://scripts/campaign/CampaignBattle.gd")
const SelectionManagerRef = preload("res://scripts/SelectionManager.gd")
const UnitRef = preload("res://scripts/Unit.gd")

# Stable ids for the Menu popup's items (independent of index / separators). The two
# MENU_FORMUP_* ids set the default multi-unit form-up distribution (radio-checked).
enum { MENU_RESTART, MENU_RESTART_REPLAY, MENU_LOAD, MENU_EDGE_SCROLL, MENU_SFX,
		MENU_FORMUP_EQUAL_DEPTH, MENU_FORMUP_EQUAL_WIDTH,
		MENU_FORMUP_CYCLE_DEPTH, MENU_FORMUP_CYCLE_WIDTH,
		MENU_REFORM_BEFORE_MOVE, MENU_WALK_ADVANCE, MENU_DISTANCE_LEGEND, MENU_ORDER_DISTANCE,
		MENU_UNIT_SPEED, MENU_KEYBINDINGS, MENU_SHORTCUTS }

var _hint: Label
var _info: Label
var _overlay: ColorRect
var _overlay_label: Label
var _menu_button: MenuButton
var _status: Label
var _paused_label: Label
var _order_mode_label: Label
var _flash_label: Label
var _watch_button: Button
var _load_dialog: FileDialog
var _error_dialog: AcceptDialog
var _keybindings_dialog: AcceptDialog
var _shortcuts_dialog: AcceptDialog
var _legend_panel: PanelContainer
var _legend_bar: ColorRect
var _legend_label: Label
var _legend_last_zoom: float = -1.0   # forces a first sync; _process re-syncs only on change
const PANEL_MIN := Vector2(240, 90)
const PANEL_BOTTOM_GAP := 20.0   # clearance between info panel and screen edge

# Single source of truth for the rebindable stance modes shown in the control-bar
# dropup. Each entry carries the popup item id, the OrderMode it maps to, the
# display label (used both as the menu text and the button caption), and the
# rebind slug. NORMAL is fixed to Esc and has no rebindable slug (empty string).
# Adding an OrderMode here updates the menu, the rebind refresh, and the caption
# in one place. See _stance_key_str() for how the slug becomes a hotkey label.
const _STANCE_ENTRIES := [
	{"id": 0, "mode": BattleRef.OrderMode.NORMAL, "label": "Normal", "slug": ""},
	{"id": 1, "mode": BattleRef.OrderMode.HOLD, "label": "Hold", "slug": "hold"},
	{"id": 2, "mode": BattleRef.OrderMode.ATTACK_FLANK, "label": "Flank", "slug": "attack_flank"},
	{"id": 3, "mode": BattleRef.OrderMode.ATTACK_REAR, "label": "Rear", "slug": "attack_rear"},
	{"id": 4, "mode": BattleRef.OrderMode.SKIRMISH, "label": "Skirmish", "slug": "skirmish"},
	{"id": 5, "mode": BattleRef.OrderMode.SUPPORT, "label": "Support", "slug": "support"},
	{"id": 6, "mode": BattleRef.OrderMode.CYCLE_CHARGE, "label": "Cycle charge", "slug": "cycle_charge"},
]

# Display names and menu order for every formation mode, shared by the button
# caption and the drop-up menu so the two never drift apart.
const _FORMATION_NAMES := {
	UnitRef.FORMATION_NORMAL: "Normal",
	UnitRef.FORMATION_TIGHT: "Tight",
	UnitRef.FORMATION_LOOSE: "Loose",
	UnitRef.FORMATION_SQUARE: "Square",
	UnitRef.FORMATION_SHIELD_WALL: "Shield Wall",
	UnitRef.FORMATION_TESTUDO: "Testudo",
}
const _FORMATION_MENU_ORDER := [
	UnitRef.FORMATION_NORMAL,
	UnitRef.FORMATION_TIGHT,
	UnitRef.FORMATION_LOOSE,
	UnitRef.FORMATION_SQUARE,
	UnitRef.FORMATION_SHIELD_WALL,
	UnitRef.FORMATION_TESTUDO,
]

var _ctrl_bar: PanelContainer
var _ctrl_formation_btn: MenuButton
var _ctrl_stance_btn: MenuButton
var _ctrl_reform_btn: Button
var _ctrl_group_attack_btn: Button
var _sel_mgr = null
var _info_panel: PanelContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # stays responsive when paused

	# Controls hint. The order-mode keys are rendered from the live Settings bindings
	# so the bar stays accurate after a rebind; _refresh_hint re-renders on change.
	_hint = Label.new()
	_hint.position = Vector2(14, 10)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_hint.add_theme_font_size_override("font_size", 14)
	add_child(_hint)
	_refresh_hint()

	# Recording / replay status (top-center).
	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status.position = Vector2(-90, 30)
	_status.custom_minimum_size = Vector2(180, 0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 15)
	if Replay.mode == Replay.Mode.PLAYBACK:
		_status.text = "▶ REPLAY"
		_status.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	else:
		_status.text = "● REC"
		_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	add_child(_status)

	# Active-pause indicator (top-center, below the REC/REPLAY status). Hidden
	# until the player toggles pause with Space.
	_paused_label = Label.new()
	_paused_label.text = "⏸ PAUSED"
	_paused_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_paused_label.position = Vector2(-90, 54)
	_paused_label.custom_minimum_size = Vector2(180, 0)
	_paused_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paused_label.add_theme_font_size_override("font_size", 18)
	_paused_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.35))
	_paused_label.visible = false
	add_child(_paused_label)

	# Armed order-mode indicator, top-center below the pause banner. Hidden
	# for the default stance; SelectionManager calls set_order_mode() to update it.
	_order_mode_label = Label.new()
	_order_mode_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_order_mode_label.position = Vector2(-120, 80)
	_order_mode_label.custom_minimum_size = Vector2(240, 0)
	_order_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_order_mode_label.add_theme_font_size_override("font_size", 16)
	_order_mode_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.35))
	_order_mode_label.visible = false
	add_child(_order_mode_label)

	# Transient toast just below the order-mode indicator, for brief one-off feedback
	# (e.g. the form-up distribution cycle hotkey). Auto-hides after a moment; see flash_message().
	_flash_label = Label.new()
	_flash_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_flash_label.position = Vector2(-120, 104)
	_flash_label.custom_minimum_size = Vector2(240, 0)
	_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash_label.add_theme_font_size_override("font_size", 15)
	_flash_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.65))
	_flash_label.visible = false
	add_child(_flash_label)

	# Menu button (top-right) gathering the global options that used to be
	# scattered across the HUD — restart, replay loading, and the edge-scroll
	# toggle. Its popup is PROCESS_MODE_ALWAYS so it stays usable while the
	# simulation is paused. Give the button an explicit width so its placement is
	# derived from that, not a font-metric-tuned magic offset.
	_menu_button = MenuButton.new()
	_menu_button.text = "☰ Menu"
	var menu_width := 120.0
	_menu_button.custom_minimum_size = Vector2(menu_width, 0)
	_menu_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_menu_button.position = Vector2(-menu_width - 6.0, 6)
	add_child(_menu_button)

	var popup := _menu_button.get_popup()
	popup.process_mode = Node.PROCESS_MODE_ALWAYS   # usable while paused
	# "Restart Battle" works mid-fight, not just from the end-of-battle overlay;
	# it always starts a fresh LIVE battle (matching the overlay's "Fight Again").
	# "Restart Replay" instead rewinds the current playback to tick 0, so it's
	# only meaningful while watching a replay — disabled (greyed) in a live battle.
	popup.add_item("Restart Battle", MENU_RESTART)
	popup.add_item("Restart Replay", MENU_RESTART_REPLAY)
	popup.set_item_disabled(popup.get_item_index(MENU_RESTART_REPLAY),
			Replay.mode != Replay.Mode.PLAYBACK)
	popup.add_item("Load Replay…", MENU_LOAD)
	popup.add_separator()
	popup.add_check_item("Mouse-edge scroll", MENU_EDGE_SCROLL)
	popup.add_check_item("Sound effects", MENU_SFX)
	# Default split for a multi-unit drag-to-form-up (radio: pick one). The live mode can
	# also be cycled mid-battle with the form-up distribution hotkey.
	popup.add_separator("Form-up: split a line by…")
	popup.add_radio_check_item("Equal depth (ranks)", MENU_FORMUP_EQUAL_DEPTH)
	popup.add_radio_check_item("Equal width (frontage)", MENU_FORMUP_EQUAL_WIDTH)
	# Which modes the Y-key cycles through (check to include, uncheck to skip).
	popup.add_separator("Form-up: Y-key cycles through…")
	popup.add_check_item("Equal depth (ranks)", MENU_FORMUP_CYCLE_DEPTH)
	popup.add_check_item("Equal width (frontage)", MENU_FORMUP_CYCLE_WIDTH)
	popup.add_separator()
	popup.add_check_item("Reform before move", MENU_REFORM_BEFORE_MOVE)
	popup.add_check_item("Walk advance (no jog/sprint)", MENU_WALK_ADVANCE)
	popup.add_check_item("Distance legend (map scale)", MENU_DISTANCE_LEGEND)
	popup.add_check_item("Order distance labels", MENU_ORDER_DISTANCE)
	popup.add_check_item("Unit speed labels", MENU_UNIT_SPEED)
	popup.add_item("Keybindings…", MENU_KEYBINDINGS)
	popup.add_item("Shortcuts… (?)", MENU_SHORTCUTS)
	_sync_setting_toggles()
	popup.id_pressed.connect(_on_menu_id)
	# Keep the check items in sync if a setting changes elsewhere. Use a named
	# method (not a lambda) so the connection is tied to this node's lifetime and
	# torn down in _exit_tree() — otherwise it would dangle on the persistent
	# Settings autoload after reload_current_scene() frees this HUD.
	Settings.changed.connect(_sync_setting_toggles)
	# Same lifetime concern: keep the hint's order-mode keys in sync after a rebind.
	Settings.changed.connect(_refresh_hint)
	# Keep the stance dropup labels in sync after a rebind (see _ctrl_bar_refresh_stance_popup).
	Settings.changed.connect(_ctrl_bar_refresh_stance_popup)

	# File picker for choosing a saved replay, plus an error popup for bad files.
	# Both stay responsive while the tree is paused (end-of-battle overlay).
	_load_dialog = FileDialog.new()
	_load_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_load_dialog.access = FileDialog.ACCESS_USERDATA
	_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_load_dialog.filters = PackedStringArray(["*.json ; Replay files"])
	_load_dialog.title = "Load Replay"
	_load_dialog.size = Vector2i(640, 480)
	_load_dialog.file_selected.connect(_on_replay_chosen)
	add_child(_load_dialog)

	_error_dialog = AcceptDialog.new()
	_error_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	# Neutral default; each caller sets a context-specific title before popping it.
	_error_dialog.title = "Replay"
	add_child(_error_dialog)

	# Rebindable order-mode hotkeys. Its own PROCESS_MODE_ALWAYS dialog so it's
	# usable while paused, like the other menu dialogs.
	_keybindings_dialog = preload("res://scripts/KeybindingsDialog.gd").new()
	add_child(_keybindings_dialog)

	# Read-only "every shortcut" reference, opened by ? or ☰ Menu → Shortcuts.
	_shortcuts_dialog = preload("res://scripts/ShortcutsOverlay.gd").new()
	add_child(_shortcuts_dialog)

	# Selected-unit info panel, pinned above the bottom-left corner. The top
	# offset is derived from the panel's own min-height + bottom margin (not a
	# hand-tuned magic number), and grow_vertical = BEGIN lets it expand UPWARD
	# if a content row or a larger font is added — so it never clips past the
	# screen's bottom edge.
	_info_panel = PanelContainer.new()
	_info_panel.custom_minimum_size = PANEL_MIN
	_info_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_info_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info_panel.position = Vector2(14.0, -(PANEL_MIN.y + PANEL_BOTTOM_GAP))
	add_child(_info_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_info_panel.add_child(margin)

	_info = Label.new()
	_info.text = "No unit selected"
	margin.add_child(_info)

	_sel_mgr = get_node_or_null("../SelectionManager")
	_build_ctrl_bar()
	_build_distance_legend()

	# End-of-battle overlay.
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.6)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	_overlay_label = Label.new()
	_overlay_label.text = "Battle Over"
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.add_theme_font_size_override("font_size", 48)
	box.add_child(_overlay_label)

	# A campaign-launched battle returns its result to the map instead of
	# restarting; "Fight Again"/"Load Replay" (which replace this battle) would strand
	# the campaign, so only offer Return + Watch Replay there. Safe to decide at _ready
	# (rather than in show_end): `active` is set before the battle scene loads and stays
	# fixed for the battle's whole lifetime — nothing toggles it mid-battle.
	if CampaignBattleRef.active:
		var ret := Button.new()
		ret.text = "⮐ Return to Campaign"
		ret.custom_minimum_size = Vector2(220, 44)
		ret.pressed.connect(_on_return_to_campaign)
		box.add_child(ret)
	else:
		var restart := Button.new()
		restart.text = "Fight Again"
		restart.custom_minimum_size = Vector2(180, 44)
		restart.pressed.connect(_on_restart)
		box.add_child(restart)

	# Replay the battle that just finished (re-runs the saved log).
	_watch_button = Button.new()
	_watch_button.text = "Watch Again" if Replay.mode == Replay.Mode.PLAYBACK else "Watch Replay"
	_watch_button.custom_minimum_size = Vector2(180, 44)
	_watch_button.pressed.connect(_on_watch_replay)
	box.add_child(_watch_button)

	# Open an older saved replay (not just the one that just finished). Hidden for a
	# campaign battle, whose only forward path is back to the map.
	if not CampaignBattleRef.active:
		var load_saved := Button.new()
		load_saved.text = "Load Replay…"
		load_saved.custom_minimum_size = Vector2(180, 44)
		load_saved.pressed.connect(_open_load_dialog)
		box.add_child(load_saved)


func _exit_tree() -> void:
	# Settings is a persistent autoload; drop our connection so it doesn't
	# outlive this HUD (e.g. across reload_current_scene()).
	if Settings.changed.is_connected(_sync_setting_toggles):
		Settings.changed.disconnect(_sync_setting_toggles)
	if Settings.changed.is_connected(_refresh_hint):
		Settings.changed.disconnect(_refresh_hint)
	if Settings.changed.is_connected(_ctrl_bar_refresh_stance_popup):
		Settings.changed.disconnect(_ctrl_bar_refresh_stance_popup)


func _sync_setting_toggles() -> void:
	var popup := _menu_button.get_popup()
	popup.set_item_checked(popup.get_item_index(MENU_EDGE_SCROLL), Settings.edge_scroll)
	popup.set_item_checked(popup.get_item_index(MENU_SFX), Settings.sfx_enabled)
	# Radio-check the chosen default form-up distribution. Compare each item to the setting
	# directly (not `not depth`) so adding a third mode later can't leave both unchecked.
	popup.set_item_checked(popup.get_item_index(MENU_FORMUP_EQUAL_DEPTH),
			Settings.form_up_dist_default == SelectionManagerRef.FormUpDist.EQUAL_DEPTH)
	popup.set_item_checked(popup.get_item_index(MENU_FORMUP_EQUAL_WIDTH),
			Settings.form_up_dist_default == SelectionManagerRef.FormUpDist.EQUAL_WIDTH)
	popup.set_item_checked(popup.get_item_index(MENU_FORMUP_CYCLE_DEPTH),
			Settings.form_up_dist_cycle.has(Settings.FORM_UP_DIST_EQUAL_DEPTH))
	popup.set_item_checked(popup.get_item_index(MENU_FORMUP_CYCLE_WIDTH),
			Settings.form_up_dist_cycle.has(Settings.FORM_UP_DIST_EQUAL_WIDTH))
	# Disable the cycle checkbox for whichever mode is the current battle default: unchecking
	# it would leave the default unreachable by the Y-key cycle, with no feedback that it
	# happened. Disabling it (rather than warning after the fact) makes the inconsistency
	# impossible instead of just visible.
	popup.set_item_disabled(popup.get_item_index(MENU_FORMUP_CYCLE_DEPTH),
			Settings.form_up_dist_default == SelectionManagerRef.FormUpDist.EQUAL_DEPTH)
	popup.set_item_disabled(popup.get_item_index(MENU_FORMUP_CYCLE_WIDTH),
			Settings.form_up_dist_default == SelectionManagerRef.FormUpDist.EQUAL_WIDTH)
	# The default can also become excluded the other way: the player narrows the cycle to one
	# OTHER mode, then later switches the default radio to the excluded one. Guarantee the
	# current default is always in the cycle, and re-check its (now-disabled) box directly —
	# not via the Settings.changed signal this setter emits, since the very first call here
	# (from _ready, before the signal is connected) must also self-correct synchronously.
	if not Settings.form_up_dist_cycle.has(Settings.form_up_dist_default):
		var cycle: Array = Settings.form_up_dist_cycle.duplicate()
		cycle.append(Settings.form_up_dist_default)
		Settings.form_up_dist_cycle = SelectionManagerRef.FORM_UP_DIST_CYCLE.filter(
				func(m) -> bool: return cycle.has(m))
		popup.set_item_checked(popup.get_item_index(MENU_FORMUP_CYCLE_DEPTH),
				Settings.form_up_dist_cycle.has(Settings.FORM_UP_DIST_EQUAL_DEPTH))
		popup.set_item_checked(popup.get_item_index(MENU_FORMUP_CYCLE_WIDTH),
				Settings.form_up_dist_cycle.has(Settings.FORM_UP_DIST_EQUAL_WIDTH))
	popup.set_item_checked(popup.get_item_index(MENU_REFORM_BEFORE_MOVE),
			Settings.reform_before_move)
	popup.set_item_checked(popup.get_item_index(MENU_WALK_ADVANCE),
			Settings.walk_advance)
	popup.set_item_checked(popup.get_item_index(MENU_DISTANCE_LEGEND),
			Settings.show_distance_legend)
	popup.set_item_checked(popup.get_item_index(MENU_ORDER_DISTANCE),
			Settings.show_order_distance)
	popup.set_item_checked(popup.get_item_index(MENU_UNIT_SPEED),
			Settings.show_unit_speed)
	_sync_distance_legend_visibility()
	_ctrl_bar_sync_settings()


## Rebuild the controls hint, rendering the order-mode keys from the live Settings
## bindings so the bar reflects rebinds instead of the hardcoded defaults.
func _refresh_hint() -> void:
	if _hint == null:
		return
	var keys: String = ""
	for entry in BattleRef.ORDER_MODE_HOTKEYS:
		if keys != "":
			keys += "/"
		keys += OS.get_keycode_string(Settings.order_binding(entry["slug"]))
	_hint.text = "LMB select / drag-box   •   RMB move or attack   •   Shift+RMB add waypoint   •   %s order mode (Esc clear)   •   T formation (Tight/Loose/Square/Normal)   •   O square   •   WASD / two-finger pan   •   wheel / pinch zoom   •   P pause   •   hold Space show orders" % keys


## Dispatch a Menu popup selection by its stable item id.
func _on_menu_id(id: int) -> void:
	match id:
		MENU_RESTART:
			_on_restart()
		MENU_RESTART_REPLAY:
			_on_restart_replay()
		MENU_LOAD:
			_open_load_dialog()
		MENU_EDGE_SCROLL:
			# Flip the setting; Settings.changed -> _sync_setting_toggles re-checks it.
			Settings.edge_scroll = not Settings.edge_scroll
		MENU_SFX:
			Settings.sfx_enabled = not Settings.sfx_enabled
		MENU_FORMUP_EQUAL_DEPTH:
			# Settings.changed -> _sync_setting_toggles re-checks the radios.
			Settings.form_up_dist_default = SelectionManagerRef.FormUpDist.EQUAL_DEPTH
		MENU_FORMUP_EQUAL_WIDTH:
			Settings.form_up_dist_default = SelectionManagerRef.FormUpDist.EQUAL_WIDTH
		MENU_FORMUP_CYCLE_DEPTH:
			_toggle_form_up_cycle(Settings.FORM_UP_DIST_EQUAL_DEPTH)
		MENU_FORMUP_CYCLE_WIDTH:
			_toggle_form_up_cycle(Settings.FORM_UP_DIST_EQUAL_WIDTH)
		MENU_REFORM_BEFORE_MOVE:
			Settings.reform_before_move = not Settings.reform_before_move
		MENU_WALK_ADVANCE:
			Settings.walk_advance = not Settings.walk_advance
		MENU_DISTANCE_LEGEND:
			# Settings.changed -> _sync_setting_toggles -> _sync_distance_legend_visibility,
			# same as every other menu toggle here.
			Settings.show_distance_legend = not Settings.show_distance_legend
		MENU_ORDER_DISTANCE:
			Settings.show_order_distance = not Settings.show_order_distance
		MENU_UNIT_SPEED:
			Settings.show_unit_speed = not Settings.show_unit_speed
		MENU_KEYBINDINGS:
			_keybindings_dialog.popup_centered()
		MENU_SHORTCUTS:
			_shortcuts_dialog.popup_centered()


func _toggle_form_up_cycle(mode: int) -> void:
	var enabled: Array = Settings.form_up_dist_cycle.duplicate()
	if enabled.has(mode):
		# The menu item is disabled for the current default (see _sync_setting_toggles), so
		# this normally can't fire for it; guard anyway since it's cheap and keeps the
		# invariant (default stays reachable by Y) true regardless of how this is reached.
		if mode == Settings.form_up_dist_default:
			_sync_setting_toggles()
			return
		enabled.erase(mode)
		# Keep at least one mode so the UI and Y-key behavior stay consistent.
		# (An empty cycle falls back silently to all modes in SelectionManager,
		# which would leave the checkboxes unchecked while Y still cycles both.)
		if enabled.is_empty():
			_sync_setting_toggles()   # Godot already auto-toggled before id_pressed; restore the checkbox
			return
	else:
		enabled.append(mode)
	# Rebuild in canonical order so the Y-key sequence is predictable regardless of
	# the order modes were checked/unchecked.
	Settings.form_up_dist_cycle = SelectionManagerRef.FORM_UP_DIST_CYCLE.filter(
			func(m) -> bool: return enabled.has(m))


func _process(_delta: float) -> void:
	_update_distance_legend()


func _unhandled_input(event: InputEvent) -> void:
	# P toggles active pause: the sim freezes but selection and camera stay
	# live (they run as PROCESS_MODE_ALWAYS), so orders can be queued while paused
	# and apply on resume. Disabled once the end-of-battle overlay is up.
	if _is_pause_keypress(event) and not _overlay.visible:
		_toggle_pause()
	elif _is_shortcuts_keypress(event) and not _overlay.visible:
		_shortcuts_dialog.popup_centered()
		get_viewport().set_input_as_handled()


## Shift+/ produces "?" on a standard layout; physical_keycode (the / key) keeps the
## binding layout-independent, like the pause/edge-scroll keys. Same shape as
## _is_pause_keypress -- Shift carries the second meaning of an otherwise-plain key.
func _is_shortcuts_keypress(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	return event.physical_keycode == KEY_SLASH and event.shift_pressed


func _is_pause_keypress(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	# P toggles pause; Shift+Space does too (plain Space is reserved for the
	# hold-to-show-orders overlay, so it must carry Shift to mean "pause"). Use
	# physical_keycode so the binding is layout-independent and unaffected by the
	# held modifier. Shift+Space is used rather than Ctrl+Space because macOS
	# reserves Ctrl+Space for input-source switching, so it never reaches the app.
	if event.physical_keycode == KEY_P:
		return true
	return event.physical_keycode == KEY_SPACE and event.shift_pressed


func _toggle_pause() -> void:
	var paused: bool = not get_tree().paused
	get_tree().paused = paused
	_paused_label.visible = paused
	get_viewport().set_input_as_handled()


func show_unit(u, group_count: int) -> void:
	if u == null or not is_instance_valid(u):
		clear_unit()
		return
	var extra: String = "" if group_count <= 1 else "  (+%d more)" % (group_count - 1)
	var kind: String
	if u.is_cavalry:
		kind = "Cavalry"
	elif u.anti_cavalry:
		kind = "Spearmen"
	elif u.is_ranged:
		kind = "Archers"
	else:
		kind = "Infantry"
	var cohesion_text: String = "" if u.cohesion >= 1.0 \
			else "  Cohesion: %d%%" % mini(roundi(u.cohesion * 100.0), 99)
	var training_text: String = "" if u.training <= 0.0 \
			else "  Training: %d%%" % clampi(roundi(u.training * 100.0), 1, 100)
	_info.text = "%s%s\nType: %s\nSoldiers: %d / %d\nMorale: %d  Fatigue: %d%%%s%s\nFormation: %s  Width: %s  Order: %s" % [
		u.unit_name, extra, kind, u.soldiers, u.max_soldiers, int(u.morale), int(u.fatigue),
		cohesion_text, training_text, u.formation_summary(), UnitFormation.files_label(UnitFormation.frontage(u)),
		u.order_summary()
	]
	if _ctrl_bar != null:
		_ctrl_bar.visible = true
		_info_panel_raise()
		_ctrl_bar_update_formation(u)
		_ctrl_bar_update_stance(_sel_mgr.get_armed_mode() if _sel_mgr != null else 0)
		update_group_attack_mode(_sel_mgr.get_group_attack_mode() if _sel_mgr != null else 0)


func clear_unit() -> void:
	_info.text = "No unit selected"
	if _ctrl_bar != null:
		_ctrl_bar.visible = false
		_info_panel_lower()


## Show the armed order mode. Empty text hides the indicator (default stance).
func set_order_mode(text: String, mode: int = BattleRef.OrderMode.NORMAL) -> void:
	if text == "":
		_order_mode_label.visible = false
	else:
		_order_mode_label.text = "Order: %s" % text
		_order_mode_label.visible = true
	_ctrl_bar_update_stance(mode)


## Briefly show a one-line toast, then auto-hide it. Used for transient feedback like the
## form-up distribution cycle. A fresh call supersedes any toast still showing (the newer
## text wins, so the older timer's hide is a no-op).
const FLASH_SECONDS := 1.3
func flash_message(text: String) -> void:
	_flash_label.text = text
	_flash_label.visible = true
	# process_always so it ticks while the sim is paused (orders/cycles work paused too).
	var timer := get_tree().create_timer(FLASH_SECONDS, true)
	timer.timeout.connect(_hide_flash.bind(text))


## Hide the toast unless a newer flash_message() has since replaced its text. Guarded against
## a freed label so a deferred timer can't touch this HUD after a scene reload.
func _hide_flash(text: String) -> void:
	if is_instance_valid(_flash_label) and _flash_label.text == text:
		_flash_label.visible = false


## Reflect the current group-attack distribution mode on the ctrl bar button.
func update_group_attack_mode(mode: int) -> void:
	if _ctrl_group_attack_btn == null:
		return
	var labels := {
		BattleRef.GroupAttackMode.FOCUSED: "Focused atk",
		BattleRef.GroupAttackMode.DISTRIBUTED: "Spread atk",
	}
	_ctrl_group_attack_btn.text = labels.get(mode, "Atk mode")


func _ctrl_bar_sync_settings() -> void:
	if _ctrl_reform_btn == null:
		return
	_ctrl_reform_btn.button_pressed = Settings.reform_before_move


# --- Distance legend (map scale bar, #364) ----------------------------------
# A small semi-translucent panel in the bottom-right corner showing the battlefield's
# real metre scale at the current camera zoom (DistanceLegend has the pure math). Bottom-
# left is the selected-unit info panel and bottom-center is the control bar, so bottom-
# right is the free corner.

const _LEGEND_MARGIN := Vector2(14.0, 14.0)
const _LEGEND_BAR_HEIGHT := 6.0
const _LEGEND_PAD := 10.0

func _build_distance_legend() -> void:
	_legend_panel = PanelContainer.new()
	_legend_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_legend_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_legend_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_legend_panel.position = -_LEGEND_MARGIN   # offset off the corner; grows up-and-left from here
	_legend_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Semi-translucent panel background (distinct from the opaque default panel style),
	# per #364's spec -- the battlefield should stay visible through it.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(_LEGEND_PAD)
	_legend_panel.add_theme_stylebox_override("panel", style)
	add_child(_legend_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_legend_panel.add_child(col)

	_legend_bar = ColorRect.new()
	_legend_bar.color = Color(1, 1, 1, 0.9)
	_legend_bar.custom_minimum_size = Vector2(DistanceLegend.MIN_PX, _LEGEND_BAR_HEIGHT)
	col.add_child(_legend_bar)

	_legend_label = Label.new()
	_legend_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_legend_label.add_theme_font_size_override("font_size", 13)
	_legend_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	col.add_child(_legend_label)

	_sync_distance_legend_visibility()


func _sync_distance_legend_visibility() -> void:
	if _legend_panel == null:
		return
	_legend_panel.visible = Settings.show_distance_legend
	if _legend_panel.visible:
		_legend_last_zoom = -1.0   # force an immediate resync; _process only updates on change


## Re-measure the bar against the live camera zoom each frame, but cheaply: skip the work
## entirely when the zoom hasn't moved (the common case while the player isn't scrolling).
func _update_distance_legend() -> void:
	if _legend_panel == null or not _legend_panel.visible:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	if is_equal_approx(cam.zoom.x, _legend_last_zoom):
		return
	_legend_last_zoom = cam.zoom.x
	var mpp: float = DistanceLegend.metres_per_pixel(cam.zoom.x, BattleRef.WORLD_UNITS_PER_METER)
	var metres: float = DistanceLegend.pick_round_metres(mpp)
	_legend_bar.custom_minimum_size.x = DistanceLegend.bar_width_px(metres, mpp)
	_legend_label.text = DistanceLegend.label_text(metres)


func _ctrl_bar_refresh_stance_popup() -> void:
	if _ctrl_stance_btn == null:
		return
	var popup := _ctrl_stance_btn.get_popup()
	for entry: Dictionary in _STANCE_ENTRIES:
		var item_id: int = entry["id"]
		popup.set_item_text(popup.get_item_index(item_id), _stance_item_text(entry))


func _ctrl_bar_update_formation(unit) -> void:
	if _ctrl_formation_btn == null or unit == null or not is_instance_valid(unit):
		return
	_ctrl_formation_btn.text = _FORMATION_NAMES.get(unit.formation_mode, "Formation") + " ▾"


func _ctrl_bar_update_stance(mode: int) -> void:
	if _ctrl_stance_btn == null:
		return
	_ctrl_stance_btn.text = _stance_label_for_mode(mode) + " ▾"


## The hotkey label shown next to a stance item: "Esc" for the fixed Normal
## entry (no rebindable slug), else the player's current binding for its slug.
func _stance_key_str(entry: Dictionary) -> String:
	var slug: String = entry["slug"]
	if slug == "":
		return "Esc"
	return OS.get_keycode_string(Settings.order_binding(slug))


## Full menu text for a stance entry: "Label  (Key)".
func _stance_item_text(entry: Dictionary) -> String:
	return "%s  (%s)" % [entry["label"], _stance_key_str(entry)]


## The display label for an OrderMode, used as the stance button caption.
## Falls back to "Normal" for an unmapped mode, matching the previous behavior.
func _stance_label_for_mode(mode: int) -> String:
	for entry: Dictionary in _STANCE_ENTRIES:
		if entry["mode"] == mode:
			return entry["label"]
	return "Normal"


## Build the bottom control bar: formation, stance, and per-order options.
func _build_ctrl_bar() -> void:
	_ctrl_bar = PanelContainer.new()
	_ctrl_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ctrl_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ctrl_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ctrl_bar.position = Vector2(0, -10)
	_ctrl_bar.visible = false
	add_child(_ctrl_bar)

	var outer := MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 8)
	outer.add_theme_constant_override("margin_right", 8)
	outer.add_theme_constant_override("margin_top", 6)
	outer.add_theme_constant_override("margin_bottom", 6)
	_ctrl_bar.add_child(outer)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	outer.add_child(hbox)

	hbox.add_child(_build_ctrl_section("Formation", _build_ctrl_formation_menu()))
	hbox.add_child(VSeparator.new())
	hbox.add_child(_build_ctrl_section("Stance", _build_ctrl_stance_menu()))
	hbox.add_child(VSeparator.new())
	hbox.add_child(_build_ctrl_section("Options", _build_ctrl_option_buttons()))

	_ctrl_bar_sync_settings()
	update_group_attack_mode(BattleRef.GroupAttackMode.FOCUSED)


func _build_ctrl_section(label_text: String, content: Control) -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	vbox.add_child(lbl)
	vbox.add_child(content)
	return vbox


func _build_ctrl_formation_menu() -> Control:
	_ctrl_formation_btn = MenuButton.new()
	_ctrl_formation_btn.text = "Normal ▾"
	_ctrl_formation_btn.custom_minimum_size = Vector2(90, 28)
	_ctrl_formation_btn.add_theme_font_size_override("font_size", 13)
	var popup := _ctrl_formation_btn.get_popup()
	for mode: int in _FORMATION_MENU_ORDER:
		popup.add_item(_FORMATION_NAMES[mode], mode)
		popup.set_item_metadata(popup.get_item_index(mode), mode)
	popup.about_to_popup.connect(_reposition_dropup.bind(popup, _ctrl_formation_btn))
	popup.id_pressed.connect(_on_formation_popup_id)
	return _ctrl_formation_btn


func _build_ctrl_stance_menu() -> Control:
	_ctrl_stance_btn = MenuButton.new()
	_ctrl_stance_btn.text = "Normal ▾"
	_ctrl_stance_btn.custom_minimum_size = Vector2(110, 28)
	_ctrl_stance_btn.add_theme_font_size_override("font_size", 13)
	var popup := _ctrl_stance_btn.get_popup()
	# NORMAL (Esc) is fixed and not rebindable; the other entries show their
	# current keybinding. _STANCE_ENTRIES drives all three stance sites.
	for entry: Dictionary in _STANCE_ENTRIES:
		var item_id: int = entry["id"]
		popup.add_item(_stance_item_text(entry), item_id)
		popup.set_item_metadata(popup.get_item_index(item_id), entry["mode"])
	popup.about_to_popup.connect(_reposition_dropup.bind(popup, _ctrl_stance_btn))
	popup.id_pressed.connect(_on_stance_popup_id)
	return _ctrl_stance_btn


func _reposition_dropup(popup: PopupMenu, btn: Control) -> void:
	# Defer so Godot finishes its first layout pass before we read popup.size.
	(func():
		popup.position = Vector2i(
			int(btn.global_position.x),
			int(btn.global_position.y) - popup.size.y
		)).call_deferred()


func _on_formation_popup_id(id: int) -> void:
	if _sel_mgr != null:
		_sel_mgr.set_formation_to(id)
	_ctrl_formation_btn.text = _FORMATION_NAMES.get(id, "Formation") + " ▾"


func _on_stance_popup_id(id: int) -> void:
	var popup := _ctrl_stance_btn.get_popup()
	var mode: int = popup.get_item_metadata(popup.get_item_index(id))
	if _sel_mgr != null:
		_sel_mgr.arm_order_mode(mode)


func _info_panel_raise() -> void:
	if _info_panel == null or _ctrl_bar == null:
		return
	var bar_h := _ctrl_bar.get_combined_minimum_size().y
	_info_panel.position.y = -(PANEL_MIN.y + PANEL_BOTTOM_GAP + bar_h + 8.0)


func _info_panel_lower() -> void:
	if _info_panel == null:
		return
	_info_panel.position.y = -(PANEL_MIN.y + PANEL_BOTTOM_GAP)


func _build_ctrl_option_buttons() -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	_ctrl_reform_btn = Button.new()
	_ctrl_reform_btn.text = "Reform"
	_ctrl_reform_btn.toggle_mode = true
	_ctrl_reform_btn.custom_minimum_size = Vector2(68, 28)
	_ctrl_reform_btn.add_theme_font_size_override("font_size", 13)
	_ctrl_reform_btn.pressed.connect(func():
		Settings.reform_before_move = not Settings.reform_before_move)
	hbox.add_child(_ctrl_reform_btn)

	_ctrl_group_attack_btn = Button.new()
	_ctrl_group_attack_btn.custom_minimum_size = Vector2(100, 28)
	_ctrl_group_attack_btn.add_theme_font_size_override("font_size", 13)
	_ctrl_group_attack_btn.pressed.connect(func():
		if _sel_mgr != null:
			_sel_mgr.toggle_group_attack_mode())
	hbox.add_child(_ctrl_group_attack_btn)

	return hbox


func show_end(text: String) -> void:
	_paused_label.visible = false   # the end overlay supersedes the pause banner
	_order_mode_label.visible = false   # armed-mode indicator is irrelevant on the end screen
	_overlay_label.text = text
	_overlay.visible = true
	get_tree().paused = true


func _on_restart() -> void:
	# Fresh battle: drop back to IDLE so Battle._ready starts a new recording.
	Replay.reset()
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_return_to_campaign() -> void:
	# Hand control back to the campaign map; CampaignBattle still holds the
	# result, which CampaignMap applies on load. Drop the recording like a restart.
	Replay.reset()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Campaign.tscn")


func _on_restart_replay() -> void:
	# Rewind the watched replay to tick 0: start_playback re-reads loaded_path and
	# resets the play index, then the scene reload replays from the start. PLAYBACK
	# only (the menu item is disabled otherwise); guarded in case it's reached anyway.
	if Replay.mode != Replay.Mode.PLAYBACK:
		return
	if not Replay.start_playback(Replay.loaded_path):
		# Loaded fine on entering PLAYBACK, so a failure now means it vanished
		# mid-watch — report it like _on_replay_chosen rather than bailing silently.
		_error_dialog.title = "Restart Replay"
		_error_dialog.dialog_text = "That replay is no longer available."
		_error_dialog.popup_centered()
		return
	get_tree().paused = false
	get_tree().reload_current_scene()


func _open_load_dialog() -> void:
	_load_dialog.current_dir = Replay.replays_dir()
	_load_dialog.popup_centered()


func _on_replay_chosen(path: String) -> void:
	if not Replay.start_playback(path):
		# Bad/incompatible file — report it without clobbering any result label.
		_error_dialog.title = "Load Replay"
		_error_dialog.dialog_text = "That file isn't a compatible replay."
		_error_dialog.popup_centered()
		return
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_watch_replay() -> void:
	# Re-run the battle just shown. While watching a replay, "Watch Again" must
	# re-run *that* file (loaded_path) — which may be an older one opened via the
	# picker — not the last live battle. After a live battle, replay what we just
	# saved. If neither exists, say so rather than playing the wrong battle.
	var path := Replay.loaded_path if Replay.mode == Replay.Mode.PLAYBACK else Replay.last_saved_path
	if path == "" or not Replay.start_playback(path):
		# Report on the button itself so the battle result label is preserved.
		_watch_button.text = "No replay available"
		_watch_button.disabled = true
		return
	get_tree().paused = false
	get_tree().reload_current_scene()
