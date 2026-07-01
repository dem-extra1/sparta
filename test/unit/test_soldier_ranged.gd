extends GutTest
## Ranged casualties at the individual level (#164 authority slice): a volley kills specific
## near-side soldiers in the health pool and reaps them, instead of the regiment blindly
## decrementing `soldiers` and letting body-trimming drop arbitrary rear men. The casualty
## COUNT is unchanged from the regiment formula; only *which* men die (geometric) and the
## body compaction differ. Deterministic -- selection reads positions + index order, no RNG.

const SEED: int = 1234567


func _target(uid: int, n: int, pos: Vector2, face: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = n
	add_child_autofree(u)                # _ready(): soldiers = max_soldiers, joins groups
	u.uid = uid
	u.team = 1
	u.position = pos
	u.facing = face
	u.state = Unit.State.FIGHTING
	u.seed_sim_soldiers()                # seed bodies + full health
	return u


func _shooter(uid: int, pos: Vector2) -> Unit:
	var u: Unit = Unit.new()
	u.max_soldiers = 10
	add_child_autofree(u)
	u.uid = uid
	u.team = 0
	u.position = pos
	u.is_ranged = true
	return u


func before_each() -> void:
	Replay.rng.seed = SEED


func _dists_to(unit: Unit, origin: Vector2) -> Array[float]:
	var out: Array[float] = []
	for p in unit._sim_soldier_pos:
		out.append(origin.distance_to(p))
	return out


func test_volley_reduces_soldiers_by_the_casualty_count() -> void:
	var target := _target(2, 20, Vector2(0, 0), Vector2.DOWN)
	var shooter := _shooter(1, Vector2(600, 400))
	SoldierMelee.apply_ranged_casualties(target, shooter.position, shooter, 5, 1.0)
	assert_eq(target.soldiers, 15, "five casualties drop the regiment count by five")


func test_volley_compacts_the_body_arrays_to_match() -> void:
	# The distinguishing mark of the per-soldier path: the body arrays shrink to the new
	# count immediately (reap compacted), rather than staying oversized until the next step.
	var target := _target(2, 20, Vector2(0, 0), Vector2.DOWN)
	var shooter := _shooter(1, Vector2(600, 400))
	SoldierMelee.apply_ranged_casualties(target, shooter.position, shooter, 5, 1.0)
	assert_eq(target._sim_soldier_hp.size(), target.soldiers, "health array tracks the survivors")
	assert_eq(target._sim_soldier_pos.size(), target.soldiers, "position array tracks the survivors")


func test_volley_kills_the_near_side_first() -> void:
	# Shooter off-axis so soldier distances are distinct; the nearest man must be among the
	# dead -- no survivor is closer to the shooter than the closest original was.
	var target := _target(2, 20, Vector2(0, 0), Vector2.DOWN)
	var shooter := _shooter(1, Vector2(600, 400))
	var origin: Vector2 = shooter.position
	var before: Array[float] = _dists_to(target, origin)
	before.sort()
	SoldierMelee.apply_ranged_casualties(target, shooter.position, shooter, 5, 1.0)
	var survivor_min: float = _dists_to(target, origin).min()
	# The 5 nearest died, so every survivor is at least as far as the 5th-nearest original.
	assert_gte(survivor_min, before[4] - 0.001,
		"every survivor is at least as far from the shooter as the last man killed")


func test_overkill_kills_the_whole_regiment() -> void:
	var target := _target(2, 8, Vector2(0, 0), Vector2.DOWN)
	var shooter := _shooter(1, Vector2(600, 400))
	SoldierMelee.apply_ranged_casualties(target, shooter.position, shooter, 50, 1.0)
	assert_eq(target.soldiers, 0, "more casualties than men leaves none standing")
	assert_true(target._sim_soldier_hp.is_empty(), "and the body arrays are emptied")


func test_selection_is_deterministic() -> void:
	var a := _target(2, 20, Vector2(0, 0), Vector2.DOWN)
	var b := _target(3, 20, Vector2(0, 0), Vector2.DOWN)
	var shooter := _shooter(1, Vector2(600, 400))
	var origin: Vector2 = shooter.position
	SoldierMelee.apply_ranged_casualties(a, shooter.position, shooter, 6, 1.0)
	SoldierMelee.apply_ranged_casualties(b, shooter.position, shooter, 6, 1.0)
	var da: Array[float] = _dists_to(a, origin)
	var db: Array[float] = _dists_to(b, origin)
	da.sort()
	db.sort()
	assert_eq(da, db, "two identical volleys leave the identical set of survivors")


func test_morale_erosion_tracks_casualties_not_the_flank_multiplier() -> void:
	# By default (REAR_MORALE_EXTRA = 0) a rear volley shakes morale only through its higher
	# body count -- not a double-counted multiplier -- so the SAME casualty count erodes morale
	# equally whatever morale_flank is passed. (A rear attack still hurts morale more in play,
	# because it kills more men; that arrives via the count, not this knob.)
	var front := _target(2, 20, Vector2(0, 0), Vector2.DOWN)
	var rear := _target(3, 20, Vector2(0, 0), Vector2.DOWN)
	var shooter := _shooter(1, Vector2(600, 400))
	SoldierMelee.apply_ranged_casualties(front, shooter.position, shooter, 5, 1.0)
	SoldierMelee.apply_ranged_casualties(rear, shooter.position, shooter, 5, 2.0)
	assert_eq(front.soldiers, rear.soldiers, "same casualty count either way")
	assert_almost_eq(rear.morale, front.morale, 0.0001,
		"equal casualties erode morale equally; the flank knob is off by default")


func test_zero_casualties_is_a_no_op() -> void:
	var target := _target(2, 12, Vector2(0, 0), Vector2.DOWN)
	var shooter := _shooter(1, Vector2(600, 400))
	SoldierMelee.apply_ranged_casualties(target, shooter.position, shooter, 0, 1.0)
	assert_eq(target.soldiers, 12, "no casualties changes nothing")
