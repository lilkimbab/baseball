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
	var elbow := skeleton.get_bone_global_pose(skeleton.find_bone("RightLowerArm")).origin
	var shoulder := skeleton.get_bone_global_pose(skeleton.find_bone("RightUpperArm")).origin
	var wrist := skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin
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
	assert_null(body.get_surface_override_material(hands), "bare hands keep the skin")
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
