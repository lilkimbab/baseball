extends SceneTree
## Writes the Godot Engine's licence and the licences of the libraries inside it to one text
## file, for the release folder (./dev release): the engine's MIT licence asks that its notice go
## with every copy of the game.
##
##   godot --headless --path game --script res://tools/engine_licence.gd -- --out <file>


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var out := str(args.get("out", "user://GODOT-LICENSE.txt"))
	var lines := PackedStringArray()
	lines.append("This game uses the Godot Engine (https://godotengine.org), version %s." % Engine.get_version_info().string)
	lines.append("")
	lines.append(Engine.get_license_text())
	lines.append("")
	lines.append("== Third-party components of the Godot Engine ==")
	lines.append("")
	for part: Dictionary in Engine.get_copyright_info():
		lines.append("- %s" % part["name"])
		for piece: Dictionary in part["parts"]:
			for holder: String in piece.get("copyright", []):
				lines.append("    (c) %s" % holder)
			lines.append("    License: %s" % piece.get("license", ""))
	lines.append("")
	lines.append("== License texts ==")
	var info := Engine.get_license_info()
	for key: String in info:
		lines.append("")
		lines.append("--- %s ---" % key)
		lines.append(str(info[key]))
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file == null:
		push_error("engine_licence: cannot write %s" % out)
		quit(1)
		return
	file.store_string("\n".join(lines) + "\n")
	print("engine_licence: %s" % out)
	quit()
