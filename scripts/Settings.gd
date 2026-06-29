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

# Multi-unit drag-to-form-up: how the dragged flank line is split among the selected
# units. Stored as an int (mirrors SelectionManager.FormUpDist: 0 = equal depth / uniform
# ranks, the default; 1 = equal width / uniform frontage) so Settings stays free of a
# dependency on that script. This is the DEFAULT a battle starts with; an on-the-fly hotkey
# cycles the live mode without rewriting this. Bump FORM_UP_DIST_MAX when a mode is added.
const FORM_UP_DIST_EQUAL_DEPTH := 0
const FORM_UP_DIST_MAX := 1
# The setter clamps to the valid range so a corrupt/hand-edited cfg (or a stale value after
# the modes change) can't propagate an out-of-range mode into the game.
var form_up_dist_default: int = FORM_UP_DIST_EQUAL_DEPTH:
	set(value):
		var clamped: int = clampi(value, 0, FORM_UP_DIST_MAX)
		if clamped == form_up_dist_default:
			return
		form_up_dist_default = clamped
		if not _loading:
			_save()
			changed.emit()

# Reform before move: when true, a fresh move order makes the unit hold its position
# for REFORM_DURATION before marching, so its ranks settle before it steps off.
# Default on (the historical default for formed infantry). Baked into each order's
# "reform" field so replays reproduce the behavior as recorded, regardless of whether
# the setting is later changed.
var reform_before_move: bool = true:
	set(value):
		if value == reform_before_move:
			return
		reform_before_move = value
		if not _loading:
			_save()
			changed.emit()

# Order-mode selector hotkeys: stable slug -> physical keycode. Slugs (and the
# menu order) are owned by Battle.ORDER_MODE_HOTKEYS; these are the factory defaults.
# Physical keycodes keep the bindings layout-independent (like the camera/pause keys).
const DEFAULT_ORDER_BINDINGS := {
	"hold": KEY_H,
	"attack_flank": KEY_F,
	"attack_rear": KEY_R,
	"skirmish": KEY_K,
	"support": KEY_G,
}

# Active bindings: a copy of the defaults overlaid with any persisted overrides.
# Mutated only via set_order_binding() / reset_order_bindings() so saves + the
# `changed` signal stay centralized.
var order_bindings: Dictionary = DEFAULT_ORDER_BINDINGS.duplicate()


func _ready() -> void:
	_load()


## Set sfx_enabled for this run only — no persist to disk, no `changed` signal
## (reusing the _load() guard). The demo recorder (tools/demo/DemoRunner.gd) calls
## this so a recording carries the game's sound (SFX default off) without rewriting
## a developer's saved preference when the recorder is run locally. Saves/restores
## the prior _loading state rather than hard-clearing it, so it stays correct if
## ever called while a load is already in progress.
func set_sfx_enabled_session(value: bool) -> void:
	var was_loading := _loading
	_loading = true
	sfx_enabled = value
	_loading = was_loading


## The physical keycode currently bound to a mode slug (or its default / KEY_NONE).
func order_binding(slug: String) -> int:
	return int(order_bindings.get(slug, DEFAULT_ORDER_BINDINGS.get(slug, KEY_NONE)))


## The mode slug currently bound to a physical keycode, or "" if none. Used by the
## selector (keycode -> mode) and by the rebind UI to detect conflicts.
func slug_for_keycode(keycode: int) -> String:
	for slug in order_bindings:
		if int(order_bindings[slug]) == keycode:
			return slug
	return ""


## Rebind a single order mode. No-ops on an unknown slug or an unchanged value.
## Callers (the rebind dialog) are responsible for conflict checks first.
func set_order_binding(slug: String, keycode: int) -> void:
	if not DEFAULT_ORDER_BINDINGS.has(slug) or int(order_bindings.get(slug, -1)) == keycode:
		return
	order_bindings[slug] = keycode
	if not _loading:
		_save()
		changed.emit()


## Restore every order-mode hotkey to its factory default.
func reset_order_bindings() -> void:
	if order_bindings == DEFAULT_ORDER_BINDINGS:
		return
	order_bindings = DEFAULT_ORDER_BINDINGS.duplicate()
	if not _loading:
		_save()
		changed.emit()


func _load(path: String = SAVE_PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	_loading = true
	edge_scroll = cfg.get_value("camera", "edge_scroll", edge_scroll)
	sfx_enabled = cfg.get_value("audio", "sfx_enabled", sfx_enabled)
	form_up_dist_default = int(cfg.get_value("gameplay", "form_up_dist_default", form_up_dist_default))
	reform_before_move = bool(cfg.get_value("gameplay", "reform_before_move", reform_before_move))
	for slug in DEFAULT_ORDER_BINDINGS:
		order_bindings[slug] = int(cfg.get_value("keybindings", slug, DEFAULT_ORDER_BINDINGS[slug]))
	_loading = false


func _save(path: String = SAVE_PATH) -> void:
	# Load the existing file first so other settings/sections aren't clobbered.
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("camera", "edge_scroll", edge_scroll)
	cfg.set_value("audio", "sfx_enabled", sfx_enabled)
	cfg.set_value("gameplay", "form_up_dist_default", form_up_dist_default)
	cfg.set_value("gameplay", "reform_before_move", reform_before_move)
	for slug in order_bindings:
		cfg.set_value("keybindings", slug, int(order_bindings[slug]))
	cfg.save(path)
