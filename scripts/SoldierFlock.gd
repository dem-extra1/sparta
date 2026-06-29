class_name SoldierFlock
## Pure, deterministic math for the cosmetic soldier-mark layer, extracted from Unit.gd.
## These are functions of their arguments only (no unit state, no RNG, no wall-clock), so
## they are directly unit-testable and reproduce on replay. The mark layer is render-only
## -- never read by the simulation. The per-frame orchestration (Unit._update_flock) and
## the MultiMesh/shadow plumbing still live on Unit; this is just the math it drives. Tuning
## constants (FLOCK_* / COMBAT_* / LOD_ZOOM_*) stay on Unit, where the orchestrator reads
## them too.


## Step one mark: a damped arrival spring toward its slot plus separation from neighbours,
## with a speed cap and a max-lag clamp for stability. Returns [new_pos, new_vel].
static func step(pos: Vector2, vel: Vector2, target: Vector2,
		neighbors: PackedVector2Array, sep_dist: float, dt: float) -> Array:
	var accel: Vector2 = (target - pos) * Unit.FLOCK_STIFFNESS - vel * Unit.FLOCK_DAMPING
	for nb in neighbors:
		var away: Vector2 = pos - nb
		var d: float = away.length()
		if d > 0.0001:
			if d < sep_dist:
				accel += (away / d) * (Unit.FLOCK_SEPARATION * (1.0 - d / sep_dist))
		else:
			# Exactly coincident -- avoided in practice (marks spawn fanned out, see
			# Unit._resize_soldiers), so this is just a guard nudge to break the symmetry.
			accel += Vector2(Unit.FLOCK_SEPARATION, 0.0)
	var nvel: Vector2 = vel + accel * dt
	var sp: float = nvel.length()
	if sp > Unit.FLOCK_MAX_SPEED:
		nvel *= Unit.FLOCK_MAX_SPEED / sp
	var npos: Vector2 = pos + nvel * dt
	var lag: Vector2 = npos - target
	var lag_len: float = lag.length()
	if lag_len > Unit.FLOCK_MAX_LAG:
		npos = target + lag * (Unit.FLOCK_MAX_LAG / lag_len)
		# Re-derive velocity from the clamped move so a clamped mark doesn't carry an
		# inflated velocity that pops once it re-enters the lag boundary, then re-bound it
		# (the move is huge only in the degenerate far-spawn case, never in normal play).
		nvel = (npos - pos) / dt
		var clamped_sp: float = nvel.length()
		if clamped_sp > Unit.FLOCK_MAX_SPEED:
			nvel *= Unit.FLOCK_MAX_SPEED / clamped_sp
	return [npos, nvel]


## Melee churn offset for one front-rank mark (Stage C). Returns an offset in the unit's
## UNROTATED local frame (forward / toward-enemy is -Y, matching UnitFormation.slots), which
## the caller rotates onto the unit's facing. `depth` is how far behind the front rank the
## mark sits (0 = front rank): the churn fades linearly to zero by COMBAT_REACH, so only the
## fighting edge moves. The forward press rides a raised sine (always into the enemy,
## surging and recoiling rather than pulling back past the line); a separate, faster
## out-of-phase term jitters it sideways. Render-only, never read by the sim.
static func combat_lunge_offset(depth: float, phase: float, t: float) -> Vector2:
	var falloff: float = clampf(1.0 - depth / Unit.COMBAT_REACH, 0.0, 1.0)
	if falloff <= 0.0:
		return Vector2.ZERO
	var press: float = Unit.COMBAT_LUNGE * falloff * (0.55 + 0.45 * sin(t * Unit.COMBAT_FREQ + phase))
	var churn: float = Unit.COMBAT_LATERAL * falloff * sin(t * Unit.COMBAT_FREQ * 1.7 + phase * 2.0)
	return Vector2(churn, -press)


## Melee weapon stroke for one front-rank fighting mark (Stage F). Returns [length, swing]:
## `length` is the blade's current px length along the unit's facing -- it pulses between a
## drawn-back `reach_px * (1 - thrust_frac)` and a full extension of `reach_px` on the attack
## cadence, so a longer-reach weapon (a spear) visibly out-thrusts a shorter one (a sword).
## `swing` is the blade's angular offset (rad) from straight-ahead, sweeping side to side so a
## sabre/sword reads as a swing rather than a pure thrust. `phase` is a per-mark offset so the
## line doesn't strike in unison. Render-only -- never read by the sim.
static func weapon_stroke(t: float, phase: float, reach_px: float,
		thrust_frac: float, swing_amp: float) -> Array:
	var beat: float = t * Unit.WEAPON_FREQ + phase
	var length: float = reach_px * (1.0 - thrust_frac * (0.5 - 0.5 * sin(beat)))
	# Swing leads the thrust by a quarter cycle so the blade sweeps across as it extends.
	var swing: float = swing_amp * sin(beat + PI * 0.5)
	return [length, swing]


## Relief corridor offset for one mark (Stage E). Returns a lateral offset pushing the mark
## away from the approach axis, opening a lane for the incoming relief partner. `mark_pos` is
## the mark's current local position; `relief_perp` is the unit vector perpendicular to the
## approach direction; `spread` is the fractional scale (0-1). Render-only.
static func relief_spread_offset(mark_pos: Vector2, relief_perp: Vector2, spread: float) -> Vector2:
	return relief_perp * mark_pos.dot(relief_perp) * spread


## Whether the zoomed-in figure LOD should be active, with hysteresis: switch ON at or past
## LOD_ZOOM_IN, OFF at or below LOD_ZOOM_OUT, and HOLD the current level in the band between
## (so the figures don't flicker on and off at the threshold).
static func lod_should_detail(currently_detailed: bool, zoom: float) -> bool:
	if zoom >= Unit.LOD_ZOOM_IN:
		return true
	if zoom <= Unit.LOD_ZOOM_OUT:
		return false
	return currently_detailed


## Deterministic pseudo-random float in [0, 1) from an int, for stable (non-flickering)
## per-mark jitter in the formation render. Cosmetic only -- never used by the simulation.
static func hash01(i: int) -> float:
	var x: float = sin(float(i) * 12.9898) * 43758.5453
	return x - floor(x)


# --- Per-frame orchestration (operates on the unit's mark arrays) ------------
# These advance the cosmetic mark layer; Unit forwards its _process callback to update()
# and keeps the MultiMesh/shadow GPU plumbing (_refresh_flock_render / _update_shadow /
# _apply_flock_color / the LOD mesh swap) plus the _setup_flock_renderer node construction.


## Seed the marks onto their formation slots at rest. Called from Unit._setup_flock_renderer.
static func seed(unit: Unit) -> void:
	var n: int = unit.soldiers
	unit._soldier_pos.resize(n)
	unit._soldier_vel.resize(n)
	var slots := UnitFormation.slots(unit, n)
	var ang: float = unit.facing.angle() + PI * 0.5
	for i in range(n):
		unit._soldier_pos[i] = slot_target(slots, i, ang)
		unit._soldier_vel[i] = Vector2.ZERO
	unit._block_extent = compute_extent(unit, slots)
	unit._update_shadow()
	unit._refresh_flock_render()
	unit._flock_settled = true


## Local-frame target for mark at slot_i: the formation slot plus stable per-mark jitter (so
## a settled block reads as a crowd, not a rigid grid), rotated into the unit's facing.
## jitter_i seeds the wobble independently from the slot so a mark moving to a new slot during
## rank cycling keeps its own stable personality. Pure -- a function of its arguments.
static func slot_target(slots: PackedVector2Array, slot_i: int, ang: float, jitter_i: int = -1) -> Vector2:
	var ji: int = jitter_i if jitter_i >= 0 else slot_i
	var jx: float = (hash01(ji * 2) - 0.5) * Unit.MARK_JITTER
	var jy: float = (hash01(ji * 2 + 1) - 0.5) * Unit.MARK_JITTER
	return (slots[slot_i] + Vector2(jx, jy)).rotated(ang)


## Block half-size: the farthest slot plus a mark radius, floored at the collision RADIUS.
## Sizes the state ring, selection halo, stat bars (in _draw) and the ground shadow.
static func compute_extent(unit: Unit, slots: PackedVector2Array) -> float:
	var mark_r: float = Unit.CAV_MARK_RADIUS if unit.is_cavalry else Unit.MARK_RADIUS
	var extent: float = Unit.RADIUS
	for s in slots:
		extent = maxf(extent, s.length())
	return extent + mark_r + 2.0


## Advance the cosmetic mark layer one render frame. Cheap fast-path when the block is
## settled and the unit hasn't moved/turned (no allocation, no integration).
static func update(unit: Unit, delta: float) -> void:
	if unit._mm_body == null:
		return
	if unit.state == Unit.State.DEAD:
		if unit._mm_body.instance_count != 0:
			unit._mm_body.instance_count = 0
			unit._mm_outline.instance_count = 0
			unit._set_weapon_instances([])
		return

	var n: int = unit.soldiers
	if unit._soldier_pos.size() != n:   # casualties (shrink) or a merge (grow)
		resize(unit, n)
		unit._flock_settled = false

	# `position` (local-to-parent), not global_position: the marks live in this node's local
	# frame, so the trail shove must be in that same frame. They coincide today (units sit
	# under an identity parent) but tracking `position` stays correct if that ever changes.
	var displacement: Vector2 = unit.position - unit._flock_last_pos
	var turned: bool = not unit.facing.is_equal_approx(unit._flock_last_facing)
	# Relief corridor (Stage E): compute lateral-spread parameters once for all marks so each
	# mark's individual offset is a cheap dot-product, and so the effect can also gate the
	# early-exit check below (a settling block must not sleep while a partner is still
	# swapping through it).
	var relief_perp: Vector2 = Vector2.ZERO
	var relief_spread: float = 0.0
	if unit._relief_partner != null and is_instance_valid(unit._relief_partner):
		var approach_raw: Vector2 = unit._relief_partner.position - unit.position
		# Guard against exact co-location: normalized() returns zero on a zero-length vector.
		# Fall back to a stable axis so the spread is maximum (as intended) rather than absent
		# precisely when overlap is highest.
		var approach: Vector2 = approach_raw.normalized() if approach_raw.length() > 0.5 \
				else Vector2.RIGHT
		relief_perp = approach.rotated(PI * 0.5)
		var dist: float = unit.position.distance_to(unit._relief_partner.position)
		var max_dist: float = unit.separation_radius + unit._relief_partner.separation_radius + 30.0
		relief_spread = Unit.RELIEF_SPREAD_MAX * clampf(1.0 - dist / max_dist, 0.0, 1.0)

	# A FIGHTING block never rests: its front rank churns against the contact line each frame
	# (Stage C), so it skips the at-rest fast-path even when the unit is standing still and not
	# turning. A unit in a relief swap likewise stays active until the partner moves clear.
	var fighting: bool = unit.state == Unit.State.FIGHTING
	if unit._flock_settled and displacement.is_zero_approx() and not turned and not fighting \
			and relief_spread <= 0.0:
		return   # at rest -- nothing to do

	unit._flock_last_pos = unit.position
	unit._flock_last_facing = unit.facing

	var slots := UnitFormation.slots(unit, n)
	var ang: float = unit.facing.angle() + PI * 0.5

	var new_extent: float = compute_extent(unit, slots)
	if not is_equal_approx(new_extent, unit._block_extent):
		unit._block_extent = new_extent
		unit._update_shadow()
		unit.queue_redraw()   # chrome (ring / halo / bars) is sized to the block

	# Trail: shove every mark back by the unit's displacement so the block lags behind the
	# advancing/wheeling regiment; the arrival spring then reels them back onto formation.
	if not displacement.is_zero_approx():
		for i in range(n):
			unit._soldier_pos[i] -= displacement

	var sep_dist: float = Unit.FORMATION_SPACING * 0.9
	var grid := build_grid(unit, sep_dist)
	var dt: float = minf(delta, Unit.FLOCK_DT_MAX)
	# Front rank depth datum (slot 0 is the front-centre rank, see UnitFormation.slots): a
	# mark's depth behind it scales how hard it churns while fighting (Stage C).
	var front_y: float = slots[0].y if n > 0 else 0.0
	if fighting:
		unit._combat_clock += dt

	# Rank cycling (Stage D): a periodic signal rotates slot assignments so front-rank marks
	# slide toward the rear and rear-rank marks advance to the front. Active only for trained
	# melee units (ranged units fire from static lines). Render-only.
	var cycling: bool = fighting and not unit.is_ranged and unit.training > 0.0 and n > 1
	# Drain the widen animation unconditionally so it always finishes even when the unit breaks
	# contact mid-animation (cycling would be false, but the anim should not freeze or re-fire
	# incorrectly on re-engagement).
	if unit._rank_cycle_anim < 1.0:
		unit._rank_cycle_anim = minf(1.0, unit._rank_cycle_anim + dt / Unit.RANK_CYCLE_ANIM_DURATION)
	if cycling:
		unit._rank_cycle_timer -= dt
		if unit._rank_cycle_timer <= 0.0:
			var files: int = UnitFormation.frontage(unit)
			unit._rank_cycle_slot_offset = (unit._rank_cycle_slot_offset + files) % n
			unit._rank_cycle_timer = Unit.RANK_CYCLE_INTERVAL / unit.training
			unit._rank_cycle_anim = 0.0
			if unit.is_inside_tree():
				Sfx.play(&"whistle")

	# Render-as-reality (phase 3+): when the soldier layer is live, shift each mark by its
	# simulated body's offset from formation so the on-screen soldier reflects the per-soldier,
	# cross-regiment separation. The unengaged bulk snaps to its slots, so the delta is ~0
	# there; the engaged front ranks hold a PERSISTENT displacement (phase 4), so a shoved
	# soldier visibly holds the push and eases in. The cosmetic offsets below (lunge,
	# rank-cycle widen, relief) still layer on top. Guarded on a size match so a 1-frame
	# casualty/merge gap falls back to the plain formation slot. to_local == p - position.
	var use_sim: bool = Unit.INDIVIDUAL_COLLISION and unit._sim_soldier_pos.size() == n

	# Weapon stroke (Stage F): front-rank marks of a fighting melee block animate a thrusting/
	# swinging blade toward the enemy, its length scaled from the unit's reach so a spear visibly
	# out-reaches a sword. Only at the figure LOD (you can't read a weapon on a flat dot) and not
	# for ranged units (they loose arrows, they don't melee-thrust). Collected here, pushed to the
	# weapon MultiMesh after the loop. Render-only -- weapon_xforms stays empty when hidden.
	var show_weapons: bool = fighting and unit._detailed_lod and not unit.is_ranged
	var mark_r: float = Unit.CAV_MARK_RADIUS if unit.is_cavalry else Unit.MARK_RADIUS
	var fwd_axis: Vector2 = Vector2(0.0, -1.0).rotated(ang)   # local forward (toward enemy)
	var reach_px: float = unit.attack_range * Unit.WEAPON_REACH_SCALE
	var w_halfwidth: float = mark_r * Unit.WEAPON_WIDTH
	# Per-type motion: spears thrust long with little swing; swords/sabres swing wider on a
	# shorter reach. Cavalry sabres swing widest.
	var thrust_frac: float = Unit.WEAPON_THRUST_SWORD
	var swing_amp: float = Unit.WEAPON_SWING_SWORD
	if unit.anti_cavalry:
		thrust_frac = Unit.WEAPON_THRUST_SPEAR
		swing_amp = Unit.WEAPON_SWING_SPEAR
	elif unit.is_cavalry:
		thrust_frac = Unit.WEAPON_THRUST_CAV
		swing_amp = Unit.WEAPON_SWING_CAV
	var weapon_xforms: Array[Transform2D] = []

	var still: bool = true
	for i in range(n):
		var slot_i: int = (i + unit._rank_cycle_slot_offset) % n if cycling else i
		var target: Vector2 = slot_target(slots, slot_i, ang, i)
		if use_sim:
			target += (unit._sim_soldier_pos[slot_i] - unit.position) - slots[slot_i].rotated(ang)
		if fighting:
			# Front-rank marks press into and recoil from the contact line; rotate the
			# (forward = -Y) lunge onto the unit's facing alongside the slot it modifies.
			var lunge := combat_lunge_offset(slots[slot_i].y - front_y, float(i) * 1.3, unit._combat_clock)
			target += lunge.rotated(ang)
		# Rear-rank widen (Stage D): during the rank-cycle animation, rear ranks spread
		# laterally to open a corridor for the front rank to fall back through. The spread
		# peaks at the midpoint (sin peaks at PI/2) then closes as the animation settles.
		if cycling and unit._rank_cycle_anim < 1.0:
			var depth: float = slots[slot_i].y - front_y   # 0 = front rank, + = deeper rear
			if depth > Unit.FORMATION_SPACING * 0.5:
				var spread_phase: float = sin(unit._rank_cycle_anim * PI)
				var norm_depth: float = minf(depth / (Unit.FORMATION_SPACING * 2.0), 1.0)
				var lateral_sign: float = signf(slots[slot_i].x) if abs(slots[slot_i].x) > 0.5 \
						else (1.0 if slot_i % 2 == 0 else -1.0)
				var widen: float = lateral_sign * Unit.RANK_CYCLE_WIDEN * spread_phase * norm_depth
				target += Vector2(widen, 0.0).rotated(ang)
		# Relief corridor (Stage E): spread marks laterally to open a lane for the incoming
		# partner. Each mark is pushed away from the approach axis in proportion to how far it
		# already sits from that axis, so the center clears and the flanks fan out.
		if relief_spread > 0.0:
			target += relief_spread_offset(unit._soldier_pos[i], relief_perp, relief_spread)
		var neighbors := neighbors_of(unit, grid, i, sep_dist)
		var res := step(unit._soldier_pos[i], unit._soldier_vel[i], target, neighbors, sep_dist, dt)
		unit._soldier_pos[i] = res[0]
		unit._soldier_vel[i] = res[1]
		if res[1].length() > Unit.FLOCK_SETTLE_VEL or res[0].distance_to(target) > Unit.FLOCK_SETTLE_POS:
			still = false
		# Front-rank weapon: build one blade instance per fighting front-rank mark. The basis
		# columns set the blade's length (along facing+swing) and thickness; the origin is the
		# mark's leading edge so the blade reaches out from the body, not the centre.
		# _sim_prone is empty when INDIVIDUAL_COLLISION is off, so the size-check gates use_sim implicitly.
		var is_prone: bool = slot_i < unit._sim_prone.size() and unit._sim_prone[slot_i] > 0.0
		if show_weapons and not is_prone and slots[slot_i].y - front_y <= Unit.WEAPON_FRONT_DEPTH:
			var stroke := weapon_stroke(unit._combat_clock, float(i) * 1.7,
					reach_px, thrust_frac, swing_amp)
			var w_dir: Vector2 = fwd_axis.rotated(stroke[1])
			var w_perp := Vector2(-w_dir.y, w_dir.x)
			var hand: Vector2 = res[0] + fwd_axis * mark_r
			weapon_xforms.append(Transform2D(w_dir * stroke[0], w_perp * w_halfwidth, hand))

	# A fighting block keeps churning, so it never sleeps even if a frame reads as "still". A
	# block in a relief spread likewise stays active: settling onto plain slot positions would
	# immediately snap marks back out (the spread-modified targets fire again next frame),
	# producing a repeating snap-then-spring flicker.
	if still and not fighting and relief_spread <= 0.0:
		# Snap exactly onto formation and sleep until the unit next moves or loses men. Use the
		# same slot-rotation condition as the main loop (minus fighting, already false here) so
		# the settled mark positions stay consistent.
		var settled_cycling: bool = not unit.is_ranged and unit.training > 0.0 and n > 1
		for i in range(n):
			var slot_i: int = (i + unit._rank_cycle_slot_offset) % n if settled_cycling else i
			unit._soldier_pos[i] = slot_target(slots, slot_i, ang, i)
			unit._soldier_vel[i] = Vector2.ZERO
		unit._flock_settled = true
	else:
		unit._flock_settled = false

	# Hard position-correction pass: push any two marks that still overlap apart by half the
	# penetration each, after the spring integration. The slot-spring can hold marks closer
	# than their diameter (especially with jitter), so this pass enforces a hard floor. One
	# pass is sufficient for typical in-play overlap; the spring reels them back next frame.
	hard_separate(unit, mark_r)

	unit._set_weapon_instances(weapon_xforms)
	unit._refresh_flock_render()


## Bucket marks into a uniform grid (cell = sep_dist) so separation is a local 3x3 lookup
## rather than O(n^2). Keyed by integer cell coords -> indices into _soldier_pos.
static func build_grid(unit: Unit, cell: float) -> Dictionary:
	var grid := {}
	for i in range(unit._soldier_pos.size()):
		var p: Vector2 = unit._soldier_pos[i]
		var k := Vector2i(int(floor(p.x / cell)), int(floor(p.y / cell)))
		if not grid.has(k):
			grid[k] = PackedInt32Array()
		grid[k].append(i)
	return grid


## Positions of marks within one cell of mark i (its separation neighbourhood).
static func neighbors_of(unit: Unit, grid: Dictionary, i: int, cell: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var p: Vector2 = unit._soldier_pos[i]
	var cx: int = int(floor(p.x / cell))
	var cy: int = int(floor(p.y / cell))
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			var k := Vector2i(cx + ox, cy + oy)
			if grid.has(k):
				for j in grid[k]:
					if j != i:
						out.append(unit._soldier_pos[j])
	return out


## Resize the mark arrays to match the live soldier count. Casualties just truncate; a merge
## grows the array, and the new marks are fanned onto a small deterministic spiral near the
## centre (a sunflower phyllotaxis) rather than stacked on the exact origin -- so they're
## never coincident, the separation step can tell them apart, and they spread out to formation
## cleanly instead of drifting as one blob.
static func resize(unit: Unit, n: int) -> void:
	var old: int = unit._soldier_pos.size()
	unit._soldier_pos.resize(n)
	unit._soldier_vel.resize(n)
	for i in range(old, n):
		var k: int = i - old
		var a: float = float(k) * 2.39996323   # golden angle (rad): even, non-repeating
		unit._soldier_pos[i] = Vector2.from_angle(a) * (0.4 * sqrt(float(k) + 0.5))
		unit._soldier_vel[i] = Vector2.ZERO


## Hard position-correction pass for individual soldier marks: resolve any pairwise overlap by
## pushing the two marks apart by half the penetration each. Uses the same grid lookup as the
## spring integration so it is O(k.n) rather than O(n^2). Cosmetic only. `mark_r` is the
## per-type mark radius (foot or cavalry).
static func hard_separate(unit: Unit, mark_r: float) -> void:
	var n: int = unit._soldier_pos.size()
	if n <= 1:
		return
	var min_dist: float = mark_r * 2.0
	var cell: float = min_dist
	var grid := build_grid(unit, cell)
	for i in range(n):
		var p: Vector2 = unit._soldier_pos[i]
		var cx: int = int(floor(p.x / cell))
		var cy: int = int(floor(p.y / cell))
		for ox in range(-1, 2):
			for oy in range(-1, 2):
				var k := Vector2i(cx + ox, cy + oy)
				if not grid.has(k):
					continue
				for j in (grid[k] as PackedInt32Array):
					if j <= i:
						continue
					var offset: Vector2 = unit._soldier_pos[i] - unit._soldier_pos[j]
					var d: float = offset.length()
					if d >= min_dist:
						continue
					var push: Vector2
					if d > 0.0001:
						push = (offset / d) * ((min_dist - d) * 0.5)
					else:
						push = Vector2(min_dist * 0.5, 0.0)
					unit._soldier_pos[i] += push
					unit._soldier_pos[j] -= push
