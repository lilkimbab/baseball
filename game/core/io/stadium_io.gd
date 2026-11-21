class_name StadiumIO
extends RefCounted
## Reads ballpark definitions from data/stadiums (docs/13 S13-1).

const DIR := "res://data/stadiums"
## The park used when none is named: the large symmetric one.
const DEFAULT := "grand_park"


static func load_park(id: String) -> StadiumDef:
	if id == "standard":
		return StadiumDef.standard()
	var path := "%s/%s.json" % [DIR, id]
	if not FileAccess.file_exists(path):
		path = "%s/%s.json" % [DIR, DEFAULT]
	return StadiumDef.from_dictionary(JsonIO.read_object(path))


## Every park's id, in name order.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for file: String in DirAccess.get_files_at(DIR):
		if file.ends_with(".json"):
			out.append(file.get_basename())
	out.sort()
	return out
