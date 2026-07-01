class_name UnitMorale
## Per-tick regiment condition updates for a Unit, extracted from Unit.gd: fatigue
## build-up/recovery (and the attack penalty it drives), the post-merge cohesion ramp, and
## morale recovery. Static helpers on the unit, driven by the fixed-step delta and combat
## state only -- no RNG, no wall-clock -- so they reproduce on replay. Called once per tick
## from Unit's _physics_process; the line-relief and merge logic live elsewhere on Unit.


## Fatigue builds while fighting and recovers while resting. Well-trained melee units
## cycle their ranks, reducing effective buildup by up to RANK_CYCLE_FATIGUE_REDUCTION.
static func tick_fatigue(u: Unit, delta: float) -> void:
	if u.state == Unit.State.FIGHTING:
		var cycle_reduction := 0.0 if u.is_ranged else u.training * Unit.RANK_CYCLE_FATIGUE_REDUCTION
		u.fatigue = minf(100.0, u.fatigue + Unit.FATIGUE_PER_SEC * (1.0 - cycle_reduction) * delta)
	else:
		u.fatigue = maxf(0.0, u.fatigue - Unit.FATIGUE_RECOVER_PER_SEC * delta)


## Attack multiplier from fatigue: 1.0 fresh, down to (1 - max penalty) spent.
static func fatigue_attack_factor(u: Unit) -> float:
	return 1.0 - Unit.FATIGUE_MAX_ATTACK_PENALTY * (u.fatigue / 100.0)


## The "strangers" cohesion debuff from a merge ramps back to full over time.
static func tick_cohesion(u: Unit, delta: float) -> void:
	if u.cohesion < 1.0:
		u.cohesion = minf(1.0, u.cohesion + Unit.COHESION_RECOVER_PER_SEC * delta)


## Morale recovers when resting; well-trained melee units also sustain it while fighting
## via visible rank rotation keeping the formation steady. In-fight recovery is scaled by
## the regiment's remaining STRENGTH RATIO (soldiers / max_soldiers), not just training: a
## thinned-out regiment has fewer fresh files left to rotate to the front, so its capacity
## to sustain morale through rank-cycling shrinks as it bleeds, and cuts off entirely once
## the regiment is CRUMBLING (below Unit.MORALE_CRUMBLE_RATIO_THRESHOLD -- see
## UnitCombat.register_casualties, which adds an extra erosion penalty at the same point).
## This is what keeps discipline from granting near-immunity to routing (see
## RANK_CYCLE_MORALE_PER_SEC): under sustained casualties the strength ratio trends toward
## 0, so in-fight recovery fades out well before the regiment is spent, and erosion always
## wins eventually -- even for a maxed-training unit. Training still sets how strong the
## recovery is while the regiment is intact, so a disciplined unit holds out longer / absorbs
## more losses before that crossover -- it just isn't a permanent floor above the rout
## threshold.
static func tick_morale(u: Unit, delta: float) -> void:
	if u.state != Unit.State.FIGHTING and u.morale < 100.0:
		u.morale = minf(100.0, u.morale + Unit.MORALE_RECOVER_PER_SEC * delta)
	elif u.state == Unit.State.FIGHTING and not u.is_ranged \
			and u.training >= Unit.RANK_CYCLE_MORALE_THRESHOLD and u.morale < 100.0:
		var strength_ratio: float = float(u.soldiers) / float(u.max_soldiers) if u.max_soldiers > 0 else 0.0
		if strength_ratio >= Unit.MORALE_CRUMBLE_RATIO_THRESHOLD:
			var recovery := Unit.RANK_CYCLE_MORALE_PER_SEC \
					* ((u.training - Unit.RANK_CYCLE_MORALE_THRESHOLD) / (1.0 - Unit.RANK_CYCLE_MORALE_THRESHOLD)) \
					* strength_ratio \
					* delta
			u.morale = minf(100.0, u.morale + recovery)
