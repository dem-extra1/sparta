extends Node2D
## Campaign map view + controller (M2, #70). Renders the province polygons, turns
## mouse clicks into move/attack orders against the headless CampaignState, runs a
## simple enemy turn, and reports turn/selection/victory to the HUD.
##
## Single-player: the human plays faction 0 (Rome); ending the turn runs the Gallic
## AI, then hands play back. A player attack on a defended enemy province is fought
## out in the tactical battle (M3, #122) unless "auto-resolve" is on; AI attacks and
## undefended moves always resolve in CampaignState.

const CampaignStateRef = preload("res://scripts/campaign/CampaignState.gd")
const CampaignLoader = preload("res://scripts/campaign/CampaignLoader.gd")
const Campaigns = preload("res://scripts/campaign/Campaigns.gd")
const CampaignBattle = preload("res://scripts/campaign/CampaignBattle.gd")

const PLAYER_FACTION := 0
const BATTLE_SCENE := "res://scenes/Battle.tscn"

@onready var _hud = $"../CampaignHUD"

var _map: Dictionary
var _state
var _selected: int = -1   # province id the player has selected, or -1
# When false (default), a player attack on a defended enemy province is fought out
# in the tactical battle (#122); when true it's auto-resolved on the map ("quick
# resolve"). AI attacks always auto-resolve regardless.
var _auto_resolve: bool = false


func _ready() -> void:
	if _hud != null:
		_hud.end_turn_pressed.connect(_on_end_turn)
		_hud.restart_pressed.connect(_restart)
		_hud.menu_pressed.connect(_to_menu)
		_hud.diplomacy_toggled.connect(_on_diplomacy_toggled)
		_hud.auto_resolve_toggled.connect(_on_auto_resolve_toggled)
	# Build the state synchronously so _draw always has a valid map, but defer the
	# first HUD push: this node's _ready runs before its sibling HUD's, so the HUD's
	# labels don't exist yet here.
	_build_state()
	# Returning from a tactical battle (#122): restore the pre-battle campaign state
	# (the scene swap destroyed it) so _draw shows the real board, then apply the
	# battle's outcome once the HUD exists (it needs to flash/announce + maybe end).
	var resumed := _resume_from_battle()
	queue_redraw()
	if resumed:
		_finish_battle_resume.call_deferred()
	else:
		_refresh_hud.call_deferred()


func _start_campaign() -> void:
	# Used for restart, when the HUD is already up — refresh immediately.
	_build_state()
	if _hud != null:
		_hud.reset_for_new_campaign()   # clear the end overlay, re-enable End Turn
	_refresh_hud()
	queue_redraw()


func _build_state() -> void:
	# Load the campaign the menu selected; fall back to the default if it failed to
	# load so the scene is never left without a map.
	_map = CampaignLoader.load_map(Campaigns.selected_path)
	if _map.is_empty():
		# Recoverable: fall back to the default campaign.
		push_warning("Campaign: could not load '%s'; using the default." % Campaigns.selected_path)
		_map = CampaignLoader.load_map(Campaigns.DEFAULT_PATH)
	if _map.is_empty():
		# Even the default failed (shipped data broken). Keep a valid empty state so
		# nothing crashes; the draw/input/HUD paths guard against an empty map.
		push_error("Campaign: default map '%s' is also unreadable." % Campaigns.DEFAULT_PATH)
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
		if not _auto_resolve and _is_contested(_selected, hit):
			# A defended enemy province: fight it out in the tactical battle. This
			# swaps scenes, so stop here — the rest resumes in _ready on return.
			_launch_tactical_battle(_selected, hit)
			return
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
	for p in _map.get("provinces", []):
		if Geometry2D.is_point_in_polygon(pos, p["polygon"]):
			return int(p["id"])
	return -1


# --- tactical battle hand-off (M3, #122) ----------------------------------

## True if moving from->to is a real fight: a defended province of a faction the
## mover is at war with — as opposed to reinforcing a friendly province, walking into
## an undefended one, or a peace-faction province. Only a real fight launches the
## tactical battle. Self-contained (doesn't assume the can_move guard at its call site).
func _is_contested(from_id: int, to_id: int) -> bool:
	var from_owner: int = _state.owner_of(from_id)
	var to_owner: int = _state.owner_of(to_id)
	return to_owner != from_owner and _state.army_of(to_id) > 0 \
			and _state.at_war(from_owner, to_owner)


## Stash the clash + a snapshot of the campaign in CampaignBattle and switch to the
## tactical battle scene. Control returns via _ready -> _resume_from_battle().
func _launch_tactical_battle(from_id: int, to_id: int) -> void:
	_capture_clash(from_id, to_id)
	get_tree().change_scene_to_file(BATTLE_SCENE)


## Populate CampaignBattle with the clash context + a pre-battle snapshot. Split from
## the scene swap so the capture is unit-testable without changing scenes.
func _capture_clash(from_id: int, to_id: int) -> void:
	var attacker: int = _state.owner_of(from_id)
	var defender: int = _state.owner_of(to_id)
	var colors: Array = _map.get("faction_colors", [])
	CampaignBattle.active = true
	CampaignBattle.result = {}
	CampaignBattle.snapshot = _state.snapshot()
	CampaignBattle.pending = {
		"from": from_id,
		"to": to_id,
		"attacker_strength": _state.army_of(from_id),
		"defender_strength": _state.army_of(to_id),
		"attacker_name": _faction_name(attacker),
		"defender_name": _faction_name(defender),
		"attacker_color": colors[attacker] if attacker < colors.size() else Color.SKY_BLUE,
		"defender_color": colors[defender] if defender < colors.size() else Color.RED,
		"to_name": str(_state.provinces[to_id]["name"]),
	}


## On load, if we're coming back from a campaign-launched battle, restore the
## pre-battle state onto the freshly map-built state. Returns true if it resumed.
func _resume_from_battle() -> bool:
	if not CampaignBattle.active or CampaignBattle.result.is_empty():
		return false
	_state.restore(CampaignBattle.snapshot)
	_selected = -1
	return true


## Apply the battle's outcome and finish the player's interrupted order, once the HUD
## is up (deferred from _ready). Mirrors the auto-resolve path's announce + win check.
func _finish_battle_resume() -> void:
	var clash: Dictionary = CampaignBattle.pending
	var outcome: Dictionary = CampaignBattle.result
	var from_id := int(clash["from"])
	var to_id := int(clash["to"])
	# resolve_attack trusts the clash was validated at launch; the restored snapshot
	# reproduces that exact pre-battle state, so the move is legal again here. Assert it
	# so a snapshot that doesn't round-trip fails loudly instead of corrupting state.
	assert(_state.can_move(from_id, to_id),
			"battle resume: restored state isn't a legal pre-battle move (snapshot drift)")
	var result: Dictionary = _state.resolve_attack(
			from_id, to_id, bool(outcome["attacker_won"]), int(outcome["survivors"]))
	CampaignBattle.clear()
	_announce(result)
	if not _check_winner():
		_refresh_hud()
		queue_redraw()


func _on_auto_resolve_toggled(on: bool) -> void:
	_auto_resolve = on


# --- turn flow ------------------------------------------------------------

func _on_end_turn() -> void:
	if _state == null or _state.winner() != CampaignStateRef.NO_WINNER:
		return
	if _state.current_faction != PLAYER_FACTION:
		return
	_selected = -1
	_state.end_turn()        # -> first non-player faction
	# Run every AI faction in turn until control returns to the player. With three+
	# factions this may be several factions (e.g. Gauls then the Germanic tribes).
	# end_turn() advances current_faction with `% n`, and PLAYER_FACTION is part of
	# that rotation, so control is guaranteed back to the player within n-1 steps —
	# the loop always terminates (no infinite-loop risk).
	while _state.current_faction != PLAYER_FACTION:
		_run_ai_diplomacy()
		_run_enemy_ai()
		if _check_winner():
			return
		_state.end_turn()
	_refresh_hud()
	queue_redraw()


## Before its military moves, the current AI faction reconsiders war/peace (#139) and
## the resulting declarations/peaces are flashed so the player sees the world shift.
## CampaignState.run_ai_diplomacy holds the (deterministic) decision logic.
func _run_ai_diplomacy() -> void:
	var messages: Array = _state.run_ai_diplomacy(_state.current_faction)
	if _hud == null or messages.is_empty():
		return
	# flash() shows a single transient line, so join this faction's notices into one
	# message — otherwise a peace + war declaration in the same turn would clobber each
	# other and only the last would be seen.
	_hud.flash("\n".join(messages))


## Greedy AI: each ready army takes the weakest adjacent province belonging to a
## faction it is at war with that it can occupy (undefended) or expects to beat (army
## >= defender); otherwise it holds. Provinces of factions it's at peace with are left
## alone, so a neutral faction is only ever attacked once war is declared (#123).
func _run_enemy_ai() -> void:
	var faction: int = _state.current_faction
	for id in _state.movable_provinces(faction):
		var target := -1
		var target_def := 1 << 30
		for n in _state.adjacency[id]:
			if _state.owner_of(n) == faction:
				continue
			if not _state.at_war(faction, _state.owner_of(n)):
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
	var colors: Array = _map.get("faction_colors", [])
	var color: Color = colors[faction] if faction < colors.size() else Color.WHITE
	_hud.update_turn(_state.turn, fname, color)
	_hud.update_standings(_standings())
	_hud.update_diplomacy(_diplomacy_entries())
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
		text = "%s taken from %s (%d survive)." \
				% [to_name, _faction_name(int(result["defender_owner"])), int(result["survivors"])]
	else:
		text = "Assault on %s repulsed; the attacking army is lost." % to_name
	_hud.flash(text)


## Diplomacy rows for the HUD: one per *other* faction that still owns a province,
## with its colour and whether the player is at war with it. Eliminated factions drop
## off (nothing left to negotiate over).
func _diplomacy_entries() -> Array:
	var owns := {}
	for id in _state.provinces:
		owns[_state.owner_of(id)] = true
	var colors: Array = _map.get("faction_colors", [])
	var entries: Array = []
	for f in _state.faction_names.size():
		if f == PLAYER_FACTION or not owns.has(f):
			continue
		entries.append({
			"id": f,
			"name": _state.faction_names[f],
			"color": colors[f] if f < colors.size() else Color.WHITE,
			"at_war": _state.at_war(PLAYER_FACTION, f),
			"truce": _state.truce_remaining(PLAYER_FACTION, f),
		})
	return entries


## Toggle the player's stance toward `fid`: sue for peace if at war, else declare war.
## A free action on the player's turn while the war is undecided; re-evaluates legal
## moves and redraws so newly-(il)legal targets update immediately.
func _on_diplomacy_toggled(fid: int) -> void:
	if _state == null or _state.winner() != CampaignStateRef.NO_WINNER:
		return
	if _state.current_faction != PLAYER_FACTION:
		return
	var fname: String = _faction_name(fid)
	if _state.at_war(PLAYER_FACTION, fid):
		# Suing for peace carries a commitment: a default truce blocks re-declaring war
		# for a few turns (#138). Without it the truce UI/rules would be unreachable in
		# normal play (only map-seeded peace would ever set one).
		var truce: int = CampaignStateRef.DEFAULT_TRUCE_TURNS
		_state.make_peace(PLAYER_FACTION, fid, truce)
		if _hud != null:
			_hud.flash("Made peace with %s (truce: %d turns)." % [fname, truce])
	elif _state.declare_war(PLAYER_FACTION, fid):
		if _hud != null:
			_hud.flash("Declared war on %s!" % fname)
	else:
		# A truce blocks re-declaring war until it expires (#138).
		if _hud != null:
			_hud.flash("Truce with %s — %d turn(s) left." % [fname, _state.truce_remaining(PLAYER_FACTION, fid)])
	# A stance change can invalidate the current selection's targets; keep it simple.
	_refresh_hud()
	queue_redraw()


func _faction_name(idx: int) -> String:
	return _state.faction_names[idx] if idx >= 0 and idx < _state.faction_names.size() else "the enemy"


func _restart() -> void:
	_start_campaign()


func _to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


# --- rendering ------------------------------------------------------------

func _draw() -> void:
	# Sea backdrop behind the provinces (covers the viewport at any size).
	draw_rect(get_viewport_rect(), Color(0.16, 0.28, 0.40))
	var colors: Array = _map.get("faction_colors", [])
	var font := ThemeDB.fallback_font
	for p in _map.get("provinces", []):
		var id := int(p["id"])
		var poly: PackedVector2Array = p["polygon"]
		var owner: int = _state.owner_of(id)
		var base: Color = colors[owner] if owner < colors.size() else Color.GRAY
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
