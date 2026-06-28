class_name SoldierMelee
## Per-soldier melee resolution (phase 4b), extracted from Unit.gd. Each engaged
## front-rank soldier of the attacker strikes the nearest enemy soldier within its
## weapon reach, rolling the model's opposed land contest (SoldierCombat); a hit
## wounds the enemy soldier's health pool, and a soldier whose health reaches 0 dies
## and is removed, re-packing the formation. Flanking (facing), the spear-vs-sword
## reach standoff (#240), the charge, and compounding wounds all emerge here, not from
## modifiers. Replay-deterministic: attackers in soldier-id order, one Replay.rng draw
## per striking attacker, and no RNG in the death-reaping.

# Knockback impulses (world units/sec added to the struck body's velocity). The shove
# lands on every in-reach strike; the firmer landed-hit impulse is additionally scaled by
# (1 + charge), so a charging hit throws the victim back harder. Tuned against playtests
# so the lines settle at body contact rather than interpenetrating or bouncing apart.
const KNOCKBACK_SHOVE: float = 14.0
const KNOCKBACK_LAND: float = 26.0


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
		var phi: float = SoldierCombat.facing_gate(defender.facing, apos - dpos)
		var cond_a: float = SoldierCombat.condition(attacker._sim_soldier_hp[ai], my_maxhp)
		var cond_d: float = SoldierCombat.condition(defender._sim_soldier_hp[target], en_maxhp)
		var p_land: float = SoldierCombat.land_chance(my_prof["skill"], en_prof["skill"], en_prof["shield"], phi, c, cond_a, cond_d)
		# Knockback is the enemy collision response (no separation pass): a small shove on
		# every in-reach strike, away from the attacker, keeps the lines from interpenetrating;
		# a landed blow adds a firmer impulse, scaled up by the attacker's charge. The body
		# holds the push and the slot-spring eases it back, so the standoff emerges from
		# press-in vs knockback. Velocity only -- never a position correction.
		defender._sim_body_vel[target] += push_dir * KNOCKBACK_SHOVE
		# One seeded draw per striking attacker, in id order, after the target is fixed.
		if Replay.rng.randf() < p_land:
			defender._sim_soldier_hp[target] -= SoldierCombat.wound(my_prof["lethality"], c, en_prof["armour"], cond_a)
			defender._sim_body_vel[target] += push_dir * (KNOCKBACK_LAND * (1.0 + c))

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
			dead += 1
	if dead == 0:
		return
	unit.soldiers = maxi(0, unit.soldiers - dead)
	UnitCombat.register_casualties(unit, dead, killer, 1.0)
