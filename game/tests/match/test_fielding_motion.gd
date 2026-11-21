extends PlayTest
## Fielding and running motion (docs/13 S12): who catches and throws when in a play, the glove
## meeting the ball, and feet that stay planted while the body moves.


func _moments(moves: PlayMoves, key: String, kind: PlayMoves.Kind) -> Array[PlayMoves.Moment]:
	var out: Array[PlayMoves.Moment] = []
	for m: PlayMoves.Moment in moves.by_key.get(key, []):
		if m.kind == kind:
			out.append(m)
	return out


# --- Who does what when ---


func test_a_grounder_to_short_is_caught_thrown_and_caught_at_first() -> void:
	var r: PlayResult = null
	for seed_value: int in 20:
		r = _run(_hit(125.0, -6.0, -15.0), [], 0, seed_value)
		if r.fielders == "6-3":
			break
	assert_eq(r.fielders, "6-3")
	var moves := PlayMoves.read(r.timeline, r.calls)
	var caught := _moments(moves, "F:SS", PlayMoves.Kind.CATCH)
	var threw := _moments(moves, "F:SS", PlayMoves.Kind.THROW)
	var took := _moments(moves, "F:1B", PlayMoves.Kind.CATCH)
	assert_eq(caught.size(), 1, "the shortstop fields it")
	assert_eq(threw.size(), 1, "and throws")
	assert_eq(took.size(), 1, "the first baseman takes the throw")
	if caught.is_empty() or threw.is_empty() or took.is_empty():
		return
	assert_lt(caught[0].time, threw[0].time, "fielded before thrown")
	assert_lt(threw[0].time, took[0].time, "thrown before it arrives")
	assert_lt(Vector2(threw[0].at.x, threw[0].at.y).distance_to(PlaySim.base_xy(1)), 2.0, "thrown to first")
	assert_lt(caught[0].at.z, 0.5, "a ground ball is caught low")
	assert_eq(moves.now("F:SS", caught[0].time), caught[0])
	assert_eq(moves.now("F:SS", threw[0].time), threw[0])
	assert_null(moves.now("F:SS", threw[0].time + 1.0), "nothing once the throw is done")
	# The out is called as the first baseman takes the throw on the bag, and the batter is
	# then still on his way, at a runner's pace.
	assert_eq(r.calls.size(), 1)
	assert_almost_eq(r.calls[0].time, took[0].time, 0.05, "called when the ball is held")
	var batter := r.timeline.position("R:b", took[0].time)
	assert_between(Vector2(batter.x, batter.y).length(), 5.0, 27.0, "the batter is on his way")
	# Nobody slides into first: the batter runs through the bag.
	for key: String in moves.by_key:
		assert_true(_moments(moves, key, PlayMoves.Kind.SLIDE).is_empty(), key)


func test_a_fly_to_centre_is_caught_in_the_air() -> void:
	var r := _run(_fly_to(91.0, 10.0, 36.0))
	assert_eq(r.fielders, "8")
	var moves := PlayMoves.read(r.timeline, r.calls)
	var caught := _moments(moves, "F:CF", PlayMoves.Kind.CATCH)
	assert_eq(caught.size(), 1)
	if not caught.is_empty():
		assert_gt(caught[0].at.z, 0.8, "taken above the knees")


func test_a_close_play_at_second_brings_a_slide() -> void:
	# A grounder with a runner on first: the force at second is often close.
	var slid := false
	for spray: float in [-15.0, -10.0, 5.0, 10.0]:
		for seed_value: int in 8:
			var r := _run(_hit(110.0, -6.0, spray), [1], 0, seed_value)
			var moves := PlayMoves.read(r.timeline, r.calls)
			for m: PlayMoves.Moment in _moments(moves, "R:r1", PlayMoves.Kind.SLIDE):
				slid = true
				assert_lt(Vector2(m.at.x, m.at.y).distance_to(PlaySim.base_xy(2)), 0.1, "into second")
	assert_true(slid, "some runner slid into second")


# --- The glove meets the ball (S12-8) ---


func _fielder(model: bool) -> Puppet:
	var p: Puppet = SkinnedPuppet.new() if model else Puppet.new()
	add_child_autofree(p)
	p.position = Field.to_world(Vector3(-8.0, 30.0, 0.0))
	p.rotation.y = MatchScene._yaw_toward(Vector2(-8.0, 30.0), Vector2.ZERO)
	return p


func _miss(p: Puppet, ball: Vector3) -> float:
	return (p.global_transform * p.glove_pocket()).distance_to(Field.to_world(ball))


func test_the_glove_pocket_meets_the_ball() -> void:
	for model: bool in [false, true]:
		if model and not SkinnedPuppet.available():
			continue
		var p := _fielder(model)
		var toward_plate := Vector2(8.0, -30.0).normalized()
		var glove_side := Vector2(toward_plate.y, -toward_plate.x)
		for spot: Vector3 in [Vector3(0.0, 0.0, 0.15), Vector3(0.2, 0.0, 1.1), Vector3(-0.3, 0.0, 1.5), Vector3(0.1, 0.0, 2.0), Vector3(0.0, 0.4, 0.3)]:
			# spot: x toward the glove side, y toward the plate, z height.
			var at := Vector2(-8.0, 30.0) + glove_side * spot.x + toward_plate * (0.45 + spot.y)
			var ball := Vector3(at.x, at.y, spot.z)
			MatchScene.catch(p, ball, 0.0)
			assert_lt(_miss(p, ball), 0.05, "%s glove at %s" % ["model" if model else "mannequin", spot])


func test_the_glove_reaches_out_only_around_the_catch() -> void:
	var p := _fielder(false)
	var ball := Vector3(-8.0, 29.4, 1.2)
	MatchScene.catch(p, ball, -0.6)
	var early := _miss(p, ball)
	MatchScene.catch(p, ball, 0.0)
	assert_lt(_miss(p, ball), 0.05)
	assert_gt(early, 0.05, "well before the ball arrives the glove is where the pose puts it")


# --- Feet stay planted ---


func _world_foot(pose: PuppetPose, foot: StringName, body: Vector3) -> Vector3:
	return body + (pose.r_foot if foot == &"r" else pose.l_foot)


func test_fielders_step_in_without_sliding_their_feet() -> void:
	var distance := 0.6
	var right_planted: Array[Vector3] = []
	var left_planted: Array[Vector3] = []
	for i: int in 21:
		var k := i / 20.0
		var pose := PuppetClips.creep(k, distance)
		assert_true(pose.hips.is_finite() and pose.r_foot.is_finite() and pose.l_foot.is_finite())
		var body := PuppetPose.at(0.0, 0.0, distance * k)
		if k >= 0.5:
			right_planted.append(_world_foot(pose, &"r", body))
		if k <= 0.5:
			left_planted.append(_world_foot(pose, &"l", body))
	for f: Vector3 in right_planted:
		assert_lt(f.distance_to(right_planted[0]), 0.01, "right foot down")
	for f: Vector3 in left_planted:
		assert_lt(f.distance_to(left_planted[0]), 0.01, "left foot down")
	var end := PuppetClips.creep(1.0, distance)
	assert_almost_eq(end.hips.y, PuppetClips.fielder_crouch().hips.y, 0.001, "in the crouch")


func test_runners_shuffle_without_sliding_their_feet() -> void:
	var length := 0.55
	for side: float in [1.0, -1.0]:
		var trail: Array[Vector3] = []
		var lead: Array[Vector3] = []
		for i: int in 21:
			var u := i / 20.0
			var pose := PuppetClips.shuffle(u, length, side)
			var body := Vector3(length * u * side, 0.0, 0.0)
			var trail_foot := &"l" if side > 0.0 else &"r"
			var lead_foot := &"r" if side > 0.0 else &"l"
			if u >= 0.5:
				trail.append(_world_foot(pose, trail_foot, body))
			if u <= 0.5:
				lead.append(_world_foot(pose, lead_foot, body))
		for f: Vector3 in trail:
			assert_lt(f.distance_to(trail[0]), 0.01, "trailing foot down once in")
		for f: Vector3 in lead:
			assert_lt(f.distance_to(lead[0]), 0.01, "leading foot down till it goes")
		# One step later the stance is as it was, moved along.
		var start := PuppetClips.shuffle(0.0, length, side)
		var finish := PuppetClips.shuffle(1.0, length, side)
		assert_almost_eq(finish.r_foot.x - finish.l_foot.x, start.r_foot.x - start.l_foot.x, 0.001)


func _frame(left: Vector3, right: Vector3, hips: Vector3) -> Dictionary[StringName, Vector3]:
	var f: Dictionary[StringName, Vector3] = {}
	f[&"LeftFoot"] = left
	f[&"RightFoot"] = right
	f[&"LeftLowerLeg"] = left.lerp(hips, 0.5)
	f[&"RightLowerLeg"] = right.lerp(hips, 0.5)
	f[&"LeftUpperLeg"] = hips + Vector3(-0.1, 0.0, 0.0)
	f[&"RightUpperLeg"] = hips + Vector3(0.1, 0.0, 0.0)
	f[&"ThoraxTop"] = hips + Vector3(0.0, 0.5, 0.0)
	return f


func test_the_pitcher_walks_back_a_foot_at_a_time() -> void:
	# Follow-through 1.4 m toward the plate (-Z), back to the set position.
	var finish := _frame(Vector3(-0.15, 0.08, -1.5), Vector3(0.2, 0.08, -1.2), Vector3(0.0, 0.9, -1.3))
	var set_frame := _frame(Vector3(-0.15, 0.08, 0.0), Vector3(0.15, 0.08, 0.05), Vector3(0.0, 0.95, 0.0))
	var steps := 0
	var was_moving: Dictionary[StringName, bool] = {&"LeftFoot": false, &"RightFoot": false}
	var last := PitchMotion.walk_back(finish, set_frame, 0.0)
	assert_eq(last[&"LeftFoot"], finish[&"LeftFoot"])
	for i: int in range(1, 101):
		var now := PitchMotion.walk_back(finish, set_frame, i / 100.0)
		var moving: Array[StringName] = []
		for foot: StringName in was_moving:
			var moved := now[foot].distance_to(last[foot]) > 0.0005
			if moved:
				moving.append(foot)
			if moved and not was_moving[foot]:
				steps += 1
			was_moving[foot] = moved
		assert_lt(moving.size(), 2, "never both feet off the ground at %d%%" % i)
		last = now
	assert_between(steps, 2, 6, "a few steps")
	for foot: StringName in [&"LeftFoot", &"RightFoot"] as Array[StringName]:
		assert_lt(last[foot].distance_to(set_frame[foot]), 0.001, "back on the rubber")


# --- Umpires (S12-6) ---


func test_umpire_signals_rise_and_fall() -> void:
	var stand := PuppetClips.umpire_signal(&"", 0.0)
	var strike := PuppetClips.umpire_signal(&"strike", 0.5)
	assert_gt(strike.r_hand.y, 1.6, "the right fist goes up for a strike")
	assert_lt(strike.l_hand.y, 1.3)
	var safe := PuppetClips.umpire_signal(&"safe", 0.5)
	assert_gt(safe.r_hand.x - safe.l_hand.x, 1.4, "both arms out for safe")
	var foul := PuppetClips.umpire_signal(&"foul", 0.5)
	assert_gt(minf(foul.r_hand.y, foul.l_hand.y), 1.8, "both arms up for a foul")
	var a := PuppetClips.umpire_signal(&"home_run", 0.4)
	var b := PuppetClips.umpire_signal(&"home_run", 0.6)
	assert_gt(a.r_hand.distance_to(b.r_hand), 0.02, "the hand circles for a home run")
	var done := PuppetClips.umpire_signal(&"strike", 2.0)
	assert_almost_eq(done.r_hand.y, stand.r_hand.y, 0.001, "and comes back down")
