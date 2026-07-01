extends AcceptDialog
## Read-only reference overlay listing every keyboard/mouse shortcut, opened with
## <kbd>?</kbd> (Shift+/) or ☰ Menu → Shortcuts. Rebindable order-mode stance keys
## (hold/flank/rear/skirmish/support) are read live from the Settings autoload, the
## same way HUD._refresh_hint() renders the top hint bar, so a rebind made via
## ☰ Menu → Keybindings is reflected here too -- this is purely a display list, not
## an editor.
##
## Everything else here is a fixed, non-rebindable key, so those rows are built once
## in _ready() from a plain data table.

const BattleRef = preload("res://scripts/Battle.gd")

# Each row: [action, key label]. A key label of "" marks a section header (no key
# column). The literal string "STANCES" is a marker: the rebindable order-mode rows
# (hold/attack_flank/attack_rear/skirmish/support) are inserted there at runtime.
const _ROWS: Array = [
	["— Selection & orders —", ""],
	["Select a unit", "LMB"],
	["Select multiple", "LMB + drag"],
	["Move", "RMB"],
	["Attack", "RMB on enemy"],
	["Form up (drag a line)", "RMB + drag"],
	["Form up in selection order", "Shift + RMB + drag"],
	["Add waypoint", "Shift + RMB"],
	["Merge selected units", "M"],
	["— Stances (Esc clears) —", ""],
	["STANCES", ""],
	["Group attack mode (focused/distributed)", "X"],
	["— Formation & drill —", ""],
	["Formation (Normal/Tight/Loose/Square)", "T"],
	["Anti-cavalry square (toggle direct)", "O"],
	["Shield wall / Testudo (toggle direct)", "L / U"],
	["Line width (narrower/wider)", "[ / ]"],
	["File-doubling (explicatio wider / duplicatio deeper)", "B / N"],
	["Form-up split mode", "Y"],
	["About-face (180° in place)", "V"],
	["Quarter-turn left / right (90° in place)", "Q / E"],
	["Wheel left / right (90° hinge on flank)", "Z / C"],
	["— Control groups —", ""],
	["Bind selection to group 0-9", "Ctrl + 0-9"],
	["Recall group 0-9", "0-9"],
	["— Camera & view —", ""],
	["Pan camera", "WASD / arrows / screen edges / two-finger swipe"],
	["Zoom", "Mouse wheel / pinch"],
	["Show all orders + formation preview", "Hold Space"],
	["Active pause", "P or Shift+Space"],
	["— Help —", ""],
	["This shortcuts list", "? (Shift+/)"],
]

# slug -> the key Label for a rebindable stance row, so a later rebind can repaint
# just that label (mirrors KeybindingsDialog._row_buttons).
var _stance_labels: Dictionary = {}


func _ready() -> void:
	title = "Keyboard Shortcuts"
	process_mode = Node.PROCESS_MODE_ALWAYS   # usable while the battle is paused
	unresizable = true

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 420)
	add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)

	for row in _ROWS:
		var action: String = row[0]
		if action == "STANCES":
			for entry in BattleRef.ORDER_MODE_HOTKEYS:
				var slug: String = entry["slug"]
				var mode_name: String = str(BattleRef.ORDER_MODE_NAMES.get(entry["mode"], slug))
				var key_label := _add_row(grid, mode_name, OS.get_keycode_string(Settings.order_binding(slug)))
				_stance_labels[slug] = key_label
			_add_row(grid, "Clear stance", "Esc")
		else:
			_add_row(grid, action, row[1])

	Settings.changed.connect(_refresh_stance_labels)


func _exit_tree() -> void:
	if Settings.changed.is_connected(_refresh_stance_labels):
		Settings.changed.disconnect(_refresh_stance_labels)


## Add one row to the grid. A section header (empty key) gets a brighter colour and
## an empty second cell. Returns the key-column Label so the caller can keep a
## reference to it (used for the live-rebindable stance rows).
func _add_row(grid: GridContainer, action: String, key: String) -> Label:
	var action_label := Label.new()
	action_label.text = action
	if key == "":
		action_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	grid.add_child(action_label)
	var key_label := Label.new()
	key_label.text = key
	key_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	grid.add_child(key_label)
	return key_label


## Re-paint the rebindable stance key labels after a rebind elsewhere (the Keybindings
## dialog) — Settings.changed fires for any setting, so filter to slugs this dialog
## actually displays.
func _refresh_stance_labels() -> void:
	for slug in _stance_labels:
		var key_label: Label = _stance_labels[slug]
		key_label.text = OS.get_keycode_string(Settings.order_binding(slug))
