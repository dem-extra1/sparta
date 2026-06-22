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

# Default truce length (in turns) applied when a faction sues for peace in normal play
# (#138). Suing for peace is meant to carry a commitment, so the gameplay callers
# (player toggle, AI diplomacy) pass this; the low-level make_peace() still defaults to
# no truce so map-seeded stances and tests can opt out.
const DEFAULT_TRUCE_TURNS := 3

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

# Truce timers (#138): pair_key -> turns remaining until war may be declared again.
# Only present while a truce is active; absent means no truce, so war is declarable.
# Ticked down once per full round in end_turn().
var _truce: Dictionary = {}

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
			# An optional third element seeds an initial truce length (#138).
			var truce_turns := int(pair[2]) if pair.size() >= 3 else 0
			make_peace(int(pair[0]), int(pair[1]), truce_turns)
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


## Put factions `a` and `b` at war (symmetric). Blocked while a truce is active (#138)
## and a no-op if a == b. Returns true if the two are now at war.
func declare_war(a: int, b: int) -> bool:
	if a == b:
		return false
	if truce_remaining(a, b) > 0:
		return false
	_peace.erase(_pair_key(a, b))
	return true


## Put factions `a` and `b` at peace (symmetric). No-op if a == b. A positive
## `truce_turns` records a truce: declaring war is blocked until it expires (#138).
## A larger value extends an existing truce; 0 leaves any current truce untouched.
func make_peace(a: int, b: int, truce_turns: int = 0) -> void:
	if a == b:
		return
	var key := _pair_key(a, b)
	_peace[key] = true
	if truce_turns > 0:
		_truce[key] = maxi(int(_truce.get(key, 0)), truce_turns)


## Turns remaining on the truce between `a` and `b` (0 if none, or for a == b). While
## this is positive, declare_war() is blocked (#138).
func truce_remaining(a: int, b: int) -> int:
	if a == b:
		return 0
	return int(_truce.get(_pair_key(a, b), 0))


## Tick every active truce down one turn; expired ones are removed, which just
## re-enables declaring war (it does not auto-declare). Called once per full round.
func _tick_truces() -> void:
	for key in _truce.keys():
		var left := int(_truce[key]) - 1
		if left <= 0:
			_truce.erase(key)
		else:
			_truce[key] = left


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
		_tick_truces()


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


# --- AI-initiated diplomacy (#139) -----------------------------------------
# The AI gets agency over war/peace, not just attacks. Heuristics are deterministic
# (no RNG) so replays and tests stay reproducible.

# Declare war only on a bordering faction you outweigh by at least 3:2 (1.5x). Kept as
# an exact integer ratio (cross-multiplied at the comparison) so there's no float
# rounding ambiguity at the threshold.
const AI_WAR_RATIO_NUM := 3
const AI_WAR_RATIO_DEN := 2
# Sue for peace when your strength is below 3:5 (0.6x) of your strongest enemy's...
const AI_PEACE_RATIO_NUM := 3
const AI_PEACE_RATIO_DEN := 5
# ...and only once you're fighting on at least this many bordering fronts.
const AI_OVEREXTENDED_FRONTS := 2


## Total army strength a faction fields across every province it owns.
func faction_strength(faction: int) -> int:
	var total := 0
	for id in provinces:
		if owner_of(id) == faction:
			total += army_of(id)
	return total


## Faction ids that still own at least one province, ascending. Eliminated factions
## drop out — there's nothing left to negotiate with.
func surviving_factions() -> Array[int]:
	var seen := {}
	for id in provinces:
		seen[owner_of(id)] = true
	var out: Array[int] = []
	for f in seen:
		out.append(int(f))
	out.sort()
	return out


## Whether any province of `a` is adjacent to a province of `b` (they share a front).
func factions_border(a: int, b: int) -> bool:
	if a == b:
		return false
	for id in provinces:
		if owner_of(id) != a:
			continue
		for n in adjacency.get(id, []):
			if owner_of(n) == b:
				return true
	return false


## Let `faction` reconsider its stances (AI-initiated diplomacy, #139). Deterministic:
## it sues for peace with its strongest enemy when overextended and outmatched, then
## declares war on the weakest bordering neutral it clearly outweighs. Respects truces
## (declare_war is gated on them). Returns human-readable messages for the UI/log —
## empty when nothing changed.
func run_ai_diplomacy(faction: int) -> Array[String]:
	var messages: Array[String] = []
	var peace_target := _ai_peace_target(faction)
	if peace_target != -1:
		# Sue for peace *with a truce* so the peace is a real commitment, not a one-turn
		# flip the AI immediately undoes (#138).
		make_peace(faction, peace_target, DEFAULT_TRUCE_TURNS)
		messages.append("%s sues for peace with %s." % [_faction_label(faction), _faction_label(peace_target)])
	var war_target := _ai_war_target(faction)
	if war_target != -1 and declare_war(faction, war_target):
		messages.append("%s declares war on %s!" % [_faction_label(faction), _faction_label(war_target)])
	return messages


## The strongest bordering enemy `faction` should sue for peace with, or -1. Fires only
## when overextended (fighting >= AI_OVEREXTENDED_FRONTS bordering enemies) and below the
## AI peace ratio (0.6x) of that strongest enemy's strength.
func _ai_peace_target(faction: int) -> int:
	var enemies: Array[int] = []
	for o in surviving_factions():
		if o != faction and at_war(faction, o) and factions_border(faction, o):
			enemies.append(o)
	if enemies.size() < AI_OVEREXTENDED_FRONTS:
		return -1
	var strongest := -1
	var strongest_strength := -1
	for o in enemies:
		var s := faction_strength(o)
		if s > strongest_strength:
			strongest_strength = s
			strongest = o
	# Exact integer compare for "my strength < 0.6 x strongest": my * 5 < strongest * 3.
	if strongest != -1 and faction_strength(faction) * AI_PEACE_RATIO_DEN < strongest_strength * AI_PEACE_RATIO_NUM:
		return strongest
	return -1


## The weakest bordering faction `faction` is at peace with (no active truce) and
## clearly outweighs (by at least the AI war ratio), or -1 if none qualify.
func _ai_war_target(faction: int) -> int:
	var my_strength := faction_strength(faction)
	var target := -1
	var target_strength := 1 << 30
	for o in surviving_factions():
		if o == faction or at_war(faction, o):
			continue
		if truce_remaining(faction, o) > 0 or not factions_border(faction, o):
			continue
		var s := faction_strength(o)
		# Exact integer compare for "my strength >= 1.5 x s": my * 2 >= s * 3.
		if my_strength * AI_WAR_RATIO_DEN >= s * AI_WAR_RATIO_NUM and s < target_strength:
			target_strength = s
			target = o
	return target


func _faction_label(faction: int) -> String:
	return faction_names[faction] if faction >= 0 and faction < faction_names.size() \
			else "Faction %d" % faction


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
		"truce": _truce.duplicate(),
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
	_truce.clear()
	var truce_snap: Dictionary = snap.get("truce", {})
	for key in truce_snap:
		_truce[key] = int(truce_snap[key])
	current_faction = int(snap.get("current_faction", current_faction))
	turn = int(snap.get("turn", turn))
