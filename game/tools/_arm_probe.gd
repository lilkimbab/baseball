extends SceneTree
var _scene: DuelScene
var _n := 0
func _initialize() -> void:
	_scene = (load("res://match/duel.tscn") as PackedScene).instantiate() as DuelScene
	_scene.mode = &"watch"
	root.add_child(_scene)
func _process(_d: float) -> bool:
	_n += 1
	if _n < 3:
		return false
	_scene.set_process(false)
	_scene.set_physics_process(false)
	var clip: JointClip = _scene.pitch_motion.clip
	var p: SkinnedPuppet = _scene.pitcher as SkinnedPuppet
	for name: String in ["knee_peak", "foot_plant", "max_layback", "release"]:
		var t: float = clip.events[StringName(name)]
		var fr := clip.sample(t)
		p.apply_joints(fr, clip)
		var rec_up := (fr[&"ThoraxTop"] - fr[&"ThoraxBottom"]).normalized()
		var rec_tilt := rad_to_deg(rec_up.angle_to(Vector3.UP))
		var mod_tilt := rad_to_deg(p.spine_dir.angle_to(Vector3.UP))
		var head: Vector3 = p.joints.get(&"Head", Vector3.ZERO)
		var hips: Vector3 = p.joints[&"Hips"]
		var rsh: Vector3 = p.joints[&"RightUpperArm"]
		var rhand: Vector3 = p.joints[&"RightHand"]
		var rel := fr[&"RightUpperArm"]
		var reh := fr[&"RightHand"]
		# The hand from the shoulder, in each trunk's own frame (x right, y up the spine, z back).
		var rec_frame := SkinnedPuppet._body_frame(fr[&"ThoraxRight"] - fr[&"ThoraxTop"], fr[&"ThoraxTop"] - fr[&"ThoraxBottom"], 0.0)
		var rec_local := rec_frame.inverse() * (reh - rel).normalized()
		var mod_local := p.chest_basis.inverse() * (rhand - rsh).normalized()
		var rec_mid := fr[&"LeftUpperArm"].lerp(fr[&"RightUpperArm"], 0.5)
		print("arm: %-11s t=%.3f trunk tilt recorded %.0f model %.0f | shoulder-mid height rec %.2f model %.2f | hips rec %.2f model %.2f" % [name, t, rec_tilt, mod_tilt, rec_mid.y, (p.joints[&"LeftUpperArm"] + rsh).y * 0.5, fr[&"LeftUpperLeg"].lerp(fr[&"RightUpperLeg"], 0.5).y, hips.y])
		print("arm:   hand from shoulder in trunk frame: recorded %s model %s" % [rec_local.snapped(Vector3.ONE * 0.01), mod_local.snapped(Vector3.ONE * 0.01)])
		var lsh: Vector3 = p.joints[&"LeftUpperArm"]
		var lel: Vector3 = p.joints[&"LeftLowerArm"]
		var lha: Vector3 = p.joints[&"LeftHand"]
		var rec_g := rec_frame.inverse() * (fr[&"LeftHand"] - fr[&"LeftUpperArm"])
		var mod_g := p.chest_basis.inverse() * (lha - lsh)
		var flex_rec := 180.0 - rad_to_deg((fr[&"LeftLowerArm"] - fr[&"LeftUpperArm"]).angle_to(fr[&"LeftHand"] - fr[&"LeftLowerArm"]))
		var flex_mod := 180.0 - rad_to_deg((lel - lsh).angle_to(lha - lel))
		print("arm:   glove from shoulder in trunk frame: recorded %s model %s | elbow flex rec %.0f model %.0f" % [rec_g.snapped(Vector3.ONE * 0.01), mod_g.snapped(Vector3.ONE * 0.01), flex_rec, flex_mod])
		# Where the shown hand bone is (the skeleton), against the solved joint.
		var shown := p.to_local(p.get_node("Skeleton3D").global_transform * Vector3.ZERO) if p.has_node("Skeleton3D") else Vector3.ZERO
		print("arm:   glove pocket %s, left hand joint %s, glove part visible %s at %s" % [p.glove_pocket().snapped(Vector3.ONE * 0.01), lha.snapped(Vector3.ONE * 0.01), p._parts[&"Glove"].visible, p.to_local(p._parts[&"Glove"].global_position).snapped(Vector3.ONE * 0.01)])
	return true
