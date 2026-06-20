extends GutTest
## RoutShockwave (#72): the cosmetic morale-shock ripple spawned when a unit routs.
## It's a render-time visual, but the spawn geometry and self-cleanup are plain logic
## worth pinning (the gradient/ring drawing is verified visually / in the demo clip).


func test_spawn_adds_one_positioned_ripple() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	RoutShockwave.spawn(parent, Vector2(30, 40), 140.0, Color.BLUE)
	assert_eq(parent.get_child_count(), 1, "spawn adds exactly one ripple node")
	var fx: RoutShockwave = parent.get_child(0)
	assert_eq(fx.global_position, Vector2(30, 40), "the ripple is centred on the router")
	assert_eq(fx._radius, 140.0, "and sized to the morale-shock radius")


func test_ripple_frees_itself_after_its_lifetime() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	RoutShockwave.spawn(parent, Vector2.ZERO, 140.0, Color.WHITE)
	var fx: RoutShockwave = parent.get_child(0)
	fx._process(0.01)
	assert_false(fx.is_queued_for_deletion(), "a fresh ripple is still alive")
	fx._process(RoutShockwave.LIFETIME)   # age past its lifetime
	assert_true(fx.is_queued_for_deletion(), "an expired ripple frees itself")
