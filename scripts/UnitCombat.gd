class_name UnitCombat
## Regiment-level combat resolution for a Unit, extracted from Unit.gd: the cavalry
## charge multiplier, the melee strike and ranged volley, friendly-fire interception, and
## the casualty/morale/rout bookkeeping. The per-SOLDIER resolution (the opposed contest,
## the wound) lives in SoldierCombat / SoldierMelee; this is the regiment-aggregate path
## (and the fallback when a pair has no engaged soldier layer). Static helpers on the unit,
## so they're directly unit-testable. The only RNG is the seeded Replay.rng stream, drawn
## in a fixed order, so battles stay replay-deterministic.


## Extra morale debuff for a flank/rear attack, ON TOP OF the extra casualties it already
## deals. A rear hit already kills more men (the flank multiplier scales the casualty count,
## and rear blows bypass shield/active defence), and morale erosion tracks the casualty
## count -- so the extra damage already costs extra morale. This knob adds a FURTHER morale
## penalty scaled by how far past frontal the attack is; 0 keeps morale driven by casualties
## alone (the default). Raise it later if flanking should shake morale beyond its body count.
const REAR_MORALE_EXTRA: float = 0.0


## Physics-based cavalry charge multiplier: the bonus is the rider's IMPACT MOMENTUM, not
## a one-shot token. It scales with the component of the unit's approach velocity aimed
## straight at the target -- so a fast, head-on gallop lands the full bonus, a
## shallow/glancing approach lands less, and a near-stationary unit lands none. Cavalry
## only, and not against other cavalry. Anti-cavalry spearmen brace and turn it into a
## speed-scaled penalty (charging onto set spears backfires). Deterministic -- derived
## from positions and move_speed, which live play and replay reach identically.
static func charge_multiplier(u: Unit, enemy: Unit) -> float:
	if not u.is_cavalry or enemy.is_cavalry:
		return 1.0
	var to_target: Vector2 = enemy.position - u.position
	if to_target.length() < 0.001:
		return 1.0
	# Speed directed at the target (combines closing speed and angle, relative to it).
	var speed_toward: float = maxf(0.0, u._approach_velocity.dot(to_target.normalized()))
	var charge: float = Unit.CHARGE_BONUS_AT_REF_SPEED * (speed_toward / Unit.CHARGE_REFERENCE_SPEED)
	# Anti-cavalry square: a spear-ring set on every side, so a charge from ANY
	# direction meets braced spears and backfires -- the same speed-scaled reversal
	# as set anti-cav spears, floored so a full charge never drops below x0.6. This
	# is what "braces the charge from any direction" means: there's no open side.
	if enemy.in_square():
		return maxf(Unit.SQUARE_CHARGE_FLOOR, 1.0 - charge * Unit.SQUARE_CHARGE_BACKFIRE)
	if enemy.anti_cavalry:
		# A braced spear line reverses the charge into a penalty that grows with the
		# closing speed, floored so it never drops below the old flat x0.6.
		return maxf(Unit.ANTI_CAV_CHARGE_FLOOR, 1.0 - charge * Unit.ANTI_CAV_CHARGE_BACKFIRE)
	# Tight formation: soldiers brace for impact, absorbing a fraction of the charge
	# bonus (but not reversing it -- that's the spearmen's specialty).
	if enemy.formation_mode == Unit.FORMATION_TIGHT:
		return 1.0 + charge * (1.0 - Unit.TIGHT_CHARGE_ABSORPTION)
	return 1.0 + charge


static func strike(u: Unit, enemy: Unit) -> void:
	# Phase 4b: when both regiments have an engaged soldier layer, resolve melee per
	# soldier (the model's opposed roll + wound against per-soldier health) instead of the
	# regiment damage formula. This is where flanking, reach (spear vs. sword, #240), and
	# charge fall out of geometry. Ranged volleys and any non-engaged edge case fall
	# through to the formula below.
	if Unit.INDIVIDUAL_COLLISION and not u.is_ranged and u.is_engaged() and enemy.is_engaged() \
			and not u._sim_soldier_pos.is_empty() and not enemy._sim_soldier_pos.is_empty():
		u.resolve_soldier_melee(enemy)
		u._approach_velocity = Vector2.ZERO   # spend the charge on this contact strike
		Sfx.play(&"hit")
		return

	# Tired troops hit softer; a freshly-merged unit hits softer still until it gels;
	# a squared unit hunkers to defend all around and so hits softer too. All scale
	# effective attack before defence.
	var eff_attack: float = float(u.attack) * UnitMorale.fatigue_attack_factor(u) * u.cohesion \
			* u.formation_attack_factor()
	var base: float = maxf(1.0, eff_attack - float(enemy.defense))
	# Draw from the seeded replay RNG (one stream, stable order) so battles are
	# reproducible. This is the simulation's only source of randomness.
	var dmg: float = base * Replay.rng.randf_range(0.6, 1.4)

	# Cavalry charge: a momentum-scaled bonus (or a backfire onto braced spears), computed
	# from the rider's impact velocity at this contact. Spend it so the charge lands only
	# on this first, contact-making strike -- not the grinding strikes that follow.
	dmg *= charge_multiplier(u, enemy)
	u._approach_velocity = Vector2.ZERO

	Sfx.play(&"hit")   # presentation only; throttled in Sfx so a line doesn't roar
	take_casualties(enemy, int(round(dmg)), u)


## A ranged volley: like a melee strike without the cavalry charge, scaled by
## RANGED_DAMAGE_FACTOR -- archers trade per-hit punch for striking from beyond melee
## reach. Draws from the same seeded RNG stream. Damage flows through take_casualties, so
## volleys inherit the same flank/rear multiplier as melee (relative to the TARGET's
## facing): fire into a flank or rear deals the full bonus.
static func shoot(u: Unit, enemy: Unit) -> void:
	# RNG consumed first so the seeded stream stays deterministic regardless of which unit
	# is ultimately hit.
	var rng_roll: float = Replay.rng.randf_range(0.6, 1.4)
	var interceptor: Unit = friendly_interceptor(u, enemy)
	var target: Unit = enemy if interceptor == null else interceptor
	var eff_attack: float = float(u.attack) * UnitMorale.fatigue_attack_factor(u) * u.cohesion \
			* u.formation_attack_factor()
	var base: float = maxf(1.0, eff_attack - float(target.defense))
	var dmg: float = base * Unit.RANGED_DAMAGE_FACTOR * rng_roll * target.missile_defense_factor()
	Sfx.play(&"shoot")
	# Cosmetic volley trail: arrows streak toward whoever was actually hit, so the player
	# can see why a friendly is taking damage. Spawned on the (deterministic) sim tick but
	# animated/faded on render time -- no effect on replays.
	if u.is_inside_tree():
		VolleyTrail.spawn(u.get_parent(), u.global_position, target.global_position, u.team_color)
	# Per-soldier casualties when the target has a soldier layer: the volley kills specific
	# near-side men in the health pool (so which men fall is geometric and the bodies compact),
	# instead of the regiment blindly dropping arbitrary rear soldiers. The casualty COUNT is
	# identical to the formula path -- both round dmg to `raw` first, then apply the same flank
	# (take_casualties does `round(raw * flank)`; the per-soldier path matches it exactly) --
	# so lethality is unchanged. No new RNG is drawn (the one volley roll above stays first).
	var raw: int = int(round(dmg))
	if Unit.INDIVIDUAL_COLLISION and not target._sim_soldier_hp.is_empty() \
			and target.state != Unit.State.DEAD and target.state != Unit.State.ROUTING:
		var flank: float = flank_multiplier(target, u)
		var casualties: int = max(1, int(round(float(raw) * flank)))
		if ProjectileField.active != null:
			# Fly the volley (#435): the arrows carry these casualties and deliver them when
			# they LAND, after their real flight time, at the launch point -- so ranged fire now
			# has travel time and lands where it was aimed. Same count, so lethality is unchanged.
			ProjectileField.active.launch(u.position, target.position, u.uid, target.uid,
					casualties, flank, _volley_is_arced(u, target))
		else:
			# No projectile field (headless unit tests): resolve immediately at the shooter.
			SoldierMelee.apply_ranged_casualties(target, u.position, u, casualties, flank)
	else:
		take_casualties(target, raw, u)


## Whether a volley arcs (a lobbed shot) or flies flat. Slice 1: always arced -- archers
## loose a lobbing volley. The auto flat-vs-arced choice by range / line-of-sight / cover is
## a later slice (#435), which is why this is a seam rather than an inline `true`.
static func _volley_is_arced(_shooter: Unit, _target: Unit) -> bool:
	return true


## Return the nearest living friendly unit that lies in the straight-line flight path from
## `u` toward `target`, or null if the path is clear. A friendly blocks a shot when their
## centre is within their own separation_radius of the flight line AND the closest point on
## that line is strictly between shooter and target (projection in [0.05, 0.95]).
static func friendly_interceptor(u: Unit, target: Unit) -> Unit:
	var seg: Vector2 = target.position - u.position
	var seg_len_sq: float = seg.length_squared()
	if seg_len_sq < 0.001:
		return null
	var closest: Unit = null
	var closest_proj: float = INF
	for u_node in u.get_tree().get_nodes_in_group("units"):
		var other: Unit = u_node as Unit
		if other == null or other == u or other.team != u.team or other.state == Unit.State.DEAD:
			continue
		var proj: float = (other.position - u.position).dot(seg) / seg_len_sq
		if proj < 0.05 or proj > 0.95:
			continue
		var foot: Vector2 = u.position + seg * proj
		if (other.position - foot).length() < other.separation_radius and proj < closest_proj:
			closest = other
			closest_proj = proj
	return closest


## Called by an attacker. Applies flanking from the DEFENDER's (`u`'s) facing.
static func take_casualties(u: Unit, amount: int, attacker: Unit) -> void:
	if u.state == Unit.State.DEAD or u.state == Unit.State.ROUTING:
		return

	var flank: float = flank_multiplier(u, attacker)
	var total: int = max(1, int(round(amount * flank)))
	u.soldiers -= total
	# `flank` wires through so REAR_MORALE_EXTRA can add an optional extra rear/flank morale
	# debuff later; at the default (0.0) morale tracks the casualty count alone (which already
	# rose with the flank). The per-soldier melee path passes 1.0 -- facing is in the strike rolls.
	register_casualties(u, total, attacker, flank)


## Apply the consequences of `total` casualties ALREADY subtracted from `u.soldiers`:
## morale erosion, the thin-regiment crumble, death/rout thresholds, and the cosmetic fallen
## markers. Shared by the regiment-formula path (take_casualties) and the per-soldier melee
## path (which compacts the dead bodies and decrements `soldiers` itself). Morale erosion is
## driven by the casualty COUNT; `morale_flank` adds only the OPTIONAL extra rear/flank debuff
## gated by REAR_MORALE_EXTRA (0 by default), so a rear attack shakes morale through its higher
## body count, not a double-counted multiplier. Callers pass their flank (1.0 = frontal/melee).
static func register_casualties(u: Unit, total: int, attacker: Unit, morale_flank: float) -> void:
	var morale_scale: float = 1.0 + REAR_MORALE_EXTRA * (morale_flank - 1.0)
	u.morale -= float(total) * 0.12 * morale_scale
	var ratio: float = float(u.soldiers) / float(u.max_soldiers)
	if ratio < 0.4:
		u.morale -= (0.4 - ratio) * 6.0   # crumble as a regiment thins out

	if u.soldiers <= 0:
		u.soldiers = 0
		u._die()
		Sfx.play(&"death")
	elif u.morale <= 0.0:
		u._rout()
		Sfx.play(&"rout")

	# Cosmetic "men fall" markers (Stage C): drop a small fading heap of bodies on the
	# contact edge where this strike's casualties fell, leaning toward where the blow came
	# from. Spawned on the deterministic sim tick but render-only -- no sim group, no
	# Replay.rng -- so it has no simulation/replay/determinism impact. Guarded by
	# is_inside_tree() like the volley trail and rout shockwave.
	if u.is_inside_tree():
		var edge: Vector2 = u.global_position
		if is_instance_valid(attacker):
			# World-space throughout: edge is global_position, so the direction to the
			# attacker must be a global delta too. Mixing in local `position` would skew the
			# offset if the units' parent ever had a non-identity transform.
			var toward: Vector2 = attacker.global_position - u.global_position
			if toward.length() > 0.001:
				edge += toward.normalized() * u._block_extent
		# Cavalry leave bigger bodies (matching their larger live marks); foot the default.
		var body_r: float = Unit.CAV_MARK_RADIUS if u.is_cavalry else Unit.MARK_RADIUS
		Fallen.spawn(u.get_parent(), edge, u.team_color, total, body_r)

	u.queue_redraw()


## 1.0 = frontal, 1.5 = flank, 2.0 = rear (relative to `u`'s facing).
## The anti-cavalry square defends on every side: it has no weak flank/rear facing,
## so an attack from ANY direction lands as a frontal hit (multiplier 1.0). This is
## the stance's defining trait — cavalry can't find an unprotected side to exploit.
static func flank_multiplier(u: Unit, attacker: Unit) -> float:
	if u.in_square():
		return 1.0
	var to_attacker: Vector2 = (attacker.position - u.position).normalized()
	var d: float = u.facing.dot(to_attacker)
	if d >= 0.35:
		return 1.0
	elif d >= -0.5:
		return 1.5
	else:
		return 2.0
