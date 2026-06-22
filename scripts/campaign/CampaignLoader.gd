extends RefCounted
## Loads a campaign map from a JSON data file (#125) into the in-memory dictionary
## that CampaignState (rules) and CampaignMap (rendering) consume. Externalizing maps
## to data lets several campaigns ship without code changes (see Campaigns.gd) and
## paves the way for the saga layer (#126).
##
## File schema (see data/campaigns/gallic_war.json):
##   {
##     "name": "Gallic War",                 # display name (optional)
##     "blurb": "...",                        # one-line description (optional)
##     "factions": [{"name","color"}, ...],   # color is an HTML hex string
##     "provinces": [
##       {"id","name","owner","army","adj":[ids], "polygon":[[x,y],...], "label":[x,y]}
##     ],
##     "peace": [[factionA, factionB], ...]    # optional; pairs that start at peace (#123)
##   }
##
## parse_map() is pure (takes already-parsed JSON) so it's unit-tested without files;
## load_map() reads + JSON-decodes a res:// path and delegates to it. A schema error
## is recoverable (the caller falls back to the default map), so both push_warning()
## with a clear message and return {} (empty = failure) rather than a hard error.

const DEFAULT_FACTION_COLOR := Color(0.7, 0.7, 0.7)


## Read and parse a campaign map from `path` (res://...). Returns {} on any error.
static func load_map(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Campaign map: file not found: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_warning("Campaign map: empty or unreadable file: %s" % path)
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("Campaign map: invalid JSON in %s (line %d): %s"
				% [path, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		push_warning("Campaign map: %s must contain a JSON object" % path)
		return {}
	return parse_map(json.data)


## Validate and convert an already-parsed map dict into the in-memory format
## (PackedVector2Array polygons, Color factions, etc). Returns {} on any error.
static func parse_map(raw: Dictionary) -> Dictionary:
	var factions: Array = raw.get("factions", [])
	if factions.is_empty():
		push_warning("Campaign map: 'factions' must be a non-empty array")
		return {}
	var faction_names: Array[String] = []
	var faction_colors: Array[Color] = []
	for f in factions:
		if typeof(f) != TYPE_DICTIONARY or not f.has("name"):
			push_warning("Campaign map: each faction needs a 'name'")
			return {}
		faction_names.append(str(f["name"]))
		faction_colors.append(Color.from_string(str(f.get("color", "")), DEFAULT_FACTION_COLOR))

	var raw_provinces: Array = raw.get("provinces", [])
	if raw_provinces.is_empty():
		push_warning("Campaign map: 'provinces' must be a non-empty array")
		return {}

	var provinces: Array = []
	var ids := {}
	for p in raw_provinces:
		if typeof(p) != TYPE_DICTIONARY:
			push_warning("Campaign map: each province must be an object")
			return {}
		for key in ["id", "name", "owner", "army", "adj", "polygon"]:
			if not p.has(key):
				push_warning("Campaign map: province is missing '%s': %s" % [key, p])
				return {}
		var id := int(p["id"])
		if ids.has(id):
			push_warning("Campaign map: duplicate province id %d" % id)
			return {}
		ids[id] = true
		var owner := int(p["owner"])
		if owner < 0 or owner >= faction_names.size():
			push_warning("Campaign map: province %d has owner %d outside 0..%d"
					% [id, owner, faction_names.size() - 1])
			return {}
		var poly := _to_polygon(p["polygon"])
		if poly.size() < 3:
			push_warning("Campaign map: province %d needs a polygon of >= 3 points" % id)
			return {}
		var adj: Array[int] = []
		for n in p["adj"]:
			adj.append(int(n))
		var label: Vector2 = _centroid(poly)
		if p.has("label"):
			var lbl = _parse_point(p["label"])
			if lbl != null:
				label = lbl
		provinces.append({
			"id": id, "name": str(p["name"]), "owner": owner, "army": int(p["army"]),
			"adj": adj, "polygon": poly, "label": label,
		})

	# Adjacency must reference provinces that exist.
	for prov in provinces:
		for n in prov["adj"]:
			if not ids.has(n):
				push_warning("Campaign map: province %d lists unknown neighbour %d" % [prov["id"], n])
				return {}

	# Adjacency must be symmetric: if A lists B, B must list A.
	var adj_index: Dictionary = {}
	for prov in provinces:
		adj_index[prov["id"]] = prov["adj"]
	for prov in provinces:
		for n in prov["adj"]:
			if not (prov["id"] in adj_index[n]):
				push_warning("Campaign map: adjacency between province %d and %d is not symmetric"
						% [prov["id"], n])
				return {}

	# Optional initial diplomacy (#123): pairs of faction indices that start at peace.
	# Validated here so a typo is caught at load time rather than silently ignored.
	var peace: Array = []
	for pair in raw.get("peace", []):
		if typeof(pair) != TYPE_ARRAY or pair.size() < 2:
			push_warning("Campaign map: each 'peace' entry must be a [factionA, factionB] pair")
			return {}
		var a := int(pair[0])
		var b := int(pair[1])
		if a < 0 or a >= faction_names.size() or b < 0 or b >= faction_names.size():
			push_warning("Campaign map: 'peace' pair [%d, %d] references an unknown faction" % [a, b])
			return {}
		if a == b:
			# A faction can't be at peace with itself; this is almost certainly a typo,
			# so surface it at load time rather than silently dropping it.
			push_warning("Campaign map: 'peace' pair [%d, %d] lists a faction with itself" % [a, b])
			return {}
		var lo := mini(a, b)
		var hi := maxi(a, b)
		if [lo, hi] in peace:
			# Duplicate pair (possibly reversed, e.g. [0, 2] and [2, 0]); make_peace is
			# idempotent so it's harmless, but a redundant entry is a hand-edit slip —
			# reject it at load time to stay consistent with the checks above.
			push_warning("Campaign map: duplicate 'peace' pair [%d, %d]" % [a, b])
			return {}
		peace.append([lo, hi])

	return {
		"name": str(raw.get("name", "Campaign")),
		"blurb": str(raw.get("blurb", "")),
		"faction_names": faction_names,
		"faction_colors": faction_colors,
		"provinces": provinces,
		"peace": peace,
	}


static func _to_polygon(points: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if typeof(points) != TYPE_ARRAY:
		return out
	for pt in points:
		var v = _parse_point(pt)
		if v == null:
			# A malformed vertex invalidates the whole polygon, so the caller's
			# ">= 3 points" check rejects the province (no spurious origin vertex).
			return PackedVector2Array()
		out.append(v)
	return out


## Parse an [x, y] point, or null if malformed (caller rejects or falls back).
static func _parse_point(pt: Variant) -> Variant:
	if typeof(pt) == TYPE_ARRAY and pt.size() >= 2:
		return Vector2(float(pt[0]), float(pt[1]))
	return null


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for v in poly:
		sum += v
	return sum / maxi(1, poly.size())
