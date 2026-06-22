class_name RoutShockwave
extends Node2D
## A morale-shock ripple drawn when a unit routs: a translucent ring that flashes
## at the router and expands while fading, sized to the rout's morale-shock radius and
## tinted by the routing unit's team. The fill is a soft radial gradient (denser at the
## centre) suggesting the shock is strongest near the router and fades to nothing at the
## edge. Purely cosmetic — spawned on the deterministic sim tick but animated on render
## time (_process), in no sim group, and frees itself; no sim/replay/determinism impact.

const LIFETIME := 0.6           # seconds the ripple is visible
const GRADIENT_STEPS := 5       # concentric discs faking the centre-dense fill
const START_SCALE := 0.45       # ring starts at this fraction of the full radius

var _radius: float = 140.0
var _color: Color = Color.WHITE
var _age: float = 0.0


## Spawn a ripple centred at `at` (world-space) reaching `radius`, tinted by `color`.
static func spawn(parent: Node, at: Vector2, radius: float, color: Color) -> void:
	var fx := RoutShockwave.new()
	parent.add_child(fx)
	fx.global_position = at
	fx._radius = radius
	fx._color = color
	fx.z_index = 4   # above the field, below volley trails and the HUD / overlay


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = clampf(_age / LIFETIME, 0.0, 1.0)
	var r: float = _radius * (START_SCALE + (1.0 - START_SCALE) * t)   # expands outward
	var fade: float = 1.0 - t                                          # whole ripple fades
	# Soft radial gradient: stacked translucent discs accumulate toward the centre.
	for i in range(GRADIENT_STEPS):
		var disc_r: float = r * (1.0 - float(i) / float(GRADIENT_STEPS))
		draw_circle(Vector2.ZERO, disc_r, Color(_color, fade * 0.1))
	# Brighter leading ring so the expanding edge reads clearly.
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(_color, fade * 0.6), 2.0)
