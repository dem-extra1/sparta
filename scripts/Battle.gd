extends Node2D

const UnitRef       := preload("res://scripts/Unit.gd")
const BattleSpawner := preload("res://scripts/BattleSpawner.gd")
const FIELD := Rect2(0, 0, 1600, 1000)

@onready var _units: Node2D = $Units
@onready var _hud = $HUD
@onready var _camera: Camera2D = $Camera2D

var _ai_timer: float = 0.0
var _ended: bool = false


func _ready() -> void:
	_camera.bounds = FIELD
	_camera.position = FIELD.position + FIELD.size * 0.5
	BattleSpawner.spawn_line(_units, 0, Vector2.DOWN, 300, FIELD)
	BattleSpawner.spawn_line(_units, 1, Vector2.UP,   700, FIELD)

func _draw() -> void:
	draw_rect(FIELD, Color(0.34, 0.42, 0.27))
	draw_rect(FIELD, Color(0.2, 0.25, 0.16), false, 4.0)
	draw_line(Vector2(0, FIELD.size.y * 0.5), Vector2(FIELD.size.x, FIELD.size.y * 0.5),
		Color(1, 1, 1, 0.08), 2.0)

func _process(delta: float) -> void:
	if _ended:
		return
	_ai_timer -= delta
	if _ai_timer <= 0.0:
		_ai_timer = 1.0
		_run_enemy_ai()
	_check_victory()

func _run_enemy_ai() -> void:
	var players := _team_units(0)
	if players.is_empty():
		return
	for u in _team_units(1):
		if u.state == UnitRef.State.FIGHTING:
			continue
		u.target_enemy = _nearest_in(u.position, players)

func _nearest_in(from: Vector2, candidates: Array):
	var best = null
	var best_d: float = INF
	for c in candidates:
		var d: float = from.distance_to(c.position)
		if d < best_d:
			best_d = d
			best = c
	return best

func _check_victory() -> void:
	var p := _team_units(0).size()
	var e := _team_units(1).size()
	if e == 0:
		_end("Mutual Destruction" if p == 0 else "Victory!")
	elif p == 0:
		_end("Defeat")

func _end(text: String) -> void:
	_ended = true
	_hud.show_end(text)

func _team_units(team: int) -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group("units"):
		var u := node as UnitRef
		if u != null and u.team == team:
			out.append(u)
	return out
