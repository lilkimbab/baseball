extends SceneTree
## Plays the recorded delivery and swing on the player model at 120 frames a second and
## reports how fast each bone turns. A recorded motion is smooth, so a bone that suddenly
## turns far in one frame points at a fault in how the recording is fitted to the model.
##
##   godot --headless --path game --script res://tools/motion_report.gd
##
## Options: --who pitch|swing|both (default both)   --limit <degrees per frame to list, default 30>

const RATE := 120.0

var _scene: DuelScene
var _limit := 30.0
var _who := "both"
var _frames := 0


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_limit = float(str(args.get("limit", "30")))
	_who = str(args.get("who", "both"))
	_scene = (load("res://match/duel.tscn") as PackedScene).instantiate() as DuelScene
	_scene.mode = &"watch"
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_scene.set_process(false)
	_scene.set_physics_process(false)
	if _scene.pitch_motion != null and _who != "swing":
		var motion := _scene.pitch_motion
		print("motion_report: delivery (%s), release at %.3f s, release point %s" % [motion.clip.source, motion.release_time, _scene.settings.release_point])
		_report(_scene.pitcher, motion.length(), func(t: float) -> void: _scene.pitcher.apply_joints(motion.frame(t), motion.clip))
	if _scene.swing_motion != null and _who != "pitch":
		var swing := _scene.swing_motion
		print("motion_report: swing (%s), stride %.3f launch %.3f contact %.3f finish %.3f" % [swing.clip.source, swing.stride, swing.launch, swing.contact, swing.finish])
		_report(_scene.batter, swing.clip.duration, func(t: float) -> void: _scene.batter.apply_joints(swing.clip.sample(t), swing.clip))
	if _scene.pitch_motion == null and _scene.swing_motion == null:
		print("motion_report: no recorded motion in the local content pack")
	return true


func _report(puppet: Puppet, length: float, pose: Callable) -> void:
	var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var count := skeleton.get_bone_count()
	var last: Array[Quaternion] = []
	var peak: Array[float] = []
	var peak_at: Array[float] = []
	last.resize(count)
	peak.resize(count)
	peak_at.resize(count)
	peak.fill(0.0)
	puppet.reset_motion()
	var steps := int(length * RATE)
	var lowest := 10.0
	for step: int in steps + 1:
		var t := step / RATE
		pose.call(t)
		for side: String in JointClip.SIDES:
			lowest = minf(lowest, puppet.joints[StringName(side + "Foot")].y)
		for bone: int in count:
			var now := skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
			if step > 0:
				var turned := rad_to_deg(last[bone].angle_to(now))
				if turned > peak[bone]:
					peak[bone] = turned
					peak_at[bone] = t
			last[bone] = now
	var order: Array[int] = []
	for bone: int in count:
		if peak[bone] >= _limit and not skeleton.get_bone_name(bone).contains("Proximal") and not skeleton.get_bone_name(bone).contains("Intermediate") \
				and not skeleton.get_bone_name(bone).contains("Distal") and not skeleton.get_bone_name(bone).contains("Metacarpal"):
			order.append(bone)
	order.sort_custom(func(a: int, b: int) -> bool: return peak[a] > peak[b])
	for bone: int in order:
		print("  %-16s turns %5.1f degrees in one frame at %.3f s" % [skeleton.get_bone_name(bone), peak[bone], peak_at[bone]])
	if order.is_empty():
		print("  no bone turns more than %.0f degrees in one frame" % _limit)
	print("  lowest ankle: %.3f m above the puppet's ground" % lowest)
