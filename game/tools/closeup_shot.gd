extends SceneTree
## Photographs the batter in his follow-through from in front, with the catcher and umpire
## out of focus behind him: the same kind of shot as the reference still in
## reference/target-closeup.png, for side-by-side comparison of model and material quality.
##
##   godot --path game --script res://tools/closeup_shot.gd -- --out build/closeup.png
##
## Options: --out <file>  --swing <seconds after contact, default 0.2>
## With a recorded swing in the local content pack the batter is shown in that swing;
## otherwise in the hand-made follow-through pose.

var _scene: DuelScene
var _camera: Camera3D
var _out := "user://closeup.png"
var _swing_time := 0.2
var _frames := 0


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_out = args.get("out", _out)
	_swing_time = float(str(args.get("swing", "0.2")))
	_scene = (load("res://match/duel.tscn") as PackedScene).instantiate() as DuelScene
	_scene.mode = &"watch"
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		_compose()
	if _frames < 40:
		return false
	root.get_texture().get_image().save_png(_out)
	print("closeup_shot: ", _out)
	return true


func _compose() -> void:
	# Freeze the scene and pose everyone by hand.
	_scene.set_process(false)
	_scene.set_physics_process(false)
	_scene.hud.visible = false
	_scene.ball_actor.visible = false
	_scene.catcher.visible = true
	_scene.umpire.visible = true
	var batter := _scene.batter
	batter.look_at_world(Field.to_world(Vector3(25.0, 60.0, 22.0)))
	# Follow-through: hands finish high by the front shoulder with the bat across the back,
	# eyes following the ball.
	var motion := _scene.swing_motion
	if motion != null:
		batter.apply_joints(motion.clip.sample(motion.contact + _swing_time), motion.clip)
	else:
		var finish := PuppetClips.swing(_swing_time, 0.11, 0.85)
		finish.r_hand = PuppetPose.at(-0.14, 1.6, -0.1)
		finish.l_hand = PuppetPose.at(-0.19, 1.55, -0.08)
		finish.bat_dir = PuppetPose.at(0.9, 0.08, -0.42).normalized()
		batter.apply(finish)
	_scene.catcher.look_at_world(Field.to_world(Vector3(10.0, 40.0, 8.0)))
	_scene.catcher.apply(PuppetClips.catcher())
	_scene.umpire.look_at_world(Field.to_world(Vector3(10.0, 40.0, 8.0)))
	_scene.umpire.apply(PuppetClips.umpire())

	_camera = Camera3D.new()
	_camera.fov = 34.0
	var blur := CameraAttributesPractical.new()
	blur.dof_blur_far_enabled = true
	blur.dof_blur_far_distance = 3.5
	blur.dof_blur_far_transition = 1.4
	blur.dof_blur_amount = 0.11
	_camera.attributes = blur
	_scene.add_child(_camera)
	# In front of the batter on the pitcher's side, wherever in the box he stands.
	var stands := Field.to_field(batter.global_position)
	_camera.look_at_from_position(Field.to_world(stands + Vector3(0.5, 2.45, 1.5)), Field.to_world(stands + Vector3(0.2, -0.2, 1.38)))
	_camera.make_current()
