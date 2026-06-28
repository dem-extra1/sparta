class_name SoldierSteering
## Friendly-avoidance steering for the engaged soldier subset (the no-teleport
## replacement for the retired global separation pass). Instead of position-correcting
## overlapping bodies, it writes a per-soldier velocity bias into each unit's `_sim_steer`,
## which SoldierBodies feeds forward — so a body damps AWAY from a crowding FRIENDLY and
## drifts off it over a few frames, never snapping. Enemy overlap is deliberately ignored
## here: the fighting resolves it through knockback (SoldierMelee), so the standoff emerges
## from press-in vs knockback rather than a separation rule.
##
## Determinism: regiments are processed in uid order and each regiment's engaged soldiers
## in ascending index, so the gathered arrays are already global-soldier-id sorted; the
## SoldierSpatialHash query then visits candidates in a reproducible order, and every pair
## is accumulated once (canonical lower-id-first) against the frozen input. No RNG, no
## instance-id / wall-clock — replay-safe like the rest of the soldier layer.

# Closing velocity a fully-overlapping friendly pair steers apart at (world units/sec),
# split evenly between the two. Tuned so crowded ranks slide back to body contact in a
# fraction of a second, without the jitter the old hard position-snap produced.
const STEER_STRENGTH: float = 60.0


## Recompute every engaged soldier's friendly-avoidance steering into its unit's
## `_sim_steer`. `frame` keys the spatial hash (tests pass a distinct frame).
static func accumulate(units: Array, frame: int) -> void:
	var sorted_units: Array = units.duplicate()
	sorted_units.sort_custom(func(x: Variant, y: Variant) -> bool: return (x as Unit).uid < (y as Unit).uid)

	# Gather engaged soldiers into parallel arrays, already in global-id order, and clear
	# each one's steering for this tick (it is fully recomputed below).
	var spos := PackedVector2Array()
	var sgids := PackedInt32Array()
	var sowners: Array = []          # owning Unit per entry
	var sslots := PackedInt32Array() # local index into the owner's _sim_steer
	var sradii := PackedFloat32Array()
	var steams := PackedInt32Array()
	for o in sorted_units:
		var u: Unit = o as Unit
		if u == null or u.state == Unit.State.DEAD:
			continue
		var engaged: PackedInt32Array = u.engaged_soldier_indices(u._sim_soldier_pos.size())
		var r: float = u.soldier_body_radius()
		for i in engaged:
			u._sim_steer[i] = Vector2.ZERO
			spos.push_back(u._sim_soldier_pos[i])
			sgids.push_back(u.soldier_id(i))
			sowners.push_back(u)
			sslots.push_back(i)
			sradii.push_back(r)
			steams.push_back(u.team)
	var n: int = spos.size()
	if n < 2:
		return

	# Accumulate each soldier's steering against the frozen input (Jacobi), each unordered
	# FRIENDLY pair once, in canonical (lower-id-first) order.
	SoldierSpatialHash.rebuild(spos, frame)
	var steer := PackedVector2Array()
	steer.resize(n)
	for a in range(n):
		for b in SoldierSpatialHash.query(spos[a]):
			if sgids[b] <= sgids[a]:
				continue   # each pair once
			if steams[a] != steams[b]:
				continue   # enemies don't steer — knockback handles them
			var v: Vector2 = _pair_steer(spos[a], spos[b], sgids[a], sgids[b], sradii[a] + sradii[b])
			steer[a] += v
			steer[b] -= v
	for k in range(n):
		sowners[k]._sim_steer[sslots[k]] = steer[k]


## Soldier `a`'s share of a friendly pair's separation velocity (b takes the negative):
## a push AWAY from `b` that scales with how deeply the pair overlaps, zero when they are
## clear. A co-located pair (d ~ 0) fans apart along a stable angle keyed off the lower id
## with a sign from the id order, so the tie-break carries no RNG / instance-id ordering.
static func _pair_steer(pos_a: Vector2, pos_b: Vector2, gid_a: int, gid_b: int, min_dist: float) -> Vector2:
	var offset: Vector2 = pos_a - pos_b
	var d: float = offset.length()
	if d >= min_dist:
		return Vector2.ZERO
	var overlap: float = (min_dist - d) / min_dist   # 0 (just touching) .. 1 (co-located)
	var dir: Vector2
	if d > 0.01:
		dir = offset / d
	else:
		var lo: int = mini(gid_a, gid_b)
		var angle: float = float(posmod(lo, 100)) / 100.0 * TAU
		var sign: float = 1.0 if gid_a > gid_b else -1.0
		dir = Vector2.RIGHT.rotated(angle) * sign
	return dir * (STEER_STRENGTH * overlap * 0.5)
