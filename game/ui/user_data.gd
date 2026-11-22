class_name UserData
extends RefCounted
## The player's own files (saves, settings, profile) under user://. Godot keeps them in a folder
## named after the game, so renaming the game (Dugout → Moneyball, 2026-11-22) would leave them
## behind in the old one: on the first start under the new name they are copied over, once.

const OLD_NAMES: Array[String] = ["Dugout"]
## What makes a user folder worth carrying over.
const OWN := ["saves", "settings.json", "profile.json"]


## Copies the old folder's files into user:// when user:// has none of its own yet. Returns
## the folder copied from, or "".
static func carry_over() -> String:
	var here := OS.get_user_data_dir()
	if _has_own(here):
		return ""
	for old: String in OLD_NAMES:
		var there := here.get_base_dir().path_join(old)
		if there != here and _has_own(there):
			copy_tree(there, here)
			return there
	return ""


static func _has_own(dir: String) -> bool:
	for name: String in OWN:
		var path := dir.path_join(name)
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
			return true
	return false


## Copies a folder's files and folders into another, keeping what is already there.
static func copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	var d := DirAccess.open(from)
	if d == null:
		return
	for file: String in d.get_files():
		var target := to.path_join(file)
		if not FileAccess.file_exists(target):
			DirAccess.copy_absolute(from.path_join(file), target)
	for sub: String in d.get_directories():
		copy_tree(from.path_join(sub), to.path_join(sub))
