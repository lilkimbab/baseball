extends GutTest
## Recorded motion: reading clips, sampling between frames, and the timing of a delivery and
## a swing around the events the game synchronises to.

const DT := 1.0 / 240.0


func _advance(motion: SwingMotion, seconds: float) -> void:
	for i: int in roundi(seconds / DT):
		motion.advance(DT)


func test_a_clip_is_read_from_its_dictionary_form() -> void:
	var clip := JointClip.from_dictionary({
		"format": 1, "kind": "pitch", "side": "L", "fps": 10.0, "ankle_height": 0.07, "source": "test",
		"events": {"release": 0.2}, "joints": ["RightHand", "LeftHand"],
		"frames": [[0, 1, 0, 1, 1, 0], [2, 1, 0, 1, 1, 0], [4, 1, 0, 1, 3, 0]],
	})
	assert_not_null(clip)
	assert_eq(clip.kind, &"pitch")
	assert_eq(clip.side, &"L")
	assert_eq(clip.frame_count(), 3)
	assert_almost_eq(clip.duration, 0.2, 1e-6)
	assert_almost_eq(clip.event(&"release"), 0.2, 1e-6)
	assert_almost_eq(clip.event(&"missing", 9.0), 9.0, 1e-6, "an unmarked moment gives the fallback")
	assert_almost_eq(clip.ankle_height, 0.07, 1e-6)


func test_sampling_interpolates_between_frames_and_holds_the_ends() -> void:
	var clip := JointClip.from_dictionary({"fps": 10.0, "joints": ["RightHand"], "frames": [[0, 1, 0], [2, 1, 0], [4, 3, 0]]})
	assert_almost_eq(clip.sample(0.05)[&"RightHand"], Vector3(1.0, 1.0, 0.0), Vector3.ONE * 1e-5)
	assert_almost_eq(clip.sample(0.15)[&"RightHand"], Vector3(3.0, 2.0, 0.0), Vector3.ONE * 1e-5)
	assert_almost_eq(clip.sample(-1.0)[&"RightHand"], Vector3(0.0, 1.0, 0.0), Vector3.ONE * 1e-5)
	assert_almost_eq(clip.sample(5.0)[&"RightHand"], Vector3(4.0, 3.0, 0.0), Vector3.ONE * 1e-5)


func test_an_empty_clip_is_refused() -> void:
	assert_null(JointClip.from_dictionary({"fps": 60.0, "joints": ["RightHand"], "frames": []}))
	assert_null(JointClip.load_file("res://no/such/clip.json"))


func test_limb_lengths_are_measured_from_the_recording() -> void:
	var still: Array[Dictionary] = [SyntheticMotion.standing(), SyntheticMotion.standing()]
	var clip := JointClip.from_frames(still, 60.0)
	assert_almost_eq(clip.leg_length, 0.872, 0.005, "hip to knee to ankle")
	assert_almost_eq(clip.arm_length, 0.556, 0.005, "shoulder to elbow to wrist")


func test_blending_frames_moves_every_joint_part_of_the_way() -> void:
	var half := JointClip.blend(SyntheticMotion.standing(), SyntheticMotion.release(), 0.5)
	var expected := SyntheticMotion.standing()[&"RightHand"].lerp(SyntheticMotion.release()[&"RightHand"], 0.5)
	assert_almost_eq(half[&"RightHand"], expected, Vector3.ONE * 1e-5)
	assert_eq(half.size(), SyntheticMotion.standing().size())


func test_a_delivery_waits_in_the_set_position_and_returns_to_it() -> void:
	var motion := PitchMotion.new(SyntheticMotion.pitch_clip())
	assert_almost_eq(motion.release_time, 1.0, 1e-6)
	var set_hand := motion.clip.sample(0.0)[&"RightHand"]
	assert_almost_eq(motion.frame(-1.0)[&"RightHand"], set_hand, Vector3.ONE * 1e-5, "before the delivery")
	assert_almost_eq(motion.frame(1.0)[&"RightHand"], motion.clip.sample(1.0)[&"RightHand"], Vector3.ONE * 1e-5, "the recording plays at its own speed")
	var finish := motion.frame(motion.clip.duration + PitchMotion.TAIL + PitchMotion.HOLD * 0.5)[&"RightHand"]
	assert_almost_eq(finish, motion.clip.sample(motion.clip.duration)[&"RightHand"], Vector3.ONE * 1e-4, "the follow-through is held")
	assert_almost_eq(motion.frame(motion.length())[&"RightHand"], set_hand, Vector3.ONE * 1e-5, "and he is back for the next pitch")


func test_a_delivery_never_jumps_between_frames() -> void:
	var motion := PitchMotion.new(SyntheticMotion.pitch_clip())
	var last := motion.frame(0.0)[&"RightHand"]
	var worst := 0.0
	for i: int in roundi((motion.length() + 0.2) * 240.0):
		var now := motion.frame(i * DT)[&"RightHand"]
		worst = maxf(worst, now.distance_to(last))
		last = now
	assert_lt(worst, 0.03, "the hand moves less than 3 cm in 1/240 s")


func test_a_batter_waits_in_the_first_part_of_the_clip() -> void:
	var motion := SwingMotion.new(SyntheticMotion.swing_clip())
	var latest := 0.0
	for i: int in 2400:
		motion.advance(DT)
		latest = maxf(latest, motion.clip_time())
	assert_eq(motion.phase, SwingMotion.Phase.IDLE)
	assert_lt(latest, motion.stride, "the waiting motion stops short of the stride")
	assert_gt(latest, motion.stride * 0.5, "but does move")
	assert_almost_eq(motion.reach_weight(), 0.0, 1e-6)


func test_the_load_runs_to_the_launch_position_and_waits_there() -> void:
	var motion := SwingMotion.new(SyntheticMotion.swing_clip())
	motion.begin_load()
	assert_eq(motion.phase, SwingMotion.Phase.LOAD)
	_advance(motion, 0.2)
	assert_between(motion.clip_time(), motion.stride + 0.15, motion.stride + 0.21, "it plays at the recorded speed")
	_advance(motion, 2.0)
	assert_almost_eq(motion.clip_time(), motion.launch, 0.01)
	assert_eq(motion.phase, SwingMotion.Phase.LOAD)


func test_the_load_starts_early_enough_to_be_ready_for_a_fastball() -> void:
	var motion := SwingMotion.new(SyntheticMotion.swing_clip())
	# Load (0.4 s) must end a swing's length (0.15 s) before the ball arrives (0.44 s after release).
	assert_almost_eq(motion.load_lead(), 0.4 - (SwingMotion.NOMINAL_FLIGHT - 0.15), 1e-5)


func test_the_swing_reaches_contact_exactly_when_asked() -> void:
	for seconds: float in [0.11, 0.13, 0.2] as Array[float]:
		var motion := SwingMotion.new(SyntheticMotion.swing_clip())
		motion.begin_load()
		_advance(motion, 1.5)
		motion.begin_swing(seconds)
		_advance(motion, seconds - DT)
		assert_lt(motion.clip_time(), motion.contact, "not there yet after %.3f s" % (seconds - DT))
		assert_gt(motion.reach_weight(), 0.9, "nearly at full reach")
		_advance(motion, 2.0 * DT)
		assert_gte(motion.clip_time(), motion.contact, "contact %.2f s after the swing began" % seconds)
		assert_eq(motion.phase, SwingMotion.Phase.FINISH)


func test_a_swing_without_a_load_still_arrives_on_time() -> void:
	var motion := SwingMotion.new(SyntheticMotion.swing_clip())
	motion.begin_swing(0.12)
	_advance(motion, 0.12 + DT)
	assert_gte(motion.clip_time(), motion.contact)


func test_after_the_finish_the_batter_returns_to_the_stance() -> void:
	var motion := SwingMotion.new(SyntheticMotion.swing_clip())
	motion.begin_load()
	_advance(motion, 1.0)
	motion.begin_swing(0.11)
	_advance(motion, 0.11 + (motion.finish - motion.contact) + SwingMotion.FINISH_HOLD + SwingMotion.RETURN_BLEND + 0.3)
	assert_eq(motion.phase, SwingMotion.Phase.IDLE)
	assert_lt(motion.clip_time(), motion.stride)
	assert_almost_eq(motion.reach_weight(), 0.0, 1e-6)


func test_a_batter_who_takes_the_pitch_steps_back_without_swinging() -> void:
	var motion := SwingMotion.new(SyntheticMotion.swing_clip())
	motion.begin_load()
	_advance(motion, 1.0)
	var loaded := motion.frame()[&"RightHand"]
	motion.relax()
	assert_eq(motion.phase, SwingMotion.Phase.IDLE)
	assert_almost_eq(motion.frame()[&"RightHand"], loaded, Vector3.ONE * 1e-4, "no jump at the moment he relaxes")
	motion.relax()
	motion.begin_swing(0.1)
	assert_eq(motion.phase, SwingMotion.Phase.SWING, "and he can swing at the next one")


func test_the_swing_never_jumps_between_frames() -> void:
	var motion := SwingMotion.new(SyntheticMotion.swing_clip())
	var last := motion.frame()[&"LeftFoot"]
	var worst := 0.0
	for i: int in 1400:
		if i == 300:
			motion.begin_load()
		if i == 560:
			motion.begin_swing(0.11)
		motion.advance(DT)
		var now := motion.frame()[&"LeftFoot"]
		worst = maxf(worst, now.distance_to(last))
		last = now
	assert_lt(worst, 0.02, "the front foot moves less than 2 cm in 1/240 s through every transition")
