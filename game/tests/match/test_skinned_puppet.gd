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
	var mesh := puppet.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var seen := {}
	for surface: int in mesh.mesh.get_surface_count():
		var name := mesh.mesh.surface_get_material(surface).resource_name
		seen[name] = (mesh.get_surface_override_material(surface) as StandardMaterial3D).albedo_color
	assert_eq(seen["Jersey"], Color(0.2, 0.3, 0.8))
	assert_eq(seen["Cap"], Color(0.8, 0.1, 0.1))
	assert_eq(seen["Socks"], Color(0.8, 0.1, 0.1))
	assert_true(seen.has("Skin") and seen.has("Pants") and seen.has("Shoes") and seen.has("Belt"))
