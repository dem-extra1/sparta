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
	# Attacker at the origin facing down; defender just ahead, in reach. Every in-reach
	# strike adds at least the defended-blow impulse (eta_def) to the defender's body
	# velocity, pointed away from the attacker (here: +y). Health is pinned high so the one
	# strike can't kill and reap the body before we read it.
	var a := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var b := _unit(2, 1, 1, Vector2(0, 6), Vector2.UP, false)
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
	var a := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var b := _unit(2, 1, 1, Vector2(5, 5), Vector2.UP, false)
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
	# cavalry body (mass 2.5): the heavy body takes a smaller impulse (J ~ 1/mass). The eta
	# can't flip in cavalry's favour -- cavalry's shield (0.25) > archer's (0.05) means its
	# p_land is strictly <= the archer's, so "cavalry lands" implies "archer lands"; the mass
	# ratio then dominates in every reachable land/defend outcome.
	Replay.rng.seed = SEED
	var atk1 := _unit(1, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var archer := _typed_defender(2, Vector2(0, 6), Vector2.UP, false, true)
	atk1.resolve_soldier_melee(archer)
	var light_kb: float = archer._sim_body_vel[0].length()
	Replay.rng.seed = SEED
	var atk2 := _unit(3, 0, 1, Vector2(0, 0), Vector2.DOWN, false)
	var cav := _typed_defender(4, Vector2(0, 6), Vector2.UP, true, false)
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
