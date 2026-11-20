class_name LeagueEnvIO
extends RefCounted
## Reads league environments from data/league_env.json and the overall-rating weights from
## data/ovr_weights.json.

const DEFAULT_PATH := "res://data/league_env.json"
const OVR_PATH := "res://data/ovr_weights.json"


static func load_default(preset: String = "") -> LeagueEnv:
	return load_file(DEFAULT_PATH, preset)


static func load_file(path: String, preset: String = "") -> LeagueEnv:
	var root := JsonIO.read_object(path)
	var presets: Dictionary = root.get("presets", {})
	var chosen := preset if preset != "" else str(root.get("default", ""))
	var p: Dictionary = presets.get(chosen, {})
	var env := LeagueEnv.new()
	env.name = chosen
	env.label = str(p.get("label", chosen))
	var pa: Dictionary = p.get("pa", {})
	var rates := PackedFloat64Array()
	var used := 0.0
	for key: String in LeagueEnv.OUTCOME_KEYS:
		if key == "OUT":
			rates.append(1.0 - used)
		else:
			var r: float = pa.get(key, 0.0)
			rates.append(r)
			used += r
	env.rates = rates
	var targets: Dictionary = p.get("targets", {})
	for key: String in targets:
		env.targets[key] = float(targets[key])

	var c: Dictionary = root.get("coefficients", {})
	env.batter_k = _tables(c.get("batter", {}))
	env.pitcher_k = _tables(c.get("pitcher", {}))
	env.defence_hits = c.get("defence_hits", -0.05)
	env.clutch = c.get("clutch", 0.04)
	var platoon: Dictionary = c.get("platoon", {})
	env.same_hand = _floats(platoon.get("same_hand", {}))
	env.opposite_hand = _floats(platoon.get("opposite_hand", {}))
	env.fatigue = _floats(c.get("fatigue", {}))

	var in_play: Dictionary = root.get("in_play", {})
	var types: Dictionary = in_play.get("out_types", {})
	env.out_types = PackedFloat64Array([types.get("ground", 0.45), types.get("fly", 0.30), types.get("line", 0.12), types.get("popup", 0.13)])
	for group: String in ["in_play", "running", "manager"]:
		var section: Dictionary = root.get(group, {})
		for key: String in section:
			if typeof(section[key]) == TYPE_FLOAT or typeof(section[key]) == TYPE_INT:
				env.values[key] = float(section[key])
	env.pitches_per_pa = _floats(root.get("pitches_per_pa", {}))
	env.calibration = _floats(root.get("calibration", {}))
	var home: Dictionary = root.get("home_advantage", {})
	env.home_hits = home.get("hits", 1.0)
	return env


static func load_overall(path: String = OVR_PATH) -> Overall:
	var root := JsonIO.read_object(path)
	var ovr := Overall.new()
	var positions: Dictionary = root.get("positions", {})
	for code: String in positions:
		ovr.weights[code] = PackedFloat64Array(positions[code] as Array)
	return ovr


static func _tables(source: Dictionary) -> Dictionary[String, Dictionary]:
	var out: Dictionary[String, Dictionary] = {}
	for key: String in source:
		out[key] = source[key]
	return out


static func _floats(source: Dictionary) -> Dictionary[String, float]:
	var out: Dictionary[String, float] = {}
	for key: String in source:
		if typeof(source[key]) == TYPE_FLOAT or typeof(source[key]) == TYPE_INT:
			out[key] = float(source[key])
	return out
