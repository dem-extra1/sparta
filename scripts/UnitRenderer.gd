extends RefCounted
## Static drawing helpers for Unit. Called from Unit._draw() so all draw_*
## calls run in the correct CanvasItem context. Replace with Sprite2D when art
## is ready — just swap the Unit._draw() body.

static func draw(unit: Unit) -> void:
	var alpha: float = 0.45 if unit.state == Unit.State.ROUTING else 1.0
	var body: Color = unit.team_color
	body.a = alpha
	_draw_token(unit, body, alpha)
	if unit.anti_cavalry:
		unit.draw_line(Vector2(0, -2), unit.facing * (Unit.RADIUS + 8.0),
			Color(0.9, 0.9, 0.7, alpha), 2.0)
	unit.draw_line(Vector2.ZERO, unit.facing * (Unit.RADIUS + 4.0),
		Color(0, 0, 0, alpha * 0.7), 3.0)
	if unit.selected:
		unit.draw_arc(Vector2.ZERO, Unit.RADIUS + 5.0, 0, TAU, 28,
			Color(0.95, 0.95, 0.3), 2.5)
	_draw_strength_bar(unit, alpha)

static func _draw_token(unit: Unit, body: Color, alpha: float) -> void:
	if unit.is_cavalry:
		unit.draw_circle(Vector2.ZERO, Unit.RADIUS, body)
		unit.draw_arc(Vector2.ZERO, Unit.RADIUS, 0, TAU, 24, Color(1, 1, 1, alpha), 2.0)
	else:
		var r := Rect2(-Unit.RADIUS, -Unit.RADIUS, Unit.RADIUS * 2.0, Unit.RADIUS * 2.0)
		unit.draw_rect(r, body)
		unit.draw_rect(r, Color(0, 0, 0, alpha * 0.6), false, 2.0)

static func _draw_strength_bar(unit: Unit, alpha: float) -> void:
	var bw: float = 38.0
	var by: float = -Unit.RADIUS - 12.0
	var frac: float = clampf(float(unit.soldiers) / float(unit.max_soldiers), 0.0, 1.0)
	unit.draw_rect(Rect2(-bw * 0.5, by, bw, 5.0), Color(0.15, 0.15, 0.15, alpha))
	unit.draw_rect(Rect2(-bw * 0.5, by, bw * frac, 5.0), Color(0.3, 0.8, 0.3, alpha))
	unit.draw_string(ThemeDB.fallback_font, Vector2(-bw * 0.5, by - 3.0), str(unit.soldiers),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, alpha))
