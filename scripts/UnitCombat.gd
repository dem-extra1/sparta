extends RefCounted
class_name UnitCombat
## Static combat helpers for Unit — targeting, striking, damage, death, routing.

const DETECTION_RANGE: float = 190.0
const ROUT_SPREAD_RANGE: float = 140.0

static func current_target(unit: Unit) -> Unit:
	if unit.target_enemy != null and is_instance_valid(unit.target_enemy) \
			and unit.target_enemy.state != Unit.State.DEAD \
			and unit.target_enemy.state != Unit.State.ROUTING:
		return unit.target_enemy
	unit.target_enemy = null
	return nearest_enemy(unit)

static func nearest_enemy(unit: Unit) -> Unit:
	var best: Unit = null
	var best_d_sq: float = DETECTION_RANGE * DETECTION_RANGE
	for u in unit.get_tree().get_nodes_in_group("units"):
		var e := u as Unit
		if e == null or e.team == unit.team:
			continue
		var d_sq: float = unit.position.distance_squared_to(e.position)
		if d_sq < best_d_sq:
			best_d_sq = d_sq
			best = e
	return best

static func strike(attacker: Unit, enemy: Unit) -> void:
	var base: float = float(max(1, attacker.attack - enemy.defense))
	var dmg: float = base * randf_range(0.6, 1.4)
	if attacker.is_cavalry and attacker._charge_ready and not enemy.is_cavalry:
		dmg *= 0.6 if enemy.anti_cavalry else 1.8
		attacker._charge_ready = false
	enemy.take_casualties(int(round(dmg)), attacker)

static func flank_multiplier(unit: Unit, attacker: Unit) -> float:
	var d: float = unit.facing.dot((attacker.position - unit.position).normalized())
	if d >= 0.35:
		return 1.0
	elif d >= -0.5:
		return 1.5
	return 2.0

static func apply_damage(unit: Unit, amount: int, attacker: Unit) -> void:
	var flank: float = flank_multiplier(unit, attacker)
	var total: int = max(1, int(round(amount * flank)))
	unit.soldiers -= total
	unit.morale -= float(total) * 0.12 * flank
	var ratio: float = float(unit.soldiers) / float(unit.max_soldiers)
	if ratio < 0.4:
		unit.morale -= (0.4 - ratio) * 6.0
	if unit.soldiers <= 0:
		unit.soldiers = 0
		kill(unit)
	elif unit.morale <= 0.0:
		start_rout(unit)
	unit.queue_redraw()

static func kill(unit: Unit) -> void:
	unit.state = Unit.State.DEAD
	unit.selected = false
	unit.remove_from_group("units")
	unit.queue_free()

static func start_rout(unit: Unit) -> void:
	if unit.state == Unit.State.ROUTING:
		return
	unit.state = Unit.State.ROUTING
	unit.selected = false
	unit.target_enemy = null
	unit.has_move_target = false
	unit._rout_timer = UnitMovement.ROUT_TIME
	unit.remove_from_group("units")
	unit.add_to_group("routers")
	for u in unit.get_tree().get_nodes_in_group("units"):
		var friend := u as Unit
		if friend == null or friend.team != unit.team:
			continue
		if unit.position.distance_to(friend.position) < ROUT_SPREAD_RANGE:
			friend.morale -= 12.0
	unit.queue_redraw()
