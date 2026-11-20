extends SceneTree
## Photographs the pitcher or the batter at chosen moments of a recorded motion, from a fixed
## camera, so a delivery or a swing can be checked frame by frame against reference footage.
##
##   godot --path game --script res://tools/motion_shots.gd -- --who pitch --out build/motion/pitch
##
## Options: --who pitch|swing   --out <path prefix>   --view side|front|back|plate
##          --times <comma-separated seconds; default: a spread over the whole motion>
##          --reach <metres up> (swing only: raise the hands, as for a high pitch)
##          --eye x,y,z --centre x,y,z --fov <degrees>   camera in the player's own terms:
##          metres to his right, above the ground, and behind him (in front is negative)

var _scene: DuelScene
var _camera: Camera3D
var _who := "pitch"
var _view := "side"
var _prefix := "user://motion"
var _times: Array[float] = []
var _reach := 0.0
var _args: Dictionary = {}
var _frames := 0
var _index := 0


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_args = args
	_who = str(args.get("who", _who))
	_view = str(args.get("view", _view))
	_prefix = str(args.get("out", _prefix))
	_reach = float(str(args.get("reach", "0")))
	for part: String in str(args.get("times", "")).split(",", false):
		_times.append(float(part))
	_scene = (load("res://match/duel.tscn") as PackedScene).instantiate() as DuelScene
	_scene.mode = &"watch"
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		if not _compose():
			return true
	if _frames < 12 or (_frames - 12) % 6 != 0:
		return false
	# Every sixth frame: save the pose shown since the last one, then show the next.
	if _index > 0:
		var path := "%s_%s_%02d.png" % [_prefix, _view, _index - 1]
		root.get_texture().get_image().save_png(path)
		print("motion_shots: %s  t=%.3f" % [path, _times[_index - 1]])
	if _index >= _times.size():
		return true
	_pose(_times[_index])
	_index += 1
	return false


func _compose() -> bool:
	_scene.set_process(false)
	_scene.set_physics_process(false)
	_scene.hud.visible = false
	_scene.ball_actor.visible = false
	var clip: JointClip = null
	if _who == "pitch" and _scene.pitch_motion != null:
		clip = _scene.pitch_motion.clip
	elif _who == "swing" and _scene.swing_motion != null:
		clip = _scene.swing_motion.clip
	if clip == null:
		print("motion_shots: no recorded %s in the local content pack" % _who)
		return false
	if _times.is_empty():
		for i: int in 12:
			_times.append(clip.duration * i / 11.0)
	print("motion_shots: %s, %.2f s, events %s" % [clip.source, clip.duration, clip.events])

	# Cameras are given in the player's own terms: to his right, above the ground, in front.
	var subject: Puppet = _scene.pitcher if _who == "pitch" else _scene.batter
	var centre := Vector3(0.0, 0.95, -0.75) if _who == "pitch" else Vector3(0.0, 0.95, -0.2)
	var eye := Vector3(5.6, 1.3, -0.75)
	match _view:
		"front":
			eye = Vector3(0.0, 1.3, -6.5)
		"back":
			eye = Vector3(0.0, 1.5, 5.5)
		"plate":
			# From where the other player stands: the batter's view of the pitcher, or the
			# pitcher's view of the batter.
			eye = Vector3(0.6, 1.2, -9.0) if _who == "pitch" else Vector3(-7.0, 1.3, -0.6)
		"left":
			eye = Vector3(-5.6, 1.3, -0.75)
	if _who == "swing" and _view == "side":
		eye = Vector3(4.6, 1.2, -0.2)
	if _args.has("eye"):
		eye = _vector(str(_args["eye"]))
	if _args.has("centre"):
		centre = _vector(str(_args["centre"]))
	_camera = Camera3D.new()
	_camera.fov = float(str(_args.get("fov", "30")))
	_scene.add_child(_camera)
	_camera.look_at_from_position(subject.global_transform * eye, subject.global_transform * centre)
	_camera.make_current()
	_scene.catcher.visible = false
	_scene.umpire.visible = false
	return true


func _pose(time: float) -> void:
	if _who == "pitch":
		_scene.pitcher.right_grip = Puppet.Grip.BALL if time < _scene.pitch_motion.release_time else Puppet.Grip.RELAXED
		_scene.pitcher.look_at_world(Field.to_world(Vector3(0.0, 0.3, 0.9)))
		# Pose the instant before as well: how a moving hand is turned depends on its speed.
		_scene.pitcher.frame_time = 1.0 / 60.0
		_scene.pitcher.reset_motion()
		_scene.pitcher.apply_joints(_scene.pitch_motion.frame(time - 1.0 / 60.0), _scene.pitch_motion.clip)
		_scene.pitcher.apply_joints(_scene.pitch_motion.frame(time), _scene.pitch_motion.clip)
		_scene.ball_actor.visible = time > 0.0 and time < _scene.pitch_motion.release_time + 0.004
		_scene.ball_actor.show_at(Field.to_field(_scene.pitcher.global_transform * _scene.pitcher.ball_spot(&"RightHand")))
		_scene.ball_actor.visible = time > 0.0 and time < _scene.pitch_motion.release_time + 0.004
	else:
		var motion := _scene.swing_motion
		var weight := smoothstep(motion.launch - 0.03, motion.contact, time) * (1.0 - smoothstep(motion.contact, motion.contact + 0.22, time))
		_scene.batter.look_at_world(Field.to_world(_scene.settings.release()))
		_scene.batter.apply_joints(motion.clip.sample(time), motion.clip, Vector3(0.0, _reach, 0.0) * weight)


static func _vector(text: String) -> Vector3:
	var parts := text.split_floats(",")
	return Vector3(parts[0], parts[1], parts[2])
