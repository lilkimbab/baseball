extends GutTest
## Runs the real duel scene headless: the state machine must keep cycling through pitches in
## every mode without input and without errors.

const DUEL := preload("res://match/duel.tscn")


const DT := 1.0 / 120.0


## Steps the scene by hand: the same calls the engine makes each physics tick, without
## waiting for real time to pass.
func _advance(scene: DuelScene, frames: int) -> void:
	for i: int in frames:
		scene.step(DT)


func _start(mode: StringName) -> DuelScene:
	var scene := DUEL.instantiate() as DuelScene
	scene.mode = mode
	scene.seed_value = 7
	# Key poses, so these tests do not depend on what the local content pack holds.
	scene.use_motion = false
	add_child_autofree(scene)
	return scene


func test_watch_mode_plays_pitch_after_pitch() -> void:
	var scene := _start(&"watch")
	_advance(scene, 1500)
	assert_gt(scene.pitches_thrown(), 1, "several pitches in about 12 seconds of game time")
	assert_between(scene.balls, 0, 3)
	assert_between(scene.strikes, 0, 2)


func test_batting_mode_without_input_only_sees_balls_and_called_strikes() -> void:
	var scene := _start(&"bat")
	var seen := {}
	for i: int in 12:
		_advance(scene, 120)
		seen[scene.duel.result] = true
	assert_gt(scene.pitches_thrown(), 1)
	assert_false(seen.has(PitchDuel.Result.SWINGING_STRIKE), "nobody swung")
	assert_false(seen.has(PitchDuel.Result.IN_PLAY), "nobody swung")


func test_pitching_mode_waits_for_the_player_then_runs_the_gauge() -> void:
	var scene := _start(&"pitch")
	_advance(scene, 240)
	assert_eq(scene.state, DuelScene.State.PRE_PITCH, "no pitch until the player acts")
	scene.selected_pitch = 2
	scene.press_pitch_button()
	assert_eq(scene.state, DuelScene.State.CHARGE)
	_advance(scene, 60)
	assert_between(scene.power, 0.4, 0.7, "power builds while the button is held")
	scene.release_pitch_button()
	assert_eq(scene.state, DuelScene.State.ACCURACY)
	_advance(scene, roundi(DuelScene.ACCURACY_TIME * DuelScene.ACCURACY_SWEET * 120.0))
	scene.press_pitch_button()
	assert_eq(scene.state, DuelScene.State.WINDUP)
	assert_gt(scene.accuracy, 0.8, "clicking on the sweet spot is accurate")
	assert_eq(scene.decision.type.id, &"slider")
	_advance(scene, roundi(PuppetClips.PITCH_RELEASE * 120.0) + 20)
	assert_eq(scene.state, DuelScene.State.LIVE, "the ball is released at the end of the delivery")
	assert_almost_eq(scene.duel.pitch.release_speed_kmh(), 132.0 * lerpf(0.93, 1.0, scene.power), 1.0)


func test_missing_the_accuracy_click_still_throws_but_badly() -> void:
	var scene := _start(&"pitch")
	_advance(scene, 10)
	scene.press_pitch_button()
	_advance(scene, 20)
	scene.release_pitch_button()
	_advance(scene, roundi(DuelScene.ACCURACY_TIME * 120.0) + 10)
	assert_eq(scene.state, DuelScene.State.WINDUP)
	assert_eq(scene.accuracy, 0.0)


func test_ball_leaves_from_the_pitchers_hand() -> void:
	var scene := _start(&"watch")
	var guard := 0
	while scene.state != DuelScene.State.LIVE and guard < 600:
		_advance(scene, 1)
		guard += 1
	assert_eq(scene.state, DuelScene.State.LIVE)
	scene.refresh(0.0)
	var hand: Vector3 = scene.pitcher.global_transform * scene.pitcher.joints[&"RightHand"]
	var release := Field.to_world(scene.duel.pitch.release_pos)
	assert_lt(hand.distance_to(release), 0.12, "the hand is at the physics release point when the ball leaves")


func test_puppet_reaches_its_targets_and_keeps_limb_lengths() -> void:
	var puppet := Puppet.new()
	add_child_autofree(puppet)
	puppet.apply(PuppetClips.stance())
	var shoulder := puppet.joints[&"RightUpperArm"]
	var elbow := puppet.joints[&"RightLowerArm"]
	var hand := puppet.joints[&"RightHand"]
	assert_almost_eq(shoulder.distance_to(elbow), puppet.upper_arm, 0.002)
	assert_almost_eq(elbow.distance_to(hand), puppet.lower_arm, 0.002)
	assert_almost_eq(hand.distance_to(PuppetClips.stance().r_hand), 0.0, 0.01, "hand is on its target")
	var hip := puppet.joints[&"LeftUpperLeg"]
	var knee := puppet.joints[&"LeftLowerLeg"]
	var ankle := puppet.joints[&"LeftFoot"]
	assert_almost_eq(hip.distance_to(knee), puppet.upper_leg, 0.002)
	assert_almost_eq(knee.distance_to(ankle), puppet.lower_leg, 0.002)


# --- Recorded motion ---


func _start_with_motion(mode: StringName) -> DuelScene:
	var scene := _start(mode)
	scene.set_motion(SyntheticMotion.pitch_clip(), SyntheticMotion.swing_clip())
	return scene


func test_with_a_recorded_delivery_the_ball_leaves_at_the_clips_release() -> void:
	var scene := _start_with_motion(&"watch")
	assert_almost_eq(scene.release_time(), 1.0, 1e-6, "the clip's release, not the key poses'")
	_advance(scene, roundi(DuelScene.AI_PITCH_DELAY * 120.0) + 2)
	assert_eq(scene.state, DuelScene.State.WINDUP)
	_advance(scene, 118)
	assert_eq(scene.state, DuelScene.State.WINDUP, "still in the delivery just before the release")
	_advance(scene, 4)
	assert_eq(scene.state, DuelScene.State.LIVE)


func test_the_ball_starts_from_the_pitchers_hand() -> void:
	var scene := _start_with_motion(&"watch")
	var default_point := DuelSettings.new().release_point
	assert_gt(scene.settings.release_point.distance_to(default_point), 0.05, "the release point comes from the motion")
	scene.pitcher.right_grip = Puppet.Grip.BALL
	scene.pitcher.reset_motion()
	scene.pitcher.apply_joints(scene.pitch_motion.frame(scene.release_time()), scene.pitch_motion.clip)
	var hand := Field.to_field(scene.pitcher.global_transform * scene.pitcher.ball_spot(&"RightHand"))
	assert_almost_eq(scene.settings.release_point, hand, Vector3.ONE * 0.01)
	assert_between(scene.settings.release_point.y, Field.RUBBER_Y - 2.5, Field.RUBBER_Y - 0.5, "in front of the rubber")
	assert_gt(scene.settings.release_point.z, Field.MOUND_HEIGHT + 1.0)
	_advance(scene, roundi((DuelScene.AI_PITCH_DELAY + 1.0) * 120.0) + 4)
	assert_eq(scene.state, DuelScene.State.LIVE)
	assert_almost_eq(scene.duel.pitch.release_pos, scene.settings.release_point, Vector3.ONE * 1e-4)


func test_watch_mode_keeps_cycling_with_recorded_motion() -> void:
	var scene := _start_with_motion(&"watch")
	_advance(scene, 2400)
	assert_gt(scene.pitches_thrown(), 2, "several pitches in 20 seconds")


func test_the_batter_strides_before_the_release_and_steps_back_after_a_take() -> void:
	var scene := _start_with_motion(&"bat")
	_advance(scene, roundi(DuelScene.AI_PITCH_DELAY * 120.0) + 2)
	assert_eq(scene.swing_motion.phase, SwingMotion.Phase.IDLE, "waiting as the delivery starts")
	_advance(scene, 116)
	assert_eq(scene.state, DuelScene.State.WINDUP)
	assert_eq(scene.swing_motion.phase, SwingMotion.Phase.LOAD, "striding before the ball is out of the hand")
	for i: int in 400:
		scene.step(DT)
		if scene.state == DuelScene.State.RESULT:
			break
	assert_eq(scene.state, DuelScene.State.RESULT)
	assert_eq(scene.swing_motion.phase, SwingMotion.Phase.IDLE, "nobody swung: back to the stance")


func test_an_ai_swing_is_shown_and_arrives_at_its_contact_time() -> void:
	var scene := _start_with_motion(&"watch")
	var checked := 0
	for i: int in 9000:
		scene.step(DT)
		var swing := scene.duel.swing
		if scene.state == DuelScene.State.LIVE and swing != null and swing.resolved and scene.swing_motion.phase == SwingMotion.Phase.FINISH:
			# Within two ticks of the swing's contact time the clip is at its contact frame.
			if absf(scene.duel.time - swing.contact_time) <= 2.0 * DT:
				assert_almost_eq(scene.swing_motion.clip_time(), scene.swing_motion.contact, 0.03)
				checked += 1
		if checked >= 2:
			break
	assert_gte(checked, 2, "the AI batter swung at least twice in 75 seconds")


func test_a_players_swing_is_shown_with_the_recorded_motion() -> void:
	var scene := _start_with_motion(&"bat")
	for i: int in 600:
		scene.step(DT)
		if scene.state == DuelScene.State.LIVE and scene.duel.time >= scene.duel.ideal_contact_time - 0.13:
			break
	scene.swing(SwingAttempt.Kind.POWER)
	assert_eq(scene.swing_motion.phase, SwingMotion.Phase.SWING)
	_advance(scene, roundi(0.13 * 120.0) + 2)
	assert_eq(scene.swing_motion.phase, SwingMotion.Phase.FINISH)
	assert_true(scene.duel.swing.resolved)


func test_without_clips_the_scene_goes_back_to_key_poses() -> void:
	var scene := _start_with_motion(&"watch")
	scene.set_motion(null, null)
	assert_null(scene.pitch_motion)
	assert_null(scene.swing_motion)
	assert_almost_eq(scene.release_time(), PuppetClips.PITCH_RELEASE, 1e-6)
	assert_eq(scene.settings.release_point, DuelSettings.new().release_point)
	_advance(scene, 1500)
	assert_gt(scene.pitches_thrown(), 1)


# --- Aiming ---


func test_a_tool_can_aim_the_pitch_without_a_mouse() -> void:
	var scene := _start(&"pitch")
	var zone := scene.duel.zone
	var spot := Vector3(zone.half_width * 0.5, Field.PLATE_FRONT_Y, zone.bottom + 0.1)
	scene.refresh(DT)
	scene.pointer_override = scene.camera.unproject_position(Field.to_world(spot))
	scene.refresh(DT)
	assert_almost_eq(scene.target, spot, Vector3.ONE * 0.02, "the target follows the pointer")


func test_the_pitch_cannot_be_aimed_at_the_batter() -> void:
	var scene := _start(&"pitch")
	var zone := scene.duel.zone
	scene.refresh(DT)
	# Pointer on the batter's head: a metre inside and well above the zone.
	scene.pointer_override = scene.camera.unproject_position(Field.to_world(Vector3(-1.0, Field.PLATE_FRONT_Y, 1.7)))
	scene.refresh(DT)
	assert_almost_eq(scene.target.x, -zone.half_width - DuelScene.AIM_BEYOND_ZONE.x, 1e-4, "held at the edge of the aiming area")
	assert_almost_eq(scene.target.z, zone.top + DuelScene.AIM_BEYOND_ZONE.y, 1e-4)
	assert_gt(scene.target.x, scene.batter.position.x + 0.3, "which stops short of where the batter stands")
