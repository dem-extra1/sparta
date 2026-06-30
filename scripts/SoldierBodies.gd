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
	unit._sim_prone = PackedFloat32Array()
	unit._sim_prone.resize(unit._sim_soldier_pos.size())             # 0 = standing
	unit._sim_soldier_stamina = PackedFloat32Array()
	unit._sim_soldier_stamina.resize(unit._sim_soldier_pos.size())
	unit._sim_soldier_stamina.fill(unit.combat_profile()["max_stamina"])
	# Per-soldier facing starts pointed at the unit heading, with no maneuver active.
	unit._sim_soldier_facing = PackedVector2Array()
	unit._sim_soldier_facing.resize(unit._sim_soldier_pos.size())
	unit._sim_soldier_facing.fill(unit.facing)
	unit._per_soldier_facing = false


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
	if unit._sim_prone.size() != n:
		unit._sim_prone.resize(n)   # index-aligned; a fresh tail body stands (0)
	var maxs: float = unit.combat_profile()["max_stamina"]
	if unit._sim_soldier_stamina.size() != n:
		# Keep the stamina pool index-aligned; any newly-added body arrives at full stamina.
		var stam_old: int = unit._sim_soldier_stamina.size()
		unit._sim_soldier_stamina.resize(n)
		for j in range(stam_old, n):
			unit._sim_soldier_stamina[j] = maxs
	if unit._sim_soldier_facing.size() != n:
		var face_old: int = unit._sim_soldier_facing.size()
		unit._sim_soldier_facing.resize(n)
		# During an owned maneuver, seed a fresh tail body at the unit heading (the
		# default sync below is skipped, so it wouldn't otherwise be set). When not
		# owned, the fill() below covers every body, so seeding here would be redundant.
		if unit._per_soldier_facing:
			for j in range(face_old, n):
				unit._sim_soldier_facing[j] = unit.facing
	# Default: bodies track the unit heading. A maneuver that owns the facings
	# (_per_soldier_facing) keeps its own values until it releases them.
	if not unit._per_soldier_facing:
		unit._sim_soldier_facing.fill(unit.facing)
	# A felled body rises on its own: decay its prone timer toward 0 each tick. Stamina
	# regens during the same pass; rising from prone costs KAPPA_P on the tick it happens.
	# The body still springs to its slot below (it's down, not removed).
	for p in range(n):
		var was_prone: bool = unit._sim_prone[p] > 0.0
		unit._sim_prone[p] = maxf(0.0, unit._sim_prone[p] - delta)
		var just_rose: bool = was_prone and unit._sim_prone[p] == 0.0
		unit._sim_soldier_stamina[p] = clampf(
			unit._sim_soldier_stamina[p] + SoldierCombat.RHO_STAMINA * delta
				- (SoldierCombat.KAPPA_P if just_rose else 0.0),
			0.0, maxs)
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
		# Engaged front-rank bodies are ~stationary in melee, so their feed-forward is just
		# the friendly-avoidance steering. The unengaged bulk feeds the unit's march velocity
		# forward, PLUS any friendly-contact steering (phase 5): a marching regiment overlapping
		# a friendly steers its contact bodies off formation while still keeping up with the
		# march, so the body->regiment coupling slides the two apart. _sim_steer is zero for any
		# body not gathered by the steering pass this tick (it clears all steer first), so this
		# reduces to the plain march for the uncrowded bulk.
		var feed_forward: Vector2 = unit._sim_steer[i] if engaged.has(i) \
				else unit._approach_velocity + unit._sim_steer[i]
		var to_slot: Vector2 = slots[i] - unit._sim_soldier_pos[i]
		var accel: Vector2 = to_slot * SPRING_STIFFNESS - (unit._sim_body_vel[i] - feed_forward) * SPRING_DAMPING
		unit._sim_body_vel[i] += accel * delta
		# Cap individual soldier speed to a jog while the unit is stationary: during the
		# reform hold phase AND whenever a formation reshape (frontage change, facing wheel)
		# plays out on an idle unit. A marching unit is exempt — its bodies need to keep
		# up with moving slots — so the cap only applies when state == IDLE.
		if unit._reform_timer > 0.0 or unit.state == Unit.State.IDLE:
			unit._sim_body_vel[i] = unit._sim_body_vel[i].limit_length(Unit.REFORM_JOG_SPEED)
		unit._sim_soldier_pos[i] += unit._sim_body_vel[i] * delta


## Slide the regiment center toward its soldiers' centroid, at a bounded velocity (phase 5).
## The formation slots are centred (mean(slots) ~ position), so the drift body_centroid -
## slot_centroid is how far the bodies have been pushed off formation as a whole; stepping
## the center a fraction of that each tick drives the slot centroid onto the body centroid
## (geometric decay, stable). When bodies are pushed off slot by friendly avoidance or
## knockback, the whole regiment follows -- so friendly regiments separate from the soldier
## level up. During a clean march the bodies sit on their moving slots (drift ~0) so this is
## silent and never double-counts the march. Capped at MAX_FOLLOW_SPEED*delta so the center
## can never teleport. Per-unit and RNG-free -- replay-safe.
static func couple(unit: Unit, delta: float) -> void:
	var n: int = unit._sim_soldier_pos.size()
	if n == 0:
		return
	var slots: PackedVector2Array = unit.soldier_world_slots(unit.soldiers)
	if slots.size() != n:
		return   # arrays mid-resize this tick; couple next tick when they realign
	var body_centroid := Vector2.ZERO
	var slot_centroid := Vector2.ZERO
	for i in range(n):
		body_centroid += unit._sim_soldier_pos[i]
		slot_centroid += slots[i]
	var inv: float = 1.0 / float(n)
	var drift: Vector2 = (body_centroid - slot_centroid) * inv
	var follow_step: Vector2 = (drift * Unit.FOLLOW_RATE * delta).limit_length(Unit.MAX_FOLLOW_SPEED * delta)
	unit._body_follow_vel = follow_step / delta if delta > 0.0 else Vector2.ZERO
	unit.position += follow_step
