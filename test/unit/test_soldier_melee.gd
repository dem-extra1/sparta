extends GutTest
## Phase 4b (see docs/combat-model.md): per-soldier melee resolution -- the first
## gameplay change. Engaged front-rank soldiers strike the nearest enemy soldier
## within reach, rolling the model's opposed land contest; hits wound a per-soldier
## health pool and a soldier at 0 health dies, re-packing the formation. These pin
## the behaviours that must emerge: casualties accrue, a longer reach lets a soldier
## hit foes who can't hit back (#240), deaths compact the arrays, and the whole pass
## is replay-deterministic.

const SEED: int = 1234567

func _unit(uid: int, team: int, n: int, pos: Vector2, face: Vector2, spear: bool) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)            # _ready() sets soldiers = max_soldiers, joins groups
	u.uid = uid
	u.team = team
	u.position = pos
	u.facing = face
	u.training = 0.5
	if spear:
		u.anti_cavalry = true        # spearman profile
		u.attack_range = 48.0        # long reach (#233: 2.4 m * 20)
	else:
		u.attack_range = 26.0        # sword/infantry reach (1.3 m * 20)
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)              # latch is_engaged() true
	u.seed_sim_soldiers()            # seed bodies + full health
	return u


func before_each() -> void:
	Replay.rng.seed = SEED           # deterministic draws for every test


# --- casualties accrue --------------------------------------------------------

func test_melee_inflicts_casualties() -> void:
	var a := _unit(1, 0, 12, Vector2(0, 0), Vector2.DOWN, false)
	var b := _unit(2, 1, 12, Vector2(0, 10), Vector2.UP, false)   # close: front ranks in reach
	var before: int = b.soldiers
	for _k in range(80):
		a.resolve_soldier_melee(b)
	assert_lt(b.soldiers, before, "the defender takes per-soldier casualties")


func test_health_accumulates_before_a_death() -> void:
	# A single exchange wounds without (necessarily) killing: health drops but the
	# soldier lives until the pool is spent.
	var a := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var b := _unit(2, 1, 1, Vector2(0, 6), Vector2.UP, false)
	var full: float = b._sim_soldier_hp[0]
	# Step until the first wound lands (deterministic seed; bounded loop).
	var rounds: int = 0
	while b.soldiers == 1 and b._sim_soldier_hp[0] >= full and rounds < 50:
		a.resolve_soldier_melee(b)
		rounds += 1
	assert_true(b.soldiers == 1 and b._sim_soldier_hp[0] < full,
		"a wound reduces health while the soldier fights on (cumulative damage)")


# --- reach standoff (#240) ----------------------------------------------------

func test_spear_reach_outranges_the_sword() -> void:
	# One spearman (reach 48) and one swordsman (reach 26), 35 apart: the spear
	# reaches the sword, the sword cannot reach back. The swordsman should die; the
	# spearman should take no wounds at all.
	var spear := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, true)
	var sword := _unit(2, 1, 1, Vector2(0, 35), Vector2.UP, false)
	var spear_full: float = spear._sim_soldier_hp[0]
	for _k in range(300):
		spear.resolve_soldier_melee(sword)   # in reach (35 < 48)
		sword.resolve_soldier_melee(spear)   # out of reach (35 > 26): no target
	assert_eq(spear.soldiers, 1, "the sword never reaches the spearman (#240)")
	assert_almost_eq(spear._sim_soldier_hp[0], spear_full, 0.001,
		"the spearman takes no wounds at all")
	assert_eq(sword.soldiers, 0, "the spear's reach kills the swordsman")


func test_equal_reach_both_take_losses() -> void:
	# Control: same reach, both in range -> both bleed (the asymmetry above is reach,
	# not some quirk of the setup).
	var a := _unit(1, 0, 12, Vector2(0, 0), Vector2.DOWN, false)
	var b := _unit(2, 1, 12, Vector2(0, 10), Vector2.UP, false)
	for _k in range(80):
		a.resolve_soldier_melee(b)
		b.resolve_soldier_melee(a)
	assert_lt(a.soldiers, a.max_soldiers, "equal reach: attacker also takes losses")
	assert_lt(b.soldiers, b.max_soldiers, "equal reach: defender takes losses")


# --- formation melee factors flow through the per-soldier path ----------------
# These drive the DOMINANT engaged-melee path (resolve_soldier_melee), not just the
# factor methods in isolation, so the shielded-stance melee effects can't be dead code.

## Total wounds dealt to a single defender over `rounds` cadences, WITHOUT killing it:
## the drop in its lone soldier's health pool. A single pair never compacts (no death),
## so the health delta is a clean, saturation-free measure of melee output. Returns the
## health lost. Asserts the defender survived so the comparison stays meaningful.
func _wounds_over(attacker: Unit, defender: Unit, rounds: int) -> float:
	var full: float = defender._sim_soldier_hp[0]
	for _k in range(rounds):
		attacker.resolve_soldier_melee(defender)
	assert_eq(defender.soldiers, 1, "the lone defender must survive for a clean wound measure")
	return full - defender._sim_soldier_hp[0]


func test_testudo_attacker_inflicts_fewer_wounds_via_soldier_path() -> void:
	# Same seed, same geometry: a TESTUDO attacker (head-down, weak melee) wounds a lone
	# defender LESS over the per-soldier cadence than a normal-formation attacker does.
	Replay.rng.seed = SEED
	var a_norm := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var d_norm := _unit(2, 1, 1, Vector2(0, 10), Vector2.UP, false)
	var normal_wounds: float = _wounds_over(a_norm, d_norm, 10)

	Replay.rng.seed = SEED
	var a_test := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	a_test.set_formation(Unit.FORMATION_TESTUDO)
	var d_test := _unit(2, 1, 1, Vector2(0, 10), Vector2.UP, false)
	var testudo_wounds: float = _wounds_over(a_test, d_test, 10)

	assert_gt(normal_wounds, 0.0, "the normal attacker lands wounds (sanity)")
	assert_lt(testudo_wounds, normal_wounds,
		"a testudo attacker wounds less over the per-soldier melee path (weak melee)")
	assert_almost_eq(testudo_wounds, normal_wounds * (1.0 - Unit.TESTUDO_MELEE_PENALTY),
		0.001, "by exactly the testudo melee penalty")


func test_shield_wall_defender_takes_fewer_frontal_wounds_via_soldier_path() -> void:
	# A SHIELD_WALL defender, struck head-on, takes FEWER wounds over the per-soldier
	# cadence than a normal-formation defender under identical seed and geometry.
	Replay.rng.seed = SEED
	var a_norm := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var d_norm := _unit(2, 1, 1, Vector2(0, 10), Vector2.UP, false)   # faces UP -> toward the attacker
	var normal_wounds: float = _wounds_over(a_norm, d_norm, 10)

	Replay.rng.seed = SEED
	var a_wall := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var d_wall := _unit(2, 1, 1, Vector2(0, 10), Vector2.UP, false)
	d_wall.set_formation(Unit.FORMATION_SHIELD_WALL)
	var wall_wounds: float = _wounds_over(a_wall, d_wall, 10)

	assert_gt(normal_wounds, 0.0, "the normal defender takes wounds (sanity)")
	assert_lt(wall_wounds, normal_wounds,
		"a frontal shield wall takes fewer wounds over the per-soldier melee path")
	assert_almost_eq(wall_wounds, normal_wounds * (1.0 - Unit.SHIELD_WALL_MELEE_DEFENSE),
		0.001, "by exactly the shield wall's frontal melee defense")


# --- deaths compact the arrays ------------------------------------------------

func test_death_compacts_the_body_arrays() -> void:
	var a := _unit(1, 0, 12, Vector2(0, 0), Vector2.DOWN, false)
	var b := _unit(2, 1, 12, Vector2(0, 10), Vector2.UP, false)
	for _k in range(120):
		a.resolve_soldier_melee(b)
	assert_lt(b.soldiers, 12, "some defenders died")
	assert_eq(b._sim_soldier_pos.size(), b.soldiers, "positions track the live count")
	assert_eq(b._sim_soldier_hp.size(), b.soldiers, "health pool tracks it too")
	assert_eq(b._sim_body_vel.size(), b.soldiers, "velocities track it too")
	assert_eq(b._sim_prone.size(), b.soldiers, "prone timers track it too")


# --- determinism --------------------------------------------------------------

func _run_casualties() -> int:
	var a := _unit(1, 0, 12, Vector2(0, 0), Vector2.DOWN, false)
	var b := _unit(2, 1, 12, Vector2(0, 10), Vector2.UP, false)
	for _k in range(80):
		a.resolve_soldier_melee(b)
	return b.soldiers


func test_melee_is_deterministic() -> void:
	Replay.rng.seed = SEED
	var first: int = _run_casualties()
	Replay.rng.seed = SEED
	var second: int = _run_casualties()
	assert_eq(first, second, "same seed + same orders reproduce the same casualties")


# --- knockback: the enemy collision response ----------------------------------

func test_in_reach_strike_shoves_the_defender_away() -> void:
	# Attacker at the origin facing down; unbraced defender just ahead, in reach. Every
	# in-reach strike adds at least the defended-blow impulse to the defender's body
	# velocity, pointed away from the attacker (here: +y). The defender is set to skirmish
	# so it isn't braced (a braced lone infantry man absorbs normal blows below J_cap). Health
	# is pinned high so the one strike can't kill and reap the body before we read it.
	var a := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var b := _unit(2, 1, 1, Vector2(0, 6), Vector2.UP, false)
	b.order_mode = Unit.ORDER_SKIRMISH   # unbraced: pure knockback with no absorption
	b._sim_soldier_hp[0] = 9999.0
	a.resolve_soldier_melee(b)
	# Infantry attacker (lethality 1) vs infantry defender (mass 1), no charge: the minimum
	# (turned-aside) impulse is the floor every in-reach strike clears.
	var min_shove: float = SoldierCombat.knockback_impulse(1.0, 0.0, 1.0, SoldierCombat.ETA_DEFENDED)
	assert_gte(b._sim_body_vel[0].y, min_shove - 1e-3,
		"the struck soldier is knocked back at least the defended-blow impulse, away from the attacker")
	assert_almost_eq(b._sim_body_vel[0].x, 0.0, 1e-3, "no lateral knockback for a head-on strike")


func test_knockback_points_away_from_the_attacker() -> void:
	# Off-axis geometry: the impulse follows the attacker->defender line, not a fixed axis.
	# Defender is in skirmish (unbraced) so the impulse is never absorbed by brace capacity.
	var a := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var b := _unit(2, 1, 1, Vector2(5, 5), Vector2.UP, false)
	b.order_mode = Unit.ORDER_SKIRMISH
	b._sim_soldier_hp[0] = 9999.0
	a.resolve_soldier_melee(b)
	assert_gt(b._sim_body_vel[0].x, 0.0, "knocked back along +x, away from the attacker")
	assert_gt(b._sim_body_vel[0].y, 0.0, "and +y")


func test_no_target_means_no_knockback() -> void:
	# Out of reach (100 apart, reach 26): no target is selected, so no shove is applied.
	var a := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var b := _unit(2, 1, 1, Vector2(0, 100), Vector2.UP, false)
	a.resolve_soldier_melee(b)
	assert_almost_eq(b._sim_body_vel[0].length(), 0.0, 1e-3,
		"a strike with nothing in reach neither rolls nor knocks back")


func test_knockback_is_deterministic() -> void:
	Replay.rng.seed = SEED
	var a := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var b := _unit(2, 1, 1, Vector2(0, 6), Vector2.UP, false)
	b._sim_soldier_hp[0] = 9999.0
	a.resolve_soldier_melee(b)
	var first: Vector2 = b._sim_body_vel[0]
	Replay.rng.seed = SEED
	var c := _unit(3, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var d := _unit(4, 1, 1, Vector2(0, 6), Vector2.UP, false)
	d._sim_soldier_hp[0] = 9999.0
	c.resolve_soldier_melee(d)
	assert_almost_eq(d._sim_body_vel[0].y, first.y, 1e-6, "same seed -> same knockback (incl. any landed impulse)")


func _typed_defender(uid: int, pos: Vector2, face: Vector2, cavalry: bool, ranged: bool) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 1
	add_child_autofree(u)
	u.uid = uid
	u.team = 1
	u.position = pos
	u.facing = face
	u.training = 0.5
	u.is_cavalry = cavalry
	u.is_ranged = ranged
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)
	u.seed_sim_soldiers()
	u._sim_soldier_hp[0] = 9999.0   # survive the strike so we can read the knockback
	return u


func test_heavier_defender_is_knocked_back_less() -> void:
	# Same infantry attacker and the same seed, striking a light archer (mass 0.9) vs a heavy
	# cavalry body (mass 2.5): the heavy body takes a smaller impulse (J ~ 1/mass). Both
	# defenders are set to skirmish so brace capacity doesn't absorb the blow — this tests
	# mass alone. The eta can't flip in cavalry's favour: cavalry's shield (0.25) > archer's
	# (0.05) means its p_land is strictly <= the archer's, so "cavalry lands" implies "archer
	# lands"; the mass ratio then dominates in every reachable land/defend outcome.
	Replay.rng.seed = SEED
	var atk1 := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var archer := _typed_defender(2, Vector2(0, 6), Vector2.UP, false, true)
	archer.order_mode = Unit.ORDER_SKIRMISH   # unbraced — test mass, not bracing
	atk1.resolve_soldier_melee(archer)
	var light_kb: float = archer._sim_body_vel[0].length()
	Replay.rng.seed = SEED
	var atk2 := _unit(3, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var cav := _typed_defender(4, Vector2(0, 6), Vector2.UP, true, false)
	cav.order_mode = Unit.ORDER_SKIRMISH
	atk2.resolve_soldier_melee(cav)
	var heavy_kb: float = cav._sim_body_vel[0].length()
	assert_lt(heavy_kb, light_kb, "a heavy (cavalry) defender is knocked back less than a light (archer) one")


# --- prone / knockdown ------------------------------------------

const TICK: float = 1.0 / 60.0


func test_prone_defender_is_hit_far_more() -> void:
	# Same attacker and seed. A standing defender facing the attacker parries (phi ~ 1); a
	# prone one has no active defence (phi 0), so it loses far more health over the same blows.
	# Both pinned high so neither dies (which would reap the body before we measure).
	Replay.rng.seed = SEED
	var a1 := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var standing := _unit(2, 1, 1, Vector2(0, 6), Vector2.UP, false)
	standing._sim_soldier_hp[0] = 99999.0
	var sfull: float = standing._sim_soldier_hp[0]
	for _k in range(30):
		a1.resolve_soldier_melee(standing)
	var standing_loss: float = sfull - standing._sim_soldier_hp[0]

	Replay.rng.seed = SEED
	var a2 := _unit(3, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var prone := _unit(4, 1, 1, Vector2(0, 6), Vector2.UP, false)
	prone._sim_soldier_hp[0] = 99999.0
	prone._sim_prone[0] = 999.0   # held down for the whole test
	var pfull: float = prone._sim_soldier_hp[0]
	for _k in range(30):
		a2.resolve_soldier_melee(prone)
	var prone_loss: float = pfull - prone._sim_soldier_hp[0]
	assert_gt(prone_loss, standing_loss, "a prone defender (no active defence) is wounded far more")


func test_prone_attacker_does_not_strike() -> void:
	var a := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	a._sim_prone[0] = 999.0   # felled: can't strike
	var b := _unit(2, 1, 1, Vector2(0, 6), Vector2.UP, false)
	b._sim_soldier_hp[0] = 9999.0
	var hp: float = b._sim_soldier_hp[0]
	a.resolve_soldier_melee(b)
	assert_almost_eq(b._sim_body_vel[0].length(), 0.0, 1e-3, "a felled attacker deals no knockback")
	assert_almost_eq(b._sim_soldier_hp[0], hp, 1e-3, "and lands no wound")


func test_prone_timer_decays_and_soldier_rises() -> void:
	var u := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	u._sim_prone[0] = SoldierCombat.PRONE_RISE_TIME
	var steps: int = int(ceil(SoldierCombat.PRONE_RISE_TIME / TICK)) + 2
	for _i in range(steps):
		SoldierBodies.step(u, TICK)
	assert_eq(u._sim_prone[0], 0.0, "a felled soldier rises on its own after PRONE_RISE_TIME")


# --- bracing (docs/combat-model.md "Bracing") ---------------------------------

# Build a single-file set defender with n soldiers, all health-pinned at 9999.
# frontage_override=1 puts every rank in one column so the file walk runs deep.
func _deep_unit(uid: int, n: int, pos: Vector2, face: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)
	u.frontage_override = 1   # single column; must be set before seed_sim_soldiers()
	u.uid = uid
	u.team = 1
	u.position = pos
	u.facing = face
	u.training = 0.5
	u.attack_range = 26.0
	u.state = Unit.State.FIGHTING
	u.tick_engaged(0.1)
	u.seed_sim_soldiers()
	for i in range(n):
		u._sim_soldier_hp[i] = 9999.0
	return u


func test_deep_set_file_is_knocked_back_less_than_a_lone_man() -> void:
	# A 3-deep single-file engaged phalanx buttresses the front man's footing with the
	# whole column (docs/combat-model.md "Bracing"). The attacker's approach velocity is
	# set high so even a defended blow generates an impulse that clears the lone man's
	# brace capacity — proving the depth absorbs surplus the lone man can't.
	Replay.rng.seed = SEED
	var atk1 := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	atk1._approach_velocity = Vector2(0, 500.0)   # large charge — impulse clears lone brace
	var lone := _unit(2, 1, 1, Vector2(0, 6), Vector2.UP, false)
	lone._sim_soldier_hp[0] = 9999.0
	SoldierMelee.resolve(atk1, lone)
	var lone_kb: float = lone._sim_body_vel[0].length()

	Replay.rng.seed = SEED
	var atk2 := _unit(3, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	atk2._approach_velocity = Vector2(0, 500.0)
	var deep := _deep_unit(4, 3, Vector2(0, 6), Vector2.UP)
	SoldierMelee.resolve(atk2, deep)
	var deep_kb: float = deep._sim_body_vel[0].length()

	assert_gt(lone_kb, 0.0, "the lone set man is knocked back (shove clears his lone brace capacity)")
	assert_lt(deep_kb, lone_kb, "the 3-deep set file is knocked back less — depth buttresses the front")


func test_flank_blow_gets_no_bracing() -> void:
	# phi = 0 for a lateral blow: the file column is never gathered, so a set lone defender
	# takes the full impulse from a flank blow (cap = 0), while the same defender hit from the
	# front absorbs part of it (phi > 0, brace capacity applied). A flank_kb > front_kb shows
	# that bracing only fires for front blows and not for flanks.
	Replay.rng.seed = SEED
	var atk_front := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	atk_front._approach_velocity = Vector2(0.0, 500.0)   # charge — same magnitude as the flank
	var def_front := _unit(2, 1, 1, Vector2(0, 6), Vector2.UP, false)   # faces the attacker: phi > 0
	def_front._sim_soldier_hp[0] = 9999.0
	SoldierMelee.resolve(atk_front, def_front)
	var front_kb: float = def_front._sim_body_vel[0].length()

	Replay.rng.seed = SEED
	var atk_flank := _unit(3, 0, 1, Vector2(-6, 0), Vector2.RIGHT, false)
	atk_flank._approach_velocity = Vector2(500.0, 0.0)   # same charge magnitude, lateral
	var def_flank := _unit(4, 1, 1, Vector2(0, 0), Vector2.DOWN, false)   # faces down: phi = 0
	def_flank._sim_soldier_hp[0] = 9999.0
	SoldierMelee.resolve(atk_flank, def_flank)
	var flank_kb: float = def_flank._sim_body_vel[0].length()

	assert_gt(flank_kb, front_kb,
		"a flank blow (phi=0) gets no bracing: full impulse vs. a front blow absorbed by brace capacity")


# --- stamina drain and exhaustion (docs/combat-model.md "Stamina") ------------

func test_spent_attacker_has_lower_cond_a() -> void:
	# Stamina at 0 reduces g(sigma) to the floor, which multiplies into cond_a.
	var a := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var prof: Dictionary = a.combat_profile()
	var maxhp: float = prof["max_health"]
	var maxstam: float = prof["max_stamina"]
	var fresh_cond: float = SoldierCombat.condition(a._sim_soldier_hp[0], maxhp) \
		* SoldierCombat.stamina_factor(a._sim_soldier_stamina[0], maxstam)
	a._sim_soldier_stamina[0] = 0.0
	var spent_cond: float = SoldierCombat.condition(a._sim_soldier_hp[0], maxhp) \
		* SoldierCombat.stamina_factor(0.0, maxstam)
	assert_almost_eq(fresh_cond, 1.0, 1e-3, "fresh soldier starts at full condition")
	assert_lt(spent_cond, fresh_cond, "a spent attacker has a lower cond_a")


func test_tired_defender_has_lower_cond_d() -> void:
	var b := _unit(2, 1, 1, Vector2(0, 6), Vector2.UP, false)
	var prof: Dictionary = b.combat_profile()
	var maxhp: float = prof["max_health"]
	var maxstam: float = prof["max_stamina"]
	var fresh_cond: float = SoldierCombat.condition(b._sim_soldier_hp[0], maxhp) \
		* SoldierCombat.stamina_factor(b._sim_soldier_stamina[0], maxstam)
	b._sim_soldier_stamina[0] = 0.0
	var tired_cond: float = SoldierCombat.condition(b._sim_soldier_hp[0], maxhp) \
		* SoldierCombat.stamina_factor(0.0, maxstam)
	assert_lt(tired_cond, fresh_cond, "a tired defender has a lower cond_d")


func test_attacker_stamina_drains_per_strike() -> void:
	var a := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var b := _unit(2, 1, 1, Vector2(0, 6), Vector2.UP, false)
	b._sim_soldier_hp[0] = 9999.0
	var stam_before: float = a._sim_soldier_stamina[0]
	a.resolve_soldier_melee(b)
	assert_lt(a._sim_soldier_stamina[0], stam_before,
		"attacker stamina drains after a strike")
	assert_almost_eq(stam_before - a._sim_soldier_stamina[0], SoldierCombat.KAPPA_A, 1e-4,
		"attacker drains exactly KAPPA_A per strike")


func test_defender_stamina_drains_when_facing_blow() -> void:
	# Defender faces the attacker (phi > 0), so KAPPA_D*(phi*(1+c)) > 0.
	var a := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var b := _unit(2, 1, 1, Vector2(0, 6), Vector2.UP, false)
	b._sim_soldier_hp[0] = 9999.0
	a._sim_soldier_hp[0] = 9999.0
	var stam_before: float = b._sim_soldier_stamina[0]
	a.resolve_soldier_melee(b)
	assert_lt(b._sim_soldier_stamina[0], stam_before,
		"front-facing defender stamina drains after meeting a blow")


func test_defender_stamina_does_not_drain_when_flanked() -> void:
	# phi = 0 for a flank blow: the formula KAPPA_D*phi*(1+c) gives 0.
	var a := _unit(1, 0, 1, Vector2(-6, 0), Vector2.RIGHT, false)
	var b := _unit(2, 1, 1, Vector2(0, 0), Vector2.DOWN, false)   # faces down: phi = 0
	b._sim_soldier_hp[0] = 9999.0
	a._sim_soldier_hp[0] = 9999.0
	var stam_before: float = b._sim_soldier_stamina[0]
	a.resolve_soldier_melee(b)
	assert_almost_eq(b._sim_soldier_stamina[0], stam_before, 1e-4,
		"a flanked defender (phi=0) does not drain stamina")


func test_stamina_regens_in_step() -> void:
	var u := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var maxstam: float = u.combat_profile()["max_stamina"]
	u._sim_soldier_stamina[0] = maxstam * 0.5
	var before: float = u._sim_soldier_stamina[0]
	SoldierBodies.step(u, 1.0)   # one full second
	assert_gt(u._sim_soldier_stamina[0], before, "stamina regens during step")
	assert_almost_eq(u._sim_soldier_stamina[0], before + SoldierCombat.RHO_STAMINA, 1e-3,
		"regen is RHO_STAMINA per second")


func test_stamina_regen_is_capped_at_max() -> void:
	var u := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var maxstam: float = u.combat_profile()["max_stamina"]
	u._sim_soldier_stamina[0] = maxstam   # already full
	SoldierBodies.step(u, 10.0)
	assert_almost_eq(u._sim_soldier_stamina[0], maxstam, 1e-4,
		"stamina does not exceed max_stamina")


func test_kappa_p_charged_on_rise() -> void:
	# A soldier that was prone rises (timer hits 0) during step — that tick costs KAPPA_P.
	var u := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var maxstam: float = u.combat_profile()["max_stamina"]
	u._sim_soldier_stamina[0] = maxstam
	u._sim_prone[0] = TICK * 0.5   # rises on the very next step
	SoldierBodies.step(u, TICK)
	var regen: float = SoldierCombat.RHO_STAMINA * TICK
	var expected: float = clampf(maxstam + regen - SoldierCombat.KAPPA_P, 0.0, maxstam)
	assert_almost_eq(u._sim_soldier_stamina[0], expected, 1e-3,
		"rising from prone costs KAPPA_P on the tick the timer hits zero")


func test_death_compacts_stamina_alongside_other_arrays() -> void:
	# Extend the existing compaction test: after deaths, all five per-soldier arrays
	# (pos, vel, hp, prone, stamina) must be index-aligned with the live count.
	var a := _unit(1, 0, 12, Vector2(0, 0), Vector2.DOWN, false)
	var b := _unit(2, 1, 12, Vector2(0, 10), Vector2.UP, false)
	for _k in range(120):
		a.resolve_soldier_melee(b)
	assert_lt(b.soldiers, 12, "some defenders died")
	assert_eq(b._sim_soldier_pos.size(), b.soldiers, "positions track the live count")
	assert_eq(b._sim_soldier_hp.size(), b.soldiers, "health pool tracks it too")
	assert_eq(b._sim_body_vel.size(), b.soldiers, "velocities track it too")
	assert_eq(b._sim_prone.size(), b.soldiers, "prone timers track it too")
	assert_eq(b._sim_soldier_stamina.size(), b.soldiers, "stamina pool tracks it too")


# --- reform after casualties (file-closing) -----------------------------------

func test_reformed_block_holds_frontage_and_closes_up_after_casualties() -> void:
	# A unit takes casualties and reforms. The held frontage does not change as depth thins
	# (the line keeps its width and loses ranks), the front rank stays full-width, and the
	# short rear rank closes toward the centre rather than fanning past the block's edges.
	var u := _unit(1, 0, 12, Vector2(0, 0), Vector2.DOWN, false)   # 12 men
	var files: int = UnitFormation.frontage(u)
	var full := UnitFormation.slots(u, 12)
	var front_edge: float = 0.0
	for i in range(files):
		front_edge = maxf(front_edge, absf(full[i].x))            # the front rank's outer |x|
	# Fell three men (front-rank indices) and reap, so the rear rank goes partial.
	u._sim_soldier_hp[0] = 0.0
	u._sim_soldier_hp[1] = 0.0
	u._sim_soldier_hp[2] = 0.0
	SoldierMelee.reap(u, u)
	assert_eq(u.soldiers, 9, "three men fell")
	assert_eq(UnitFormation.frontage(u), files, "frontage holds as the block thins")
	var slots := UnitFormation.slots(u, u.soldiers)  # target layout for survivors, not current world positions
	# Front rank still spans the full frontage (the width the line holds).
	var reformed_front: float = 0.0
	for i in range(files):
		reformed_front = maxf(reformed_front, absf(slots[i].x))
	assert_almost_eq(reformed_front, front_edge, 0.001, "the front rank keeps its full width")
	# No reformed body sits outside that width -- the block closes UP, never bulges out.
	for i in range(slots.size()):
		assert_true(absf(slots[i].x) <= front_edge + 0.001,
			"reformed slot %d stays within the block's frontage" % i)
