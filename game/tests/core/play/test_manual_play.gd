extends PlayTest
## The player's own fielding in the play (docs/04 2.3), the chances that could have gone
## either way and the tries that came up short (docs/04 3.4), and a play taken up part way.


func _manual(kind: Position.Kind, time: float = -1.0, at: Vector3 = Vector3.ZERO) -> PlayChoice:
	var p := PlayChoice.new()
	p.manual_fielder = kind
	p.manual_time = time
	p.manual_at = at
	return p


func _choose(path: Trajectory, bases: Array[int], outs: int, seed_value: int, choice: PlayChoice) -> PlayResult:
	var c := _context(path, bases, outs)
	choice.apply(c)
	return PlaySim.run(c, Rng.new(seed_value))


## When and where the ball is `distance` m out along its path.
func _where(path: Trajectory, distance: float) -> Vector4:
	var t := 0.0
	while t < path.duration():
		var p := path.position_at(t)
		if Trajectory.ground_distance(p) >= distance:
			return Vector4(t, p.x, p.y, p.z)
		t += 0.01
	var end := path.end_point()
	return Vector4(path.duration(), end.x, end.y, end.z)


# --- The player's own fielder ---


func test_a_grounder_the_player_s_shortstop_never_gets_to_goes_through() -> void:
	var path := _hit(125.0, -6.0, -15.0)
	for seed_value: int in 10:
		var r := _choose(path, [], 0, seed_value, _manual(Position.Kind.SS))
		assert_ne(r.direction, 6, "he is not given the ball he did not field (seed %d)" % seed_value)
		assert_ne(r.result, PaResult.Kind.GROUND_OUT, "and with nobody else there it is no out at first")
		var first := PlayMoves.read(r.timeline, r.calls)
		assert_false(first.by_key.has("F:SS") and (first.by_key["F:SS"] as Array).any(func(m: PlayMoves.Moment) -> bool: return m.kind == PlayMoves.Kind.CATCH and m.time < 2.0),
			"nor is he shown fielding it")


func test_a_grounder_the_player_s_shortstop_fields_is_thrown_to_first() -> void:
	var path := _hit(125.0, -6.0, -15.0)
	var got := _where(path, 38.0)
	var outs := 0
	for seed_value: int in 10:
		var choice := _manual(Position.Kind.SS, got.x, Vector3(got.y, got.z, got.w))
		choice.manual_track = PackedVector3Array([Vector3(0.5, got.y - 2.0, got.z), Vector3(got.x, got.y - 0.6, got.z)])
		var r := _choose(path, [], 0, seed_value, choice)
		assert_eq(r.direction, 6, "the shortstop has it")
		if r.result == PaResult.Kind.GROUND_OUT:
			outs += 1
			assert_eq(r.fielders, "6-3")
		# He is shown where the player took him, not on a line from where he stood.
		var shown := r.timeline.position("F:SS", 0.5)
		assert_almost_eq(shown.x, got.y - 2.0, 0.01)
	assert_gt(outs, 7, "fielded in time, it is the same out")


func test_he_cannot_throw_before_the_player_has_said_where() -> void:
	var path := _hit(125.0, -6.0, -15.0)
	var got := _where(path, 38.0)
	var choice := _manual(Position.Kind.SS, got.x, Vector3(got.y, got.z, got.w))
	var quick := _choose(path, [], 0, 2, choice)
	choice.manual_ready = got.x + 1.6
	var late := _choose(path, [], 0, 2, choice)
	assert_gt(quick.timeline.throws.size(), 0)
	assert_lt(quick.timeline.throws[0][0].x, got.x + 1.2, "at once, he lets it go as soon as he can")
	assert_gte(late.timeline.throws[0][0].x, got.x + 1.6 - 1e-6, "held, not before the player let him")


func test_a_fly_the_player_s_centre_fielder_catches_is_an_out_and_one_he_does_not_is_a_hit() -> void:
	var path := _fly_to(95.0, 3.0, 34.0)
	var auto := _run(path)
	assert_eq(auto.result, PaResult.Kind.FLY_OUT, "by itself: a routine fly to centre")
	assert_eq(auto.direction, 8)
	var land := path.events[0]
	# Caught a moment before it comes down.
	var t := land.time - 0.06
	var caught := _choose(path, [], 0, 1, _manual(Position.Kind.CF, t, path.position_at(t)))
	assert_eq(caught.result, PaResult.Kind.FLY_OUT)
	assert_eq(caught.fielders, "8")
	var dropped := _choose(path, [], 0, 1, _manual(Position.Kind.CF))
	assert_true(PaResult.is_hit(dropped.result), "nobody else was going for it: it falls for a hit")
	assert_ne(dropped.direction, 8, "and a team-mate runs it down")


func test_runners_wait_on_a_fly_the_player_may_catch() -> void:
	# A man on first on a fly to centre: he goes part way and waits, whoever catches it or not.
	var path := _fly_to(95.0, 3.0, 34.0)
	var land := path.events[0].time
	var waiting := _choose(path, [1], 0, 1, _manual(Position.Kind.CF))
	var at := waiting.timeline.position("R:r1", land - 0.2)
	var bag := PlaySim.base_xy(1)
	assert_between(Vector2(at.x, at.y).distance_to(bag), 3.0, 16.0, "part way, not off for second")


# --- Chances in doubt, tries that came up short ---


func test_a_routine_play_has_no_hard_chance_and_a_grounder_no_fence() -> void:
	var fly := _run(_fly_to(91.0, 10.0, 36.0))
	assert_false(fly.has_hard_chance())
	assert_between(fly.short_of_fence, 15.0, 40.0, "caught well short of the fence")
	var grounder := _run(_hit(125.0, -6.0, -15.0))
	assert_false(grounder.has_hard_chance())
	assert_eq(grounder.short_of_fence, INF)


func test_a_fly_to_the_foot_of_the_fence_is_noted_as_one() -> void:
	var found := false
	for distance: float in [112.0, 114.0, 116.0, 118.0]:
		var r := _run(_fly_to(distance, 0.0, 30.0))
		if r.result != PaResult.Kind.HOME_RUN and r.short_of_fence < 6.0:
			found = true
			assert_gt(r.short_of_fence, -0.5)
	assert_true(found, "some deep fly came down by the fence")


func test_a_ball_in_the_gap_is_a_chance_in_doubt_and_a_missed_dive_is_shown() -> void:
	var made := 0
	var missed := 0
	var shown := 0
	for spray: float in [-28.0, -24.0, -20.0, 14.0, 18.0, 22.0, 26.0]:
		for distance: float in [70.0, 76.0, 82.0, 88.0]:
			var path := _fly_to(distance, spray, 24.0)
			for seed_value: int in 8:
				var r := _run(path, [], 0, seed_value)
				if not r.has_hard_chance():
					continue
				assert_between(r.hard_odds, 0.0, 1.0)
				if r.hard_made:
					made += 1
					assert_true(r.result == PaResult.Kind.FLY_OUT or r.result == PaResult.Kind.LINE_OUT or not r.hard_air)
					continue
				missed += 1
				if r.timeline.miss_keys.is_empty():
					continue
				shown += 1
				# The man who dived is laid out near where the ball went by, and is not the
				# one shown catching it then.
				var key := r.timeline.miss_keys[0]
				var miss := r.timeline.misses[0]
				var he := r.timeline.position(key, miss.x)
				var off := Vector2(he.x - miss.y, he.y - miss.z).length()
				assert_between(off, 0.5, PlaySim.MISSED_BY + 0.1, "short of it by a dive's length")
				var moves := PlayMoves.read(r.timeline, r.calls)
				var kinds := (moves.by_key[key] as Array).map(func(m: PlayMoves.Moment) -> int: return m.kind)
				assert_has(kinds, PlayMoves.Kind.MISS)
				for m: PlayMoves.Moment in moves.by_key[key]:
					if m.kind == PlayMoves.Kind.CATCH:
						assert_gt(m.time, miss.x + 0.5, "he does not catch what he missed")
	assert_gt(made, 3, "hard catches made")
	assert_gt(missed, 3, "and missed")
	assert_eq(shown, missed, "every try that came up short is in the timeline")


func test_a_diving_stop_leaves_him_a_dive_s_length_from_the_ball() -> void:
	# Grounders in the hole between short and third, harder and harder to get to.
	var found := false
	for spray: float in range(-18, -34, -1):
		for seed_value: int in 6:
			var r := _run(_hit(130.0, -6.0, float(spray)), [], 0, seed_value)
			if not r.hard_made or r.hard_air:
				continue
			found = true
			var key := "F:%s" % Position.code(r.hard_fielder)
			var he := r.timeline.position(key, r.hard_time)
			var off := Vector2(he.x - r.hard_at.x, he.y - r.hard_at.y).length()
			assert_almost_eq(off, PlaySim.STRETCH, 0.05, "at full stretch")
			var up := r.timeline.position(key, r.hard_time + PlaySim.UP_AGAIN)
			assert_lt(Vector2(up.x - r.hard_at.x, up.y - r.hard_at.y).length(), 0.05, "and up where it was")
			assert_eq(r.direction, Position.scoring_number(r.hard_fielder), "the ball is his")
	assert_true(found, "some grounder was stopped with a dive")


func test_the_first_baseman_goes_to_the_ball_before_he_takes_it_to_the_bag() -> void:
	# (He used to be shown running from where he stood straight to the bag.)
	var found := false
	for spray: float in [30.0, 34.0, 38.0, 41.0]:
		for seed_value: int in 4:
			var path := _hit(95.0, -8.0, spray)
			var r := _run(path, [], 0, seed_value)
			if r.fielders != "3":
				continue
			found = true
			var moves := PlayMoves.read(r.timeline, r.calls)
			var first: PlayMoves.Moment = null
			for m: PlayMoves.Moment in moves.by_key.get("F:1B", []):
				if m.kind == PlayMoves.Kind.CATCH and first == null:
					first = m
			assert_not_null(first, "he fields it")
			if first == null:
				continue
			var ball := path.position_at(first.time)
			var he := r.timeline.position("F:1B", first.time)
			assert_lt(Vector2(he.x - ball.x, he.y - ball.y).length(), PlayMoves.REACH + 0.01)
			assert_lt(first.time, r.timeline.duration - 0.2, "before he is on the bag with it")
	assert_true(found, "some grounder was taken to the bag by the first baseman himself")


# --- A play taken up part way ---


func test_a_play_taken_up_part_way_moves_nobody_at_once() -> void:
	var next := PlayTimeline.new()
	next.add("F:SS", 0.0, Vector3(-8.0, 40.0, 0.0))
	next.add("F:SS", 2.0, Vector3(0.0, 38.0, 0.0))
	next.add("F:CF", 0.0, Vector3(0.0, 95.0, 0.0))
	next.add("R:a", 0.0, Vector3(19.0, 19.0, 0.0))
	next.add("R:a", 4.0, Vector3(0.0, 38.8, 0.0))
	next.add("ball", 0.0, Vector3(0.0, 0.3, 0.9))
	next.add("ball", 3.0, Vector3(0.0, 60.0, 0.0))
	var shown: Dictionary[String, Vector3] = {
		"F:SS": Vector3(-14.0, 44.0, 0.0), "F:CF": Vector3(1.0, 94.0, 0.0), "R:a": Vector3(19.0, 19.0, 0.0),
	}
	var joined := PlayTimeline.stitched(next, 1.0, shown)
	assert_eq(joined.duration, next.duration)
	assert_eq(joined.position("F:SS", 1.0), Vector3(-14.0, 44.0, 0.0), "he is where he was shown")
	assert_eq(joined.position("ball", 1.5), next.position("ball", 1.5), "the ball is the new play's")
	# He runs to where the new play has him and is with it from then on.
	var worst := 0.0
	var t := 1.0
	while t < 4.0:
		var a := joined.position("F:SS", t)
		var b := joined.position("F:SS", t + 0.05)
		worst = maxf(worst, Vector2(b.x - a.x, b.y - a.y).length() / 0.05)
		t += 0.05
	assert_lt(worst, 9.6, "at a run, no faster")
	assert_eq(joined.position("F:SS", 2.6), next.position("F:SS", 2.6))
	# One the new play leaves standing a step away stays put; a runner goes on from his spot.
	assert_eq(joined.position("F:CF", 3.0), Vector3(1.0, 94.0, 0.0))
	assert_eq(joined.position("R:a", 4.0), next.position("R:a", 4.0))
