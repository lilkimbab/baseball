class_name RosterIO
extends RefCounted
## Reads and writes roster packs (docs/07 section 5) and the name table.

const NAMES_PATH := "res://data/names.ko.json"


static func load_pack(path: String) -> Array[Team]:
	var root := JsonIO.read_object(path)
	var players: Dictionary[String, Player] = {}
	var player_list: Array = root.get("players", [])
	for entry: Dictionary in player_list:
		var p := player_from(entry)
		players[p.id] = p
	var teams: Array[Team] = []
	var team_list: Array = root.get("teams", [])
	for entry: Dictionary in team_list:
		var t := Team.new()
		t.id = str(entry.get("id", ""))
		t.name = str(entry.get("name", ""))
		t.short_name = str(entry.get("short", ""))
		t.stadium = str(entry.get("stadium", ""))
		var colors: Dictionary = entry.get("colors", {})
		t.primary = Color.from_string(str(colors.get("primary", "#12355b")), t.primary)
		t.secondary = Color.from_string(str(colors.get("secondary", "#f2f2f2")), t.secondary)
		t.accent = Color.from_string(str(colors.get("accent", "#e0a100")), t.accent)
		var style: Dictionary = entry.get("manager", {})
		t.steal_style = style.get("steal", 1.0)
		t.bunt_style = style.get("bunt", 1.0)
		var ids: Array = entry.get("players", [])
		for id: Variant in ids:
			if players.has(str(id)):
				t.players.append(players[str(id)])
		if entry.has("registered"):
			t.registered = PackedStringArray(entry["registered"] as Array)
		teams.append(t)
	return teams


static func save_pack(path: String, pack_id: String, pack_name: String, season: int, teams: Array[Team]) -> Error:
	var team_list: Array = []
	var player_list: Array = []
	for t: Team in teams:
		var ids: Array = []
		for p: Player in t.players:
			ids.append(p.id)
			player_list.append(player_to(p))
		var entry := {
			"id": t.id, "name": t.name, "short": t.short_name, "stadium": t.stadium,
			"colors": {"primary": "#" + t.primary.to_html(false), "secondary": "#" + t.secondary.to_html(false), "accent": "#" + t.accent.to_html(false)},
			"manager": {"steal": snappedf(t.steal_style, 0.01), "bunt": snappedf(t.bunt_style, 0.01)},
			"players": ids,
		}
		if not t.registered.is_empty():
			entry["registered"] = Array(t.registered)
		team_list.append(entry)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	# One line per club and per player keeps the file small and still easy to read and diff.
	var lines := PackedStringArray()
	lines.append('{"format": 1, "id": %s, "name": %s, "season": %d, "league_env": "kbo_2025",' % [JSON.stringify(pack_id), JSON.stringify(pack_name), season])
	lines.append(' "teams": [')
	for i: int in team_list.size():
		lines.append("  " + JSON.stringify(team_list[i], "", false) + ("," if i < team_list.size() - 1 else ""))
	lines.append(' ],')
	lines.append(' "players": [')
	for i: int in player_list.size():
		lines.append("  " + JSON.stringify(player_list[i], "", false) + ("," if i < player_list.size() - 1 else ""))
	lines.append(' ]}')
	file.store_string("\n".join(lines) + "\n")
	return OK


static func player_from(entry: Dictionary) -> Player:
	var p := Player.new()
	p.id = str(entry.get("id", ""))
	p.name = str(entry.get("name", ""))
	p.number = int(entry.get("number", 0))
	p.born = int(entry.get("born", 2000))
	p.bats = StringName(str(entry.get("bats", "R")))
	p.throws = StringName(str(entry.get("throws", "R")))
	p.height_cm = entry.get("height_cm", 183.0)
	p.weight_kg = entry.get("weight_kg", 88.0)
	p.origin = StringName(str(entry.get("origin", "")))
	var positions: Dictionary = entry.get("positions", {})
	for code: String in positions:
		p.positions[code] = float(positions[code])
	var b: Dictionary = entry.get("batting", {})
	p.batting.contact_r = b.get("contact_r", 50.0)
	p.batting.contact_l = b.get("contact_l", 50.0)
	p.batting.power_r = b.get("power_r", 50.0)
	p.batting.power_l = b.get("power_l", 50.0)
	p.batting.eye = b.get("eye", 50.0)
	p.batting.speed = b.get("speed", 50.0)
	p.batting.baserunning = b.get("baserunning", 50.0)
	p.batting.bunt = b.get("bunt", 50.0)
	p.batting.clutch = b.get("clutch", 50.0)
	var f: Dictionary = entry.get("fielding", {})
	p.fielding.range = f.get("range", 50.0)
	p.fielding.hands = f.get("hands", 50.0)
	p.fielding.arm = f.get("arm", 50.0)
	p.fielding.accuracy = f.get("accuracy", 50.0)
	if entry.has("pitching") and entry["pitching"] != null:
		var pr: Dictionary = entry["pitching"]
		p.pitching = PitchingRatings.new()
		p.pitching.stamina = pr.get("stamina", 50.0)
		p.pitching.control = pr.get("control", 50.0)
		p.pitching.composure = pr.get("composure", 50.0)
		p.pitching.hold = pr.get("hold", 50.0)
		p.pitching.fielding = pr.get("fielding", 50.0)
		var arsenal: Array = pr.get("arsenal", [])
		for a: Dictionary in arsenal:
			var pitch := ArsenalPitch.new()
			pitch.type = StringName(str(a.get("type", "four_seam")))
			pitch.velo_avg = a.get("velo_avg", 144.0)
			pitch.velo_max = a.get("velo_max", 149.0)
			pitch.movement = a.get("movement", 50.0)
			pitch.command = a.get("command", 50.0)
			pitch.usage = a.get("usage", 0.25)
			p.pitching.arsenal.append(pitch)
	var forms: Dictionary = entry.get("forms", {})
	for key: String in forms:
		if forms[key] != null:
			p.forms[key] = str(forms[key])
	return p


static func player_to(p: Player) -> Dictionary:
	var d := {
		"id": p.id, "name": p.name, "number": p.number, "born": p.born,
		"bats": String(p.bats), "throws": String(p.throws),
		"height_cm": snappedf(p.height_cm, 0.1), "weight_kg": snappedf(p.weight_kg, 0.1),
		"positions": p.positions.duplicate(),
		"batting": {
			"contact_r": _r(p.batting.contact_r), "contact_l": _r(p.batting.contact_l), "power_r": _r(p.batting.power_r), "power_l": _r(p.batting.power_l),
			"eye": _r(p.batting.eye), "speed": _r(p.batting.speed), "baserunning": _r(p.batting.baserunning), "bunt": _r(p.batting.bunt), "clutch": _r(p.batting.clutch),
		},
		"fielding": {"range": _r(p.fielding.range), "hands": _r(p.fielding.hands), "arm": _r(p.fielding.arm), "accuracy": _r(p.fielding.accuracy)},
		"forms": p.forms.duplicate(),
	}
	if p.origin != &"":
		d["origin"] = String(p.origin)
	if p.pitching != null:
		var arsenal: Array = []
		for a: ArsenalPitch in p.pitching.arsenal:
			arsenal.append({"type": String(a.type), "velo_avg": snappedf(a.velo_avg, 0.1), "velo_max": snappedf(a.velo_max, 0.1), "movement": _r(a.movement), "command": _r(a.command), "usage": snappedf(a.usage, 0.01)})
		d["pitching"] = {"stamina": _r(p.pitching.stamina), "control": _r(p.pitching.control), "composure": _r(p.pitching.composure), "hold": _r(p.pitching.hold), "fielding": _r(p.pitching.fielding), "arsenal": arsenal}
	return d


static func _r(value: float) -> int:
	return roundi(value)


static func load_names(path: String = NAMES_PATH) -> NameTable:
	var root := JsonIO.read_object(path)
	var t := NameTable.new()
	var surnames: Dictionary = root.get("surnames", {})
	for s: String in surnames:
		t.surnames.append(s)
		t.surname_weights.append(float(surnames[s]))
	t.first = PackedStringArray(root.get("first", []) as Array)
	t.second = PackedStringArray(root.get("second", []) as Array)
	var avoid: Array = root.get("avoid", [])
	for name: Variant in avoid:
		t.avoid[str(name)] = true
	var cities: Array = root.get("cities", [])
	for c: Dictionary in cities:
		t.city_names.append(str(c.get("name", "")))
		t.city_codes.append(str(c.get("code", "")))
	t.nicknames = PackedStringArray(root.get("nicknames", []) as Array)
	t.foreign_first = PackedStringArray(root.get("foreign_first", []) as Array)
	t.foreign_last = PackedStringArray(root.get("foreign_last", []) as Array)
	t.asia_first = PackedStringArray(root.get("asia_first", []) as Array)
	t.asia_last = PackedStringArray(root.get("asia_last", []) as Array)
	var colors: Array = root.get("colors", [])
	for row: Array in colors:
		var palette := PackedColorArray()
		for hex: Variant in row:
			palette.append(Color.from_string(str(hex), Color.WHITE))
		t.colors.append(palette)
	return t
