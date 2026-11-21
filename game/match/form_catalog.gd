class_name FormCatalog
extends RefCounted
## The pitching and batting forms in the local content pack (content-local/forms/, made by
## ./dev mocap forms from the OBP recordings; docs/13 S10) and which one each player uses.
##
## A player's form comes from his own entry (Player.forms) if it names one in the pack;
## otherwise it is picked for him, the same every time: a pitcher by the arm-slot shares of
## data/forms/forms.json among forms of his hand, a batter among forms of his side. Without the
## pack everyone uses the default clips (or the key poses).

class Form:
	var id := ""
	var name := ""
	var hand := "R"
	## Pitchers: "overhand", "three_quarter", "sidearm". Batters: the stride ("leg_kick",
	## "toe_tap", "no_stride").
	var kind := ""


static var _pitch: Array[Form] = []
static var _swing: Array[Form] = []
static var _slot_shares: Dictionary[String, float] = {}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var root := MotionLibrary.pack_root().path_join("forms")
	_pitch = _read(root.path_join("pitch.json"), "slot")
	_swing = _read(root.path_join("swing.json"), "stride")
	var shares: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/forms/forms.json")) if FileAccess.file_exists("res://data/forms/forms.json") else null
	if shares is Dictionary:
		var s: Dictionary = (shares as Dictionary).get("arm_slot_shares", {})
		for key: String in s:
			_slot_shares[key] = float(s[key])


static func _read(path: String, kind_key: String) -> Array[Form]:
	var out: Array[Form] = []
	if not FileAccess.file_exists(path):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return out
	for entry: Dictionary in (data as Dictionary).get("forms", []):
		var f := Form.new()
		f.id = str(entry.get("id", ""))
		f.name = str(entry.get("name", ""))
		f.hand = str(entry.get("hand", "R"))
		f.kind = str(entry.get(kind_key, ""))
		out.append(f)
	return out


static func pitch_forms() -> Array[Form]:
	ensure_loaded()
	return _pitch


static func swing_forms() -> Array[Form]:
	ensure_loaded()
	return _swing


static func _find(list: Array[Form], id: String) -> Form:
	for f: Form in list:
		if f.id == id:
			return f
	return null


## The pitching form for a pitcher, or "" when the pack has none.
static func pitch_form(p: Player) -> String:
	ensure_loaded()
	if _pitch.is_empty() or p == null:
		return ""
	if p.forms.has("pitching") and _find(_pitch, p.forms["pitching"]) != null:
		return p.forms["pitching"]
	var hand := "L" if p.throws == &"L" else "R"
	var roll := float(hash(p.id + ":slot") % 10000) / 10000.0
	var slot := "three_quarter"
	var acc := 0.0
	for key: String in _slot_shares:
		acc += _slot_shares[key]
		if roll < acc:
			slot = key
			break
	var pool := _pitch.filter(func(f: Form) -> bool: return f.hand == hand and f.kind == slot)
	if pool.is_empty():
		pool = _pitch.filter(func(f: Form) -> bool: return f.hand == hand)
	if pool.is_empty():
		pool = _pitch
	return (pool[hash(p.id + ":form") % pool.size()] as Form).id


## The batting form for a batter facing a pitcher of the given hand (a switch hitter takes the
## other side), or "".
static func swing_form(p: Player, pitcher_throws: StringName = &"R") -> String:
	ensure_loaded()
	if _swing.is_empty() or p == null:
		return ""
	if p.forms.has("batting") and _find(_swing, p.forms["batting"]) != null:
		return p.forms["batting"]
	var side := "L" if p.batting_side(pitcher_throws) == &"L" else "R"
	var pool := _swing.filter(func(f: Form) -> bool: return f.hand == side)
	if pool.is_empty():
		pool = _swing
	return (pool[hash(p.id + ":swing:" + side) % pool.size()] as Form).id
