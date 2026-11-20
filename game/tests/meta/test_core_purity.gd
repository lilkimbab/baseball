extends GutTest
## Enforces the architecture rule from docs/07: everything under core/ is pure logic.
## It must not touch the scene tree, input, rendering, engine physics, wall-clock time or
## engine random numbers, so it can run headless and stay deterministic.

const CORE_DIR := "res://core"

## Substrings that must not appear in code (comments are stripped before checking).
const FORBIDDEN: Array[String] = [
	"extends Node",
	"Node3D",
	"SceneTree",
	"get_tree(",
	"Input.",
	"Engine.",
	"RenderingServer",
	"PhysicsServer",
	"DisplayServer",
	"AudioServer",
	"OS.",
	"Time.",
	"randf(",
	"randi(",
	"randf_range(",
	"randi_range(",
	"randfn(",
	"randomize(",
	"RandomNumberGenerator",
]


func _scripts_under(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for sub: String in dir.get_directories():
		found.append_array(_scripts_under(dir_path.path_join(sub)))
	for file: String in dir.get_files():
		if file.ends_with(".gd"):
			found.append(dir_path.path_join(file))
	return found


func _code_lines(path: String) -> Array[String]:
	var lines: Array[String] = []
	for raw: String in FileAccess.get_file_as_string(path).split("\n"):
		var hash_at := raw.find("#")
		lines.append(raw if hash_at < 0 else raw.substr(0, hash_at))
	return lines


func test_core_contains_scripts() -> void:
	assert_gt(_scripts_under(CORE_DIR).size(), 0, "core/ should not be empty")


func test_core_scripts_use_no_scene_engine_or_random_apis() -> void:
	var violations: Array[String] = []
	for path: String in _scripts_under(CORE_DIR):
		var lines := _code_lines(path)
		for i: int in lines.size():
			for token: String in FORBIDDEN:
				if lines[i].contains(token):
					violations.append("%s:%d uses '%s'" % [path, i + 1, token])
	assert_eq(violations, [] as Array[String], "core/ must stay free of scene and engine APIs")


func test_core_scripts_declare_a_class_name() -> void:
	var missing: Array[String] = []
	for path: String in _scripts_under(CORE_DIR):
		var declared := false
		for line: String in _code_lines(path):
			if line.begins_with("class_name "):
				declared = true
				break
		if not declared:
			missing.append(path)
	assert_eq(missing, [] as Array[String], "every core script needs a class_name")
