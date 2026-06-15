extends CanvasLayer
## On-screen UI coordinator. Layout is built by HUDLayout; logic lives here.

const HUDLayout := preload("res://scripts/HUDLayout.gd")

var _info: Label
var _overlay: ColorRect
var _overlay_label: Label
var _paused_label: Label
var _edge_toggle: CheckButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	HUDLayout.build_hint_bar(self)
	_paused_label = HUDLayout.build_pause_label(self)
	_edge_toggle  = HUDLayout.build_edge_toggle(self)
	_info         = HUDLayout.build_unit_panel(self)
	var end       := HUDLayout.build_end_overlay(self, _on_restart)
	_overlay = end[0]
	_overlay_label = end[1]
	Settings.changed.connect(_sync_edge_toggle)


func _exit_tree() -> void:
	if Settings.changed.is_connected(_sync_edge_toggle):
		Settings.changed.disconnect(_sync_edge_toggle)


func _sync_edge_toggle() -> void:
	_edge_toggle.button_pressed = Settings.edge_scroll


func _unhandled_input(event: InputEvent) -> void:
	if _is_pause_keypress(event) and not _overlay.visible:
		_toggle_pause()


func _is_pause_keypress(event: InputEvent) -> bool:
	return event is InputEventKey \
		and event.pressed and not event.echo \
		and event.keycode == KEY_SPACE


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
	var kind: String = "Cavalry" if u.is_cavalry else ("Spearmen" if u.anti_cavalry else "Infantry")
	_info.text = "%s%s\nType: %s\nSoldiers: %d / %d\nMorale: %d" % [
		u.unit_name, extra, kind, u.soldiers, u.max_soldiers, int(u.morale)]


func clear_unit() -> void:
	_info.text = "No unit selected"


func show_end(text: String) -> void:
	_paused_label.visible = false
	_overlay_label.text = text
	_overlay.visible = true
	get_tree().paused = true


func _on_restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
