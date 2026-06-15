extends RefCounted
## Static helpers for SelectionManager — unit picking and order placement.

const UnitRef := preload("res://scripts/Unit.gd")

static func unit_at(world_pos: Vector2, team: int, friendly: bool, tree: SceneTree):
	var best = null
	var best_d: float = UnitRef.RADIUS + 6.0
	for node in tree.get_nodes_in_group("units"):
		var unit := node as UnitRef
		if unit == null:
			continue
		if friendly and unit.team != team:
			continue
		if not friendly and unit.team == team:
			continue
		var d: float = unit.position.distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = unit
	return best

static func box_select(rect: Rect2, tree: SceneTree) -> Array:
	var out: Array = []
	for node in tree.get_nodes_in_group("units"):
		if node.team == 0 and rect.has_point(node.position):
			out.append(node)
	return out

static func issue_order(selected: Array, world_pos: Vector2, tree: SceneTree) -> void:
	if selected.is_empty():
		return
	var enemy = unit_at(world_pos, 1, false, tree)
	var i: int = 0
	for unit in selected:
		if not is_instance_valid(unit):
			continue
		if enemy != null:
			unit.target_enemy = enemy
			unit.has_move_target = false
		else:
			var cols: int = 4
			var off := Vector2((i % cols) * 42 - 63, (i / cols) * 42)
			unit.move_target = world_pos + off
			unit.has_move_target = true
			unit.target_enemy = null
		i += 1
