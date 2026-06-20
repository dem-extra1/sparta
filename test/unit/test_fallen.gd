extends GutTest
## Fallen (#32 Stage C): the cosmetic "men fall" body markers dropped where melee casualties
## occur. It's a render-time visual, but the spawn geometry, the body-count cap, and the
## self-cleanup are plain logic worth pinning (the drawing/fade is verified visually / in the
## demo clip).


func test_spawn_adds_one_positioned_heap() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	Fallen.spawn(parent, Vector2(60, 70), Color.RED, 4)
	assert_eq(parent.get_child_count(), 1, "spawn adds exactly one fallen-heap node")
	var fx: Fallen = parent.get_child(0)
	assert_eq(fx.global_position, Vector2(60, 70), "the heap drops where the men fell")
	assert_eq(fx._marks.size(), 4, "one body mark per casualty (under the cap)")


func test_a_single_casualty_still_drops_one_body() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	Fallen.spawn(parent, Vector2.ZERO, Color.WHITE, 1)
	var fx: Fallen = parent.get_child(0)
	assert_eq(fx._marks.size(), 1, "a single casualty still leaves one body")


func test_body_count_is_capped() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	Fallen.spawn(parent, Vector2.ZERO, Color.WHITE, 1000)
	var fx: Fallen = parent.get_child(0)
	assert_eq(fx._marks.size(), Fallen.MAX_MARKS, "a big casualty event caps at MAX_MARKS bodies")


func test_heap_frees_itself_after_its_lifetime() -> void:
	var parent := Node2D.new()
	add_child_autofree(parent)
	Fallen.spawn(parent, Vector2.ZERO, Color.WHITE, 3)
	var fx: Fallen = parent.get_child(0)
	fx._process(0.01)
	assert_false(fx.is_queued_for_deletion(), "a fresh heap is still on the field")
	fx._process(Fallen.LIFETIME)   # age past its lifetime
	assert_true(fx.is_queued_for_deletion(), "a fully-faded heap frees itself")
