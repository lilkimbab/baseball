class_name JsonIO
extends RefCounted
## Reads JSON files. Untyped dictionaries stop at core/io: callers convert to typed objects.


## Parses a JSON file whose top level is an object. Returns {} and logs an error on failure.
static func read_object(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("JsonIO: file not found: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JsonIO: %s is not a JSON object" % path)
		return {}
	return parsed
