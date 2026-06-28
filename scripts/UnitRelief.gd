class_name UnitRelief
## Line-relief swaps for a Unit, extracted from Unit.gd: a fresh regiment takes over an
## engaged friendly's fight while the tired one peels back to the rear. The pair is
## mutually exempt from separation (Unit._separation_exempt reads `_relief_partner`) so
## they pass through each other during the swap; the exemption clears once they're apart.
## Static helpers on the unit -- deterministic (positions / state only, no RNG), so live
## play and replay swap identically. The `_relief_partner` link itself lives on Unit.


## Begin relieving an engaged friendly: `u` (fresh) takes over `tired`'s fight and
## advances, `tired` peels back to the rear.
static func begin(u: Unit, tired: Unit) -> void:
	if tired == u:
		return   # a unit can't relieve itself (a self-link would never clear)
	# If either unit was already mid-relief with someone else, close those old back-links
	# first so a previous partner doesn't keep a dangling exemption.
	var old_self: Unit = u._relief_partner
	if is_instance_valid(old_self) and old_self != tired:
		old_self._relief_partner = null
	var old_tired: Unit = tired._relief_partner
	if is_instance_valid(old_tired) and old_tired != u:
		old_tired._relief_partner = null
	u._relief_partner = tired
	tired._relief_partner = u
	# Take over the tired unit's fight so the front isn't left open. A unit can be
	# FIGHTING an auto-acquired foe with target_enemy still null, so fall back to its
	# nearest enemy rather than just walking onto an empty slot.
	var foe: Unit = tired.target_enemy
	if foe == null:
		foe = UnitTargeting.nearest_enemy(tired)
	u.target_enemy = foe
	if foe != null:
		u.has_move_target = false
	else:
		u.move_target = tired.position   # truly no foe: advance onto its slot
		u.has_move_target = true
	# Tired unit disengages and falls back toward its own back edge.
	tired.target_enemy = null
	tired.move_target = _rear_point(tired)
	tired.has_move_target = true


## A point toward `u`'s own back edge -- where a relieved unit retreats to.
static func _rear_point(u: Unit) -> Vector2:
	var back: Vector2 = Vector2.UP if u.team == 0 else Vector2.DOWN
	return u.position + back * 160.0


## End the relief exemption once the partner has left the line (gone, dead, or routing) or
## the swapping pair has moved clear of each other.
static func update(u: Unit) -> void:
	if u._relief_partner == null:
		return
	var gone: bool = not is_instance_valid(u._relief_partner) \
		or u._relief_partner.state == Unit.State.DEAD \
		or u._relief_partner.state == Unit.State.ROUTING
	var apart: bool = is_instance_valid(u._relief_partner) \
		and u.position.distance_to(u._relief_partner.position) \
			> u.separation_radius + u._relief_partner.separation_radius + 24.0
	if gone or apart:
		var partner: Unit = u._relief_partner
		u._relief_partner = null
		if is_instance_valid(partner) and partner._relief_partner == u:
			partner._relief_partner = null
