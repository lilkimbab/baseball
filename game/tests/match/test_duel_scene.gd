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
	assert_almost_eq(shoulder.distance_to(elbow), Puppet.UPPER_ARM, 0.002)
	assert_almost_eq(elbow.distance_to(hand), Puppet.LOWER_ARM, 0.002)
	assert_almost_eq(hand.distance_to(PuppetClips.stance().r_hand), 0.0, 0.01, "hand is on its target")
	var hip := puppet.joints[&"LeftUpperLeg"]
	var knee := puppet.joints[&"LeftLowerLeg"]
	var ankle := puppet.joints[&"LeftFoot"]
	assert_almost_eq(hip.distance_to(knee), Puppet.UPPER_LEG, 0.002)
	assert_almost_eq(knee.distance_to(ankle), Puppet.LOWER_LEG, 0.002)
