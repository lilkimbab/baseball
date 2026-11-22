extends GutTest
## The player's files follow the game to its new name (Dugout → Moneyball).

const BASE := "user://test_user_data"


func after_each() -> void:
	_remove(ProjectSettings.globalize_path(BASE))


func _remove(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f: String in d.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub: String in d.get_directories():
		_remove(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_the_old_folder_is_copied_without_overwriting() -> void:
	var root := ProjectSettings.globalize_path(BASE)
	var old := root.path_join("Dugout")
	var new := root.path_join("Moneyball")
	_write(old.path_join("settings.json"), "{\"music\": 0.3}")
	_write(old.path_join("saves/league_1.json"), "{}")
	_write(new.path_join("profile.json"), "{\"new\": true}")
	_write(old.path_join("profile.json"), "{\"old\": true}")
	UserData.copy_tree(old, new)
	assert_true(FileAccess.file_exists(new.path_join("settings.json")))
	assert_true(FileAccess.file_exists(new.path_join("saves/league_1.json")), "folders too")
	assert_eq(FileAccess.get_file_as_string(new.path_join("profile.json")), "{\"new\": true}", "what is there stays")
	assert_true(UserData._has_own(old))
	assert_false(UserData._has_own(root.path_join("nobody")))
