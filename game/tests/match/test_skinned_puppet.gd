extends GutTest
## The skinned player model must follow the same poses as the mannequin.


func _model() -> SkinnedPuppet:
	var puppet := SkinnedPuppet.new()
	add_child_autofree(puppet)
	return puppet


func test_model_asset_is_available() -> void:
	assert_true(SkinnedPuppet.available(), "run ./dev model to build the player model")


func test_proportions_are_measured_from_the_model() -> void:
	var puppet := _model()
	assert_between(puppet.upper_arm, 0.20, 0.34, "upper arm (m)")
	assert_between(puppet.lower_arm, 0.20, 0.32, "forearm (m)")
	assert_between(puppet.upper_leg, 0.35, 0.50, "thigh (m)")
	assert_between(puppet.lower_leg, 0.35, 0.48, "shin (m)")
	assert_between(puppet.shoulder_half, 0.14, 0.23, "half shoulder width (m)")
	assert_between(puppet.spine, 0.42, 0.62, "hip to shoulder line (m)")


func test_hands_and_feet_land_on_reachable_targets() -> void:
	var puppet := _model()
	var pose := PuppetClips.fielder_ready()
	# The key poses were drawn for the mannequin's longer arms; use a target this model reaches.
	pose.r_hand = PuppetPose.at(0.28, 1.0, 0.3)
	puppet.apply(pose)
	var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var to_puppet := puppet.global_transform.affine_inverse() * skeleton.global_transform
	var wrist := to_puppet * skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin
	var ankle := to_puppet * skeleton.get_bone_global_pose(skeleton.find_bone("LeftFoot")).origin
	assert_lt(wrist.distance_to(pose.r_hand), 0.01, "right wrist is at its target")
	assert_lt(ankle.distance_to(pose.l_foot), 0.01, "left ankle is at its target")


func test_pelvis_follows_the_pose() -> void:
	var puppet := _model()
	var pose := PuppetClips.catcher()
	puppet.apply(pose)
	var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var to_puppet := puppet.global_transform.affine_inverse() * skeleton.global_transform
	var left := to_puppet * skeleton.get_bone_global_pose(skeleton.find_bone("LeftUpperLeg")).origin
	var right := to_puppet * skeleton.get_bone_global_pose(skeleton.find_bone("RightUpperLeg")).origin
	assert_lt(left.lerp(right, 0.5).distance_to(pose.hips), 0.03, "hip joints are centred on the pose's hips")
	assert_lt(pose.hips.y, 0.6, "the catcher is crouching")


func test_every_bone_stays_finite_through_the_delivery_and_the_swing() -> void:
	var puppet := _model()
	var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var ok := true
	for step: int in 22:
		puppet.apply(PuppetClips.pitch(step * 0.1))
		for bone: int in skeleton.get_bone_count():
			ok = ok and skeleton.get_bone_global_pose(bone).is_finite()
	for step: int in 16:
		puppet.apply(PuppetClips.swing(-0.15 + step * 0.05, 0.11, 0.8))
		for bone: int in skeleton.get_bone_count():
			ok = ok and skeleton.get_bone_global_pose(bone).is_finite()
	assert_true(ok, "no NaN or infinite bone transforms")


func test_bones_keep_their_length() -> void:
	var puppet := _model()
	var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	puppet.apply(PuppetClips.pitch(PuppetClips.PITCH_RELEASE))
	var to_puppet := puppet.global_transform.affine_inverse() * skeleton.global_transform
	var elbow := to_puppet * skeleton.get_bone_global_pose(skeleton.find_bone("RightLowerArm")).origin
	var shoulder := to_puppet * skeleton.get_bone_global_pose(skeleton.find_bone("RightUpperArm")).origin
	var wrist := to_puppet * skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin
	assert_almost_eq(shoulder.distance_to(elbow), puppet.upper_arm, 0.003, "posing must not stretch the arm")
	assert_almost_eq(elbow.distance_to(wrist), puppet.lower_arm, 0.003)


func test_team_colours_are_applied_to_the_uniform() -> void:
	var puppet := SkinnedPuppet.new()
	puppet.set_colors(Color(0.2, 0.3, 0.8), Color(0.9, 0.9, 0.9), Color(0.8, 0.1, 0.1))
	add_child_autofree(puppet)
	assert_eq(puppet.uniform.jersey, Color(0.2, 0.3, 0.8))
	var plain := {}
	var textured := {}
	for mesh: MeshInstance3D in puppet.find_children("*", "MeshInstance3D", true, false):
		for surface: int in mesh.mesh.get_surface_count():
			var material := mesh.get_surface_override_material(surface) as StandardMaterial3D
			if material == null:
				continue
			var source := mesh.mesh.surface_get_material(surface).resource_name
			plain[source] = material.albedo_color
			textured[source] = material.albedo_texture != null
	assert_eq(plain["Cap"], Color(0.8, 0.1, 0.1))
	assert_eq(plain["Helmet"], Color(0.8, 0.1, 0.1))
	assert_eq(plain["Socks"], Color(0.8, 0.1, 0.1))
	assert_true(textured["Jersey"] and textured["Pants"], "cloth is painted into a texture")
	assert_true(plain.has("Shoes") and plain.has("Belt"))


func test_model_has_separate_clothes_shoes_and_a_face() -> void:
	var puppet := _model()
	for part: String in ["Body", "Jersey", "Pants", "Shoes", "Cap", "Helmet", "Eyes", "Eyebrows"]:
		assert_not_null(puppet.find_child(part, true, false), "missing %s" % part)


func test_catchers_gear_is_only_shown_when_worn() -> void:
	var puppet := _model()
	puppet.apply(PuppetClips.catcher())
	for piece: String in ["Mask", "ChestProtector", "ShinGuards"]:
		assert_false((puppet.find_child(piece, true, false) as MeshInstance3D).visible, "%s hidden by default" % piece)
	puppet.gear = [&"Mask", &"ChestProtector", &"ShinGuards"]
	puppet.apply(PuppetClips.catcher())
	for piece: String in ["Mask", "ChestProtector", "ShinGuards"]:
		assert_true((puppet.find_child(piece, true, false) as MeshInstance3D).visible, "%s shown on the catcher" % piece)
	assert_not_null(puppet.find_child("Collar", true, false), "the jersey has a collar band")


func test_batting_gloves_cover_the_hands() -> void:
	var puppet := _model()
	var body := puppet.find_child("Body", true, false) as MeshInstance3D
	var hands := -1
	for surface: int in body.mesh.get_surface_count():
		if body.mesh.surface_get_material(surface).resource_name == "Hands":
			hands = surface
	assert_gt(hands, -1, "the hands are their own surface")
	var bare := body.get_surface_override_material(hands) as StandardMaterial3D
	assert_not_null(bare.albedo_texture, "bare hands keep the skin texture")
	assert_eq(bare.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "and skin is drawn solid")
	puppet.gloves = true
	puppet.repaint()
	var glove := body.get_surface_override_material(hands) as StandardMaterial3D
	assert_lt(glove.albedo_color.v, 0.2, "gloves are dark")


func test_headgear_switches_between_cap_and_helmet() -> void:
	var puppet := _model()
	var cap := puppet.find_child("Cap", true, false) as MeshInstance3D
	var helmet := puppet.find_child("Helmet", true, false) as MeshInstance3D
	puppet.apply(PuppetClips.stance())
	assert_true(cap.visible and not helmet.visible, "a cap by default")
	puppet.headgear = &"helmet"
	puppet.apply(PuppetClips.stance())
	assert_true(helmet.visible and not cap.visible)


func test_a_bat_grip_closes_the_fingers() -> void:
	var puppet := _model()
	var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var wrist := skeleton.find_bone("RightHand")
	var tip := skeleton.find_bone("RightMiddleDistal")
	puppet.apply(PuppetClips.stance())
	var open_reach := skeleton.get_bone_global_pose(wrist).origin.distance_to(skeleton.get_bone_global_pose(tip).origin)
	puppet.right_grip = Puppet.Grip.BAT
	puppet.apply(PuppetClips.stance())
	var closed_reach := skeleton.get_bone_global_pose(wrist).origin.distance_to(skeleton.get_bone_global_pose(tip).origin)
	assert_lt(closed_reach, open_reach * 0.8, "fingertips come back toward the wrist in a fist")
	assert_gt(closed_reach, 0.02, "but the hand does not collapse")


func test_head_turns_toward_what_the_player_is_watching() -> void:
	var puppet := _model()
	var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var to_puppet := puppet.global_transform.affine_inverse() * skeleton.global_transform
	var head := skeleton.find_bone("Head")
	var rest_forward := skeleton.get_bone_global_rest(head).basis.inverse() * Vector3.BACK
	# Something off to the puppet's left at head height.
	puppet.look_target = Vector3(-5.0, 1.6, -1.0)
	puppet.has_look_target = true
	puppet.apply(PuppetClips.stance())
	var facing := to_puppet.basis * (skeleton.get_bone_global_pose(head).basis * rest_forward)
	assert_lt(facing.x, -0.5, "the face points to the left")
	puppet.look_target = Vector3(5.0, 1.6, -1.0)
	puppet.apply(PuppetClips.stance())
	facing = to_puppet.basis * (skeleton.get_bone_global_pose(head).basis * rest_forward)
	assert_gt(facing.x, 0.5, "and to the right")


func test_name_number_and_team_word_are_painted_on_the_jersey() -> void:
	var puppet := _model()
	puppet.uniform.wordmark = "Harbor"
	puppet.set_back_lettering(18, "서강민")
	var jersey := puppet.find_child("Jersey", true, false) as MeshInstance3D
	var art := jersey.get_node("Art").get_child(0) as UniformArt
	assert_eq(art.style.number, 18)
	assert_eq(art.style.player_name, "서강민")
	assert_eq(art.style.wordmark, "Harbor")
	var viewport := jersey.get_node("Art") as SubViewport
	assert_almost_eq(float(viewport.size.x) / viewport.size.y, 2.0 * art.half_size.x / art.half_size.y, 0.05, "texture matches the garment so letters are not stretched")


# --- Recorded motion (apply_joints) ---


func _bone_at(puppet: SkinnedPuppet, bone: String) -> Vector3:
	var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var to_puppet := puppet.global_transform.affine_inverse() * skeleton.global_transform
	return to_puppet * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin


func _still(frame: Dictionary[StringName, Vector3]) -> JointClip:
	var frames: Array[Dictionary] = [frame, frame]
	return JointClip.from_frames(frames, 60.0)


func test_the_model_is_scaled_to_the_players_height() -> void:
	var tall := SkinnedPuppet.new()
	tall.height = 1.95
	add_child_autofree(tall)
	var short := SkinnedPuppet.new()
	short.height = 1.7
	add_child_autofree(short)
	assert_almost_eq(tall.upper_leg / short.upper_leg, 1.95 / 1.7, 0.01, "legs scale with height")
	assert_almost_eq(tall.upper_arm / short.upper_arm, 1.95 / 1.7, 0.01, "and arms")
	var body := tall.find_child("Body", true, false) as MeshInstance3D
	var top := (tall.global_transform.affine_inverse() * body.global_transform * Vector3(0.0, SkinnedPuppet.mesh_top(body.mesh), 0.0)).y
	assert_almost_eq(top, 1.95, 0.01, "the top of the head is at the player's height")


func test_recorded_feet_stay_on_the_ground_where_they_stood() -> void:
	var puppet := _model()
	var frame := SyntheticMotion.squat()
	var clip := _still(SyntheticMotion.standing())
	puppet.apply_joints(frame, clip)
	var scale := (puppet.upper_leg + puppet.lower_leg) / clip.leg_length
	for side: String in ["Left", "Right"]:
		var ankle := _bone_at(puppet, side + "Foot")
		var recorded: Vector3 = frame[StringName(side + "Foot")]
		assert_almost_eq(ankle.y, _bone_at(puppet, side + "Foot").y, 0.001)
		assert_almost_eq(Vector2(ankle.x, ankle.z), Vector2(recorded.x, recorded.z) * scale, Vector2.ONE * 0.01, "%s foot keeps its place, scaled to the model's legs" % side)
	puppet.apply(PuppetClips.fielder_ready())
	var standing_ankle := _bone_at(puppet, "LeftFoot").y
	puppet.apply_joints(frame, clip)
	assert_almost_eq(_bone_at(puppet, "LeftFoot").y, standing_ankle, 0.02, "a recorded standing ankle sits at the model's ankle height")


func test_recorded_knees_bend_forward_and_elbows_toward_their_recorded_side() -> void:
	var puppet := _model()
	puppet.apply_joints(SyntheticMotion.squat(), _still(SyntheticMotion.standing()))
	for side: String in ["Left", "Right"]:
		var hip := _bone_at(puppet, side + "UpperLeg")
		var knee := _bone_at(puppet, side + "LowerLeg")
		var ankle := _bone_at(puppet, side + "Foot")
		assert_lt(knee.z, minf(hip.z, ankle.z) - 0.1, "%s knee is in front of the hip and the ankle" % side)
	puppet.apply_joints(SyntheticMotion.release(), _still(SyntheticMotion.standing()))
	var shoulder := _bone_at(puppet, "RightUpperArm")
	var elbow := _bone_at(puppet, "RightLowerArm")
	var wrist := _bone_at(puppet, "RightHand")
	assert_gt(wrist.y, elbow.y, "throwing hand above the elbow")
	assert_gt(elbow.y, shoulder.y, "elbow above the shoulder, as recorded")
	assert_lt(wrist.z, shoulder.z - 0.2, "and the hand out in front")


func test_bones_keep_their_length_and_stay_finite_through_recorded_motion() -> void:
	var puppet := _model()
	var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var ok := true
	var worst := 0.0
	for clip: JointClip in [SyntheticMotion.pitch_clip(), SyntheticMotion.swing_clip()] as Array[JointClip]:
		puppet.reset_motion()
		for step: int in roundi(clip.duration * 60.0) + 1:
			puppet.apply_joints(clip.sample(step / 60.0), clip)
			for bone: int in skeleton.get_bone_count():
				ok = ok and skeleton.get_bone_global_pose(bone).is_finite()
			for side: String in ["Left", "Right"]:
				worst = maxf(worst, absf(_bone_at(puppet, side + "UpperArm").distance_to(_bone_at(puppet, side + "LowerArm")) - puppet.upper_arm))
				worst = maxf(worst, absf(_bone_at(puppet, side + "LowerLeg").distance_to(_bone_at(puppet, side + "Foot")) - puppet.lower_leg))
	assert_true(ok, "no NaN or infinite bone transforms")
	assert_lt(worst, 0.003, "fitting a recording must not stretch arms or legs")


func test_the_trunk_and_feet_turn_with_the_recorded_body() -> void:
	var puppet := _model()
	var clip := _still(SyntheticMotion.standing())
	puppet.apply_joints(SyntheticMotion.standing(), clip)
	var ahead := _bone_at(puppet, "LeftToes") - _bone_at(puppet, "LeftFoot")
	assert_lt(ahead.z, -0.05, "standing as recorded, toes point forward")
	# The same player turned a quarter turn to his left, as a pitcher stands in the stretch.
	puppet.reset_motion()
	puppet.apply_joints(SyntheticMotion.turned(SyntheticMotion.standing(), PI / 2.0), clip)
	var turned := _bone_at(puppet, "LeftToes") - _bone_at(puppet, "LeftFoot")
	assert_lt(turned.x, -0.05, "toes follow the body round")
	assert_almost_eq(turned.z, 0.0, 0.04)
	var across := _bone_at(puppet, "RightUpperArm") - _bone_at(puppet, "LeftUpperArm")
	assert_lt(across.z, -0.2, "and so do the shoulders")


func test_two_hands_on_a_bat_stay_together_and_the_bat_follows_the_recording() -> void:
	var puppet := _model()
	puppet.show_bat = true
	puppet.left_grip = Puppet.Grip.BAT
	puppet.right_grip = Puppet.Grip.BAT
	var clip := _still(SyntheticMotion.standing())
	for frame: Dictionary[StringName, Vector3] in [SyntheticMotion.stance(), SyntheticMotion.contact()] as Array[Dictionary]:
		puppet.apply_joints(frame, clip)
		var recorded: float = frame[&"LeftHand"].distance_to(frame[&"RightHand"])
		var apart := _bone_at(puppet, "LeftHand").distance_to(_bone_at(puppet, "RightHand"))
		assert_almost_eq(apart, recorded * (puppet.upper_arm + puppet.lower_arm) / clip.arm_length, 0.02, "wrists as far apart as recorded")
		assert_lt(puppet.joints[&"LeftHand"].distance_to(puppet.joints[&"RightHand"]), 0.16, "both hands on the handle")
		assert_almost_eq(puppet.bat_dir, Puppet.bat_direction(frame), Vector3.ONE * 1e-4)
		var along := (puppet.sweet_spot() - puppet.bat_grip).normalized()
		assert_almost_eq(along, puppet.bat_dir, Vector3.ONE * 1e-4, "the sweet spot lies along the bat")


func test_moving_the_hands_moves_the_bat_by_the_same_amount() -> void:
	var puppet := _model()
	puppet.show_bat = true
	var clip := SyntheticMotion.swing_clip()
	puppet.apply_joints(SyntheticMotion.contact(), clip)
	var before := puppet.sweet_spot()
	var reach := Vector3(0.0, 0.12, -0.08)
	puppet.apply_joints(SyntheticMotion.contact(), clip, reach)
	assert_almost_eq(puppet.sweet_spot() - before, reach, Vector3.ONE * 0.03, "a swing at a higher, farther pitch")


func test_the_head_watches_its_target_when_the_recorded_trunk_is_turned() -> void:
	var puppet := _model()
	var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var to_puppet := puppet.global_transform.affine_inverse() * skeleton.global_transform
	var head := skeleton.find_bone("Head")
	var rest_forward := skeleton.get_bone_global_rest(head).basis.inverse() * Vector3.BACK
	puppet.look_target = Vector3(0.0, 1.6, -18.0)
	puppet.has_look_target = true
	# Trunk turned 60 degrees to the left: the head turns back to keep looking straight ahead.
	puppet.apply_joints(SyntheticMotion.turned(SyntheticMotion.standing(), deg_to_rad(60.0)), _still(SyntheticMotion.standing()))
	var facing := (to_puppet.basis * (skeleton.get_bone_global_pose(head).basis * rest_forward)).normalized()
	assert_lt(facing.z, -0.95, "the face points at the target")


func test_the_mannequin_shows_recorded_joints_as_they_are() -> void:
	var puppet := Puppet.new()
	add_child_autofree(puppet)
	var frame := SyntheticMotion.release()
	puppet.apply_joints(frame, SyntheticMotion.pitch_clip())
	assert_eq(puppet.joints[&"RightHand"], frame[&"RightHand"])
	assert_eq(puppet.joints[&"LeftFoot"], frame[&"LeftFoot"])
	assert_almost_eq(puppet.joints[&"Hips"], frame[&"LeftUpperLeg"].lerp(frame[&"RightUpperLeg"], 0.5), Vector3.ONE * 1e-5)


# --- Real sizes ---


func test_limbs_are_in_proportion_to_height() -> void:
	var puppet := _model()
	var arm := (puppet.upper_arm + puppet.lower_arm) / puppet.height
	var leg := (puppet.upper_leg + puppet.lower_leg) / puppet.height
	assert_between(arm, 0.305, 0.33, "shoulder to wrist is about 31.6% of height")
	assert_between(leg, 0.48, 0.505, "hip to ankle is about 49.2% of height")
	assert_between(puppet.shoulder_half * 2.0 / puppet.height, 0.19, 0.23, "shoulder joints about a fifth of height apart")


func test_equipment_is_real_size() -> void:
	var puppet := _model()
	puppet.show_bat = true
	puppet.apply(PuppetClips.stance())
	var bat := (puppet.get("_parts") as Dictionary)[&"Bat"] as MeshInstance3D
	var bat_box := bat.mesh.get_aabb().size
	assert_almost_eq(bat_box.y, 0.851, 0.003, "a 33.5 in bat")
	assert_almost_eq(bat_box.x, 0.0662, 0.002, "2.61 in barrel")
	puppet.show_bat = false
	puppet.apply(PuppetClips.fielder_ready())
	var glove := (puppet.get("_parts") as Dictionary)[&"Glove"] as MeshInstance3D
	assert_almost_eq(glove.mesh.get_aabb().size.y, 0.305, 0.004, "a 12 in glove")
	puppet.glove_kind = &"mitt"
	puppet.apply(PuppetClips.catcher())
	assert_almost_eq(glove.mesh.get_aabb().size.y, 0.33, 0.004, "a catcher's mitt")
	assert_gt(glove.mesh.get_aabb().size.x, 0.26, "which is rounder than a fielder's glove")


func test_the_ball_is_drawn_at_its_real_size() -> void:
	var ball := BallActor.new()
	add_child_autofree(ball)
	var sphere := (ball.get_child(0) as MeshInstance3D).mesh as SphereMesh
	assert_almost_eq(sphere.radius * 2.0, 0.0732, 0.0005, "73 mm across")


func test_a_held_ball_sits_in_the_fingers_not_inside_the_hand() -> void:
	var puppet := _model()
	puppet.right_grip = Puppet.Grip.BALL
	puppet.apply(PuppetClips.pitch(PuppetClips.PITCH_RELEASE))
	var knuckle := _bone_at(puppet, "RightMiddleProximal")
	var ball := puppet.ball_spot(&"RightHand")
	assert_between(ball.distance_to(knuckle), 0.04, 0.07, "one ball radius and a finger's thickness from the knuckles")


func test_head_size_and_belt_height_are_in_proportion() -> void:
	var puppet := _model()
	var body := puppet.find_child("Body", true, false) as MeshInstance3D
	var eyes := puppet.find_child("Eyes", true, false) as MeshInstance3D
	var pants := puppet.find_child("Pants", true, false) as MeshInstance3D
	var top := SkinnedPuppet.mesh_top(body.mesh)
	# Eyes sit a little above the middle of the head, so top-to-eyes is about 0.54 of the head
	# height. A grown man is 7.5 to 8.2 head-heights tall.
	var eyes_down := (top - eyes.get_aabb().get_center().y) / top
	assert_between(eyes_down, 0.54 / 8.2, 0.54 / 7.5, "head size: top of the head to the eyes")
	# Baseball trousers are worn on the hips: the top of the belt at about 59% of height.
	assert_between(pants.get_aabb().end.y / top, 0.575, 0.605, "top of the belt")


# --- S11-1 builds ---


func _model_mesh(b: StringName) -> MeshInstance3D:
	var scene := (load(SkinnedPuppet.model_for(b)) as PackedScene).instantiate() as Node3D
	autofree(scene)
	return scene.find_child("Body", true, false) as MeshInstance3D


func test_four_builds_are_built_and_a_heavy_one_is_thicker() -> void:
	for b: StringName in [&"lean", &"solid", &"heavy"]:
		assert_ne(SkinnedPuppet.model_for(b), SkinnedPuppet.MODEL, "%s was built" % b)
	# Compared at the same height: the jersey (made over the body) is deeper front to back at
	# the chest, where the arms hang clear at the sides.
	var lean_depth := _chest_depth(&"lean")
	var heavy_depth := _chest_depth(&"heavy")
	assert_gt(heavy_depth, lean_depth * 1.12, "heavy %.3f against lean %.3f of height" % [heavy_depth, lean_depth])


## Front-to-back depth of the jersey at chest height, as a share of the model's height.
func _chest_depth(b: StringName) -> float:
	var scene := (load(SkinnedPuppet.model_for(b)) as PackedScene).instantiate() as Node3D
	autofree(scene)
	var body := scene.find_child("Body", true, false) as MeshInstance3D
	var top := SkinnedPuppet.mesh_top(body.mesh)
	var jersey := scene.find_child("Jersey", true, false) as MeshInstance3D
	var low := INF
	var high := -INF
	for surface: int in jersey.mesh.get_surface_count():
		var verts: PackedVector3Array = jersey.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for v: Vector3 in verts:
			if absf(v.y - top * 0.72) < 0.015 and absf(v.x) < 0.15:
				low = minf(low, v.z)
				high = maxf(high, v.z)
	return (high - low) / top


func test_every_build_keeps_the_limb_proportions() -> void:
	for b: StringName in [&"lean", &"standard", &"solid", &"heavy"]:
		var puppet := SkinnedPuppet.new()
		puppet.build = b
		add_child_autofree(puppet)
		assert_between(puppet.upper_arm, 0.20, 0.34, "%s upper arm" % b)
		assert_between(puppet.lower_arm, 0.20, 0.32, "%s forearm" % b)
		assert_between(puppet.upper_leg, 0.35, 0.50, "%s thigh" % b)
		assert_between(puppet.lower_leg, 0.35, 0.48, "%s shin" % b)
		assert_between((puppet.upper_arm + puppet.lower_arm) / puppet.height, 0.28, 0.34, "%s arm share of height" % b)


func test_a_player_gets_the_build_for_his_body_and_position() -> void:
	assert_eq(SkinnedPuppet.build_for(183.0, 75.0), &"lean")
	assert_eq(SkinnedPuppet.build_for(183.0, 88.0), &"standard")
	assert_eq(SkinnedPuppet.build_for(183.0, 95.0), &"solid")
	assert_eq(SkinnedPuppet.build_for(183.0, 105.0), &"heavy")
	assert_eq(SkinnedPuppet.build_for(183.0, 88.0, Position.Kind.C), &"solid", "a catcher a little thicker")
	assert_eq(SkinnedPuppet.build_for(183.0, 82.0, Position.Kind.SS), &"lean", "a shortstop a little leaner")


func test_a_figure_changes_body_between_players() -> void:
	var puppet := SkinnedPuppet.new()
	add_child_autofree(puppet)
	var arm := puppet.upper_arm
	puppet.set_body(1.95, &"heavy")
	assert_eq(puppet.build, &"heavy")
	assert_almost_eq(puppet.upper_arm / arm, 1.95 / 1.83, 0.02, "the new model is scaled to his height")
	puppet.apply(PuppetClips.fielder_ready())
	puppet.set_body(1.70, &"heavy")
	assert_almost_eq(puppet.upper_arm / arm, 1.70 / 1.83, 0.02)


# --- S11-3 skin and light ---


func test_skin_scatters_light_and_eyes_are_glossy() -> void:
	var puppet := _model()
	var skin: StandardMaterial3D = null
	var eyes: StandardMaterial3D = null
	for part: MeshInstance3D in puppet.find_children("*", "MeshInstance3D", true, false):
		for surface: int in part.mesh.get_surface_count():
			var m := part.get_surface_override_material(surface) as StandardMaterial3D
			if m == null:
				continue
			if part.mesh.surface_get_material(surface).resource_name == "Skin":
				skin = m
			if part.name == &"Eyes":
				eyes = m
	assert_not_null(skin)
	assert_true(skin.subsurf_scatter_enabled, "light scatters under the skin")
	assert_true(skin.subsurf_scatter_skin_mode)
	assert_not_null(skin.roughness_texture, "some places shine, others are matte")
	assert_not_null(eyes)
	assert_lt(eyes.roughness, 0.1, "a wet cornea")


func test_shadows_are_not_lit_blue() -> void:
	var scene := (load("res://match/duel.tscn") as PackedScene).instantiate() as DuelScene
	scene.use_motion = false
	add_child_autofree(scene)
	var env := (scene.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
	assert_lt(env.ambient_light_sky_contribution, 1.0, "part of the ambient light is warm bounce light")
	assert_gte(env.ambient_light_color.r, env.ambient_light_color.b)
	var sun := scene.find_children("*", "DirectionalLight3D", true, false)[0] as DirectionalLight3D
	assert_gt(sun.light_color.r, sun.light_color.b, "a warm sun")


# --- S11-4 hair ---


func test_four_hair_styles_one_shown_and_none_under_the_cap() -> void:
	var puppet := _model()
	var styles: Array[MeshInstance3D] = []
	for i: int in range(1, 5):
		var h := puppet.find_child("Hair%d" % i, true, false) as MeshInstance3D
		assert_not_null(h, "style %d is in the model" % i)
		if h != null:
			styles.append(h)
	var shown := styles.filter(func(h: MeshInstance3D) -> bool: return h.visible)
	assert_eq(shown.size(), 1, "one style shows")
	puppet.set_hair(3, Color(0.3, 0.2, 0.1))
	assert_true(styles[2].visible)
	assert_false(styles[0].visible)
	# Nothing of the hair reaches up into the cap.
	var cap := puppet.find_child("Cap", true, false) as MeshInstance3D
	var cap_bottom := cap.get_aabb().position.y
	for h: MeshInstance3D in styles:
		assert_lte(h.get_aabb().end.y, cap_bottom + 0.01, "%s stays below the cap" % h.name)


# --- S11-5 helmet and cap ---


func test_the_helmet_flap_is_on_the_pitcher_side_and_both_for_a_switch_hitter() -> void:
	var puppet := _model()
	puppet.headgear = &"helmet"
	puppet.apply(PuppetClips.fielder_ready())
	var left := puppet.find_child("HelmetFlapLeft", true, false) as MeshInstance3D
	var right := puppet.find_child("HelmetFlapRight", true, false) as MeshInstance3D
	assert_not_null(left)
	assert_not_null(right)
	assert_true(left.visible, "a right-handed batter covers his left ear")
	assert_false(right.visible)
	# The left flap is on the model's left (+X in the model, which faces +Z).
	assert_gt(left.get_aabb().get_center().x, 0.0)
	assert_lt(right.get_aabb().get_center().x, 0.0)
	puppet.helmet_flaps = &"both"
	puppet.apply(PuppetClips.fielder_ready())
	assert_true(left.visible and right.visible, "a switch hitter covers both")
	puppet.headgear = &"cap"
	puppet.apply(PuppetClips.fielder_ready())
	assert_false(left.visible or right.visible, "no flaps on a cap")
	assert_true((puppet.find_child("CapButton", true, false) as MeshInstance3D).visible)


func test_the_team_letter_sits_on_the_front_of_the_cap() -> void:
	var puppet := _model()
	puppet.set_logo("해", Color.ORANGE)
	var labels := puppet.find_children("*", "Label3D", true, false)
	assert_eq(labels.size(), 2, "cap and helmet")
	var cap_label := labels[0] as Label3D
	assert_eq(cap_label.text, "해")
	assert_true(cap_label.visible)
	# In front of the face: closer to the camera side than the head's centre.
	var head := puppet.find_child("Cap", true, false) as MeshInstance3D
	var front := puppet.to_local(cap_label.global_position)
	var centre := puppet.to_local(head.global_transform * head.get_aabb().get_center())
	assert_lt(front.z, centre.z, "the puppet faces -Z: the letter is on the front")


# --- S11-6 faces ---


func test_every_player_on_a_club_has_his_own_face() -> void:
	var puppet := _model()
	var body := puppet.find_child("Body", true, false) as MeshInstance3D
	assert_gt(body.get_blend_shape_count(), 10, "the face keys came through as blend shapes")
	var seen: Dictionary[String, bool] = {}
	for i: int in 28:
		var weights := puppet.set_face("p%05d" % (i + 1))
		assert_false(weights.is_empty())
		var key := ""
		for k: String in weights:
			key += "%s=%.3f;" % [k, weights[k]]
			assert_between(weights[k], 0.0, 0.61, "moderate, so brows and eyes stay in place")
		assert_false(seen.has(key), "28 different faces")
		seen[key] = true
	# The same player always gets the same face.
	assert_eq(puppet.set_face("p00007"), puppet.set_face("p00007"))
