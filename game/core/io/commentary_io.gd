class_name CommentaryIO
extends RefCounted
## Reads the play-by-play templates (data/commentary.ko.json).

const DEFAULT_PATH := "res://data/commentary.ko.json"

static var _default: Commentary


static func load_default() -> Commentary:
	if _default == null:
		_default = load_file(DEFAULT_PATH)
	return _default


static func load_file(path: String) -> Commentary:
	var root := JsonIO.read_object(path)
	var c := Commentary.new()
	for key: String in root:
		var v: Variant = root[key]
		if v is Array:
			c.templates[key] = PackedStringArray(v)
	return c
