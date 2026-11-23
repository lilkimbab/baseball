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
	var half := roundi(scene.gauge_time * scene.sweet * 60.0)
	_advance(scene, half)
	assert_between(scene.power, 0.4, 0.6, "he winds up to his full speed while the button is held")
	assert_eq(scene.state, DuelScene.State.CHARGE, "and nothing is thrown until it is let go")
	_advance(scene, roundi(scene.gauge_time * scene.sweet * 120.0) - half)
	scene.release_pitch_button()
	assert_eq(scene.state, DuelScene.State.WINDUP, "letting go is the pitch")
	assert_gt(scene.accuracy, 0.9, "let go as the ring meets the circle, it is accurate")
	assert_almost_eq(scene.power, 1.0, 0.02, "and at his full speed")
	assert_true(scene.decision.by_hand)
	assert_eq(scene.decision.type.id, &"slider")
	_advance(scene, roundi(PuppetClips.PITCH_RELEASE * 120.0) + 20)
	assert_eq(scene.state, DuelScene.State.LIVE, "the ball is released at the end of the delivery")
	assert_almost_eq(scene.duel.pitch.release_speed_kmh(), 132.0 * DuelScene.effort_for(scene.power), 1.0)


func test_holding_the_button_too_long_still_throws_but_badly() -> void:
	var scene := _start(&"pitch")
	_advance(scene, 10)
	scene.press_pitch_button()
	_advance(scene, roundi(scene.gauge_time * 120.0) + 10)
	assert_eq(scene.state, DuelScene.State.WINDUP)
	assert_eq(scene.accuracy, 0.0)
	# And one let go at once is as bad, and slow.
	var quick := _start(&"pitch")
	_advance(quick, 10)
	quick.press_pitch_button()
	_advance(quick, 6)
	quick.release_pitch_button()
	assert_eq(quick.state, DuelScene.State.WINDUP)
	assert_eq(quick.accuracy, 0.0)
	assert_lt(quick.power, 0.1)


func test_the_player_s_pitch_goes_where_he_aimed_when_he_times_it() -> void:
	# docs/04 5.2: the miss follows his timing far more closely than a computer pitcher's draw.
	assert_almost_eq(PitchDuel.player_scatter(1.0), PitchDuel.PLAYER_BEST, 1e-6)
	assert_almost_eq(PitchDuel.player_scatter(0.0), PitchDuel.PLAYER_WORST, 1e-6)
	assert_lt(PitchDuel.player_scatter(0.75), 0.5, "a twentieth of a second off, half his usual miss")
	assert_gt(PitchDuel.player_scatter(0.4), 0.85, "well off, about his usual miss")
	var scene := _start(&"pitch")
	var worst := 0.0
	var total := 0.0
	var thrown := 0
	while thrown < 12:
		while scene.state != DuelScene.State.PRE_PITCH:
			_advance(scene, 1)
		_advance(scene, 5)
		scene.target = scene.duel.zone.point(0.15 + 0.07 * (thrown % 10), 0.85 - 0.07 * (thrown % 10))
		var aimed := scene.target
		scene.selected_pitch = thrown % scene.pitch_ids.size()
		scene.press_pitch_button()
		_advance(scene, roundi(scene.gauge_time * scene.sweet * 120.0))
		scene.release_pitch_button()
		while scene.state == DuelScene.State.WINDUP:
			_advance(scene, 1)
		var at := scene.duel.pitch.plate_pos
		var miss := Vector2(at.x - aimed.x, at.z - aimed.z).length()
		worst = maxf(worst, miss)
		total += miss
		thrown += 1
	assert_lt(total / thrown, 0.05, "on average within a ball's width of the spot")
	assert_lt(worst, 0.12, "and never far from it")


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
	# The release point is the hand at the moment of release, measured then (not when the
	# delivery was chosen, through the figure as it happened to stand).
	var scene := _start_with_motion(&"watch")
	_advance(scene, roundi((DuelScene.AI_PITCH_DELAY + 1.0) * 120.0) + 4)
	assert_eq(scene.state, DuelScene.State.LIVE)
	var start := scene.duel.pitch.release_pos
	scene.pitcher.apply_joints(scene.pitch_motion.frame(scene.release_time()), scene.pitch_motion.clip)
	var hand := Field.to_field(scene.pitcher.global_transform * scene.pitcher.ball_spot(&"RightHand"))
	assert_almost_eq(start, hand, Vector3.ONE * 0.01)
	assert_between(start.y, Field.RUBBER_Y - 2.5, Field.RUBBER_Y - 0.5, "in front of the rubber")
	assert_gt(start.z, Field.MOUND_HEIGHT + 1.0)
	assert_gt(start.distance_to(DuelSettings.new().release_point), 0.05, "the recorded delivery's, not the default")


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


func test_the_pitch_can_be_aimed_at_the_batter_s_body_but_not_his_head() -> void:
	# The user (2026-11-23): a pitcher may throw at a batter (KBO rules on beanballs follow);
	# never at the head, and not far past him.
	var scene := _start(&"pitch")
	var zone := scene.duel.zone
	scene.refresh(DT)
	# Pointer on the batter's head: a metre inside and well above the zone.
	scene.pointer_override = scene.camera.unproject_position(Field.to_world(Vector3(-1.0, Field.PLATE_FRONT_Y, 1.7)))
	scene.refresh(DT)
	assert_almost_eq(scene.target.x, -zone.half_width - DuelScene.AIM_AT_BODY, 1e-4, "as far in as his body")
	assert_almost_eq(scene.target.z, zone.top + DuelScene.AIM_BEYOND_ZONE.y, 1e-4, "no higher than a little over the zone")
	assert_lt(scene.target.z, 1.5, "not at his head")
	# The other side stays near the zone.
	scene.pointer_override = scene.camera.unproject_position(Field.to_world(Vector3(1.0, Field.PLATE_FRONT_Y, 0.8)))
	scene.refresh(DT)
	assert_almost_eq(scene.target.x, zone.half_width + DuelScene.AIM_BEYOND_ZONE.x, 1e-4)


func test_the_mound_is_a_surface_that_faces_up_at_its_regulation_height() -> void:
	var park := GreyboxField.new()
	add_child_autofree(park)
	var mound := park.get_node("Mound") as MeshInstance3D
	var arrays := mound.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var facing_up := 0
	var top := 0.0
	for i: int in vertices.size():
		top = maxf(top, vertices[i].y)
		if normals[i].y > 0.5:
			facing_up += 1
	assert_eq(facing_up, vertices.size(), "every part of the mound faces the sky")
	assert_almost_eq(top, Field.MOUND_HEIGHT, 1e-4, "ten inches high")
	# Godot draws the side a triangle winds clockwise on: from above, that is a cross product pointing down.
	var a := vertices[indices[0]]
	var b := vertices[indices[1]]
	var c := vertices[indices[2]]
	assert_lt((b - a).cross(c - a).y, 0.0, "triangles wind so that the top is the visible side")


func test_the_pitching_camera_shows_batter_and_pitcher_at_reference_sizes() -> void:
	var scene := _start(&"pitch")
	scene.refresh(DT)
	var camera := scene.camera
	var tall := func(at: Vector3, height: float) -> float:
		return camera.unproject_position(Field.to_world(at)).y - camera.unproject_position(Field.to_world(at + Vector3(0.0, 0.0, height))).y
	var view := float(scene.get_viewport().get_visible_rect().size.y)
	var pitcher: float = tall.call(Vector3(0.0, Field.RUBBER_Y, Field.MOUND_HEIGHT), 1.83) / view
	var batter: float = tall.call(Vector3(-0.95, 0.3, 0.0), 1.83) / view
	# reference/target-pitchview.png: the pitcher is close to half the picture's height and the
	# batter nearly as tall (tools/reference/pitch_view.json).
	assert_between(pitcher, 0.40, 0.52, "pitcher's share of the picture height")
	assert_between(pitcher / batter, 1.2, 1.4, "pitcher against batter")


# --- Aiming displays (the player's requests: a bat cursor, the pitch's path, a still catcher) ---


func test_the_path_of_a_pitch_runs_from_the_hand_to_the_plate() -> void:
	var cfg := PhysicsConfigIO.load_default()
	var curve: PitchType = PitchCatalogIO.load_default()[&"curve"]
	var release := Vector3(-0.55, 16.76, 1.8)
	var target := Vector3(0.1, Field.PLATE_FRONT_Y, 0.6)
	var flight := PitchModel.throw_type(cfg, curve, release, target)
	var path := PitchModel.path(cfg, flight, 0.045)
	assert_gt(path.size(), 10, "a ball every 0.045 s over half a second and more")
	assert_lt(path[0].distance_to(release), 0.001)
	assert_lt(path[path.size() - 1].distance_to(flight.plate_pos), 0.001)
	for i: int in range(1, path.size()):
		assert_lt(path[i].y, path[i - 1].y, "always coming in")
	# A curve drops: its highest point is above both ends of a straight line between them.
	var top := 0.0
	for p: Vector3 in path:
		top = maxf(top, p.z)
	assert_gt(top, release.z, "it rises out of the hand before it breaks down")
	assert_lt(flight.movement.y, -0.1, "and breaks down")


func test_the_player_sees_where_his_pitch_arrives_before_he_throws() -> void:
	var scene := _start(&"pitch")
	for i: int in 30:
		scene.step(DT)
		scene.refresh(DT)
	assert_eq(scene.state, DuelScene.State.PRE_PITCH)
	# A straight fastball: its mark in the zone and nothing else. A pitch that moves: only
	# the last few metres of its path, bending into the mark. Nothing starts at the pitcher
	# (drawn from his hand, the path came out of his neck on the screen).
	for i: int in scene.pitch_ids.size():
		scene.selected_pitch = i
		scene.refresh(DT)
		var type := scene.selected_type()
		var path := scene.preview
		assert_false(path.is_empty(), "%s: something is shown while he aims" % type.id)
		assert_lt(path[path.size() - 1].distance_to(scene.target), 0.03, "%s: it ends at his target" % type.id)
		if DuelScene.goes_straight(type):
			assert_eq(path.size(), 1, "%s: only where it arrives" % type.id)
		else:
			assert_between(path.size(), 4, DuelScene.TAIL_POINTS, "%s: the end of its path" % type.id)
			assert_lt(path[0].y, Field.PLATE_FRONT_Y + 9.0, "%s: from no further than a few metres out" % type.id)
			assert_gt(path[0].y, path[path.size() - 1].y, "%s: coming in" % type.id)
	scene.selected_pitch = 0
	scene.refresh(DT)
	var first := scene.preview.duplicate()
	scene.target += Vector3(0.2, 0.0, -0.2)
	scene.pointer_override = scene.camera.unproject_position(Field.to_world(scene.target))
	scene.refresh(DT)
	assert_ne(scene.preview[scene.preview.size() - 1], first[first.size() - 1], "it follows the target")


func test_the_pitch_wheel_chooses_the_pitch_the_pointer_goes_toward() -> void:
	var scene := _start(&"pitch")
	for i: int in 30:
		scene.step(DT)
		scene.refresh(DT)
	assert_eq(scene.state, DuelScene.State.PRE_PITCH)
	# Six directions round a ring: the first pitch straight up, the rest clockwise.
	assert_eq(DuelScene.WHEEL_SLOTS, 6, "a pitcher throws six pitches at most")
	assert_almost_eq(DuelScene.wheel_direction(0).angle_to(Vector2.UP), 0.0, 0.001)
	assert_gt(DuelScene.wheel_direction(1).x, 0.5, "the second to the upper right")
	assert_gt(DuelScene.wheel_direction(3).y, 0.9, "the fourth straight down")
	var middle := Vector2(640.0, 360.0)
	var aim := scene.target
	scene.selected_pitch = 0
	for slot: int in scene.pitch_ids.size():
		scene.open_wheel(middle)
		assert_true(scene.wheel_open)
		scene.pointer_override = middle + DuelScene.wheel_direction(slot) * 120.0
		scene.refresh(DT)
		assert_eq(scene.wheel_pick, slot, "the pointer is toward pitch %d" % (slot + 1))
		assert_eq(scene.target, aim, "the target does not move while a pitch is chosen")
		scene.close_wheel()
		assert_eq(scene.selected_pitch, slot)
		assert_false(scene.wheel_open)
	# In the middle of the wheel, or toward a direction with no pitch, nothing changes.
	scene.open_wheel(middle)
	scene.pointer_override = middle + Vector2(3.0, 2.0)
	scene.refresh(DT)
	assert_eq(scene.wheel_pick, -1, "the middle chooses nothing")
	if scene.pitch_ids.size() < DuelScene.WHEEL_SLOTS:
		scene.pointer_override = middle + DuelScene.wheel_direction(DuelScene.WHEEL_SLOTS - 1) * 120.0
		scene.refresh(DT)
		assert_eq(scene.wheel_pick, -1, "no pitch in that direction")
	var before := scene.selected_pitch
	scene.close_wheel()
	assert_eq(scene.selected_pitch, before, "the pitch already chosen is kept")


func test_the_batter_aims_with_the_pointer_by_default() -> void:
	var scene := _start(&"bat")
	assert_true(scene.aim_enabled, "the bat cursor is on")
	var spot := Vector3(-0.15, Field.PLATE_FRONT_Y, 0.6)
	scene.pointer_override = scene.camera.unproject_position(Field.to_world(spot))
	scene.refresh(DT)
	assert_lt(Vector2(scene.aim_point.x, scene.aim_point.z).distance_to(Vector2(spot.x, spot.z)), 0.02, "the cursor is where the pointer is")


func test_the_gauge_is_not_the_same_twice() -> void:
	# The user: random ring sizes so the rhythm cannot be learned. Each pitch's ring starts at
	# its own size and meets the circle at its own moment, between about 0.6 and 1.3 s.
	var scene := _start(&"pitch")
	var moments: Array[float] = []
	for i: int in 8:
		while scene.state != DuelScene.State.PRE_PITCH:
			_advance(scene, 1)
		_advance(scene, 5)
		scene.press_pitch_button()
		moments.append(scene.gauge_time * scene.sweet)
		assert_between(scene.gauge_from, DuelScene.GAUGE_FROM_MIN, DuelScene.GAUGE_FROM_MAX)
		_advance(scene, roundi(scene.gauge_time * scene.sweet * 120.0))
		assert_gt(scene.ring_accuracy(), 0.9, "on the circle at this pitch's own moment")
		scene.release_pitch_button()
	moments.sort()
	assert_gt(moments[moments.size() - 1] - moments[0], 0.2, "moments %s apart" % str(moments))
	for m: float in moments:
		assert_between(m, 0.5, 1.4)


func test_a_pitch_s_command_sets_how_forgiving_the_moment_is() -> void:
	# The user asked what decides it pitcher by pitcher: each pitch's command (its window),
	# his control (DuelSettings.command: how near a perfect pitch goes), fatigue and, with a
	# runner in scoring position, composure (the ring's pace).
	assert_gt(DuelScene.window_share(90.0), DuelScene.window_share(30.0))
	assert_almost_eq(DuelScene.window_share(0.0), 0.8, 1e-6)
	assert_almost_eq(DuelScene.window_share(100.0), 1.25, 1e-6)
	var scene := _start(&"pitch")
	_advance(scene, 10)
	scene.settings.command = 90.0
	scene.press_pitch_button()
	var wide := scene.tolerance
	scene.release_pitch_button()
	while scene.state != DuelScene.State.PRE_PITCH:
		_advance(scene, 1)
	_advance(scene, 5)
	scene.settings.command = 30.0
	scene.press_pitch_button()
	assert_lt(scene.tolerance, wide, "a pitch he commands less is less forgiving")
