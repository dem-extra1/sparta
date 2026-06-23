extends RefCounted
## Loads a campaign map from a JSON data file into the in-memory dictionary
## that CampaignState (rules) and CampaignMap (rendering) consume. Externalizing maps
## to data lets several campaigns ship without code changes (see Campaigns.gd) and
## paves the way for the saga layer.
##
## File schema (see data/campaigns/gallic_war.json):
##   {
##     "name": "Gallic War",                 # display name (optional)
##     "blurb": "...",                        # one-line description (optional)
##     "factions": [{"name","color"}, ...],   # color is an HTML hex string
##     "rulers": [{"name","trait"}, ...],     # optional; parallel to factions.
##                                            # name: ruler's personal name (default "").
##                                            # trait: "aggressive", "defensive", or "normal"
##                                            #   (default "normal"). Controls AI war/peace
##                                            #   thresholds for that faction.
##     "provinces": [
##       {"id","name","owner","army","adj":[ids], "polygon":[[x,y],...], "label":[x,y],
##        "one_way": <bool>}     # optional, default false; declares this province's
##                               # one-way exits intentional, suppressing the asymmetry warning
##     ],
##     "peace": [[factionA, factionB], ...]    # optional; pairs that start at peace.
##                                              # A 3rd element sets an initial truce in
##                                              # turns: [factionA, factionB, truceTurns].
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
		var adj_seen := {}
		for n in p["adj"]:
			var neighbor := int(n)
			if neighbor == id:
				push_warning("Campaign map: province %d lists itself in 'adj'" % id)
				return {}
			if adj_seen.has(neighbor):
				push_warning("Campaign map: province %d has duplicate neighbour %d in 'adj'" % [id, neighbor])
				return {}
			adj_seen[neighbor] = true
			adj.append(neighbor)
		var label: Vector2 = _centroid(poly)
		if p.has("label"):
			var lbl = _parse_point(p["label"])
			if lbl != null:
				label = lbl
		# Optional "one_way" flag: declares this province's exits intentionally one-way, so
		# the asymmetry check below skips it. Validation-only — movement is already directed.
		# Require a real boolean: bool("false") is true and bool(0) is false in GDScript, so
		# coercing a stray string/number would silently flip intent. Reject instead.
		var one_way := false
		if p.has("one_way"):
			if typeof(p["one_way"]) != TYPE_BOOL:
				push_warning("Campaign map: province %d 'one_way' must be a boolean (true/false)" % id)
				return {}
			one_way = p["one_way"]
		provinces.append({
			"id": id, "name": str(p["name"]), "owner": owner, "army": int(p["army"]),
			"adj": adj, "polygon": poly, "label": label,
			"one_way": one_way,
		})

	# Adjacency must reference provinces that exist.
	for prov in provinces:
		for n in prov["adj"]:
			if not ids.has(n):
				push_warning("Campaign map: province %d lists unknown neighbour %d" % [prov["id"], n])
				return {}

	# Adjacency may be one-way: movement uses directed adjacency, so an edge A->B
	# without B->A is a legal one-way pass (e.g. a mountain pass or river crossing). The
	# far more common cause of asymmetry, though, is a hand-edit typo, so warn on any
	# un-flagged one-way edge — unless the source province opts in with "one_way": true,
	# declaring its asymmetric exits intentional. Either way the map still loads; this is
	# a lint, not a hard error (the unknown-neighbour check above already rejects edges to
	# ids that don't exist). The flag is province-level: it silences the warning for *all*
	# of the province's exits, not one edge (simple common case; an edge-level opt-in can
	# follow if a map ever needs mixed intentional/typo exits on the same province).
	var adj_index: Dictionary = {}
	for prov in provinces:
		adj_index[prov["id"]] = prov["adj"]
	for prov in provinces:
		if prov["one_way"]:
			continue
		for n in prov["adj"]:
			if not (prov["id"] in adj_index[n]):
				push_warning(("Campaign map: adjacency %d -> %d is one-way (province %d doesn't list %d back). "
						+ "Set \"one_way\": true on province %d if that's intentional; otherwise it's likely a typo.")
						% [prov["id"], n, n, prov["id"], prov["id"]])

	# Optional initial diplomacy: pairs of faction indices that start at peace,
	# with an optional third element giving an initial truce length in turns.
	# Validated here so a typo is caught at load time rather than silently ignored.
	var peace: Array = []
	var seen_pairs := {}
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
		var key := "%d-%d" % [lo, hi]
		if seen_pairs.has(key):
			# Duplicate pair (possibly reversed, e.g. [0, 2] and [2, 0]); make_peace is
			# idempotent so it's harmless, but a redundant entry is a hand-edit slip —
			# reject it at load time to stay consistent with the checks above.
			push_warning("Campaign map: duplicate 'peace' pair [%d, %d]" % [a, b])
			return {}
		seen_pairs[key] = true
		var entry := [lo, hi]
		if pair.size() >= 3:
			var truce_turns := int(pair[2])
			if truce_turns < 0:
				push_warning("Campaign map: 'peace' pair [%d, %d] has a negative truce length %d"
						% [a, b, truce_turns])
				return {}
			# Carry a positive truce through; 0 means "peace, no truce", same as a bare pair.
			if truce_turns > 0:
				entry.append(truce_turns)
		peace.append(entry)

	# Optional rulers: one {name, trait} per faction, surfaced in the turn banner and
	# used to flavour AI diplomacy. CampaignState._init() normalises bad data defensively
	# (truncates/pads to the faction count, unknown traits fall back to "normal"), so this
	# is a soft lint that surfaces likely typos at load time rather than a hard rejection.
	var raw_rulers: Variant = raw.get("rulers", [])
	if typeof(raw_rulers) != TYPE_ARRAY:
		push_warning("Campaign map: 'rulers' should be an array of {name, trait} objects")
	else:
		for r in raw_rulers:
			if typeof(r) != TYPE_DICTIONARY:
				push_warning("Campaign map: each 'rulers' entry should be a {name, trait} object")
				continue
			var t := str(r.get("trait", "normal"))
			if t != "normal" and t != "aggressive" and t != "defensive":
				push_warning(("Campaign map: ruler trait '%s' is not one of "
						+ "normal/aggressive/defensive; it will default to normal") % t)

	return {
		"name": str(raw.get("name", "Campaign")),
		"blurb": str(raw.get("blurb", "")),
		"faction_names": faction_names,
		"faction_colors": faction_colors,
		"provinces": provinces,
		"peace": peace,
		"rulers": raw_rulers,
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
