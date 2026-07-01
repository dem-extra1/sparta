class_name ProjectilePhysics
## Pure ballistics for projectile entities (#435): a level-ground launch solver and the
## height arc, as deterministic functions of (geometry, gravity, angle) only -- no node,
## no RNG, no wall-clock -- so they're directly unit-testable and replay-safe (mirrors
## DistanceLegend / CameraKeyframes). Horizontal motion is linear from the launch point to
## the aim point; the height z(t) is a gravity parabola above the launch level. A projectile
## entity samples ground_at()/height_at() each physics tick; when z returns to 0 it has
## landed, and the landing ground position is tested against soldier/object footprints.
##
## Units are world units (Battle.WORLD_UNITS_PER_METER = 20 wu/m) and seconds. `gravity` is
## a tunable balance knob in wu/s^2: real gravity is 9.8*20 = 196, but a lower value gives
## slower, higher, more readable arcs at battlefield ranges -- ProjectileField owns the value.

# Launch angles (radians) the auto fire-mode picks between: a low, fast, flat trajectory for
# a direct shot at the front, and a high lob that clears intervening ranks / cover. The
# engine chooses which per shot (line-of-sight / cover gating lands in a later slice).
const ANGLE_FLAT: float = 20.0 * PI / 180.0
const ANGLE_ARCED: float = 55.0 * PI / 180.0


## Launch speed and flight time to carry a projectile a level-ground horizontal distance
## `dist` at launch angle `angle` (radians above horizontal) under `gravity`, from the range
## equation R = v^2 sin(2θ)/g. Returns {speed, flight_time}, both 0 for a degenerate input
## (non-positive dist/gravity, or an angle outside (0, 90deg) where the level-ground range is
## undefined/zero).
static func solve_launch(dist: float, gravity: float, angle: float) -> Dictionary:
	if dist <= 0.0 or gravity <= 0.0 or angle <= 0.0 or angle >= PI * 0.5:
		return {"speed": 0.0, "flight_time": 0.0}
	var s2: float = sin(2.0 * angle)
	if s2 <= 0.0:
		return {"speed": 0.0, "flight_time": 0.0}
	var speed: float = sqrt(dist * gravity / s2)
	var flight_time: float = 2.0 * speed * sin(angle) / gravity
	return {"speed": speed, "flight_time": flight_time}


## Height above the launch level at time `t` for a shot launched at `speed`,`angle` under
## `gravity`: z(t) = v sinθ · t − ½ g t². Zero at t = 0 and again at the flight time.
static func height_at(speed: float, angle: float, gravity: float, t: float) -> float:
	return speed * sin(angle) * t - 0.5 * gravity * t * t


## Peak height of that arc (reached at t = v sinθ / g). 0 for a non-positive gravity.
static func peak_height(speed: float, angle: float, gravity: float) -> float:
	if gravity <= 0.0:
		return 0.0
	var vz: float = speed * sin(angle)
	return vz * vz / (2.0 * gravity)


## Ground (horizontal) position at flight fraction `f` in [0, 1]: linear from `from` to `to`.
## `f` = t / flight_time; clamped so a sampler slightly past landing stays at the target.
static func ground_at(from: Vector2, to: Vector2, f: float) -> Vector2:
	return from.lerp(to, clampf(f, 0.0, 1.0))
