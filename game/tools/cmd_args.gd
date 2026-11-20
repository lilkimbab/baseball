class_name CmdArgs
extends RefCounted
## Parses "--key value", "--key=value" and "--flag" from the arguments given after "--" on the
## Godot command line (OS.get_cmdline_user_args()).


## Returns { key: value } with the leading dashes removed. A flag with no value maps to "true".
static func parse(argv: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var i := 0
	while i < argv.size():
		var token := argv[i]
		if token.begins_with("--"):
			var key := token.substr(2)
			var has_value := i + 1 < argv.size() and not argv[i + 1].begins_with("--")
			if key.contains("="):
				out[key.get_slice("=", 0)] = key.substr(key.find("=") + 1)
			elif has_value:
				out[key] = argv[i + 1]
				i += 1
			else:
				out[key] = "true"
		i += 1
	return out
