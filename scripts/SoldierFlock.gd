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
