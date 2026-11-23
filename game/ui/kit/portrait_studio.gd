class_name PortraitStudio
extends Node
## Headshots for lists and cards (2K14 and The Show put a face beside every player's name):
## the menus' own 3D figure (PlayerStage) in his club's uniform, framed head and shoulders,
## drawn off screen one at a time and kept — in memory, and on disk (user://portraits/) so a
## roster opens with its faces the next time. A table asks for a face and gets it a few frames
## later through its callback (DataTable.set_portrait).
##
##   PortraitStudio.request(self, player, team, func(face: Texture2D) -> void: table.set_portrait(row, face))

## Raise when the figure changes (face, uniform, framing), so old pictures are drawn again.
const VERSION := 3
const SIDE := 160
## Frames to let a figure dress itself and its textures settle before the picture is taken.
const SETTLE := 3

static var _cache: Dictionary = {}
static var _studio: PortraitStudio

var _stage: PlayerStage
var _queue: Array = []
var _current: Array = []
var _wait := 0


## A face for a player in a club's uniform: at once if it is kept, else later.
static func request(holder: Node, p: Player, team: Team, done: Callable) -> void:
	if p == null or holder == null or not holder.is_inside_tree():
		return
	# Nothing is drawn without a screen (the tests run headless).
	if DisplayServer.get_name() == "headless":
		return
	var key := "%s_%s_%d" % [p.id, team.id if team != null else "none", VERSION]
	if _cache.has(key):
		done.call(_cache[key])
		return
	var disk := _disk_path(key)
	if FileAccess.file_exists(disk):
		var img := Image.load_from_file(disk)
		if img != null and not img.is_empty():
			var tex := ImageTexture.create_from_image(img)
			_cache[key] = tex
			done.call(tex)
			return
	if _studio == null or not is_instance_valid(_studio):
		_studio = PortraitStudio.new()
		# Not straight away: the screen asking is still being put together under the root.
		holder.get_tree().root.add_child.call_deferred(_studio)
	_studio._queue.append([key, p, team, done])


## How many faces are still to be drawn (the loading screen waits for a game's line-ups).
static func pending() -> int:
	if _studio == null or not is_instance_valid(_studio):
		return 0
	return _studio._queue.size() + (0 if _studio._current.is_empty() else 1)


## A picture box with the player's face, filled in when it is ready.
static func face(holder: Node, p: Player, team: Team, side: float = 64.0) -> TextureRect:
	var box := TextureRect.new()
	box.custom_minimum_size = Vector2(side, side)
	box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	box.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if p == null:
		return box
	box.texture = cached(p, team)
	if box.texture == null:
		# Asked once the box is in the tree (the studio hangs on the scene tree).
		box.ready.connect(func() -> void:
			request(box, p, team, func(tex: Texture2D) -> void:
				if is_instance_valid(box):
					box.texture = tex), CONNECT_ONE_SHOT)
	return box


static func cached(p: Player, team: Team) -> Texture2D:
	var key := "%s_%s_%d" % [p.id, team.id if team != null else "none", VERSION]
	return _cache.get(key)


static func _disk_path(key: String) -> String:
	return "user://portraits/%s.png" % key.md5_text()


func _ready() -> void:
	# Drawn off screen (a hidden viewport is not drawn at all).
	_stage = PlayerStage.make(SIDE, SIDE, PlayerStage.Framing.HEAD)
	_stage.turning = false
	_stage.position = Vector2(-4000.0, -4000.0)
	_stage.size = Vector2(SIDE, SIDE)
	add_child(_stage)
	DirAccess.make_dir_recursive_absolute("user://portraits")


func _process(_delta: float) -> void:
	if _current.is_empty():
		if _queue.is_empty():
			# Nothing to take: the figure is not drawn (a hidden viewport is not rendered —
			# in a game it would cost a frame's share for nothing).
			_stage.visible = false
			return
		_stage.visible = true
		_current = _queue.pop_front()
		if _cache.has(_current[0]):
			_finish(_cache[_current[0]])
			return
		_stage.show_player(_current[1], _current[2])
		_wait = SETTLE
		return
	_wait -= 1
	if _wait > 0:
		return
	var img := _stage.get_child(0).get_texture().get_image() as Image if _stage.get_child_count() > 0 else null
	if img == null or img.is_empty():
		_finish(null)
		return
	img.save_png(_disk_path(_current[0]))
	var tex := ImageTexture.create_from_image(img)
	_cache[_current[0]] = tex
	_finish(tex)


func _finish(tex: Texture2D) -> void:
	var done: Callable = _current[3]
	_current = []
	if tex != null and done.is_valid():
		done.call(tex)
