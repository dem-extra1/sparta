extends GutTest
## CampaignBattle: the campaign<->tactical-battle hand-off holder. The scene
## swap itself isn't unit-tested, but the pure strength<->units mapping and the
## holder lifecycle are.

const CampaignBattle = preload("res://scripts/campaign/CampaignBattle.gd")


func test_units_for_scales_and_caps() -> void:
	assert_eq(CampaignBattle.units_for(1), 1, "a 1-strength army fields 1 unit")
	assert_eq(CampaignBattle.units_for(5), 5, "small armies map 1:1 to units")
	assert_eq(CampaignBattle.units_for(0), 1, "even a 0/empty strength fields at least 1 unit")
	assert_eq(CampaignBattle.units_for(999), CampaignBattle.MAX_UNITS, "a huge stack is capped")


func test_survivors_strength_scales_back() -> void:
	# 1:1 spawn (strength 5 -> 5 units): 3 survivors -> 3 strength.
	assert_eq(CampaignBattle.survivors_strength(5, 5, 3), 3, "survivors map back 1:1 when uncapped")
	# Full survival keeps full strength.
	assert_eq(CampaignBattle.survivors_strength(5, 5, 5), 5, "no losses keeps full strength")
	# A winner always keeps at least 1 even after heavy losses.
	assert_eq(CampaignBattle.survivors_strength(10, 10, 1), 1, "a battered winner keeps a token army")
	# Annihilated / nothing spawned -> 0.
	assert_eq(CampaignBattle.survivors_strength(5, 5, 0), 0, "an annihilated side returns 0")
	assert_eq(CampaignBattle.survivors_strength(5, 0, 3), 0, "no spawn -> 0 (guards divide-by-zero)")


func test_survivors_strength_unscales_a_capped_spawn() -> void:
	# A 24-strength stack spawns MAX_UNITS (12); half surviving -> ~half strength.
	var spawned: int = CampaignBattle.units_for(24)
	assert_eq(spawned, CampaignBattle.MAX_UNITS)
	assert_eq(CampaignBattle.survivors_strength(24, spawned, 6), 12, "6/12 of a capped 24 -> 12")


func test_clear_resets_the_holder() -> void:
	CampaignBattle.active = true
	CampaignBattle.pending = {"from": 0, "to": 1}
	CampaignBattle.result = {"attacker_won": true, "survivors": 3}
	CampaignBattle.snapshot = {"turn": 4}
	CampaignBattle.clear()
	assert_false(CampaignBattle.active, "cleared active flag")
	assert_true(CampaignBattle.pending.is_empty(), "cleared pending clash")
	assert_true(CampaignBattle.result.is_empty(), "cleared result")
	assert_true(CampaignBattle.snapshot.is_empty(), "cleared snapshot")
