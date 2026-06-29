class_name SoldierMelee
## Per-soldier melee resolution (phase 4b), extracted from Unit.gd. Each engaged
## front-rank soldier of the attacker strikes the nearest enemy soldier within its
## weapon reach, rolling the model's opposed land contest (SoldierCombat); a hit
## wounds the enemy soldier's health pool, and a soldier whose health reaches 0 dies
## and is removed, re-packing the formation. Flanking (facing), the spear-vs-sword reach
## standoff, the charge, and compounding wounds all emerge here, not from modifiers.
## Replay-deterministic: attackers in soldier-id order, a fixed TWO Replay.rng draws per
## in-reach strike (the land roll, then the fall roll), and no RNG in the death-reaping.

## Resolve one melee cadence of `attacker`'s engaged front rank striking `defender`.
static func resolve(attacker: Unit, defender: Unit) -> void:
	var attackers: PackedInt32Array = attacker.engaged_soldier_indices(attacker._sim_soldier_pos.size())
	var defenders: PackedInt32Array = defender.engaged_soldier_indices(defender._sim_soldier_pos.size())
	if attackers.is_empty() or defenders.is_empty():
		return

	var my_prof: Dictionary = attacker.combat_profile()
	var en_prof: Dictionary = defender.combat_profile()
	var my_maxhp: float = my_prof["max_health"]
	var en_maxhp: float = en_prof["max_health"]
	var reach: float = attacker.soldier_reach()

	for ai in attackers:
		if ai < attacker._sim_prone.size() and attacker._sim_prone[ai] > 0.0:
			continue   # a felled attacker can't strike (no target search, no RNG — order stays stable)
		var apos: Vector2 = attacker._sim_soldier_pos[ai]
		# Nearest LIVING enemy soldier within reach — a longer reach lets us hit foes
		# who can't hit back (the spear screen).
		var target: int = -1
		var best_d: float = reach
		for di in defenders:
			if defender._sim_soldier_hp[di] <= 0.0:
				continue
			var d: float = apos.distance_to(defender._sim_soldier_pos[di])
			if d <= best_d:
				best_d = d
				target = di
		if target < 0:
			continue   # nothing in reach this strike — no RNG drawn, so order stays stable

		var dpos: Vector2 = defender._sim_soldier_pos[target]
		var axis: Vector2 = dpos - apos
		var push_dir: Vector2 = axis.normalized() if axis.length() > 0.001 else Vector2.ZERO
		# Closing speed along the strike axis -> the charge term c (bind on its own
		# line; an inline ternary as a call arg can mis-evaluate in GDScript).
		var closing: float = attacker._approach_velocity.dot(push_dir)
		var c: float = SoldierCombat.charge_factor(closing)
		# A prone defender has no active defence (phi -> 0): only its armour saves it.
		var prone_d: bool = target < defender._sim_prone.size() and defender._sim_prone[target] > 0.0
		var phi: float = 0.0 if prone_d else SoldierCombat.facing_gate(defender.facing, apos - dpos)
		var cond_a: float = SoldierCombat.condition(attacker._sim_soldier_hp[ai], my_maxhp)
		var cond_d: float = SoldierCombat.condition(defender._sim_soldier_hp[target], en_maxhp)
		var p_land: float = SoldierCombat.land_chance(my_prof["skill"], en_prof["skill"], en_prof["shield"], phi, c, cond_a, cond_d)
		# One seeded draw per striking attacker, in id order, after the target is fixed.
		var landed: bool = Replay.rng.randf() < p_land
		# Knockback is the enemy collision response (no separation pass): every in-reach strike
		# imparts a momentum impulse away from the attacker -- a clean landing transmits full
		# momentum (eta 1), a turned-aside blow a fraction (ETA_DEFENDED), and a heavier body
		# (high mass) is shoved less. So a charging horse throws foot back hard while shrugging
		# off shoves, and a blocked spear wall still pushes a stalled enemy back. The body holds
		# the push and the slot-spring eases it back. Velocity only -- never a position snap.
		var eta: float = 1.0 if landed else SoldierCombat.ETA_DEFENDED
		var impulse_mag: float = SoldierCombat.knockback_impulse(my_prof["lethality"], c, en_prof["mass"], eta)
		defender._sim_body_vel[target] += push_dir * impulse_mag
		if landed:
			defender._sim_soldier_hp[target] -= SoldierCombat.wound(my_prof["lethality"], c, en_prof["armour"], cond_a)
		# Going prone: a big enough impulse fells the defender. The fall roll is a second seeded
		# draw per striking attacker, ALWAYS drawn (after the land roll, in id order) so the draw
		# count per in-reach strike is fixed -- the size guard gates only the assignment, never
		# the draw, so an out-of-sync array can't silently shift the RNG stream. A felled body
		# loses active defence and can't strike until it rises; a fresh blow on a downed man
		# refreshes the timer, keeping him down under assault.
		var fall_roll: float = Replay.rng.randf()
		if target < defender._sim_prone.size() \
				and fall_roll < SoldierCombat.prone_chance(impulse_mag, en_prof["mass"]):
			defender._sim_prone[target] = SoldierCombat.PRONE_RISE_TIME

	reap(defender, attacker)


## Remove `unit`'s soldiers whose health has reached 0: compact them out of the
## per-soldier arrays (so the formation re-packs around the survivors), drop the
## regiment count to match, and route the deaths through the unit's shared casualty
## handler for morale, rout/death, and the cosmetic fallen markers. `killer` is the
## attacking regiment (morale/fallen direction). Facing is already in the strike
## rolls, so the morale flank is 1.0 here. Deterministic — no RNG; walks high-to-low
## so a removal never shifts an index still to be checked.
static func reap(unit: Unit, killer: Unit) -> void:
	var dead: int = 0
	for i in range(unit._sim_soldier_hp.size() - 1, -1, -1):
		if unit._sim_soldier_hp[i] <= 0.0:
			unit._sim_soldier_pos.remove_at(i)
			unit._sim_body_vel.remove_at(i)
			unit._sim_soldier_hp.remove_at(i)
			if i < unit._sim_steer.size():
				unit._sim_steer.remove_at(i)   # keep the steering array index-aligned
			if i < unit._sim_prone.size():
				unit._sim_prone.remove_at(i)   # and the prone timer
			dead += 1
	if dead == 0:
		return
	unit.soldiers = maxi(0, unit.soldiers - dead)
	UnitCombat.register_casualties(unit, dead, killer, 1.0)
