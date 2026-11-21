extends SceneTree
## Photographs every kind of backdrop (or every park) without playing a game: a park is built
## with its lights and sky, and looked at from the plate toward centre field and from high
## behind home.
##
##   ./dev tool-win backdrop_shots build/backdrops/b [--park grand_park] [--only harbour,beach] [--time night]
##   ./dev tool-win backdrop_shots build/parks/p --parks      (every park, with its own backdrop)

var _prefix := "user://backdrop"
var _items: Array[Array] = []
var _index := -1
var _frames := 0
var _view := 0
var _root: Node3D
var _camera: Camera3D
var _time: StringName = &"day"
const VIEWS := ["plate", "high"]


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_prefix = str(args.get("out", _prefix))
	_time = StringName(str(args.get("time", "day")))
	var park := str(args.get("park", "grand_park"))
	if args.has("parks"):
		for id: String in StadiumIO.ids():
			_items.append([id, ""])
	else:
		var kinds := PackedStringArray(str(args["only"]).split(",")) if args.has("only") else PackedStringArray()
		for kind: StringName in Backdrop.KINDS:
			if kinds.is_empty() or kinds.has(String(kind)):
				_items.append([park, String(kind)])
	_next()


func _next() -> void:
	if _root != null:
		_root.queue_free()
	_index += 1
	_frames = 0
	_view = 0
	if _index >= _items.size():
		quit()
		return
	var def := StadiumIO.load_park(str(_items[_index][0]))
	if str(_items[_index][1]) != "":
		def.backdrop = StringName(str(_items[_index][1]))
	_root = Node3D.new()
	root.add_child(_root)
	var park := StadiumBuilder.new(def)
	_root.add_child(park)
	var lighting := ParkLighting.new(def, _time)
	_root.add_child(lighting)
	park.set_lights(lighting.lights_on(), lighting.darkness())
	var crowd := Crowd.new(park)
	crowd.fill = 0.85
	_root.add_child(crowd)
	_camera = Camera3D.new()
	_camera.far = 4000.0
	_root.add_child(_camera)
	_camera.make_current()


func _process(_delta: float) -> bool:
	if _root == null:
		return false
	_frames += 1
	if _frames == 2:
		if VIEWS[_view] == "plate":
			_camera.fov = 52.0
			_camera.look_at_from_position(Field.to_world(Vector3(1.5, -6.0, 3.2)), Field.to_world(Vector3(0.0, 130.0, 22.0)))
		else:
			_camera.fov = 62.0
			_camera.look_at_from_position(Field.to_world(Vector3(0.0, -70.0, 85.0)), Field.to_world(Vector3(0.0, 160.0, 0.0)))
	if _frames < 26:
		return false
	var label := str(_items[_index][1]) if str(_items[_index][1]) != "" else str(_items[_index][0])
	var path := "%s_%s_%s.png" % [_prefix, label, VIEWS[_view]]
	root.get_texture().get_image().save_png(path)
	print("backdrop_shots: ", path)
	_view += 1
	_frames = 0
	if _view >= VIEWS.size():
		_next()
	return false
