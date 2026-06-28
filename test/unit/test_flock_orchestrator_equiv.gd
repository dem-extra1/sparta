extends GutTest
## Equivalence guard for the _update_flock orchestrator extraction: drives a unit's
## cosmetic mark layer through a fixed, deterministic sequence (march, then stand-and-
## fight) and pins a checksum + sample mark positions of the resulting _soldier_pos. The
## golden values were captured from the pre-extraction code; if the moved orchestrator
## reproduces them exactly, the render math is byte-identical. Render-only, no RNG.

const DT: float = 1.0 / 60.0


func _driven_unit() -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 24
	add_child_autofree(u)              # _ready() -> _setup_flock_renderer() seeds the marks
	u.uid = 1
	u.training = 0.0                   # disable rank cycling for a simpler, stable golden
	u.position = Vector2(100.0, 100.0)
	u.facing = Vector2.DOWN
	# Phase 1: march downfield -- exercises the trail shove + arrival spring + separation.
	for _i in range(40):
		u.position += Vector2(0.0, 2.0)
		u.facing = Vector2.DOWN
		SoldierFlock.update(u, DT)
	# Phase 2: stand and fight -- exercises the combat lunge/churn + hard separation.
	u.state = Unit.State.FIGHTING
	for _i in range(40):
		SoldierFlock.update(u, DT)
	return u


func _checksum(positions: PackedVector2Array) -> float:
	var s: float = 0.0
	for i in range(positions.size()):
		s += positions[i].x * float(i + 1) + positions[i].y * float(i + 2)
	return s


func test_orchestrator_reproduces_golden_positions() -> void:
	# Golden captured from the pre-extraction Unit._update_flock; the moved orchestrator
	# must reproduce these mark positions byte-for-byte.
	var u := _driven_unit()
	var pos: PackedVector2Array = u._soldier_pos
	assert_eq(pos.size(), 24, "one mark per soldier")
	assert_almost_eq(_checksum(pos), -538.877361, 0.001, "the whole mark field matches the golden checksum")
	assert_almost_eq(pos[0].x, 10.974200, 1e-4, "mark[0].x")
	assert_almost_eq(pos[0].y, 5.607024, 1e-4, "mark[0].y")
	assert_almost_eq(pos[7].x, 9.814677, 1e-4, "mark[7].x")
	assert_almost_eq(pos[7].y, 2.424032, 1e-4, "mark[7].y")
	assert_almost_eq(pos[15].x, 6.729129, 1e-4, "mark[15].x")
	assert_almost_eq(pos[15].y, -2.227783, 1e-4, "mark[15].y")
	assert_almost_eq(pos[23].x, -3.375500, 1e-4, "mark[23].x")
	assert_almost_eq(pos[23].y, -5.533300, 1e-4, "mark[23].y")
