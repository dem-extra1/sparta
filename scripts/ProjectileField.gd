class_name ProjectileField
## In-flight projectiles (#435), held as plain-data parallel arrays — no nodes — and ticked
## once per physics frame by Battle after the soldier passes settle. A ranged volley enqueues
## a projectile carrying its already-rolled casualty count (UnitCombat.shoot); the projectile
## flies a real ProjectilePhysics height arc, and when it lands (elapsed >= flight_time) it
## delivers those casualties to the target via the per-soldier path, using the launch point as
## the near-side selection origin (the men the arrows reach first).
##
## Determinism (replays depend on it): projectiles are appended in launch order and resolved
## in that order; the field draws NO RNG — the volley's single roll already happened at launch
## — and ticks on the fixed physics delta. Same seed + orders reproduce the same battle.
##
## Slice 1 delivers the volley's casualties on landing (arrows now have travel time, and land
## where they were aimed even if the target has moved on). Per-arrow landing hit-detection,
## shield-arc blocking, cover/LOS, and non-soldier targets are later slices (#435).

const UnitRef = preload("res://scripts/Unit.gd")

static var active: ProjectileField = null

# Gravity (wu/s^2): deliberately low vs. real 9.8*20 = 196, so volleys arc slowly and high
# enough to read at battlefield ranges. A balance knob.
const GRAVITY: float = 90.0

# Parallel arrays, one entry per in-flight projectile (all appended together, compacted together).
var _from: Array[Vector2] = []       # launch ground position (near-side selection origin)
var _to: Array[Vector2] = []         # aim / landing ground position
var _elapsed: Array[float] = []      # seconds since launch
var _flight: Array[float] = []       # total flight time to landing
var _speed: Array[float] = []        # launch speed (for the height arc)
var _angle: Array[float] = []        # launch angle
var _shooter_uid: Array[int] = []
var _target_uid: Array[int] = []
var _casualties: Array[int] = []
var _flank: Array[float] = []


## Number of projectiles in flight (for tests / diagnostics).
func count() -> int:
	return _elapsed.size()


## Enqueue a volley projectile flying from `from` to `to`, carrying `casualties` (flank already
## folded in) against `target_uid`, keyed to `shooter_uid` for the morale/fallen direction.
## `arced` picks the lob vs the flat trajectory. A degenerate (zero-distance) solve lands on
## the next tick so the casualties still resolve.
func launch(from: Vector2, to: Vector2, shooter_uid: int, target_uid: int,
		casualties: int, flank: float, arced: bool) -> void:
	var dist: float = from.distance_to(to)
	var angle: float = ProjectilePhysics.ANGLE_ARCED if arced else ProjectilePhysics.ANGLE_FLAT
	var sol: Dictionary = ProjectilePhysics.solve_launch(dist, GRAVITY, angle)
	var flight: float = sol["flight_time"]
	if flight <= 0.0:
		flight = get_physics_delta()   # degenerate: resolve next tick rather than never
	_from.append(from)
	_to.append(to)
	_elapsed.append(0.0)
	_flight.append(flight)
	_speed.append(sol["speed"])
	_angle.append(angle)
	_shooter_uid.append(shooter_uid)
	_target_uid.append(target_uid)
	_casualties.append(casualties)
	_flank.append(flank)


## Advance every projectile by `delta`; resolve and remove any that have landed. Landed
## projectiles resolve in launch (array) order — deterministic, no RNG. `battle` supplies the
## uid->unit lookup.
func step(delta: float, battle: Node) -> void:
	var i: int = 0
	while i < _elapsed.size():
		_elapsed[i] += delta
		if _elapsed[i] >= _flight[i]:
			_resolve(i, battle)
			_remove_at(i)          # compact in place; don't advance i (the next entry shifts in)
		else:
			i += 1


## Height of projectile `i` above the ground right now (for a renderer; 0 once landed).
func height_of(i: int) -> float:
	return ProjectilePhysics.height_at(_speed[i], _angle[i], GRAVITY, _elapsed[i])


## Ground position of projectile `i` right now.
func ground_of(i: int) -> Vector2:
	var f: float = _elapsed[i] / _flight[i] if _flight[i] > 0.0 else 1.0
	return ProjectilePhysics.ground_at(_from[i], _to[i], f)


## Deliver projectile `i`'s casualties to its target. Skips a dead/routing/freed target. Uses
## the launch point as the near-side selection origin; the shooter (if still alive) is the
## killer for morale/fallen direction. Falls back to the regiment formula if the target has
## no soldier layer.
func _resolve(i: int, battle: Node) -> void:
	var target = battle.unit_by_uid(_target_uid[i])
	if target == null or not is_instance_valid(target):
		return
	if target.state == UnitRef.State.DEAD or target.state == UnitRef.State.ROUTING:
		return
	var killer = battle.unit_by_uid(_shooter_uid[i])   # may be null if the shooter has died
	if not target._sim_soldier_hp.is_empty():
		SoldierMelee.apply_ranged_casualties(target, _from[i], killer, _casualties[i], _flank[i])
	elif killer != null:
		# Fallback for a target with no soldier layer. `_casualties[i]` ALREADY has the flank
		# folded in (in shoot), so apply it directly -- routing it through take_casualties would
		# re-apply flank_multiplier and double it. register_casualties handles morale/rout.
		target.soldiers = maxi(0, target.soldiers - _casualties[i])
		UnitCombat.register_casualties(target, _casualties[i], killer, _flank[i])


## Remove projectile `index` from every parallel array (swap-free, order-preserving).
func _remove_at(index: int) -> void:
	_from.remove_at(index)
	_to.remove_at(index)
	_elapsed.remove_at(index)
	_flight.remove_at(index)
	_speed.remove_at(index)
	_angle.remove_at(index)
	_shooter_uid.remove_at(index)
	_target_uid.remove_at(index)
	_casualties.remove_at(index)
	_flank.remove_at(index)


## The fixed physics step (deterministic); 1/60 fallback when no SceneTree is available.
func get_physics_delta() -> float:
	return 1.0 / float(maxi(1, Engine.physics_ticks_per_second))
