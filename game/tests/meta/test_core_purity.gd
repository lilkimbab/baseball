extends GutTest
## Enforces the architecture rule from docs/07: everything under core/ is pure logic.
## It must not touch the scene tree, input, rendering, engine physics, wall-clock time or
## engine random numbers, so it can run headless and stay deterministic.

const CORE_DIR := "res://core"

## Patterns that must not appear in code (comments are stripped before checking).
## Engine singletons are matched as whole words so names like "LAST_POS." do not trip them.
const FORBIDDEN: Array[String] = [
	"extends Node",
	"\\bNode3D\\b",
	"\\bSceneTree\\b",
	"\\bget_tree\\(",
	"\\bInput\\.",
	"\\bEngine\\.",
	"\\bOS\\.",
	"\\bTime\\.",
	"\\b(Rendering|Physics|Display|Audio)Server\\b",
	"\\b(randf|randi|randf_range|randi_range|randfn|randomize|seed)\\(",
	"\\bRandomNumberGenerator\\b",
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
	var patterns: Array[RegEx] = []
	for source: String in FORBIDDEN:
		patterns.append(RegEx.create_from_string(source))
	var violations: Array[String] = []
	for path: String in _scripts_under(CORE_DIR):
		var lines := _code_lines(path)
		for i: int in lines.size():
			for pattern: RegEx in patterns:
				var found := pattern.search(lines[i])
				if found != null:
					violations.append("%s:%d uses '%s'" % [path, i + 1, found.get_string()])
	assert_eq(violations, [] as Array[String], "core/ must stay free of scene and engine APIs")


func test_the_purity_patterns_catch_what_they_should() -> void:
	var bad: Array[String] = ["var x := randf()", "Engine.get_frames_per_second()", "extends Node3D", "OS.get_name()", "get_tree().quit()"]
	var fine: Array[String] = ["var last_pos := LAST_POS.x", "rng.next_float()", "extends RefCounted", "flight_time += dt", "push_error(\"x\")"]
	var patterns: Array[RegEx] = []
	for source: String in FORBIDDEN:
		patterns.append(RegEx.create_from_string(source))
	for line: String in bad:
		var caught := false
		for pattern: RegEx in patterns:
			caught = caught or pattern.search(line) != null
		assert_true(caught, "should be rejected: %s" % line)
	for line: String in fine:
		var caught := false
		for pattern: RegEx in patterns:
			caught = caught or pattern.search(line) != null
		assert_false(caught, "should be allowed: %s" % line)


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
