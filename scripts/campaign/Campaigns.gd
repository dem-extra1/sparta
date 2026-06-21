extends RefCounted
## Registry of the campaigns the main menu offers (#125). Adding a campaign is now
## data-only plus one row here: drop a JSON map under data/campaigns/ and list it.
##
## `selected_path` is set by the main menu before it switches to the campaign scene,
## and read by CampaignMap when it builds its state. It defaults to the Gallic War so
## the campaign scene also runs standalone (e.g. opened directly in the editor).

# Each entry: {id, name, path}. `name` is the button label shown in the main menu.
# The map file also carries its own name/blurb (loaded by CampaignLoader); those are
# reserved for a future campaign-picker screen (#126) and aren't displayed yet.
const LIST := [
	{
		"id": "gallic_war",
		"name": "Gallic War",
		"path": "res://data/campaigns/gallic_war.json",
	},
]

const DEFAULT_PATH := "res://data/campaigns/gallic_war.json"

# Set by MainMenu before change_scene_to_file; read by CampaignMap on load.
static var selected_path: String = DEFAULT_PATH
