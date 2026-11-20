extends GutTest
## Checks on the recorded delivery and swing in the local content pack. The pack is not part
## of the repository, so these are skipped where it is absent ("./dev mocap" builds it).


func _speed(clip: JointClip, joint: StringName, time: float) -> float:
	var span := 0.01
	return clip.sample(time + span)[joint].distance_to(clip.sample(time - span)[joint]) / (2.0 * span)


func test_the_delivery_releases_the_ball_at_arm_speed_in_front_of_the_body() -> void:
	var clip := MotionLibrary.find(&"pitch")
	if clip == null:
		pending("no recorded delivery in content-local/")
		return
	var hand: StringName = &"LeftHandTip" if clip.side == &"L" else &"RightHandTip"
	var shoulder: StringName = &"LeftUpperArm" if clip.side == &"L" else &"RightUpperArm"
	var release := clip.event(&"release", -1.0)
	assert_between(release, 0.5, clip.duration - 0.1, "release is marked, with follow-through after it")
	assert_gt(_speed(clip, hand, release), 15.0, "the hand is at throwing speed when the ball leaves")
	var fastest := 0.0
	var fastest_at := 0.0
	for i: int in roundi(clip.duration * 240.0):
		var speed := _speed(clip, hand, i / 240.0)
		if speed > fastest:
			fastest = speed
			fastest_at = i / 240.0
	assert_almost_eq(fastest_at, release, 0.03, "the hand is fastest at the release")
	var at_release := clip.sample(release)
	assert_lt(at_release[hand].z, at_release[shoulder].z - 0.1, "the hand is ahead of the shoulder")
	assert_lt(at_release[hand].z, -1.0, "and well down the mound from the rubber")
	var set_position := clip.sample(0.0)
	assert_lt(_speed(clip, hand, 0.05), 1.0, "the clip opens on a still set position")
	assert_almost_eq(set_position[&"RightFoot" if clip.side != &"L" else &"LeftFoot"].y, clip.ankle_height, 0.03, "pivot foot on the ground at the origin")


func test_the_swing_meets_the_ball_with_the_barrel_at_full_speed() -> void:
	var clip := MotionLibrary.find(&"swing")
	if clip == null:
		pending("no recorded swing in content-local/")
		return
	var motion := SwingMotion.new(clip)
	assert_lt(motion.stride, motion.launch)
	assert_lt(motion.launch, motion.contact)
	assert_lt(motion.contact, motion.finish)
	assert_between(motion.contact - motion.launch, 0.08, 0.25, "launch to contact is a swing's length")
	assert_gt(motion.stride, 0.5, "there is some stance to wait in")
	assert_gt(_speed(clip, &"BatSweetSpot", motion.contact), 18.0, "barrel speed at contact")
	assert_lt(_speed(clip, &"BatGrip", motion.launch - 0.03), 3.0, "hands still slow before the launch")
	var at_contact := clip.sample(motion.contact)
	assert_lt(at_contact[&"BatSweetSpot"].z, -0.5, "the barrel is out over the plate")
	assert_between(at_contact[&"BatSweetSpot"].y, 0.3, 1.3, "at a hittable height")
	assert_between(at_contact[&"BatSweetSpot"].distance_to(at_contact[&"BatGrip"]), 0.4, 0.7, "sweet spot to hands")


func test_the_player_model_follows_the_recordings_without_breaking() -> void:
	var clips: Array[JointClip] = [MotionLibrary.find(&"pitch"), MotionLibrary.find(&"swing")]
	if clips[0] == null or clips[1] == null:
		pending("no recorded motion in content-local/")
		return
	var puppet := SkinnedPuppet.new()
	add_child_autofree(puppet)
	var skeleton := puppet.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for clip: JointClip in clips:
		puppet.reset_motion()
		var ok := true
		var lowest := 10.0
		var worst_leg_turn := 0.0
		var last := Quaternion.IDENTITY
		var thigh := skeleton.find_bone("LeftUpperLeg")
		for step: int in roundi(clip.duration * 120.0) + 1:
			puppet.apply_joints(clip.sample(step / 120.0), clip)
			for bone: int in skeleton.get_bone_count():
				ok = ok and skeleton.get_bone_global_pose(bone).is_finite()
			lowest = minf(lowest, minf(puppet.joints[&"LeftFoot"].y, puppet.joints[&"RightFoot"].y))
			var now := skeleton.get_bone_global_pose(thigh).basis.get_rotation_quaternion()
			if step > 0:
				worst_leg_turn = maxf(worst_leg_turn, rad_to_deg(last.angle_to(now)))
			last = now
		assert_true(ok, "%s: every bone transform is finite" % clip.source)
		assert_gt(lowest, -0.15, "%s: feet do not go through the ground" % clip.source)
		assert_lt(worst_leg_turn, 12.0, "%s: the thigh never snaps round in one frame" % clip.source)
