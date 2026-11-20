class_name PitchCatalogIO
extends RefCounted
## Loads the pitch type catalogue from data/pitch_types.json.

const DEFAULT_PATH := "res://data/pitch_types.json"

static var _default: Dictionary[StringName, PitchType] = {}


static func load_default() -> Dictionary[StringName, PitchType]:
	if _default.is_empty():
		_default = load_file(DEFAULT_PATH)
	return _default


static func load_file(path: String) -> Dictionary[StringName, PitchType]:
	var out: Dictionary[StringName, PitchType] = {}
	var root := JsonIO.read_object(path)
	var types: Array = root.get("types", [])
	for entry: Dictionary in types:
		var t := PitchType.new()
		t.id = StringName(str(entry.get("id", "")))
		t.label = entry.get("label", "")
		t.family = StringName(str(entry.get("family", "")))
		t.speed_kmh = entry.get("speed_kmh", 0.0)
		t.spin_rpm = entry.get("spin_rpm", 0.0)
		t.efficiency = entry.get("efficiency", 1.0)
		t.tilt_deg = entry.get("tilt_deg", 0.0)
		out[t.id] = t
	return out
