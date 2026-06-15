extends Node2D
## Sets up the battlefield, spawns both armies, runs the enemy AI, and decides
## when the battle is won or lost.

# Preload instead of relying on Unit's global class_name, so the project loads
# without the editor-built global-class cache (works headless / first run / CI).
const UnitRef = preload("res://scripts/Unit.gd")

const FIELD := Rect2(0, 0, 1600, 1000)

# Global movement scale: lower = units move slower (relative speeds preserved).
const SPEED_SCALE: float = 0.6

@onready var _units: Node2D = $Units
@onready var _hud = $HUD
@onready var _camera: Camera2D = $Camera2D

var _ai_timer: float = 0.0
var _ended: bool = false


func _ready() -> void:
	_camera.bounds = FIELD
	_camera.position = FIELD.position + FIELD.size * 0.5

	# Player army (team 0) deploys along the top, facing down.
	_spawn_line(0, Vector2.DOWN, 300)
	# Enemy army (team 1) deploys along the bottom, facing up.
	_spawn_line(1, Vector2.UP, 700)


func _draw() -> void:
	# Simple grass field + a center line, so the world is readable before art.
	draw_rect(FIELD, Color(0.34, 0.42, 0.27))
	draw_rect(FIELD, Color(0.2, 0.25, 0.16), false, 4.0)
	draw_line(Vector2(0, FIELD.size.y * 0.5), Vector2(FIELD.size.x, FIELD.size.y * 0.5),
		Color(1, 1, 1, 0.08), 2.0)


func _spawn_line(team: int, facing: Vector2, y: float) -> void:
	# Loadout: spearmen, infantry, infantry, cavalry, cavalry.
	var loadout := [
		{"name": "Spearmen", "anti_cav": true, "cav": false, "soldiers": 140, "atk": 11, "def": 8, "spd": 80},
		{"name": "Infantry", "anti_cav": false, "cav": false, "soldiers": 120, "atk": 13, "def": 6, "spd": 90},
		{"name": "Infantry", "anti_cav": false, "cav": false, "soldiers": 120, "atk": 13, "def": 6, "spd": 90},
		{"name": "Cavalry", "anti_cav": false, "cav": true, "soldiers": 80, "atk": 16, "def": 5, "spd": 160},
		{"name": "Cavalry", "anti_cav": false, "cav": true, "soldiers": 80, "atk": 16, "def": 5, "spd": 160},
	]
	var count: int = loadout.size()
	var spacing: float = 150.0
	var start_x: float = FIELD.size.x * 0.5 - (count - 1) * spacing * 0.5

	for i in range(count):
		var d: Dictionary = loadout[i]
		var u := UnitRef.new()
		u.unit_name = "%s %d" % [d["name"], i + 1]
		u.team = team
		u.anti_cavalry = d["anti_cav"]
		u.is_cavalry = d["cav"]
		u.max_soldiers = d["soldiers"]
		u.attack = d["atk"]
		u.defense = d["def"]
		u.move_speed = d["spd"] * SPEED_SCALE
		u.facing = facing
		u.position = Vector2(start_x + i * spacing, y)
		_units.add_child(u)


func _process(delta: float) -> void:
	if _ended:
		return

	_ai_timer -= delta
	if _ai_timer <= 0.0:
		_ai_timer = 1.0
		_run_enemy_ai()

	_check_victory()


func _run_enemy_ai() -> void:
	# Each idle enemy advances on the nearest player unit; combat auto-resolves.
	var players := _team_units(0)
	if players.is_empty():
		return
	for u in _team_units(1):
		if u.state == UnitRef.State.FIGHTING:
			continue
		var nearest = null
		var best: float = INF
		for p in players:
			var d: float = u.position.distance_to(p.position)
			if d < best:
				best = d
				nearest = p
		if nearest != null:
			u.target_enemy = nearest


func _team_units(team: int) -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group("units"):
		var u = node as UnitRef
		if u != null and u.team == team:
			out.append(u)
	return out


func _check_victory() -> void:
	var p: int = _team_units(0).size()
	var e: int = _team_units(1).size()
	if p == 0 and e == 0:
		_end("Mutual Destruction")
	elif e == 0:
		_end("Victory!")
	elif p == 0:
		_end("Defeat")


func _end(text: String) -> void:
	_ended = true
	_hud.show_end(text)
