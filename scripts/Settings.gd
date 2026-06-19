extends Node
## Game-wide settings (autoload singleton: "Settings").
## Persists to user://settings.cfg so choices survive between runs.

const SAVE_PATH := "user://settings.cfg"

signal changed

# True while _load() applies persisted values, so the setter doesn't
# round-trip back to disk or fire `changed` during startup.
var _loading: bool = false

# Pan the camera when the mouse touches a screen edge. Default off.
var edge_scroll: bool = false:
	set(value):
		if value == edge_scroll:
			return
		edge_scroll = value
		if not _loading:
			_save()
			changed.emit()

# Play sound effects (combat, selection, orders, battle outcome). Default off.
var sfx_enabled: bool = false:
	set(value):
		if value == sfx_enabled:
			return
		sfx_enabled = value
		if not _loading:
			_save()
			changed.emit()


func _ready() -> void:
	_load()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	_loading = true
	edge_scroll = cfg.get_value("camera", "edge_scroll", edge_scroll)
	sfx_enabled = cfg.get_value("audio", "sfx_enabled", sfx_enabled)
	_loading = false


func _save() -> void:
	# Load any existing file first so other settings aren't clobbered.
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("camera", "edge_scroll", edge_scroll)
	cfg.set_value("audio", "sfx_enabled", sfx_enabled)
	cfg.save(SAVE_PATH)
