extends RefCounted
## Campaign-map game state and rules (M2, #70) — pure logic, no scene/Node deps so
## it runs headless and is unit-tested directly (test/unit/test_campaign_state.gd).
##
## A campaign is a single war (#70): two or more factions contest a set of provinces,
## with per-pair war/peace stances (#123). Each province has an owner and a stationed
## army (an integer strength). On a faction's turn each of its armies may move once
## into an adjacent province — reinforcing a friendly one or attacking an enemy one it
## is at war with. A contested fight is auto-resolved here (move_or_attack) or decided
## by the tactical battle and applied via resolve_attack (M3, #122). A faction wins by
## owning every province.
##
## State is built from a map dictionary (see scripts/campaign/CampaignLoader.gd); only
## the dynamic fields (owner, army) and the adjacency/names are kept here — geometry
## (polygons, label positions, colours) lives with the map data for the renderer.

const NO_WINNER := -1

# province id -> {id, name, owner, army}
var provinces: Dictionary = {}
# province id -> Array[int] of adjacent province ids
var adjacency: Dictionary = {}
# faction id -> display name
var faction_names: Array[String] = []

var current_faction: int = 0
var turn: int = 1

# Province ids whose army has already acted this turn (can't move again until the
# owning faction's next turn). Reset whenever play returns to a faction.
var _acted: Dictionary = {}

# Diplomacy (#123): factions are at war by default (this is a war campaign); only
# explicitly-made peace is recorded here, as a set of normalized "a-b" pair keys.
# A faction is never at war with itself. Maps/UI can later seed/change stances via
# make_peace()/declare_war(); for now the rules layer just gates attacks on it.
var _peace: Dictionary = {}

var _rng := RandomNumberGenerator.new()

# Home-ground edge for the defender, and the casualty severity of a fight. Pulled
# out as constants so the auto-resolve is easy to tune (and to read in tests).
const DEFENDER_BONUS := 1.2
const ROLL_MIN := 0.75
const ROLL_MAX := 1.25
const CASUALTY_SEVERITY := 0.6


## Build from a map dict: {faction_names:[...], provinces:[{id,name,owner,army,adj}, ...],
## peace:[[a,b], ...]}. `peace` is optional — listed pairs start at peace, everything
## else at war (#123). A fixed `rng_seed` (>= 0) makes auto-resolve deterministic for
## tests; -1 randomises.
func _init(map: Dictionary, rng_seed: int = -1) -> void:
	faction_names = []
	for fname in map.get("faction_names", []):
		faction_names.append(str(fname))
	for p in map.get("provinces", []):
		var id := int(p["id"])
		provinces[id] = {
			"id": id,
			"name": str(p.get("name", "Province %d" % id)),
			"owner": int(p.get("owner", 0)),
			"army": int(p.get("army", 0)),
		}
		var adj: Array[int] = []
		for n in p.get("adj", []):
			adj.append(int(n))
		adjacency[id] = adj
	# Optional initial diplomacy: a map may list faction pairs that start at peace
	# (everything else defaults to war). This is how a neutral faction is seeded —
	# at peace with all belligerents until someone declares war (#123). The shape
	# check is a defensive guard, not the primary validator: CampaignLoader.parse_map
	# already rejects malformed peace entries, so a well-formed map never trips it.
	for pair in map.get("peace", []):
		if typeof(pair) == TYPE_ARRAY and pair.size() >= 2:
			make_peace(int(pair[0]), int(pair[1]))
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()


func owner_of(id: int) -> int:
	return int(provinces[id]["owner"])


func army_of(id: int) -> int:
	return int(provinces[id]["army"])


func are_adjacent(a: int, b: int) -> bool:
	return adjacency.has(a) and (b in adjacency[a])


## True if the army in `from_id` may act on `to_id` this turn: same-faction mover,
## the mover holds an army that hasn't acted, the two provinces are adjacent, and —
## if `to_id` belongs to another faction — the mover is at war with that faction.
func can_move(from_id: int, to_id: int) -> bool:
	if from_id == to_id:
		return false
	if not provinces.has(from_id) or not provinces.has(to_id):
		return false
	if owner_of(from_id) != current_faction:
		return false
	if army_of(from_id) <= 0:
		return false
	if _acted.has(from_id):
		return false
	# Must be adjacent, and — entering another faction's province (occupy or attack)
	# being an act of war — the mover must be at war with them. Reinforcing your own
	# province is always allowed.
	var to_owner := owner_of(to_id)
	return are_adjacent(from_id, to_id) \
			and (to_owner == current_faction or at_war(current_faction, to_owner))


# --- diplomacy (#123) ------------------------------------------------------

func _pair_key(a: int, b: int) -> String:
	return "%d-%d" % [mini(a, b), maxi(a, b)]


## Whether factions `a` and `b` are at war. Factions are at war by default; a faction
## is never at war with itself.
func at_war(a: int, b: int) -> bool:
	if a == b:
		return false
	return not _peace.has(_pair_key(a, b))


## Put factions `a` and `b` at war (symmetric). No-op if a == b.
func declare_war(a: int, b: int) -> void:
	if a == b:
		return
	_peace.erase(_pair_key(a, b))


## Put factions `a` and `b` at peace (symmetric). No-op if a == b.
func make_peace(a: int, b: int) -> void:
	if a == b:
		return
	_peace[_pair_key(a, b)] = true


## Move/attack the army in `from_id` into `to_id`. Caller must check can_move first.
## Returns a result dict describing what happened:
##   {ok, combat, attacker_won, from, to, attacker, defender, defender_owner, survivors}
## `defender_owner` is the faction that held `to` before the move (useful for messaging
## with 3+ factions, since `to`'s owner may change on capture).
func move_or_attack(from_id: int, to_id: int) -> Dictionary:
	if not can_move(from_id, to_id):
		return {"ok": false}
	var from: Dictionary = provinces[from_id]
	var to: Dictionary = provinces[to_id]
	var moving: int = int(from["army"])
	var result := {
		"ok": true, "combat": false, "reinforced": false, "attacker_won": true,
		"from": from_id, "to": to_id, "attacker": moving,
		"defender": int(to["army"]), "defender_owner": int(to["owner"]), "survivors": moving,
	}

	if to["owner"] == from["owner"]:
		# Reinforce a friendly province: stacks merge.
		to["army"] = int(to["army"]) + moving
		from["army"] = 0
		result["reinforced"] = true
		result["survivors"] = int(to["army"])
		_mark_acted(from_id, to_id)
		return result

	if int(to["army"]) <= 0:
		# Undefended enemy/neutral province: occupy it outright.
		to["owner"] = from["owner"]
		to["army"] = moving
		from["army"] = 0
		_mark_acted(from_id, to_id)
		return result

	# Contested: auto-resolve with dice, then apply the outcome through the shared
	# settle path. The tactical-battle hookup (#122) decides the same outcome a
	# different way (resolve_attack) and reuses _settle, so both converge.
	result["combat"] = true
	var atk_roll := moving * _rng.randf_range(ROLL_MIN, ROLL_MAX)
	var def_roll := int(to["army"]) * DEFENDER_BONUS * _rng.randf_range(ROLL_MIN, ROLL_MAX)
	if atk_roll > def_roll:
		var closeness := def_roll / atk_roll   # 0 (rout) .. 1 (near thing)
		var survivors: int = maxi(1, int(round(moving * (1.0 - CASUALTY_SEVERITY * closeness))))
		_settle(result, from_id, to_id, true, survivors)
	else:
		var closeness := atk_roll / def_roll
		var survivors: int = maxi(1, int(round(int(to["army"]) * (1.0 - CASUALTY_SEVERITY * closeness))))
		_settle(result, from_id, to_id, false, survivors)
	return result


## Apply a *decided* contested outcome to a from->to clash (the M3 tactical battle
## replaces the dice, #122). `survivors` is the winning side's remaining strength.
## Mirrors move_or_attack's contested branch so a fought-out battle and an
## auto-resolve converge on the same state transition. The caller is responsible for
## having validated the clash (e.g. via the can_move that launched the battle).
func resolve_attack(from_id: int, to_id: int, attacker_won: bool, survivors: int) -> Dictionary:
	var from: Dictionary = provinces[from_id]
	var to: Dictionary = provinces[to_id]
	var result := {
		"ok": true, "combat": true, "reinforced": false, "attacker_won": attacker_won,
		"from": from_id, "to": to_id, "attacker": int(from["army"]),
		"defender": int(to["army"]), "defender_owner": int(to["owner"]), "survivors": survivors,
	}
	_settle(result, from_id, to_id, attacker_won, survivors)
	return result


## Shared state transition for a resolved contested fight. On a win the attacker
## takes `to` with `survivors` and its origin empties (and is marked acted); on a
## loss the attacking army is spent and `to`'s defender is left with `survivors`.
func _settle(result: Dictionary, from_id: int, to_id: int, attacker_won: bool, survivors: int) -> void:
	var from: Dictionary = provinces[from_id]
	var to: Dictionary = provinces[to_id]
	if attacker_won:
		to["owner"] = from["owner"]
		to["army"] = survivors
		from["army"] = 0
		_mark_acted(from_id, to_id)
	else:
		to["army"] = survivors
		from["army"] = 0   # the attacking army is spent
		# from_id was never in _acted (can_move guards against that); nothing to erase,
		# and its army is gone, so it can't act again this turn regardless.
	result["attacker_won"] = attacker_won
	result["survivors"] = survivors


func _mark_acted(from_id: int, to_id: int) -> void:
	# The mover's origin is now empty; the army that arrived in `to` has acted.
	_acted.erase(from_id)
	_acted[to_id] = true


## End the current faction's turn: hand play to the next faction and clear the
## acted flags so its armies can move. `turn` increments when play wraps to faction 0.
func end_turn() -> void:
	var n := maxi(1, faction_names.size())
	current_faction = (current_faction + 1) % n
	_acted.clear()
	if current_faction == 0:
		turn += 1


## The faction owning every province, or NO_WINNER while the war is undecided.
func winner() -> int:
	var owners := {}
	for id in provinces:
		owners[owner_of(id)] = true
	if owners.size() == 1:
		return owners.keys()[0]
	return NO_WINNER


## Province ids owned by `faction` that still hold a movable (not-yet-acted) army.
func movable_provinces(faction: int) -> Array[int]:
	var out: Array[int] = []
	for id in provinces:
		if owner_of(id) == faction and army_of(id) > 0 and not _acted.has(id):
			out.append(int(id))
	out.sort()
	return out


func has_acted(id: int) -> bool:
	return _acted.has(id)


# --- serialization (#122) --------------------------------------------------
# The campaign->battle hand-off swaps scenes, which destroys this state object, so
# the dynamic fields are snapshotted into a plain Dictionary (held in CampaignBattle)
# and restored onto a freshly map-built state when control returns. Only the mutable
# fields travel — the map (adjacency, names, geometry) is reloaded from data.

## Capture the mutable state (province owners/armies, who has acted, diplomacy, whose
## turn it is) as a plain Dictionary that restore() can re-apply.
func snapshot() -> Dictionary:
	var owners := {}
	var armies := {}
	for id in provinces:
		owners[id] = owner_of(id)
		armies[id] = army_of(id)
	return {
		"owners": owners,
		"armies": armies,
		"acted": _acted.keys(),
		"peace": _peace.keys(),
		"current_faction": current_faction,
		"turn": turn,
	}


## Re-apply a snapshot() onto this state. Assumes the same map (province ids) it was
## taken from; ids absent from the snapshot keep their map-built values.
func restore(snap: Dictionary) -> void:
	var owners: Dictionary = snap.get("owners", {})
	var armies: Dictionary = snap.get("armies", {})
	for id in provinces:
		if owners.has(id):
			provinces[id]["owner"] = int(owners[id])
		if armies.has(id):
			provinces[id]["army"] = int(armies[id])
	_acted.clear()
	for id in snap.get("acted", []):
		_acted[int(id)] = true
	_peace.clear()
	for key in snap.get("peace", []):
		_peace[key] = true
	current_faction = int(snap.get("current_faction", current_faction))
	turn = int(snap.get("turn", turn))
