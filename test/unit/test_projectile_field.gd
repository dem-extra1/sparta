extends GutTest
## In-flight projectile field (#435 slice 1): a volley enqueues a projectile that flies its
## arc and delivers its casualties on LANDING (ranged fire now has travel time). Verifies the
## flight delay, the on-landing resolution against the per-soldier health pool, determinism,
## and the dead/degenerate guards. No RNG is drawn in the field, so it's replay-safe.

const SEED: int = 1234567


## Minimal stand-in for Battle (a Node, like the real caller): the field only needs the
## uid -> unit lookup.
class FakeBattle extends Node:
	var by_uid: Dictionary = {}
	func unit_by_uid(uid: int):
		return by_uid.get(uid, null)


func before_each() -> void:
	Replay.rng.seed = SEED


func _unit(uid: int, team: int, n: int, pos: Vector2, face: Vector2, ranged: bool) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)
	u.uid = uid
	u.team = team
	u.position = pos
	u.facing = face
	u.is_ranged = ranged
	u.state = Unit.State.FIGHTING
	if not ranged:
		u.seed_sim_soldiers()    # a melee target gets a soldier layer for the volley to bite
	return u


func _field_and_battle(shooter: Unit, target: Unit) -> Array:
	var field := ProjectileField.new()
	var battle := FakeBattle.new()
	add_child_autofree(battle)
	battle.by_uid[shooter.uid] = shooter
	battle.by_uid[target.uid] = target
	return [field, battle]


func test_launch_puts_one_projectile_in_flight() -> void:
	var shooter := _unit(1, 0, 10, Vector2(0, 0), Vector2.DOWN, true)
	var target := _unit(2, 1, 20, Vector2(400, 0), Vector2.UP, false)
	var fb: Array = _field_and_battle(shooter, target)
	var field: ProjectileField = fb[0]
	field.launch(shooter.position, target.position, shooter.uid, target.uid, 5, 1.0, true)
	assert_eq(field.count(), 1, "the volley is now a projectile in flight")


func test_casualties_are_withheld_until_the_arrow_lands() -> void:
	var shooter := _unit(1, 0, 10, Vector2(0, 0), Vector2.DOWN, true)
	var target := _unit(2, 1, 20, Vector2(400, 0), Vector2.UP, false)
	var fb: Array = _field_and_battle(shooter, target)
	var field: ProjectileField = fb[0]
	var battle: FakeBattle = fb[1]
	field.launch(shooter.position, target.position, shooter.uid, target.uid, 5, 1.0, true)
	field.step(0.05, battle)   # a sliver of the multi-second flight
	assert_eq(target.soldiers, 20, "no one falls while the arrows are still in the air")
	assert_eq(field.count(), 1, "the projectile is still flying")


func test_arrow_delivers_its_casualties_on_landing() -> void:
	var shooter := _unit(1, 0, 10, Vector2(0, 0), Vector2.DOWN, true)
	var target := _unit(2, 1, 20, Vector2(400, 0), Vector2.UP, false)
	var fb: Array = _field_and_battle(shooter, target)
	var field: ProjectileField = fb[0]
	var battle: FakeBattle = fb[1]
	field.launch(shooter.position, target.position, shooter.uid, target.uid, 5, 1.0, true)
	field.step(10.0, battle)   # well past any flight time -> it lands
	assert_eq(target.soldiers, 15, "the five casualties land with the arrows")
	assert_eq(field.count(), 0, "the spent projectile is removed")
	assert_eq(target._sim_soldier_hp.size(), 15, "and the bodies compact around the survivors")


func test_landing_is_deterministic() -> void:
	var results: Array[int] = []
	for _run in range(2):
		var shooter := _unit(1, 0, 10, Vector2(0, 0), Vector2.DOWN, true)
		var target := _unit(2, 1, 20, Vector2(400, 0), Vector2.UP, false)
		var fb: Array = _field_and_battle(shooter, target)
		var field: ProjectileField = fb[0]
		field.launch(shooter.position, target.position, shooter.uid, target.uid, 6, 1.0, true)
		field.step(10.0, fb[1])
		results.append(target.soldiers)
	assert_eq(results[0], results[1], "same launch -> same survivors, every run")


func test_target_that_dies_in_flight_is_skipped() -> void:
	var shooter := _unit(1, 0, 10, Vector2(0, 0), Vector2.DOWN, true)
	var target := _unit(2, 1, 20, Vector2(400, 0), Vector2.UP, false)
	var fb: Array = _field_and_battle(shooter, target)
	var field: ProjectileField = fb[0]
	field.launch(shooter.position, target.position, shooter.uid, target.uid, 5, 1.0, true)
	target.state = Unit.State.ROUTING   # routed away before the arrows arrive
	field.step(10.0, fb[1])
	assert_eq(field.count(), 0, "the projectile is still consumed")
	assert_eq(target.soldiers, 20, "but a routing target takes no casualties (matches take_casualties)")


func test_fallback_applies_the_flanked_count_without_re_flanking() -> void:
	# A target with no soldier layer (e.g. an archer regiment) takes the volley through the
	# regiment fallback. `casualties` already has the flank baked in, so soldiers must drop by
	# exactly that count -- not flank x it (the double-flank the review caught).
	var shooter := _unit(1, 0, 10, Vector2(0, 0), Vector2.DOWN, true)
	var target := _unit(2, 1, 20, Vector2(400, 0), Vector2.UP, true)   # ranged -> no soldier layer
	var fb: Array = _field_and_battle(shooter, target)
	var field: ProjectileField = fb[0]
	assert_true(target._sim_soldier_hp.is_empty(), "precondition: the target has no soldier layer")
	field.launch(shooter.position, target.position, shooter.uid, target.uid, 5, 2.0, true)
	field.step(10.0, fb[1])
	assert_eq(target.soldiers, 15, "drops by exactly the pre-flanked count (5), not 5x2")


func test_zero_distance_shot_still_lands() -> void:
	var shooter := _unit(1, 0, 10, Vector2(100, 100), Vector2.DOWN, true)
	var target := _unit(2, 1, 20, Vector2(100, 100), Vector2.UP, false)
	var fb: Array = _field_and_battle(shooter, target)
	var field: ProjectileField = fb[0]
	# from == to: solve_launch returns a 0 flight time; the field must still resolve it.
	field.launch(shooter.position, target.position, shooter.uid, target.uid, 3, 1.0, true)
	field.step(1.0, fb[1])
	assert_eq(field.count(), 0, "a degenerate shot doesn't get stuck in flight forever")
	assert_eq(target.soldiers, 17, "it lands and delivers its casualties")
