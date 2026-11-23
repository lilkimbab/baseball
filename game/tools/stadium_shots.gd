extends SceneTree
## Photographs each ballpark from the views that matter: the batting view toward
## centre field, the pitching view toward home, high behind home, and from the outfield.
##
##   ./dev tool-win stadium_shots build/stadium/park [--park harbor_field]

var _prefix := "user://park"
var _parks := PackedStringArray()
var _scene: MatchScene
var _frames := 0
var _view := 0
var _cam: Camera3D
var _time := "day"
const VIEWS := ["bat", "pitch", "high", "outfield", "line", "board"]


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_prefix = args.get("out", _prefix)
	_parks = PackedStringArray([str(args["park"])]) if args.has("park") else StadiumIO.ids()
	_time = str(args.get("time", "day"))
	_cam = Camera3D.new()
	_cam.far = 900.0
	root.add_child.call_deferred(_cam)
	_load(0)


func _load(i: int) -> void:
	if _scene != null:
		_scene.queue_free()
	_scene = (load("res://match/match.tscn") as PackedScene).instantiate() as MatchScene
	_scene.human_team = -1
	_scene.innings = 3
	_scene.stadium_id = _parks[i]
	_scene.seed_value = 3
	_scene.time_of_day = StringName(_time)
	root.add_child(_scene)
	_frames = 0
	_view = 0


func _process(_delta: float) -> bool:
	_frames += 1
	# The park alone: none of the broadcast's cards over it, no HUD.
	if _scene.broadcast.current != null:
		_scene.broadcast.skip_all()
	for n: Node in _scene.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	if _frames < 20:
		return false
	var cam := _cam
	if VIEWS[_view] == "bat":
		_scene.camera.make_current()
	else:
		_cam.make_current()
	match VIEWS[_view]:
		"pitch":
			cam.look_at_from_position(Field.to_world(Vector3(1.0, 24.0, 2.4)), Field.to_world(Vector3(0.0, 0.0, 1.0)))
			cam.fov = 40.0
		"high":
			cam.look_at_from_position(Field.to_world(Vector3(0.0, -8.0, 30.0)), Field.to_world(Vector3(0.0, 70.0, 0.0)))
			cam.fov = 60.0
		"outfield":
			cam.look_at_from_position(Field.to_world(Vector3(20.0, 100.0, 8.0)), Field.to_world(Vector3(0.0, -10.0, 4.0)))
			cam.fov = 60.0
		"board":
			var face := _scene.park.find_child("Scoreboard", false, false) as Node3D
			if face != null:
				cam.look_at_from_position(Field.to_world(Vector3(0.0, 20.0, 8.0)), face.global_position)
				cam.fov = 22.0
		"line":
			cam.look_at_from_position(Field.to_world(Vector3(4.0, 30.0, 1.8)), Field.to_world(Vector3(26.0, 6.0, 0.5)))
			cam.fov = 60.0
	if _frames % 6 == 0:
		root.get_texture().get_image().save_png("%s_%s_%s_%s.png" % [_prefix, _parks[_parks.find(_scene.stadium_id)], _time, VIEWS[_view]])
		print("stadium_shots: %s %s" % [_scene.stadium_id, VIEWS[_view]])
		_view += 1
		if _view >= VIEWS.size():
			var next := _parks.find(_scene.stadium_id) + 1
			if next >= _parks.size():
				return true
			_load(next)
	return false
