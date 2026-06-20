extends RefCounted
## The first campaign map (#70): a compact Gallic War — Rome (faction 0) holds the
## south and the Italian gateway; the Gallic tribes (faction 1) hold the rest. The
## player (Rome) wins by conquering every province.
##
## Static, hand-authored data: province polygons are placeholder geometry drawn in
## code (no external art, matching the project's self-drawn approach) — a base-map
## image and tidier regions can come later. Geometry (polygon, label) is consumed by
## the renderer; CampaignState reads only owner/army/adj/name.

const ROME := 0
const GAULS := 1

const FACTION_NAMES := ["Rome", "Gallic Tribes"]
# Indexed by faction id: the colour a faction's provinces are drawn in.
const FACTION_COLORS := [Color(0.36, 0.52, 0.86), Color(0.82, 0.36, 0.32)]


## A fresh map dictionary. Returns new copies each call so a restart starts clean.
static func new_map() -> Dictionary:
	return {
		"faction_names": FACTION_NAMES.duplicate(),
		"faction_colors": FACTION_COLORS.duplicate(),
		"provinces": [
			{
				"id": 0, "name": "Narbonensis", "owner": ROME, "army": 5,
				"adj": [1, 2, 5, 6], "label": Vector2(560, 565),
				"polygon": PackedVector2Array([
					Vector2(460, 500), Vector2(660, 500), Vector2(700, 600),
					Vector2(540, 640), Vector2(440, 590),
				]),
			},
			{
				"id": 1, "name": "Aquitania", "owner": GAULS, "army": 3,
				"adj": [0, 2, 4], "label": Vector2(300, 490),
				"polygon": PackedVector2Array([
					Vector2(220, 400), Vector2(400, 420), Vector2(420, 540),
					Vector2(300, 600), Vector2(200, 500),
				]),
			},
			{
				"id": 2, "name": "Celtica", "owner": GAULS, "army": 4,
				"adj": [0, 1, 3, 4, 6], "label": Vector2(520, 380),
				"polygon": PackedVector2Array([
					Vector2(420, 300), Vector2(640, 300), Vector2(640, 440),
					Vector2(440, 460), Vector2(400, 380),
				]),
			},
			{
				"id": 3, "name": "Belgica", "owner": GAULS, "army": 5,
				"adj": [2, 4, 6], "label": Vector2(620, 190),
				"polygon": PackedVector2Array([
					Vector2(520, 120), Vector2(740, 120), Vector2(760, 240),
					Vector2(560, 260), Vector2(500, 200),
				]),
			},
			{
				"id": 4, "name": "Armorica", "owner": GAULS, "army": 3,
				"adj": [1, 2, 3], "label": Vector2(260, 240),
				"polygon": PackedVector2Array([
					Vector2(160, 160), Vector2(360, 160), Vector2(380, 300),
					Vector2(220, 320), Vector2(140, 260),
				]),
			},
			{
				"id": 5, "name": "Cisalpina", "owner": ROME, "army": 6,
				"adj": [0, 6], "label": Vector2(960, 540),
				"polygon": PackedVector2Array([
					Vector2(860, 460), Vector2(1060, 460), Vector2(1080, 600),
					Vector2(900, 620), Vector2(840, 540),
				]),
			},
			{
				"id": 6, "name": "Helvetia", "owner": GAULS, "army": 4,
				"adj": [0, 2, 3, 5], "label": Vector2(820, 380),
				"polygon": PackedVector2Array([
					Vector2(720, 300), Vector2(920, 300), Vector2(940, 440),
					Vector2(760, 460), Vector2(700, 400),
				]),
			},
		],
	}
