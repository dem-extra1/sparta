extends GutTest
## SelectionManager order-overlay helpers (#101): the SUPPORT-ward resolution that
## decides whether the hold-Space overlay draws a supporter→ward link. The drawing
## itself is visual, but the ward-validity guard is pure logic and worth pinning.

const SelectionManagerScript = preload("res://scripts/SelectionManager.gd")
const UnitScript = preload("res://scripts/Unit.gd")


func _sm() -> Node2D:
	var sm = SelectionManagerScript.new()
	add_child_autofree(sm)   # runs _ready(): only sets z_index / process_mode
	return sm


func _unit() -> Unit:
	var u: Unit = UnitScript.new()
	add_child_autofree(u)
	return u


func test_support_ward_resolves_a_valid_ward() -> void:
	var sm := _sm()
	var u := _unit()
	var ward := _unit()
	u.support_target = ward
	assert_eq(sm._support_ward_of(u), ward, "a live ward is returned for the overlay link")


func test_support_ward_is_null_without_a_ward() -> void:
	var sm := _sm()
	var u := _unit()
	assert_null(sm._support_ward_of(u), "no ward -> nothing to draw")


func test_support_ward_skips_a_dead_ward() -> void:
	var sm := _sm()
	var u := _unit()
	var ward := _unit()
	u.support_target = ward
	ward.state = UnitScript.State.DEAD
	assert_null(sm._support_ward_of(u), "a dead ward is not drawn")


func test_support_ward_skips_a_routing_ward() -> void:
	var sm := _sm()
	var u := _unit()
	var ward := _unit()
	u.support_target = ward
	ward.state = UnitScript.State.ROUTING
	assert_null(sm._support_ward_of(u), "a routing ward is not drawn")
