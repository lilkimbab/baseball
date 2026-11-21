extends SceneTree
## Plays the recorded delivery and swing on the player model at 120 frames a second and
## reports how fast each bone turns. A recorded motion is smooth, so a bone that suddenly
## turns far in one frame points at a fault in how the recording is fitted to the model.
##
##   godot --headless --path game --script res://tools/motion_report.gd
##
## Options: --who pitch|swing|both (default both)   --limit <degrees per frame to list, default 30>
##          --forms: every form in the local pack (content-local/forms/), each passing when no
##          bone turns more than the limit in one frame (swings: --limit, 45 in ./dev mocap forms, as the
##          wrists roll about 40 degrees a frame through contact; deliveries: --pitch-limit, default 70,
##          as a real arm whips through about 50 degrees a frame at release); the failing ones
##          are listed in content-local/forms/failing.txt for ./dev mocap forms to replace

const RATE := 120.0

var _scene: DuelScene
var _limit := 30.0
var _who := "both"
var _frames := 0
var _forms := false
var _pitch_limit := 70.0


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_limit = float(str(args.get("limit", "30")))
	_who = str(args.get("who", "both"))
	_forms = args.has("forms")
	_pitch_limit = float(str(args.get("pitch-limit", "70")))
	_scene = (load("res://match/duel.tscn") as PackedScene).instantiate() as DuelScene
	_scene.mode = &"watch"
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_scene.set_process(false)
	_scene.set_physics_process(false)
	if _forms:
		_report_forms()
		return true
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


## Every form of the pack in turn: pass or fail.
func _report_forms() -> void:
	var failed := 0
	var total := 0
	var failing := PackedStringArray()
	for f: FormCatalog.Form in FormCatalog.pitch_forms():
		_scene.set_motion(MotionLibrary.find(&"pitch", StringName(f.id)), null)
		var motion := _scene.pitch_motion
		var worst := _worst(_scene.pitcher, motion.length(), func(t: float) -> void: _scene.pitcher.apply_joints(motion.frame(t), motion.clip))
		total += 1
		if worst >= _pitch_limit:
			failed += 1
			failing.append(f.id)
		print("motion_report: %s %s  %s  worst %.1f°/frame  release %.3f s" % [f.id, f.name, "ok" if worst < _pitch_limit else "FAIL", worst, motion.release_time])
	for f: FormCatalog.Form in FormCatalog.swing_forms():
		for suffix: String in ["", "_high", "_low"]:
			_scene.set_motion(null, MotionLibrary.find(&"swing", StringName(f.id + suffix)))
			var swing := _scene.swing_motion
			var worst := _worst(_scene.batter, swing.clip.duration, func(t: float) -> void: _scene.batter.apply_joints(swing.clip.sample(t), swing.clip))
			total += 1
			if worst >= _limit:
				failed += 1
				failing.append(f.id + suffix)
			print("motion_report: %s%s %s  %s  worst %.1f°/frame" % [f.id, suffix, f.name, "ok" if worst < _limit else "FAIL", worst])
	print("motion_report: %d of %d clips pass (deliveries under %.0f, swings under %.0f degrees a frame)" % [total - failed, total, _pitch_limit, _limit])
	var path := MotionLibrary.pack_root().path_join("forms/failing.txt")
	if failing.is_empty():
		DirAccess.remove_absolute(path)
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string("\n".join(failing) + "\n")


## The fastest any body bone turns in one frame (fingers left out).
func _worst(puppet: Puppet, length: float, pose: Callable) -> float:
	var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var count := skeleton.get_bone_count()
	var last: Array[Quaternion] = []
	last.resize(count)
	puppet.reset_motion()
	var worst := 0.0
	for step: int in int(length * RATE) + 1:
		pose.call(step / RATE)
		for bone: int in count:
			var now := skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
			var name := skeleton.get_bone_name(bone)
			if step > 0 and not (name.contains("Proximal") or name.contains("Intermediate") or name.contains("Distal") or name.contains("Metacarpal")):
				worst = maxf(worst, rad_to_deg(last[bone].angle_to(now)))
			last[bone] = now
	return worst


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
