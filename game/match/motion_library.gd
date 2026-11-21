class_name MotionLibrary
extends RefCounted
## Finds recorded motions. They live in the local content pack (content-local/animations/),
## which is not part of the repository: the motion-capture data they are made from may only
## be used non-commercially. Without the pack the game falls back to its own key poses.

static var _cache: Dictionary[String, JointClip] = {}


## The local content pack: content-local/ beside the game folder.
static func pack_root() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("content-local")


## A swing with the same batter's high and low swings attached, when the pack has them.
static func swing(form: StringName) -> SwingMotion:
	var main := find(&"swing", form)
	if main == null:
		return null
	var m := SwingMotion.new(main)
	m.high = find(&"swing", StringName(String(form) + "_high"))
	m.low = find(&"swing", StringName(String(form) + "_low"))
	return m


## The clip for a kind of motion (&"pitch", &"swing") and a form, or null if the pack has none.
static func find(kind: StringName, form: StringName = &"default") -> JointClip:
	var path := pack_root().path_join("animations/%s/%s.json" % [kind, form])
	if not _cache.has(path):
		_cache[path] = JointClip.load_file(path)
	return _cache[path]
