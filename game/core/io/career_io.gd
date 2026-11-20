class_name CareerIO
extends RefCounted
## Reads data/career.ko.json into CareerRules.

const PATH := "res://data/career.ko.json"


static func load_default() -> CareerRules:
	var root := JsonIO.read_object(PATH)
	var r := CareerRules.new()
	r.base = float(root.get("base", r.base))
	r.strength = float(root.get("strength", r.strength))
	r.weakness = float(root.get("weakness", r.weakness))
	r.positions = PackedStringArray(root.get("positions", []) as Array)
	var names: Dictionary = root.get("position_names", {})
	for key: String in names:
		r.position_names[key] = str(names[key])
	r.batter_types = _types(root.get("batter_types", []))
	r.pitcher_types = _types(root.get("pitcher_types", []))
	var bodies: Array = root.get("bodies", [])
	for entry: Dictionary in bodies:
		var b := CareerRules.Body.new()
		b.id = str(entry.get("id", ""))
		b.name = str(entry.get("name", ""))
		b.height = float(entry.get("height", 183.0))
		b.weight = float(entry.get("weight", 88.0))
		r.bodies.append(b)
	r.skins = PackedStringArray(root.get("skins", []) as Array)
	r.hairs = PackedStringArray(root.get("hairs", []) as Array)
	r.beards = PackedStringArray(root.get("beards", []) as Array)
	var gp: Dictionary = root.get("gp", {})
	for field: String in ["batting", "running", "fielding", "pitching"]:
		r.gp[field] = gp.get(field, {})
	r.scene_goal_gp = float(gp.get("scene_goal", r.scene_goal_gp))
	r.game_goal_gp = float(gp.get("game_goal", r.game_goal_gp))
	r.clutch = float(gp.get("clutch", r.clutch))
	r.cost_base = float(gp.get("cost_base", r.cost_base))
	r.type_discount = float(gp.get("type_discount", r.type_discount))
	var ratings: Dictionary = root.get("ratings", {})
	for field: String in ratings:
		r.ratings[field] = PackedStringArray(ratings[field] as Array)
	var goals: Dictionary = root.get("game_goals", {})
	for key: String in goals:
		r.game_goals[key] = goals[key]
	return r


static func _types(list: Array) -> Array[CareerRules.PlayerType]:
	var out: Array[CareerRules.PlayerType] = []
	for entry: Dictionary in list:
		var t := CareerRules.PlayerType.new()
		t.id = str(entry.get("id", ""))
		t.name = str(entry.get("name", ""))
		t.strengths = PackedStringArray(entry.get("strengths", []) as Array)
		t.weak = PackedStringArray(entry.get("weak", []) as Array)
		t.all = float(entry.get("all", 0.0))
		var pitches: Array = entry.get("pitches", [])
		for p: Variant in pitches:
			t.pitches.append(StringName(str(p)))
		t.velocity = float(entry.get("velocity", 144.0))
		out.append(t)
	return out
