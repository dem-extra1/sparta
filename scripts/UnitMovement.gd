extends RefCounted
## Static movement helpers for Unit — face, translate, separate, rout.

const MAX_SEPARATION_PUSH: float = 3.0
const ROUT_TIME: float = 6.0

static func move_to(unit: Unit, point: Vector2, delta: float) -> void:
	var to: Vector2 = point - unit.position
	if to.length() < 1.0:
		return
	var dir: Vector2 = to.normalized()
	face_dir(unit, dir)
	unit.position += dir * unit.move_speed * delta
	unit.state = Unit.State.MOVING
	unit._moved_last_frame = true

static func face(unit: Unit, point: Vector2) -> void:
	face_dir(unit, point - unit.position)

static func face_dir(unit: Unit, dir: Vector2) -> void:
	if dir.length() > 0.01:
		unit.facing = dir.normalized()

static func separate(unit: Unit) -> void:
	var push: Vector2 = Vector2.ZERO
	for u in unit.get_tree().get_nodes_in_group("units"):
		if u == unit:
			continue
		var min_dist: float = unit.separation_radius + u.separation_radius
		var offset: Vector2 = unit.position - u.position
		var d_sq: float = offset.length_squared()
		if d_sq >= min_dist * min_dist:
			continue
		if d_sq > 0.0001:
			var d: float = sqrt(d_sq)
			push += (offset / d) * (min_dist - d)
		else:
			push += Vector2.from_angle(randf() * TAU)
	if push != Vector2.ZERO:
		unit.position += (push * 0.5).limit_length(MAX_SEPARATION_PUSH)

static func process_rout(unit: Unit, delta: float) -> void:
	var flee: Vector2 = Vector2.UP if unit.team == 0 else Vector2.DOWN
	unit.facing = flee
	unit.position += flee * (unit.move_speed * 1.3) * delta
	unit._rout_timer -= delta
	if unit._rout_timer <= 0.0:
		unit.state = Unit.State.DEAD
		unit.queue_free()
	else:
		unit.queue_redraw()

static func tick_ai(unit: Unit, enemy: Unit, delta: float) -> void:
	if enemy != null:
		var dist: float = unit.position.distance_to(enemy.position)
		if dist <= unit.attack_range + Unit.RADIUS:
			unit.state = Unit.State.FIGHTING
			face(unit, enemy.position)
			if unit._attack_cd <= 0.0:
				unit._attack_cd = Unit.ATTACK_INTERVAL
				UnitCombat.strike(unit, enemy)
			return
		if unit.target_enemy != null:
			move_to(unit, enemy.position, delta)
			return
	if unit.has_move_target:
		if unit.position.distance_to(unit.move_target) > 5.0:
			move_to(unit, unit.move_target, delta)
		else:
			unit.has_move_target = false
			unit.state = Unit.State.IDLE
	elif enemy != null:
		move_to(unit, enemy.position, delta)
	else:
		unit.state = Unit.State.IDLE
	if not unit._moved_last_frame and unit.state != Unit.State.FIGHTING:
		unit._charge_ready = true
