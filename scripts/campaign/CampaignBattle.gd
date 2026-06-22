extends RefCounted
## Hand-off between the campaign map and a tactical battle (M3, #122).
##
## A contested province clash on the campaign map can be fought out in the real
## tactical battle (scenes/Battle.tscn) instead of being auto-resolved by dice in
## CampaignState. Because Godot's change_scene_to_file is one-way, this static
## holder ferries data across the round-trip (same persist-across-scenes pattern as
## Campaigns.selected_path):
##
##   Campaign -> Battle : `pending` (who's fighting, army sizes) + `snapshot`
##                        (the campaign state to restore on return).
##   Battle -> Campaign : `result` (attacker_won + the winner's surviving strength).
##
## `active` marks a battle as campaign-launched so Battle.tscn seeds its armies from
## the clash and offers "Return to Campaign", and CampaignMap knows to resume from
## the snapshot and apply the result. Cleared once the campaign consumes the result
## (and defensively whenever the main menu loads).

# Each campaign army-strength point spawns one battle unit, capped so a huge stack
# still fits the deployment line; the survivor mapping scales by the spawned count
# so the round-trip stays faithful even when capped.
const MAX_UNITS := 12

# A campaign-launched battle is in progress / awaiting pickup. False for the
# standalone "Tactical Battle" menu option (which spawns the default loadout).
static var active: bool = false

# Clash context the battle reads: {from, to, attacker_strength, defender_strength,
# attacker_name, defender_name, attacker_color, defender_color, to_name}.
static var pending: Dictionary = {}

# Outcome the campaign applies: {attacker_won: bool, survivors: int}. Empty until
# the battle ends.
static var result: Dictionary = {}

# CampaignState.snapshot() taken before the fight, restored when control returns so
# the rest of the campaign (other provinces, turn, diplomacy) survives the scene swap.
static var snapshot: Dictionary = {}


## Number of battle units to deploy for a campaign army of `strength` (>= 1, capped).
static func units_for(strength: int) -> int:
	return clampi(strength, 1, MAX_UNITS)


## Map a side's surviving battle units back to campaign army strength, scaled by how
## many it deployed (so a capped spawn still returns a proportional strength). The
## winner keeps at least 1; an annihilated side returns 0.
static func survivors_strength(start_strength: int, spawned: int, surviving: int) -> int:
	if spawned <= 0 or surviving <= 0:
		return 0
	return maxi(1, int(round(float(start_strength) * float(surviving) / float(spawned))))


## Forget any in-flight battle (after the campaign applies the result, or when the
## main menu loads so a later standalone battle isn't mistaken for a campaign one).
static func clear() -> void:
	active = false
	pending = {}
	result = {}
	snapshot = {}
