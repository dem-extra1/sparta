extends GutTest
## Selection helpers (issue #11): the pure type classification, number-key
## mapping, and control-group bind/recall behind double-click type-select and
## control groups. (Live mouse/key routing is exercised manually — see #12.)

const SelectionScript = preload("res://scripts/SelectionManager.gd")
const UnitScript = preload("res://scripts/Unit.gd")


func _sm() -> Node:
	var sm = SelectionScript.new()
	add_child_autofree(sm)
	return sm


func _unit(cav: bool, anti: bool) -> Unit:
	var u: Unit = UnitScript.new()
	u.is_cavalry = cav
	u.anti_cavalry = anti
	add_child_autofree(u)
	return u


func test_same_type_matches_role_not_identity() -> void:
	var sm := _sm()
	var inf1 := _unit(false, false)
	var inf2 := _unit(false, false)
	var spear := _unit(false, true)
	var cav := _unit(true, false)
	var cav2 := _unit(true, false)
	assert_true(sm._same_type(inf1, inf2), "two infantry share a type")
	assert_true(sm._same_type(cav, cav2), "two distinct cavalry share a type")
	assert_false(sm._same_type(inf1, spear), "infantry and spearmen differ")
	assert_false(sm._same_type(inf1, cav), "infantry and cavalry differ")


func test_same_type_distinguishes_archers() -> void:
	var sm := _sm()
	var inf := _unit(false, false)
	var archer := _unit(false, false)
	archer.is_ranged = true
	var archer2 := _unit(false, false)
	archer2.is_ranged = true
	assert_false(sm._same_type(inf, archer), "an archer is a different type from infantry")
	assert_true(sm._same_type(archer, archer2), "two archers share a type")


func test_digit_for_keycode_maps_number_row_only() -> void:
	var sm := _sm()
	assert_eq(sm._digit_for_keycode(KEY_0), 0, "KEY_0 -> group 0")
	assert_eq(sm._digit_for_keycode(KEY_9), 9, "KEY_9 -> group 9")
	assert_eq(sm._digit_for_keycode(KEY_A), -1, "letters are not group keys")


func test_bind_then_recall_restores_selection() -> void:
	var sm := _sm()
	var a := _unit(false, false)
	var b := _unit(true, false)
	sm._select(a)
	sm._select(b)
	sm._bind_group(1)
	sm._clear_selection()
	assert_eq(sm._selected.size(), 0, "selection is cleared")
	sm._recall_group(1)
	assert_eq(sm._selected.size(), 2, "recalling group 1 restores both bound units")


func test_recall_unbound_group_is_a_noop() -> void:
	var sm := _sm()
	var a := _unit(false, false)
	sm._select(a)
	sm._recall_group(5)   # never bound
	assert_eq(sm._selected.size(), 1, "recalling an empty slot leaves selection intact")


# --- _unit_at DEAD filter (issue #52) --------------------------------------

func test_unit_at_skips_dead_units() -> void:
	var sm := _sm()
	# Put the DEAD unit exactly under the cursor and the living one slightly off,
	# so the dead node is the strictly nearer candidate. _unit_at uses a strict
	# `<` on distance, so without the DEAD guard the dead unit would win regardless
	# of group iteration order — this fails if the guard regresses.
	var dead := _unit(false, false)
	dead.team = 0
	dead.position = Vector2(100, 100)   # exactly under the click, about to be freed
	dead.state = Unit.State.DEAD
	var alive := _unit(false, false)
	alive.team = 0
	alive.position = Vector2(105, 100)   # 5px off, so it only wins once dead is skipped
	assert_eq(sm._unit_at(Vector2(100, 100), 0), alive,
		"_unit_at returns the living unit, skipping the nearer dead one")


func test_unit_at_returns_null_when_only_match_is_dead() -> void:
	var sm := _sm()
	var dead := _unit(false, false)
	dead.team = 0
	dead.position = Vector2(50, 50)
	dead.state = Unit.State.DEAD
	assert_null(sm._unit_at(Vector2(50, 50), 0),
		"a click on a dead unit's last position selects nothing")
