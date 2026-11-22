class_name ClubIO
extends RefCounted
## Reads data/club.ko.json into ClubRules.

const PATH := "res://data/club.ko.json"


static func load_default() -> ClubRules:
	return load_rules(PATH)


static func load_rules(path: String) -> ClubRules:
	var root := JsonIO.read_object(path)
	var r := ClubRules.new()
	var grades: Array = root.get("grades", [])
	for entry: Dictionary in grades:
		var g := ClubRules.Grade.new()
		g.name = str(entry.get("grade", "D"))
		g.min_ovr = float(entry.get("min", 0.0))
		g.cost = int(entry.get("cost", 1))
		r.grades.append(g)
	r.cost_caps = PackedInt32Array(root.get("cost_caps", [90, 75, 60]) as Array)
	var c: Dictionary = root.get("condition", {})
	r.condition_levels = PackedStringArray(c.get("levels", r.condition_levels) as Array)
	r.condition_effect = PackedFloat64Array(c.get("effect", r.condition_effect) as Array)
	r.condition_change = float(c.get("change", r.condition_change))
	r.toward_normal = float(c.get("toward_normal", r.toward_normal))
	r.streak_games = int(c.get("streak_games", r.streak_games))
	r.streak_drop = float(c.get("streak_drop", r.streak_drop))
	var s: Dictionary = root.get("scouting", {})
	r.scout_candidates = int(s.get("candidates", r.scout_candidates))
	r.scout_talent = PackedFloat64Array(s.get("talent_by_division", r.scout_talent) as Array)
	r.scout_spread = float(s.get("spread", r.scout_spread))
	r.scout_level_bonus = float(s.get("level_bonus", r.scout_level_bonus))
	r.scout_max_level = int(s.get("max_level", r.scout_max_level))
	r.second_team_size = int(s.get("second_team_size", r.second_team_size))
	var t: Dictionary = root.get("training", {})
	r.train_per_day = int(t.get("per_day", r.train_per_day))
	r.train_gain = float(t.get("gain", r.train_gain))
	r.age_rates = _table(t.get("age_rates", []))
	r.headroom = _table(t.get("headroom", []))
	var focus: Dictionary = t.get("focus", {})
	for key: String in focus:
		r.focus[key] = PackedStringArray(focus[key] as Array)
	var points: Dictionary = root.get("points", {})
	for key: String in points:
		if points[key] is Array:
			r.scout_upgrade = PackedInt32Array(points[key] as Array)
		else:
			r.points[key] = int(points[key])
	r.trait_tiers = PackedFloat64Array(root.get("trait_tiers", r.trait_tiers) as Array)
	var traits: Array = root.get("traits", [])
	for entry: Dictionary in traits:
		var d := ClubRules.TraitDef.new()
		d.id = str(entry.get("id", ""))
		d.name = str(entry.get("name", ""))
		d.kind = StringName(str(entry.get("kind", "batter")))
		d.effect = _floats(entry.get("effect", {}))
		d.note = str(entry.get("note", ""))
		r.traits.append(d)
	var colors: Array = root.get("team_colors", [])
	for entry: Dictionary in colors:
		var d := ClubRules.ColorDef.new()
		d.id = str(entry.get("id", ""))
		d.name = str(entry.get("name", ""))
		var need: Dictionary = entry.get("need", {})
		d.need_kind = StringName(str(need.get("kind", "batter")))
		d.rating = str(need.get("rating", ""))
		d.at_least = float(need.get("at_least", 0.0))
		d.grade_at_least = str(need.get("grade_at_least", ""))
		d.count = int(need.get("count", 0))
		d.steps = PackedInt32Array(need.get("steps", []) as Array)
		d.bonus = _floats(entry.get("bonus", {}))
		d.to = StringName(str(entry.get("to", "batter")))
		r.colors.append(d)
	r.color_limit = int(root.get("team_color_limit", r.color_limit))
	r.color_cap = float(root.get("team_color_cap", r.color_cap))
	return r


static func _table(rows: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for row: Array in rows:
		out.append(Vector2(float(row[0]), float(row[1])))
	return out


static func _floats(d: Dictionary) -> Dictionary[String, float]:
	var out: Dictionary[String, float] = {}
	for key: String in d:
		out[key] = float(d[key])
	return out
