class_name SoldierBodies
## Persistent per-soldier body dynamics (phase 4), extracted from Unit.gd. The
## engaged front-rank bodies spring toward their formation slots and integrate their
## own velocity, so a body shoved by the separation pass HOLDS the displacement and
## eases back rather than snapping to formation; the unengaged bulk snaps to its
## slots. Operates on a Unit's `_sim_soldier_pos` / `_sim_body_vel` (the state stays
## on the unit, where the render and the separation pass read it). Deterministic and
## order-free across soldiers, no RNG — replay-safe like the rest of the soldier layer.

# Near-critically-damped arrival spring (DAMPING ~ 2*sqrt(STIFFNESS)): a body eases
# onto its slot without overshoot or oscillation.
const SPRING_STIFFNESS: float = 120.0
const SPRING_DAMPING: float = 22.0


## Seed a unit's bodies onto its current formation slots, at rest (zero velocity) and
## at full per-type health.
static func seed(unit: Unit) -> void:
	unit._sim_soldier_pos = unit.soldier_world_slots(unit.soldiers)
	unit._sim_body_vel = PackedVector2Array()
	unit._sim_body_vel.resize(unit._sim_soldier_pos.size())
	unit._sim_soldier_hp = PackedFloat32Array()
	unit._sim_soldier_hp.resize(unit._sim_soldier_pos.size())
	unit._sim_soldier_hp.fill(unit.combat_profile()["max_health"])   # everyone starts at full health


## Advance a unit's persistent bodies one fixed step. Only ENGAGED front-rank bodies
## persist (spring + integrate); the unengaged bulk snaps to its slots (it is never
## separated, and a persistent spring would only make the marching bulk lag, whereas
## engaged regiments are ~stationary in melee). Resizes to the live soldier count
## first — a casualty trims the rear bodies; the first call (empty arrays) seeds every
## body on its slot at rest. Order-free across soldiers; driven by the fixed physics
## delta, so it reproduces on replay.
static func step(unit: Unit, delta: float) -> void:
	var slots: PackedVector2Array = unit.soldier_world_slots(unit.soldiers)
	var n: int = slots.size()
	var old_n: int = unit._sim_soldier_pos.size()
	if old_n != n:
		# resize trims/extends at the tail (rear bodies); seed any newly-added body on
		# its slot at rest, so it never springs in from the array default (0, 0).
		unit._sim_soldier_pos.resize(n)
		unit._sim_body_vel.resize(n)
		for j in range(old_n, n):
			unit._sim_soldier_pos[j] = slots[j]
			unit._sim_body_vel[j] = Vector2.ZERO
	if unit._sim_soldier_hp.size() != n:
		# Keep the health pool index-aligned; any newly-added body arrives at full health.
		var hp_old: int = unit._sim_soldier_hp.size()
		var maxhp: float = unit.combat_profile()["max_health"]
		unit._sim_soldier_hp.resize(n)
		for j in range(hp_old, n):
			unit._sim_soldier_hp[j] = maxhp
	var engaged := {}
	for idx in unit.engaged_soldier_indices(n):
		engaged[idx] = true
	for i in range(n):
		if not engaged.has(i):
			# Unengaged bulk: snap to the slot at rest (re-seed, phase-3 behaviour).
			unit._sim_soldier_pos[i] = slots[i]
			unit._sim_body_vel[i] = Vector2.ZERO
			continue
		# Engaged front rank: near-critically-damped arrival spring (semi-implicit
		# Euler, fixed delta), so a separated body holds its push and eases back.
		var to_slot: Vector2 = slots[i] - unit._sim_soldier_pos[i]
		var accel: Vector2 = to_slot * SPRING_STIFFNESS - unit._sim_body_vel[i] * SPRING_DAMPING
		unit._sim_body_vel[i] += accel * delta
		unit._sim_soldier_pos[i] += unit._sim_body_vel[i] * delta
