class_name SoldierBodies
## Persistent per-soldier body dynamics (phase 4), extracted from Unit.gd. Every body
## accelerates toward its formation slot and integrates its own velocity — no body ever
## teleports. An engaged front-rank body knocked back by melee HOLDS the displacement and
## eases back rather than snapping, and feeds its friendly-avoidance steering velocity
## forward so it drifts off a crowding friend; the unengaged bulk feeds the unit's march
## velocity forward so it tracks its moving slots with no lag, easing onto a reformed slot
## instead of snapping. Operates on a Unit's `_sim_soldier_pos` / `_sim_body_vel` /
## `_sim_steer` (the state stays on the unit, where the render, steering, and melee read
## it). Deterministic and order-free across soldiers, no RNG — replay-safe like the rest
## of the soldier layer.

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
	unit._sim_steer = PackedVector2Array()
	unit._sim_steer.resize(unit._sim_soldier_pos.size())
	unit._sim_soldier_hp = PackedFloat32Array()
	unit._sim_soldier_hp.resize(unit._sim_soldier_pos.size())
	unit._sim_soldier_hp.fill(unit.combat_profile()["max_health"])   # everyone starts at full health


## Advance a unit's persistent bodies one fixed step. Every body springs toward its slot
## and integrates its velocity; the unengaged bulk additionally feeds the unit's march
## velocity forward, which cancels the lag a plain spring would give a moving formation
## (engaged regiments are ~stationary in melee, so their feed-forward is zero). Resizes
## to the live soldier count first — a casualty trims the rear bodies; the first call
## (empty arrays) seeds every body on its slot at rest. Order-free across soldiers; driven
## by the fixed physics delta, so it reproduces on replay.
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
	if unit._sim_steer.size() != n:
		# Index-aligned with the bodies; a fresh tail entry carries no steering yet. The
		# steering pass overwrites the engaged entries each tick before this runs.
		unit._sim_steer.resize(n)
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
	# No body ever teleports: every body accelerates toward its slot and integrates its
	# own velocity (semi-implicit Euler, fixed delta), so position only ever changes by
	# velocity * delta.
	for i in range(n):
		# Damp around a feed-forward velocity. For the marching bulk that is the unit's
		# march velocity (the rate its formation slots translate), so a body keeps up with
		# zero lag and eases onto a reformed or rotated slot over a few frames instead of
		# snapping to it. For an engaged front-rank body it is the friendly-avoidance
		# steering velocity (zero when no friendly crowds it, leaving the unchanged
		# near-critically-damped hold-and-recover spring that lets a body keep a knockback
		# push and ease back). (`_approach_velocity` is itself zero while a unit stands
		# idle, so an idle bulk eases onto its slots, not drifts.)
		var feed_forward: Vector2 = unit._sim_steer[i] if engaged.has(i) else unit._approach_velocity
		var to_slot: Vector2 = slots[i] - unit._sim_soldier_pos[i]
		var accel: Vector2 = to_slot * SPRING_STIFFNESS - (unit._sim_body_vel[i] - feed_forward) * SPRING_DAMPING
		unit._sim_body_vel[i] += accel * delta
		unit._sim_soldier_pos[i] += unit._sim_body_vel[i] * delta
