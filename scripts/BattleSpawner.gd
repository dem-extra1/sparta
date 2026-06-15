extends RefCounted
## Static helpers that build and place a unit line on the battlefield.

const UnitRef := preload("res://scripts/Unit.gd")
const SPEED_SCALE: float = 0.6

static func spawn_line(
		parent: Node2D, team: int, facing: Vector2, y: float, field: Rect2) -> void:
	var loadout := _make_loadout()
	var count: int = loadout.size()
	var spacing: float = 150.0
	var start_x: float = field.size.x * 0.5 - (count - 1) * spacing * 0.5
	for i in range(count):
		var u := _make_unit(loadout[i], team, facing, i)
		u.position = Vector2(start_x + i * spacing, y)
		parent.add_child(u)

static func _make_loadout() -> Array:
	return [
		{"name": "Spearmen", "anti_cav": true,  "cav": false, "soldiers": 140, "atk": 11, "def": 8,  "spd": 80},
		{"name": "Infantry", "anti_cav": false, "cav": false, "soldiers": 120, "atk": 13, "def": 6,  "spd": 90},
		{"name": "Infantry", "anti_cav": false, "cav": false, "soldiers": 120, "atk": 13, "def": 6,  "spd": 90},
		{"name": "Cavalry",  "anti_cav": false, "cav": true,  "soldiers": 80,  "atk": 16, "def": 5,  "spd": 160},
		{"name": "Cavalry",  "anti_cav": false, "cav": true,  "soldiers": 80,  "atk": 16, "def": 5,  "spd": 160},
	]

static func _make_unit(d: Dictionary, team: int, facing: Vector2, idx: int) -> UnitRef:
	var u := UnitRef.new()
	u.unit_name    = "%s %d" % [d["name"], idx + 1]
	u.team         = team
	u.anti_cavalry = d["anti_cav"]
	u.is_cavalry   = d["cav"]
	u.max_soldiers = d["soldiers"]
	u.attack       = d["atk"]
	u.defense      = d["def"]
	u.move_speed   = d["spd"] * SPEED_SCALE
	u.facing       = facing
	return u
