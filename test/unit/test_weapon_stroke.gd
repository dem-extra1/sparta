extends GutTest
## Weapon animation (Stage F): the pure stroke math (SoldierFlock.weapon_stroke) and the
## shared blade mesh (UnitMeshes.weapon_mesh). These are render-only and deterministic
## functions of their arguments, so they reproduce on replay and are directly unit-testable.


# Sample a full cadence cycle and return [min_len, max_len, max_abs_swing].
func _sweep(reach_px: float, thrust_frac: float, swing_amp: float) -> Array:
	var min_len: float = INF
	var max_len: float = -INF
	var max_swing: float = 0.0
	var t: float = 0.0
	while t <= 1.2:   # > one cycle at WEAPON_FREQ (period ~0.84 s)
		var s := SoldierFlock.weapon_stroke(t, 0.0, reach_px, thrust_frac, swing_amp)
		min_len = minf(min_len, s[0])
		max_len = maxf(max_len, s[0])
		max_swing = maxf(max_swing, absf(s[1]))
		t += 0.005
	return [min_len, max_len, max_swing]


func test_thrust_peaks_at_full_reach_and_draws_back_by_thrust_frac() -> void:
	var sweep := _sweep(50.0, 0.5, 0.4)
	assert_almost_eq(sweep[1], 50.0, 0.05, "peak blade length is the full reach")
	assert_almost_eq(sweep[0], 25.0, 0.05, "drawn-back length is reach * (1 - thrust_frac)")


func test_zero_thrust_holds_a_constant_length() -> void:
	var sweep := _sweep(40.0, 0.0, 0.0)
	assert_almost_eq(sweep[0], 40.0, 0.001, "no thrust -> length never shrinks")
	assert_almost_eq(sweep[1], 40.0, 0.001, "no thrust -> length never grows")


func test_swing_stays_within_its_amplitude() -> void:
	var sweep := _sweep(50.0, 0.4, 0.45)
	assert_almost_eq(sweep[2], 0.45, 0.01, "swing reaches but never exceeds its amplitude")


func test_length_scales_with_reach_so_a_spear_outreaches_a_sword() -> void:
	# Same cadence, same moment: a longer-reach weapon draws a proportionally longer blade.
	var spear := SoldierFlock.weapon_stroke(0.3, 1.0, 48.0, 0.5, 0.1)
	var sword := SoldierFlock.weapon_stroke(0.3, 1.0, 26.0, 0.5, 0.1)
	assert_gt(spear[0], sword[0], "the spear's blade is longer than the sword's")
	assert_almost_eq(spear[0] / sword[0], 48.0 / 26.0, 0.001,
			"blade length is linear in reach, so the reach ratio is preserved")


func test_stroke_is_deterministic() -> void:
	var a := SoldierFlock.weapon_stroke(0.137, 2.4, 30.0, 0.35, 0.45)
	var b := SoldierFlock.weapon_stroke(0.137, 2.4, 30.0, 0.35, 0.45)
	assert_eq(a, b, "same inputs reproduce the same stroke (replay-safe)")


func test_per_mark_phase_desynchronises_the_line() -> void:
	# Two marks at the same instant but different phases give different strokes, so the
	# front rank doesn't thrust in lockstep.
	var m0 := SoldierFlock.weapon_stroke(0.2, 0.0, 40.0, 0.5, 0.4)
	var m1 := SoldierFlock.weapon_stroke(0.2, 1.7, 40.0, 0.5, 0.4)
	assert_ne(m0[0], m1[0], "different phases -> different blade lengths at the same time")


func test_weapon_mesh_is_a_single_cached_surface() -> void:
	var m := UnitMeshes.weapon_mesh()
	assert_not_null(m, "weapon_mesh returns a mesh")
	assert_eq(m.get_surface_count(), 1, "the blade is one surface")
	assert_same(m, UnitMeshes.weapon_mesh(), "the blade mesh is shared/cached across units")
