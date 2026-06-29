class_name SoldierCombat
## The probabilistic per-soldier combat MATH from docs/combat-model.md, as pure,
## deterministic, unit-testable functions. Extracted from Unit.gd so the model lives
## in one focused place: the per-type profile, the charge term, the facing gate, the
## opposed land contest, and the wound. Every function maps to an equation in the
## design note, so the two can be checked against each other. No state, no RNG, no
## node — callers (Unit's melee path) draw the random number and apply the result.
##
## Condition factors q(h), g(sigma) (health x stamina) enter through the cond_a /
## cond_d parameters; callers pass 1 where a factor isn't modelled yet.

# Land contest (opposed roll): p_land = clip(L(beta*(A - D)), p_min, p_max), where
#   A = s_A * cond_A + mu * c                  (attacker offence + charge-to-hit)
#   D = phi_D * (s_D + lambda * b_D) * cond_D   (defender active defence, facing-gated)
# and L is the logistic. See docs/combat-model.md "The land contest".
const HIT_SHARPNESS: float = 3.0          # beta: how sharply the skill gap swings the odds
const CHARGE_HIT_WEIGHT: float = 0.5      # mu: closing speed's weight in the attack
const SHIELD_DEFENSE_WEIGHT: float = 0.6  # lambda: shield's weight in active defence
const LAND_MIN: float = 0.05              # p_min: a blow is never impossible
const LAND_MAX: float = 0.95              # p_max: a blow is never automatic

# Wound: delta_h = D0 * lethality_A * (1 + c) * (1 - armour_D) * cond_A. D0 is the
# base damage scale — the wound a baseline weapon (lethality = 1) deals to an
# unarmoured, standing target. See docs/combat-model.md "Wound".
const DAMAGE_SCALE: float = 34.0

# Reference gallop speed (world units/sec) the charge term normalises against, so
# c ~ 1 at a full charge. Mirrors Unit.CHARGE_REFERENCE_SPEED (the regiment-level
# charge), kept here too so the per-soldier model is self-contained.
const CHARGE_REFERENCE_SPEED: float = 170.0

# Floor of the health condition factor q(h): a near-dead soldier still fights, at this
# fraction of full effectiveness. q scales both offence and active defence.
const COND_HEALTH_FLOOR: float = 0.5

# Knockback impulse (docs/combat-model.md "Knockback impulse"):
#   J = KNOCKBACK_IMPULSE_SCALE * lethality_A * (1 + c) * eta / m_D
# the velocity (world units/sec) added to the struck body along the strike axis. Scaled by
# the blow's force (lethality, and the charge term 1+c) and INVERSELY by the defender's mass
# -- a heavy horse is shoved less than a light archer. eta is the fraction of momentum
# transmitted: 1 for a clean landing, ETA_DEFENDED for a turned-aside blow (a blocked blow
# draws no blood but still shoves -- a spear wall pushes a stalled enemy back). J0 / eta_def
# are tuned to the prior flat knockback feel at baseline (lethality 1, c 0, mass 1: landed
# ~40, defended ~14), so the lines still settle at body contact; mass + charge now scale it.
const KNOCKBACK_IMPULSE_SCALE: float = 40.0   # J0
const ETA_DEFENDED: float = 0.35              # eta for a defended (not landed) blow

# Going prone (docs/combat-model.md "Going prone and getting up"): a knockback impulse J
# large enough to clear a mass- and bracing-raised threshold can fell the defender.
#   p_prone = clip((J - J_fall * (1 + br_D) * m_D) / J_scale, 0, p_prone_max)
# A felled soldier loses active defence, can't strike, and rises after PRONE_RISE_TIME.
# Tuned so a normal melee shove (J ~ 14..40) almost never fells, but a charge impulse (well
# above the threshold) often does, and a heavy/braced defender resists.
const PRONE_FALL_THRESHOLD: float = 55.0   # J_fall: impulse below this never fells a man
const PRONE_SCALE: float = 90.0            # J_scale: how fast the fall chance climbs with surplus J
const PRONE_CHANCE_MAX: float = 0.6        # p_prone_max: no single blow is a sure knockdown
const PRONE_RISE_TIME: float = 1.2         # T_up (seconds) a felled soldier needs to stand


## Per-type combat profile (docs/combat-model.md "Soldier attributes"): skill is the
## unit's training; armour, shield, lethality, and the health/stamina pools are per
## type. Pure and static so it is testable without a live node.
static func profile_for(p_is_cavalry: bool, p_anti_cavalry: bool, p_is_ranged: bool, p_training: float) -> Dictionary:
	var skill: float = clampf(p_training, 0.0, 1.0)
	if p_is_cavalry:
		return {"skill": skill, "armour": 0.40, "shield": 0.25, "lethality": 1.10, "max_health": 140.0, "max_stamina": 120.0, "mass": 2.5}
	if p_anti_cavalry:
		return {"skill": skill, "armour": 0.35, "shield": 0.65, "lethality": 0.85, "max_health": 100.0, "max_stamina": 100.0, "mass": 1.0}
	if p_is_ranged:
		return {"skill": skill, "armour": 0.10, "shield": 0.05, "lethality": 0.50, "max_health": 80.0, "max_stamina": 90.0, "mass": 0.9}
	return {"skill": skill, "armour": 0.45, "shield": 0.60, "lethality": 1.00, "max_health": 110.0, "max_stamina": 100.0, "mass": 1.0}


## The charge factor c from a closing speed (world units/sec) along the strike axis:
## the relative velocity aimed at the target, clamped non-negative and normalised by
## the reference gallop. Symmetric in the pair by construction (both combatants see
## the same closing speed). See docs/combat-model.md "Closing velocity".
static func charge_factor(closing_speed: float) -> float:
	return maxf(0.0, closing_speed) / CHARGE_REFERENCE_SPEED


## The facing gate phi_D in [0,1]: how well the defender can bring active defence
## (parry, shield, deflect) to bear. `defender_facing` is the direction the defender
## faces; `attack_from_dir` points from the defender toward the attacker. Front blow
## -> ~1, flank -> small, back -> 0 (armour only). A degenerate (zero-length) facing
## or direction returns 1 — an undefined facing is fully met, never a free back-strike.
static func facing_gate(defender_facing: Vector2, attack_from_dir: Vector2) -> float:
	if defender_facing.length_squared() < 1e-6 or attack_from_dir.length_squared() < 1e-6:
		return 1.0
	return maxf(0.0, defender_facing.normalized().dot(attack_from_dir.normalized()))


## The land-contest probability that an attacker's strike lands: the opposed roll of
## offence (skill + charge) against facing-gated active defence (skill + shield),
## squashed through the logistic and clipped to [p_min, p_max]. `cond_a`/`cond_d` are
## the attacker's/defender's condition factors q*g. See docs/combat-model.md.
static func land_chance(skill_a: float, skill_d: float, shield_d: float, phi_d: float, c: float, cond_a: float = 1.0, cond_d: float = 1.0) -> float:
	var offence: float = skill_a * cond_a + CHARGE_HIT_WEIGHT * maxf(0.0, c)
	var defence: float = phi_d * (skill_d + SHIELD_DEFENSE_WEIGHT * shield_d) * cond_d
	var x: float = HIT_SHARPNESS * (offence - defence)
	var p: float = 1.0 / (1.0 + exp(-x))
	return clampf(p, LAND_MIN, LAND_MAX)


## The wound (health removed) from a landed blow: lethality, amplified by closing
## momentum (1 + c), blunted by the defender's armour, scaled by the attacker's
## condition. Always >= 0. See docs/combat-model.md "Wound".
static func wound(lethality_a: float, c: float, armour_d: float, cond_a: float = 1.0) -> float:
	var armour: float = clampf(armour_d, 0.0, 1.0)
	var cond: float = clampf(cond_a, 0.0, 1.0)
	return DAMAGE_SCALE * maxf(0.0, lethality_a) * (1.0 + maxf(0.0, c)) * (1.0 - armour) * cond


## Knockback impulse magnitude J (world units/sec along the strike axis): the blow's force
## (lethality * (1 + charge)) divided by the defender's mass, times eta (1 landed, < 1
## defended). See docs/combat-model.md "Knockback impulse". Pure; never negative.
static func knockback_impulse(lethality_a: float, c: float, defender_mass: float, eta: float) -> float:
	# Numerator (force * charge * eta) over the defender's mass -- grouped so eta reads as a
	# numerator term, not part of the denominator.
	var force: float = KNOCKBACK_IMPULSE_SCALE * maxf(0.0, lethality_a) * (1.0 + maxf(0.0, c)) * maxf(0.0, eta)
	return force / maxf(0.01, defender_mass)


## Probability that a knockback impulse `impulse_j` fells the defender (docs/combat-model.md
## "Going prone"): surplus impulse over a mass- and bracing-raised threshold, scaled and
## capped. `brace_d` is 0 until bracing lands. Pure; clamped to [0, PRONE_CHANCE_MAX].
static func prone_chance(impulse_j: float, defender_mass: float, brace_d: float = 0.0) -> float:
	var threshold: float = PRONE_FALL_THRESHOLD * (1.0 + maxf(0.0, brace_d)) * maxf(0.01, defender_mass)
	return clampf((impulse_j - threshold) / PRONE_SCALE, 0.0, PRONE_CHANCE_MAX)


# Bracing (docs/combat-model.md "Bracing and the knockback chain"): a set, deep, front-facing
# file resists a shove with the whole column's footing, not one man's. The struck man's
# capacity is its own brace plus an attenuated sum of the braced ranks behind him:
#   C_i = BRACE_CAPACITY * (br_i + sum_{k>=1} ZETA^k * br_{i+k})
# A knockback below C_i is absorbed (the charge breaks on the braced depth); only the surplus
# moves the front man. The depth-brace sum also raises his prone threshold.
const ZETA: float = 0.5             # per-rank support-transmission efficiency (0..1]
const BRACE_CAPACITY: float = 50.0  # J_cap: impulse a fully-set man (br = 1) absorbs


## Depth-buttressed brace sum down a file: file_braces[0] is the struck man's brace, [1..] the
## braced ranks directly behind him IN ORDER, truncated by the caller at the first dead/missing
## rank (the T -> 0 break for loose or unfacing men is a follow-up — per-soldier truncation is
## not yet in the melee resolver). Returns sum_k ZETA^k * br_k (the bracketed term).
static func brace_depth(file_braces: PackedFloat32Array) -> float:
	var total: float = 0.0
	var z: float = 1.0
	for br in file_braces:
		total += z * maxf(0.0, br)
		z *= ZETA
	return total


## Impulse the struck man's set file can absorb: J_cap times the depth-brace sum.
static func brace_capacity(file_braces: PackedFloat32Array) -> float:
	return BRACE_CAPACITY * brace_depth(file_braces)


## The health condition factor q(h) in [COND_HEALTH_FLOOR, 1] for a soldier at `hp`
## out of `maxhp`: a wounded soldier fights worse — q scales both its offence and its
## active defence in the land contest — so wounds compound. See docs/combat-model.md.
static func condition(hp: float, maxhp: float) -> float:
	if maxhp <= 0.0:
		return 1.0
	return COND_HEALTH_FLOOR + (1.0 - COND_HEALTH_FLOOR) * clampf(hp / maxhp, 0.0, 1.0)


# Stamina pool (docs/combat-model.md "Stamina"): every action drains stamina; rest
# restores it. Low stamina degrades both offence and active defence through g(sigma).
const COND_STAMINA_FLOOR: float = 0.4   # g(0): a spent soldier fights at 40% effectiveness
const KAPPA_A: float = 2.0              # stamina drained per strike thrown
const KAPPA_D: float = 1.5             # base stamina drained per blow met (scaled by phi*(1+c))
const KAPPA_P: float = 10.0            # stamina cost of rising from prone
const RHO_STAMINA: float = 6.0         # stamina restored per second (flat; posture table deferred)


## The fatigue factor g(sigma) in [COND_STAMINA_FLOOR, 1]: a spent soldier fights worse
## in both offence and active defence, so stamina drain compounds like wounds.
## See docs/combat-model.md. Pure; callers pass 1 where stamina isn't modelled.
static func stamina_factor(stamina: float, max_stamina: float) -> float:
	if max_stamina <= 0.0:
		return 1.0
	return COND_STAMINA_FLOOR + (1.0 - COND_STAMINA_FLOOR) * clampf(stamina / max_stamina, 0.0, 1.0)
