extends GutTest
## Phase 4a of individual-level collision (see docs/combat-model.md): the
## probabilistic per-soldier combat MATH, as pure deterministic functions, before
## it is wired into the live melee loop (phase 4b). These pin each equation in the
## design note against its implementation — the per-type profile, the charge term,
## the facing gate, the opposed land contest, and the wound — so the spec and the
## code can be checked against each other and the math stays reproducible.

const TOL: float = 1e-4

# --- Per-type combat profile (docs/combat-model.md "Soldier attributes") ------

func test_profile_skill_is_training() -> void:
	# Skill s is the unit's training, clamped to [0, 1], for every type.
	assert_almost_eq(SoldierCombat.profile_for(false, true, false, 0.75)["skill"], 0.75, TOL)
	assert_almost_eq(SoldierCombat.profile_for(true, false, false, 0.6)["skill"], 0.6, TOL)
	assert_almost_eq(SoldierCombat.profile_for(false, false, false, 1.4)["skill"], 1.0, TOL,
		"training above 1 clamps to 1")
	assert_almost_eq(SoldierCombat.profile_for(false, false, false, -0.2)["skill"], 0.0, TOL,
		"training below 0 clamps to 0")


func test_profile_spearmen_values() -> void:
	var p: Dictionary = SoldierCombat.profile_for(false, true, false, 0.75)
	assert_almost_eq(p["armour"], 0.35, TOL)
	assert_almost_eq(p["shield"], 0.65, TOL)
	assert_almost_eq(p["lethality"], 0.85, TOL)
	assert_almost_eq(p["max_health"], 100.0, TOL)
	assert_almost_eq(p["max_stamina"], 100.0, TOL)


func test_profile_cavalry_values() -> void:
	# Cavalry flag wins even if other flags are set (it is checked first).
	var p: Dictionary = SoldierCombat.profile_for(true, false, false, 0.6)
	assert_almost_eq(p["armour"], 0.40, TOL)
	assert_almost_eq(p["shield"], 0.25, TOL)
	assert_almost_eq(p["lethality"], 1.10, TOL)
	assert_almost_eq(p["max_health"], 140.0, TOL)
	assert_almost_eq(p["max_stamina"], 120.0, TOL)


func test_profile_archer_values() -> void:
	var p: Dictionary = SoldierCombat.profile_for(false, false, true, 0.3)
	assert_almost_eq(p["armour"], 0.10, TOL)
	assert_almost_eq(p["shield"], 0.05, TOL)
	assert_almost_eq(p["lethality"], 0.50, TOL)
	assert_almost_eq(p["max_health"], 80.0, TOL)


func test_profile_infantry_is_the_default() -> void:
	var p: Dictionary = SoldierCombat.profile_for(false, false, false, 0.5)
	assert_almost_eq(p["armour"], 0.45, TOL)
	assert_almost_eq(p["shield"], 0.60, TOL)
	assert_almost_eq(p["lethality"], 1.00, TOL)
	assert_almost_eq(p["max_health"], 110.0, TOL)


func test_instance_profile_reads_own_flags() -> void:
	var u: Unit = Unit.new()
	add_child_autofree(u)            # _ready() sets soldiers + joins groups
	u.anti_cavalry = true
	u.training = 0.75
	var p: Dictionary = u.combat_profile()
	assert_almost_eq(p["skill"], 0.75, TOL)
	assert_almost_eq(p["lethality"], 0.85, TOL, "anti-cavalry reads the spearman profile")


# --- Charge factor c (docs/combat-model.md "Closing velocity") ----------------

func test_charge_factor_zero_when_not_closing() -> void:
	assert_almost_eq(SoldierCombat.charge_factor(0.0), 0.0, TOL)
	assert_almost_eq(SoldierCombat.charge_factor(-50.0), 0.0, TOL,
		"a receding soldier deals no charge")


func test_charge_factor_is_one_at_reference_speed() -> void:
	assert_almost_eq(SoldierCombat.charge_factor(SoldierCombat.CHARGE_REFERENCE_SPEED), 1.0, TOL)


func test_charge_factor_is_monotonic() -> void:
	assert_gt(SoldierCombat.charge_factor(120.0), SoldierCombat.charge_factor(60.0),
		"a faster close gives a bigger charge")


# --- Facing gate phi (docs/combat-model.md "The land contest") ----------------

func test_facing_gate_full_to_the_front() -> void:
	# Defender faces +Y; the blow comes from +Y (dead ahead): fully met.
	assert_almost_eq(SoldierCombat.facing_gate(Vector2.DOWN, Vector2.DOWN), 1.0, TOL)


func test_facing_gate_zero_to_the_back() -> void:
	# Defender faces +Y; the blow comes from behind (-Y): no active defence.
	assert_almost_eq(SoldierCombat.facing_gate(Vector2.DOWN, Vector2.UP), 0.0, TOL)


func test_facing_gate_zero_to_the_flank() -> void:
	# A perpendicular blow gives a dot of 0, clamped to 0 (no negative gate).
	assert_almost_eq(SoldierCombat.facing_gate(Vector2.DOWN, Vector2.RIGHT), 0.0, TOL)


func test_facing_gate_partial_off_axis() -> void:
	var phi: float = SoldierCombat.facing_gate(Vector2.DOWN, (Vector2.DOWN + Vector2.RIGHT))
	assert_almost_eq(phi, sqrt(0.5), TOL, "a 45-degree blow is partly met")


func test_facing_gate_degenerate_is_fully_met() -> void:
	# An undefined facing is treated as fully met, never a free back-strike.
	assert_almost_eq(SoldierCombat.facing_gate(Vector2.ZERO, Vector2.DOWN), 1.0, TOL)


# --- Land contest p_land (docs/combat-model.md "The land contest") ------------

func test_land_even_match_front_is_a_coin_flip() -> void:
	# Equal skill, facing the blow, no charge: A = D, so L(0) = 0.5.
	assert_almost_eq(SoldierCombat.land_chance(0.5, 0.5, 0.0, 1.0, 0.0), 0.5, TOL)


func test_land_skill_gap_raises_the_chance() -> void:
	var even: float = SoldierCombat.land_chance(0.5, 0.5, 0.0, 1.0, 0.0)
	var veteran: float = SoldierCombat.land_chance(0.9, 0.3, 0.0, 1.0, 0.0)
	assert_gt(veteran, even, "a more skilled attacker lands more often")


func test_land_back_strike_ignores_skill_and_shield() -> void:
	# phi = 0 zeroes the defender's active defence, so a shielded, skilled
	# defender struck from behind is as exposed as a helpless one.
	var front: float = SoldierCombat.land_chance(0.5, 0.8, 0.65, 1.0, 0.0)
	var back: float = SoldierCombat.land_chance(0.5, 0.8, 0.65, 0.0, 0.0)
	assert_gt(back, front, "a blow to the back lands far more often")
	# With phi = 0 the defence term vanishes entirely: only the attacker's offence
	# remains, so the shield and the defender's skill make no difference.
	var back_no_shield: float = SoldierCombat.land_chance(0.5, 0.2, 0.0, 0.0, 0.0)
	assert_almost_eq(back, back_no_shield, TOL,
		"from behind, the defender's shield and skill do not matter")


func test_land_shield_lowers_the_chance() -> void:
	var no_shield: float = SoldierCombat.land_chance(0.5, 0.5, 0.0, 1.0, 0.0)
	var shielded: float = SoldierCombat.land_chance(0.5, 0.5, 0.8, 1.0, 0.0)
	assert_lt(shielded, no_shield, "a shield turns more blows")


func test_land_charge_raises_the_chance() -> void:
	var standing: float = SoldierCombat.land_chance(0.5, 0.5, 0.0, 1.0, 0.0)
	var charging: float = SoldierCombat.land_chance(0.5, 0.5, 0.0, 1.0, 1.0)
	assert_gt(charging, standing, "closing fast makes the blow harder to evade")


func test_land_is_clipped_to_the_bounds() -> void:
	# A hopeless mismatch still never reaches 0 or 1.
	var floor_case: float = SoldierCombat.land_chance(0.0, 1.0, 1.0, 1.0, 0.0)
	var ceil_case: float = SoldierCombat.land_chance(1.0, 0.0, 0.0, 0.0, 1.0)
	assert_almost_eq(floor_case, SoldierCombat.LAND_MIN, TOL, "never impossible")
	assert_almost_eq(ceil_case, SoldierCombat.LAND_MAX, TOL, "never automatic")


func test_land_condition_factors_shift_the_odds() -> void:
	var fresh_vs_fresh: float = SoldierCombat.land_chance(0.5, 0.5, 0.0, 1.0, 0.0, 1.0, 1.0)
	var fresh_vs_spent: float = SoldierCombat.land_chance(0.5, 0.5, 0.0, 1.0, 0.0, 1.0, 0.4)
	assert_gt(fresh_vs_spent, fresh_vs_fresh,
		"a wounded or winded defender (low cond_d) is easier to land on")


# --- Wound delta_h (docs/combat-model.md "Wound") -----------------------------

func test_wound_baseline_is_the_damage_scale() -> void:
	# lethality 1, no charge, no armour, full condition: exactly D0.
	assert_almost_eq(SoldierCombat.wound(1.0, 0.0, 0.0), SoldierCombat.DAMAGE_SCALE, TOL)


func test_wound_armour_reduces_it() -> void:
	var bare: float = SoldierCombat.wound(1.0, 0.0, 0.0)
	var armoured: float = SoldierCombat.wound(1.0, 0.0, 0.45)
	assert_almost_eq(armoured, SoldierCombat.DAMAGE_SCALE * 0.55, TOL)
	assert_lt(armoured, bare, "armour blunts the wound")


func test_wound_full_armour_stops_it() -> void:
	assert_almost_eq(SoldierCombat.wound(1.0, 0.0, 1.0), 0.0, TOL)


func test_wound_charge_amplifies_it() -> void:
	var standing: float = SoldierCombat.wound(1.0, 0.0, 0.0)
	var charging: float = SoldierCombat.wound(1.0, 1.0, 0.0)
	assert_almost_eq(charging, standing * 2.0, TOL, "a charge at c=1 doubles the wound")


func test_wound_scales_with_lethality_and_condition() -> void:
	assert_almost_eq(SoldierCombat.wound(0.5, 0.0, 0.0), SoldierCombat.DAMAGE_SCALE * 0.5, TOL)
	assert_almost_eq(SoldierCombat.wound(1.0, 0.0, 0.0, 0.5), SoldierCombat.DAMAGE_SCALE * 0.5, TOL,
		"a wounded attacker (low cond_a) hits softer")


func test_wound_is_never_negative() -> void:
	# Out-of-range inputs are clamped, never producing a healing "wound".
	assert_almost_eq(SoldierCombat.wound(1.0, -5.0, 1.5), 0.0, TOL)


# --- Determinism: the math is a pure function of its inputs -------------------

func test_math_is_deterministic() -> void:
	# Same inputs, same outputs, every call — no RNG, no state.
	var a: float = SoldierCombat.land_chance(0.7, 0.4, 0.3, 0.8, 0.5)
	var b: float = SoldierCombat.land_chance(0.7, 0.4, 0.3, 0.8, 0.5)
	assert_eq(a, b, "land chance is a pure function")
	var w1: float = SoldierCombat.wound(0.85, 0.7, 0.35)
	var w2: float = SoldierCombat.wound(0.85, 0.7, 0.35)
	assert_eq(w1, w2, "wound is a pure function")


# --- mass + knockback impulse (#201 slice A) -------------------

func test_profiles_carry_per_type_mass() -> void:
	assert_almost_eq(SoldierCombat.profile_for(true, false, false, 0.5)["mass"], 2.5, 1e-6, "cavalry are heavy")
	assert_almost_eq(SoldierCombat.profile_for(false, true, false, 0.5)["mass"], 1.0, 1e-6, "spearmen baseline mass")
	assert_almost_eq(SoldierCombat.profile_for(false, false, false, 0.5)["mass"], 1.0, 1e-6, "infantry baseline mass")
	assert_almost_eq(SoldierCombat.profile_for(false, false, true, 0.5)["mass"], 0.9, 1e-6, "archers are light")


func test_knockback_impulse_baseline() -> void:
	# lethality 1, no charge, mass 1, landed -> the base scale.
	assert_almost_eq(SoldierCombat.knockback_impulse(1.0, 0.0, 1.0, 1.0),
			SoldierCombat.KNOCKBACK_IMPULSE_SCALE, 1e-6, "baseline landed impulse is J0")


func test_knockback_impulse_is_inverse_in_mass() -> void:
	var light: float = SoldierCombat.knockback_impulse(1.0, 0.0, 1.0, 1.0)
	var heavy: float = SoldierCombat.knockback_impulse(1.0, 0.0, 2.0, 1.0)
	assert_almost_eq(heavy, light * 0.5, 1e-5, "doubling the defender's mass halves the knockback")


func test_knockback_impulse_scales_with_charge_and_lethality() -> void:
	var base: float = SoldierCombat.knockback_impulse(1.0, 0.0, 1.0, 1.0)
	assert_almost_eq(SoldierCombat.knockback_impulse(1.0, 1.0, 1.0, 1.0), base * 2.0, 1e-5,
			"a full charge (c=1) doubles the impulse via (1+c)")
	assert_almost_eq(SoldierCombat.knockback_impulse(2.0, 0.0, 1.0, 1.0), base * 2.0, 1e-5,
			"twice the lethality, twice the impulse")


func test_defended_impulse_is_a_fraction_of_a_landed_one() -> void:
	var landed: float = SoldierCombat.knockback_impulse(1.0, 0.0, 1.0, 1.0)
	var defended: float = SoldierCombat.knockback_impulse(1.0, 0.0, 1.0, SoldierCombat.ETA_DEFENDED)
	assert_almost_eq(defended, landed * SoldierCombat.ETA_DEFENDED, 1e-5, "a turned-aside blow still shoves, less")
	assert_lt(defended, landed, "but less than a clean landing")


func test_knockback_impulse_never_negative() -> void:
	assert_eq(SoldierCombat.knockback_impulse(-1.0, 0.0, 1.0, 1.0), 0.0, "negative lethality clamps to no impulse")
	assert_gt(SoldierCombat.knockback_impulse(1.0, 0.0, 0.0, 1.0), 0.0, "zero mass is floored, not a divide-by-zero")
