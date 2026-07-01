extends GutTest
## Pure projectile ballistics (#435): the level-ground launch solver and the height arc.
## A function of (geometry, gravity, angle) only -- no node/RNG needed (mirrors
## test_distance_legend). Gravity is an arbitrary positive test value; the real balance
## value lives on ProjectileField.

const G: float = 196.0   # ~9.8 m/s^2 * 20 wu/m; any positive value exercises the math


# --- solve_launch: reaches the target -----------------------------------------

func test_solved_shot_returns_to_ground_at_the_flight_time() -> void:
	# The whole contract: a shot solved for distance d at angle θ is back at launch height
	# exactly at flight_time (i.e. it lands on the target, which sits at the same level).
	var dist: float = 400.0
	var sol: Dictionary = ProjectilePhysics.solve_launch(dist, G, ProjectilePhysics.ANGLE_ARCED)
	assert_gt(sol["flight_time"], 0.0, "a valid shot has a positive flight time")
	var z_end: float = ProjectilePhysics.height_at(sol["speed"], ProjectilePhysics.ANGLE_ARCED, G, sol["flight_time"])
	assert_almost_eq(z_end, 0.0, 0.001, "height returns to 0 exactly at the flight time")


func test_horizontal_range_matches_the_requested_distance() -> void:
	# Horizontal speed * flight time must cover the requested distance (the range equation).
	var dist: float = 300.0
	var angle: float = ProjectilePhysics.ANGLE_FLAT
	var sol: Dictionary = ProjectilePhysics.solve_launch(dist, G, angle)
	var horizontal: float = sol["speed"] * cos(angle) * sol["flight_time"]
	assert_almost_eq(horizontal, dist, 0.01, "the shot covers exactly the requested ground distance")


func test_arced_shot_flies_higher_and_longer_than_a_flat_one() -> void:
	var dist: float = 400.0
	var flat: Dictionary = ProjectilePhysics.solve_launch(dist, G, ProjectilePhysics.ANGLE_FLAT)
	var arced: Dictionary = ProjectilePhysics.solve_launch(dist, G, ProjectilePhysics.ANGLE_ARCED)
	assert_gt(arced["flight_time"], flat["flight_time"],
		"the lob is in the air longer than the flat shot for the same distance")
	var flat_peak: float = ProjectilePhysics.peak_height(flat["speed"], ProjectilePhysics.ANGLE_FLAT, G)
	var arced_peak: float = ProjectilePhysics.peak_height(arced["speed"], ProjectilePhysics.ANGLE_ARCED, G)
	assert_gt(arced_peak, flat_peak, "the lob arcs higher -- it can clear ranks a flat shot can't")


# --- height arc ---------------------------------------------------------------

func test_height_is_zero_at_launch_and_positive_mid_flight() -> void:
	var sol: Dictionary = ProjectilePhysics.solve_launch(400.0, G, ProjectilePhysics.ANGLE_ARCED)
	var a: float = ProjectilePhysics.ANGLE_ARCED
	assert_eq(ProjectilePhysics.height_at(sol["speed"], a, G, 0.0), 0.0, "on the ground at launch")
	var mid: float = ProjectilePhysics.height_at(sol["speed"], a, G, sol["flight_time"] * 0.5)
	assert_gt(mid, 0.0, "airborne mid-flight")


func test_peak_height_matches_the_apex_of_the_arc() -> void:
	var sol: Dictionary = ProjectilePhysics.solve_launch(400.0, G, ProjectilePhysics.ANGLE_ARCED)
	var a: float = ProjectilePhysics.ANGLE_ARCED
	# The apex is at the midpoint of a level-ground flight; height_at there equals peak_height.
	var apex_t: float = sol["flight_time"] * 0.5
	assert_almost_eq(ProjectilePhysics.height_at(sol["speed"], a, G, apex_t),
		ProjectilePhysics.peak_height(sol["speed"], a, G), 0.001,
		"the analytic peak matches the sampled apex")


# --- ground track + guards ----------------------------------------------------

func test_ground_at_is_linear_and_clamped() -> void:
	var from := Vector2(0, 0)
	var to := Vector2(400, 0)
	assert_eq(ProjectilePhysics.ground_at(from, to, 0.0), from, "starts at the launch point")
	assert_eq(ProjectilePhysics.ground_at(from, to, 0.5), Vector2(200, 0), "halfway is the midpoint")
	assert_eq(ProjectilePhysics.ground_at(from, to, 1.0), to, "ends at the target")
	assert_eq(ProjectilePhysics.ground_at(from, to, 1.5), to, "past 1.0 clamps to the target")


func test_solve_launch_guards_degenerate_input() -> void:
	assert_eq(ProjectilePhysics.solve_launch(0.0, G, ProjectilePhysics.ANGLE_ARCED)["flight_time"], 0.0, "zero distance")
	assert_eq(ProjectilePhysics.solve_launch(400.0, 0.0, ProjectilePhysics.ANGLE_ARCED)["flight_time"], 0.0, "zero gravity")
	assert_eq(ProjectilePhysics.solve_launch(400.0, G, 0.0)["flight_time"], 0.0, "zero angle")
	assert_eq(ProjectilePhysics.solve_launch(400.0, G, PI * 0.5)["flight_time"], 0.0, "vertical (90deg) has no ground range")


func test_peak_height_guards_nonpositive_gravity() -> void:
	assert_eq(ProjectilePhysics.peak_height(500.0, ProjectilePhysics.ANGLE_ARCED, 0.0), 0.0, "no gravity guarded")
