extends GutTest
## Motion matching for running fielders and runners (approved proposal 4) over the CMU
## recordings (approved proposal 3) in the local content pack.


func _matcher() -> MotionMatcher:
	var mm := MotionMatcher.shared()
	if mm == null:
		pass_test("no CMU recordings in the local content pack")
	return mm


func test_the_database_holds_the_recorded_running() -> void:
	var mm := _matcher()
	if mm == null:
		return
	assert_gt(mm.clips.size(), 30, "runs, jogs, turns and stops")
	assert_gt(mm.size(), 1000, "frames to choose from")
	# Every frame faces -Z: across the hips is +X.
	for clip: JointClip in mm.clips:
		var f := clip.sample(clip.duration * 0.5)
		var across := f[&"RightUpperLeg"] - f[&"LeftUpperLeg"]
		assert_lt(absf(across.z), 0.02, clip.source)


func test_it_picks_motion_that_goes_where_he_is_going() -> void:
	var mm := _matcher()
	if mm == null:
		return
	# Running straight ahead fast: a run, going ahead.
	var fast := mm.search(Vector2(0.0, -7.0), Vector2(0.0, -1.4), Vector2(0.0, -2.8), PackedFloat32Array())
	assert_gt(mm.entry_speed[fast], 2.5, "a run, not a walk")
	var o := fast * MotionMatcher.FEATURES
	assert_lt(mm.features[o + 1], 0.0, "going ahead")
	# Slowing to a stop: something slow.
	var stopping := mm.search(Vector2(0.0, -1.0), Vector2(0.0, -0.1), Vector2(0.0, -0.1), PackedFloat32Array())
	assert_lt(mm.entry_speed[stopping], mm.entry_speed[fast])
	# Veering right: the future lies to the right.
	var veer := mm.search(Vector2(1.0, -3.5), Vector2(0.4, -0.6), Vector2(1.0, -1.1), PackedFloat32Array())
	assert_gt(mm.features[veer * MotionMatcher.FEATURES + 4], 0.0)


func test_playback_gives_finite_poses_and_blends() -> void:
	var mm := _matcher()
	if mm == null:
		return
	var pb := MotionMatcher.Playback.new(mm)
	var last: Dictionary[StringName, Vector3] = {}
	for i: int in 120:
		var turn := Vector2(sin(i * 0.05), -cos(i * 0.05)) * 6.0
		var pose := pb.step(1.0 / 60.0, turn, turn * 0.2, turn * 0.4)
		assert_false(pose.has(&"Root"))
		for joint: StringName in pose:
			assert_true(pose[joint].is_finite())
		if not last.is_empty():
			# No jumps: the hips move a few centimetres a frame at most.
			var hips := pose[&"LeftUpperLeg"].lerp(pose[&"RightUpperLeg"], 0.5)
			var was := last[&"LeftUpperLeg"].lerp(last[&"RightUpperLeg"], 0.5)
			assert_lt(hips.distance_to(was), 0.12, "frame %d" % i)
		last = pose
