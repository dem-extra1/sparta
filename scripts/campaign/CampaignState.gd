extends RefCounted
## Campaign-map game state and rules (M2, #70) — pure logic, no scene/Node deps so
## it runs headless and is unit-tested directly (test/unit/test_campaign_state.gd).
##
## A campaign is a single war (#70): two factions contest a set of provinces. Each
## province has an owner and a stationed army (an integer strength). On a faction's
## turn each of its armies may move once into an adjacent province — reinforcing a
## friendly one or attacking an enemy/neutral one (battles are auto-resolved here;
## the tactical-battle hookup is M3). A faction wins by owning every province.
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

var _rng := RandomNumberGenerator.new()

# Home-ground edge for the defender, and the casualty severity of a fight. Pulled
# out as constants so the auto-resolve is easy to tune (and to read in tests).
const DEFENDER_BONUS := 1.2
const ROLL_MIN := 0.75
const ROLL_MAX := 1.25
const CASUALTY_SEVERITY := 0.6


## Build from a map dict: {faction_names:[...], provinces:[{id,name,owner,army,adj}, ...]}.
## A fixed `rng_seed` (>= 0) makes auto-resolve deterministic for tests; -1 randomises.
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
## the mover holds an army that hasn't acted, and the two provinces are adjacent.
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
	return are_adjacent(from_id, to_id)


## Move/attack the army in `from_id` into `to_id`. Caller must check can_move first.
## Returns a result dict describing what happened:
##   {ok, combat, attacker_won, from, to, attacker, defender, survivors}
func move_or_attack(from_id: int, to_id: int) -> Dictionary:
	if not can_move(from_id, to_id):
		return {"ok": false}
	var from: Dictionary = provinces[from_id]
	var to: Dictionary = provinces[to_id]
	var moving: int = int(from["army"])
	var result := {
		"ok": true, "combat": false, "reinforced": false, "attacker_won": true,
		"from": from_id, "to": to_id, "attacker": moving,
		"defender": int(to["army"]), "survivors": moving,
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

	# Contested: auto-resolve.
	result["combat"] = true
	var atk_roll := moving * _rng.randf_range(ROLL_MIN, ROLL_MAX)
	var def_roll := int(to["army"]) * DEFENDER_BONUS * _rng.randf_range(ROLL_MIN, ROLL_MAX)
	if atk_roll > def_roll:
		var closeness := def_roll / atk_roll   # 0 (rout) .. 1 (near thing)
		var survivors: int = maxi(1, int(round(moving * (1.0 - CASUALTY_SEVERITY * closeness))))
		to["owner"] = from["owner"]
		to["army"] = survivors
		from["army"] = 0
		result["attacker_won"] = true
		result["survivors"] = survivors
		_mark_acted(from_id, to_id)
	else:
		var closeness := atk_roll / def_roll
		var survivors: int = maxi(1, int(round(int(to["army"]) * (1.0 - CASUALTY_SEVERITY * closeness))))
		to["army"] = survivors
		from["army"] = 0   # the attacking army is spent
		result["attacker_won"] = false
		result["survivors"] = survivors
		# from_id was never in _acted (can_move guards against that); nothing to erase,
		# and its army is gone, so it can't act again this turn regardless.
	return result


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
