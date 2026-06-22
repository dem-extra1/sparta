class_name Fallen
extends Node2D
## Fallen soldiers (Stage C): a small heap of dark body marks dropped where men fall in
## melee, fading into the ground as the fight moves on. Spawned from Unit.take_casualties on
## the deterministic sim tick but animated on render time (_process), in no sim group, and
## frees itself — so it carries no sim/replay/determinism state. The scatter is index-based
## (a golden-angle heap), never touching the sim's seeded RNG, so it stays replay-safe.
## Purely cosmetic — the body count is verified visually / in the demo clip.

const LIFETIME := 2.2           # seconds a heap stays before it has fully faded
const MAX_MARKS := 6            # cap on bodies drawn per casualty event (keeps it light)
const SCATTER := 7.0            # base radius the bodies are strewn over, for foot-soldier size (px)
const MARK_RADIUS: float = Unit.MARK_RADIUS   # default body size: a foot soldier (cavalry overrides)
const FADE_START := 0.5         # fraction of LIFETIME the heap stays opaque before fading

var _color: Color = Color(0.2, 0.2, 0.2)
var _marks: PackedVector2Array = PackedVector2Array()
var _mark_radius: float = MARK_RADIUS   # body size for this heap (foot vs cavalry, set by spawn)
var _age: float = 0.0


## Spawn a heap at `at` (world space). `count` (casualties this strike) scales the heap up
## to MAX_MARKS bodies; a single casualty still drops one. Colour is the dead unit's team
## colour, darkened so the bodies read as fallen rather than a live block. `mark_radius` is
## the per-body size — foot soldiers by default, larger for cavalry (Unit.CAV_MARK_RADIUS),
## so a fallen cavalry heap reads as bigger bodies, matching the bigger live cavalry marks.
static func spawn(parent: Node, at: Vector2, color: Color, count: int,
		mark_radius: float = MARK_RADIUS) -> void:
	var fx := Fallen.new()
	fx._mark_radius = mark_radius
	# Widen the heap in proportion to the body size, so bigger (cavalry) bodies don't pack
	# into the same footprint as foot soldiers — the whole pile scales, not just the marks.
	var scaled_scatter: float = SCATTER * (mark_radius / MARK_RADIUS)
	var n: int = clampi(count, 1, MAX_MARKS)
	for i in range(n):
		# Deterministic golden-angle scatter (no RNG): an even, non-repeating spread that
		# reads as a small heap rather than a ring, and never stacks two bodies exactly.
		# The radius denominator is MAX_MARKS (not n) on purpose: the heap's spread scales
		# with the casualty count — a lone death stays a tight speck at the drop point, a big
		# hit fans out to the full scatter radius — so deadlier blows leave visibly bigger
		# piles. (Using n instead would fix every heap to one radius and push a single body
		# further off the drop point.)
		var a: float = float(i) * 2.39996323
		var rad: float = scaled_scatter * sqrt((float(i) + 0.5) / float(MAX_MARKS))
		fx._marks.push_back(Vector2.from_angle(a) * rad)
	fx._color = Color(color.r * 0.4, color.g * 0.4, color.b * 0.4)
	parent.add_child(fx)
	fx.global_position = at
	fx.z_index = 1   # on the ground: above the field (0), below the soldier marks (eff 2)


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = clampf(_age / LIFETIME, 0.0, 1.0)
	# Hold the bodies opaque for the first part of their life, then fade them out.
	var fade: float = 1.0 - smoothstep(FADE_START, 1.0, t)
	var col := Color(_color, fade * 0.7)
	for m in _marks:
		draw_circle(m, _mark_radius, col)
