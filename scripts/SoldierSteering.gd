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


## Recompute every steering body's friendly-avoidance bias into its unit's `_sim_steer`.
## `frame` keys the spatial hash (tests pass a distinct frame). A regiment contributes its
## engaged front ranks (the original tier) and -- when its block overlaps a FRIENDLY
## regiment's block -- ALL its bodies (the friendly-contact tier, phase 5), so two
## friendlies pressing together steer apart even when neither is fighting; the
## body->regiment coupling then slides the two regiments off each other.
static func accumulate(units: Array, frame: int) -> void:
	var sorted_units: Array = units.duplicate()
	sorted_units.sort_custom(func(x: Variant, y: Variant) -> bool: return (x as Unit).uid < (y as Unit).uid)

	# Clear EVERY body's steering for this tick (recomputed below). Clearing all bodies --
	# not just the gathered ones -- means a body that drops out of the gathered set this tick
	# (no longer engaged / no longer overlapping a friendly) carries no stale bias into
	# SoldierBodies' feed-forward.
	for o in sorted_units:
		var u0: Unit = o as Unit
		if u0 == null or u0.state == Unit.State.DEAD:
			continue
		if u0._sim_steer.size() != u0._sim_soldier_pos.size():
			u0._sim_steer.resize(u0._sim_soldier_pos.size())
		u0._sim_steer.fill(Vector2.ZERO)

	# Precompute each living regiment's block extent once per tick. soldier_block_extent()
	# allocates a fresh PackedVector2Array (via UnitFormation.slots) and runs
	# SoldierFlock.compute_extent, so computing it here -- rather than per pair inside the
	# O(regiments^2) friendly broadphase below -- keeps large stacks (past ~30 friendly
	# regiments/side) off a recompute-and-allocate-per-pair cliff. Keyed by Unit so the
	# broadphase looks both endpoints up in O(1).
	var extents := {}
	for o in sorted_units:
		var ue: Unit = o as Unit
		if ue == null or ue.state == Unit.State.DEAD:
			continue
		extents[ue] = ue.soldier_block_extent()

	# Gather steering bodies into parallel arrays, already in global-id order.
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
		var nb: int = u._sim_soldier_pos.size()
		if nb == 0 or u._sim_steer.size() != nb:
			continue
		var r: float = u.soldier_body_radius()
		var idxs: PackedInt32Array
		if _overlaps_friendly(u, sorted_units, extents):
			idxs = PackedInt32Array()
			idxs.resize(nb)
			for i in range(nb):
				idxs[i] = i   # friendly-contact tier: all bodies
		else:
			idxs = u.engaged_soldier_indices(nb)   # original engaged tier
		for i in idxs:
			spos.push_back(u._sim_soldier_pos[i])
			sgids.push_back(u.soldier_id(i))
			sowners.push_back(u)
			sslots.push_back(i)
			sradii.push_back(r)
			steams.push_back(u.team)
	var n: int = spos.size()
	if n < 2:
		return

	# Accumulate each body's steering against the frozen input (Jacobi), each unordered
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
			var owner_a: Unit = sowners[a]
			var owner_b: Unit = sowners[b]
			if owner_a == owner_b:
				continue   # intra-regiment spacing is the formation spring's job, not steering's
			# Friendlies that pass cleanly through each other (a mover and an idle, or a
			# relief pair) don't shove — the exemption that used to live in _separate().
			if owner_a._separation_exempt(owner_b):
				continue
			var push: Vector2 = _pair_push(spos[a], spos[b], sgids[a], sgids[b], sradii[a] + sradii[b])
			if push == Vector2.ZERO:
				continue
			# Engaged-anchor asymmetry: a fighting regiment holds and the friendly newcomer
			# flows around it (mirrors _push_share's friendly branch). A symmetric pair
			# splits 0.5/0.5, exactly the original behaviour.
			var shares: Vector2 = _friendly_shares(owner_a, owner_b)
			steer[a] += push * shares.x
			steer[b] -= push * shares.y
	for k in range(n):
		sowners[k]._sim_steer[sslots[k]] = steer[k]


## Whether `u`'s block overlaps any living FRIENDLY regiment's block (a cheap deterministic
## regiment broadphase over the unit list — there are only dozens of regiments). Gates the
## friendly-contact tier so an uncrowded line costs the same as before. `extents` holds each
## living regiment's `soldier_block_extent()` precomputed once for the tick, so the scan reads
## both endpoints' reach from the cache instead of recomputing (and reallocating) per pair.
static func _overlaps_friendly(u: Unit, sorted_units: Array, extents: Dictionary) -> bool:
	# `extents` is populated for every living unit in the same pass that calls this, so the
	# lookups here and at extents[v] below always hit. Assert the invariant rather than let a
	# future partial-dict caller fall through to a cryptic null-as-float mismatch downstream.
	assert(extents.has(u), "extents must be populated for all living units before _overlaps_friendly")
	var reach_u: float = extents[u]
	for o in sorted_units:
		var v: Unit = o as Unit
		if v == null or v == u or v.state == Unit.State.DEAD or v.team != u.team:
			continue
		if u.position.distance_to(v.position) < reach_u + extents[v]:
			return true
	return false


## Per-soldier shares of a friendly pair's separation push (sum to 1). Even (0.5/0.5)
## normally; when exactly one owner is engaged (fighting) it holds (share 0) and the other
## yields fully (share 1), so a newcomer flows around a fighting friendly. Mirrors
## `_push_share`'s friendly branch.
static func _friendly_shares(owner_a: Unit, owner_b: Unit) -> Vector2:
	# (The caller has already skipped same-regiment pairs, so owner_a != owner_b here.)
	if owner_a.is_engaged() == owner_b.is_engaged():
		return Vector2(0.5, 0.5)
	return Vector2(0.0, 1.0) if owner_a.is_engaged() else Vector2(1.0, 0.0)


## The full separation push on soldier `a` away from `b` (caller applies the per-soldier
## shares), scaled by how deeply the pair overlaps, zero when clear. A co-located pair
## (d ~ 0) fans apart along a stable angle keyed off the lower id with a sign from the id
## order, so the tie-break carries no RNG / instance-id ordering.
static func _pair_push(pos_a: Vector2, pos_b: Vector2, gid_a: int, gid_b: int, min_dist: float) -> Vector2:
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
		var sgn: float = 1.0 if gid_a > gid_b else -1.0
		dir = Vector2.RIGHT.rotated(angle) * sgn
	return dir * (STEER_STRENGTH * overlap)
