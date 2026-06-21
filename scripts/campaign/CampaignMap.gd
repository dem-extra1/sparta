extends Node2D
## Campaign map view + controller (M2, #70). Renders the province polygons, turns
## mouse clicks into move/attack orders against the headless CampaignState, runs a
## simple enemy turn, and reports turn/selection/victory to the HUD.
##
## Single-player: the human plays faction 0 (Rome); ending the turn runs the Gallic
## AI, then hands play back. Battles are auto-resolved in CampaignState (the tactical
## hookup is M3).

const CampaignStateRef = preload("res://scripts/campaign/CampaignState.gd")
const GallicWar = preload("res://scripts/campaign/GallicWar.gd")

const PLAYER_FACTION := 0

@onready var _hud = $"../CampaignHUD"

var _map: Dictionary
var _state
var _selected: int = -1   # province id the player has selected, or -1


func _ready() -> void:
	if _hud != null:
		_hud.end_turn_pressed.connect(_on_end_turn)
		_hud.restart_pressed.connect(_restart)
		_hud.menu_pressed.connect(_to_menu)
	# Build the state synchronously so _draw always has a valid map, but defer the
	# first HUD push: this node's _ready runs before its sibling HUD's, so the HUD's
	# labels don't exist yet here.
	_build_state()
	queue_redraw()
	_refresh_hud.call_deferred()


func _start_campaign() -> void:
	# Used for restart, when the HUD is already up — refresh immediately.
	_build_state()
	if _hud != null:
		_hud.reset_for_new_campaign()   # clear the end overlay, re-enable End Turn
	_refresh_hud()
	queue_redraw()


func _build_state() -> void:
	_map = GallicWar.new_map()
	_state = CampaignStateRef.new(_map)
	_selected = -1


# --- input ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _state == null or _state.winner() != CampaignStateRef.NO_WINNER:
		return
	if _state.current_faction != PLAYER_FACTION:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click(get_global_mouse_position())


func _on_click(pos: Vector2) -> void:
	var hit := _province_at(pos)
	if hit == -1:
		_selected = -1
		_refresh_hud()
		queue_redraw()
		return

	if _selected == -1:
		# First click: select one of your own armies.
		if _state.owner_of(hit) == PLAYER_FACTION and _state.army_of(hit) > 0 \
				and not _state.has_acted(hit):
			_selected = hit
	elif hit == _selected:
		_selected = -1
	elif _state.can_move(_selected, hit):
		var result: Dictionary = _state.move_or_attack(_selected, hit)
		_announce(result)
		_selected = -1
		_check_winner()
	else:
		# Clicking another own, ready army re-targets the selection; otherwise clear.
		if _state.owner_of(hit) == PLAYER_FACTION and _state.army_of(hit) > 0 \
				and not _state.has_acted(hit):
			_selected = hit
		else:
			_selected = -1
	_refresh_hud()
	queue_redraw()


func _province_at(pos: Vector2) -> int:
	for p in _map["provinces"]:
		if Geometry2D.is_point_in_polygon(pos, p["polygon"]):
			return int(p["id"])
	return -1


# --- turn flow ------------------------------------------------------------

func _on_end_turn() -> void:
	if _state == null or _state.winner() != CampaignStateRef.NO_WINNER:
		return
	if _state.current_faction != PLAYER_FACTION:
		return
	_selected = -1
	_state.end_turn()        # -> enemy faction
	_run_enemy_ai()
	if _check_winner():
		return
	_state.end_turn()        # -> back to the player
	_refresh_hud()
	queue_redraw()


## Greedy Gallic AI: each ready army takes the weakest adjacent enemy province it can
## occupy (undefended) or expects to beat (army >= defender); otherwise it holds.
func _run_enemy_ai() -> void:
	var faction: int = _state.current_faction
	for id in _state.movable_provinces(faction):
		var target := -1
		var target_def := 1 << 30
		for n in _state.adjacency[id]:
			if _state.owner_of(n) == faction:
				continue
			var d: int = _state.army_of(n)
			if d < target_def:
				target_def = d
				target = n
		if target == -1:
			continue
		# Account for the defender's home edge so the AI doesn't pick even fights it's
		# actually the underdog in.
		if target_def == 0 or _state.army_of(id) >= target_def * CampaignStateRef.DEFENDER_BONUS:
			_state.move_or_attack(id, target)


func _check_winner() -> bool:
	var w: int = _state.winner()
	if w == CampaignStateRef.NO_WINNER:
		return false
	_selected = -1
	queue_redraw()
	var won := w == PLAYER_FACTION
	var who: String = _state.faction_names[w] if w < _state.faction_names.size() else "Someone"
	var msg := "🏆 Victory — %s conquers all!" % _state.faction_names[PLAYER_FACTION] if won \
			else "☠ Defeat — overrun by %s." % who
	if _hud != null:
		_hud.show_victory(msg)
	return true


# --- HUD glue -------------------------------------------------------------

func _refresh_hud() -> void:
	if _hud == null:
		return
	var faction: int = _state.current_faction
	var fname: String = _state.faction_names[faction] if faction < _state.faction_names.size() else "?"
	var color: Color = _map["faction_colors"][faction] if faction < _map["faction_colors"].size() else Color.WHITE
	_hud.update_turn(_state.turn, fname, color)
	_hud.update_standings(_standings())
	if _selected != -1:
		var p: Dictionary = _state.provinces[_selected]
		_hud.update_selection("Selected: %s (%d) — pick an adjacent province to move or attack." \
				% [p["name"], int(p["army"])])
	else:
		_hud.update_selection("Click one of your armies (blue), then an adjacent province.")


func _standings() -> String:
	var counts := {}
	for id in _state.provinces:
		var o: int = _state.owner_of(id)
		counts[o] = int(counts.get(o, 0)) + 1
	var parts: Array[String] = []
	for f in _state.faction_names.size():
		parts.append("%s: %d" % [_state.faction_names[f], int(counts.get(f, 0))])
	return "   ".join(parts)


func _announce(result: Dictionary) -> void:
	if _hud == null or not result.get("ok", false):
		return
	var to_name: String = _state.provinces[result["to"]]["name"]
	var text := ""
	if not result["combat"]:
		# Distinguish merging into a friendly province from taking an undefended one
		# (owner_of(to) is the player in both cases, so use the result's flag).
		text = "Reinforced %s." % to_name if result.get("reinforced", false) \
				else "Occupied %s." % to_name
	elif result["attacker_won"]:
		text = "%s taken from %s (%d survive)." % [to_name, _enemy_name(), int(result["survivors"])]
	else:
		text = "Assault on %s repulsed; the attacking army is lost." % to_name
	_hud.flash(text)


## The non-player faction's display name (two-faction slice); falls back gracefully.
func _enemy_name() -> String:
	if _state.faction_names.size() > 1:
		return _state.faction_names[1 - PLAYER_FACTION]
	return "the enemy"


func _restart() -> void:
	_start_campaign()


func _to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


# --- rendering ------------------------------------------------------------

func _draw() -> void:
	# Sea backdrop behind the provinces (covers the viewport at any size).
	draw_rect(get_viewport_rect(), Color(0.16, 0.28, 0.40))
	var font := ThemeDB.fallback_font
	for p in _map["provinces"]:
		var id := int(p["id"])
		var poly: PackedVector2Array = p["polygon"]
		var owner: int = _state.owner_of(id)
		var base: Color = _map["faction_colors"][owner] if owner < _map["faction_colors"].size() else Color.GRAY
		# Dim provinces whose army has already acted so the player sees what's spent.
		var fill := base
		if _state.has_acted(id):
			fill = base.darkened(0.25)
		draw_colored_polygon(poly, fill)

		# Outline: bright white for the selection, soft dark edge otherwise.
		var outline := Color(1, 1, 1, 0.9) if id == _selected else Color(0, 0, 0, 0.45)
		var width := 3.0 if id == _selected else 1.5
		var closed := poly + PackedVector2Array([poly[0]])
		draw_polyline(closed, outline, width)

		# When something is selected, ring the legal targets so moves are discoverable.
		if _selected != -1 and id != _selected and _state.can_move(_selected, id):
			draw_polyline(closed, Color(1.0, 0.95, 0.4, 0.85), 2.5)

		var label: Vector2 = p["label"]
		var title: String = str(p["name"])
		draw_string(font, label - Vector2(title.length() * 3.2, 6), title,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.95))
		# Army count comes from the live state, not the static map data (which keeps
		# the starting values), so it reflects moves and combat.
		draw_string(font, label + Vector2(-8, 16), "⚔ %d" % _state.army_of(id),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 0.85))
