extends Node2D
class_name Unit

const UnitCombat   := preload("res://scripts/UnitCombat.gd")
const UnitMovement := preload("res://scripts/UnitMovement.gd")
const UnitRenderer := preload("res://scripts/UnitRenderer.gd")

enum State { IDLE, MOVING, FIGHTING, ROUTING, DEAD }

@export var unit_name: String = "Spearmen"
@export var team: int = 0
@export var max_soldiers: int = 120
@export var attack: int = 12
@export var defense: int = 6
@export var move_speed: float = 90.0
@export var attack_range: float = 26.0
@export var is_cavalry: bool = false
@export var anti_cavalry: bool = false
## Center-to-center separation floor = sum of both units' radii. Keep below
## attack_range + RADIUS so units press into melee instead of bouncing apart.
@export var separation_radius: float = 19.0

var soldiers: int
var morale: float = 100.0
var state: int = State.IDLE
var facing: Vector2 = Vector2.DOWN
var move_target: Vector2 = Vector2.ZERO
var has_move_target: bool = false
var target_enemy: Unit = null
var selected: bool = false
var team_color: Color = Color.WHITE
var _attack_cd: float = 0.0
var _rout_timer: float = 0.0
var _moved_last_frame: bool = false
var _charge_ready: bool = true

const RADIUS: float = 18.0
const ATTACK_INTERVAL: float = 0.6


func _ready() -> void:
	soldiers = max_soldiers
	team_color = Color("4a7fd6") if team == 0 else Color("d65a4a")
	add_to_group("units")
	z_index = 1
	queue_redraw()


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if state == State.ROUTING:
		UnitMovement.process_rout(self, delta)
		return
	UnitMovement.separate(self)
	_attack_cd = max(0.0, _attack_cd - delta)
	_moved_last_frame = false
	UnitMovement.tick_ai(self, UnitCombat.current_target(self), delta)
	queue_redraw()


func take_casualties(amount: int, attacker: Unit) -> void:
	if state == State.DEAD or state == State.ROUTING:
		return
	UnitCombat.apply_damage(self, amount, attacker)


func _draw() -> void:
	UnitRenderer.draw(self)
