class_name MotionLibrary
extends RefCounted
## Finds recorded motions. They live in the local content pack (content-local/animations/),
## which is not part of the repository: the motion-capture data they are made from may only
## be used non-commercially. Without the pack the game falls back to its own key poses.

static var _cache: Dictionary[String, JointClip] = {}


## The local content pack: content-local/ beside the game folder.
static func pack_root() -> String:
	return LocalContent.dir()


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


## Reads these clips ([kind, form] pairs: a game's line-ups, as it loads) on a worker thread and
## keeps them: a man's clips read when he first came up stalled the game 50-90 ms (the user,
## 2026-11-23: "it stutters a little").
static func warm(keys: Array) -> void:
	var paths := PackedStringArray()
	for k: Array in keys:
		var path := pack_root().path_join("animations/%s/%s.json" % [k[0], k[1]])
		if not _cache.has(path) and not paths.has(path):
			paths.append(path)
	if paths.is_empty():
		return
	WorkerThreadPool.add_task(func() -> void:
		var loaded: Dictionary = {}
		for path: String in paths:
			loaded[path] = JointClip.load_file(path)
		MotionLibrary._take.call_deferred(loaded))


static func _take(loaded: Dictionary) -> void:
	for path: String in loaded:
		if not _cache.has(path):
			_cache[path] = loaded[path]
