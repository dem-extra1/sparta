class_name VolleyTrail
extends Node2D
## A short-lived arrow-volley trail (#65): a small cluster of streaks that fly from a
## ranged unit toward its target when it looses a volley (Unit._shoot), fading as they
## land. Purely cosmetic — spawned on the deterministic sim tick but animated on render
## time (_process), so it carries no sim/replay/determinism state and frees itself when
## done. Not in the "units"/"routers" groups, so no scan ever picks it up.

const LIFETIME := 0.30          # seconds a volley streak stays visible
const STREAKS := 3              # number of streaks drawn to suggest a volley
const SPREAD := 6.0             # perpendicular spacing between streaks (px)
const STREAK_LEN := 0.16        # streak length as a fraction of the whole flight

var _delta: Vector2 = Vector2.ZERO   # shooter -> target offset, in world space
var _color: Color = Color.WHITE
var _age: float = 0.0


## Spawn a trail under `parent` flying from `from` to `to` (both world-space). Colour
## is the shooter's team colour, brightened so the arrows read against the field.
static func spawn(parent: Node, from: Vector2, to: Vector2, color: Color) -> void:
	var trail := VolleyTrail.new()
	parent.add_child(trail)
	trail.global_position = from
	trail._delta = to - from
	trail._color = color.lerp(Color.WHITE, 0.5)
	trail.z_index = 5   # above unit bodies, below the HUD / selection overlay


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = clampf(_age / LIFETIME, 0.0, 1.0)
	var tail_t: float = maxf(0.0, t - STREAK_LEN)   # streak trails behind the arrowhead
	var col := Color(_color, (1.0 - t) * 0.9)       # streaks dim as they land
	var perp := Vector2.ZERO
	if _delta.length() > 0.001:
		perp = _delta.orthogonal().normalized() * SPREAD
	for i in range(STREAKS):
		var lane: float = float(i) - float(STREAKS - 1) * 0.5   # centered offsets
		var off: Vector2 = perp * lane
		draw_line(_delta * tail_t + off, _delta * t + off, col, 1.5)
