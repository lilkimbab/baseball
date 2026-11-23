class_name LocalContent
extends RefCounted
## Where the local content pack is (content-local/: recorded motions, real sounds and music, real
## seasons; never in git). Run from the project it is beside the game folder; an exported game
## sets `root` to the folder beside its executable as it starts (SplashScreen), since res:// is
## then inside the .pck and has no folder on disk.

static var root := ""


static func dir() -> String:
	if root != "":
		return root
	return ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("content-local")
