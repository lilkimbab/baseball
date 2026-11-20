extends PlayTest
## The play after contact: who fields the ball, throws, runners, calls (docs/13 S5-2 to S5-7).

# --- Movement (S5-3, S5-5) ---


func test_an_average_runner_gets_down_the_line_in_about_4_3_seconds() -> void:
	assert_almost_eq(motion.batter_to_first(50.0, false), 4.3, 0.1, "right-handed batter")
	assert_lt(motion.batter_to_first(50.0, true), motion.batter_to_first(50.0, false), "a left-handed batter is a step closer")
	assert_almost_eq(motion.top_speed_for(99.0), 9.3, 0.01)
	assert_between(motion.path_factor, 1.03, 1.06, "rounding the bases is 3-6 % longer than the straight lines")


func test_an_average_catcher_pops_2_0_to_second() -> void:
	var throw := motion.throw_time(Field.SECOND_BASE.length(), motion.throw_speed(Position.Kind.C, 50.0))
	assert_almost_eq(motion.transfer_for(Position.Kind.C, 50.0) + throw, 2.0, 0.05)


func test_time_to_cover_inverts_distance_after() -> void:
	for d: float in [1.0, 10.0, 27.4, 60.0]:
		var t := motion.time_to_cover(d, 8.0)
		assert_almost_eq(motion.distance_after(t, 8.0), d, 0.01)


func test_a_ball_with_half_a_second_to_spare_is_caught_98_percent_of_the_time() -> void:
	assert_gt(motion.catch_chance(0.5) * (1.0 - motion.fly_drop), 0.98)


# --- Alignment (S5-2) ---


func test_every_alignment_keeps_to_the_shift_rule() -> void:
	for bases: Array[int] in [[] as Array[int], [1] as Array[int], [3] as Array[int], [1, 2] as Array[int], [1, 2, 3] as Array[int]]:
		for outs: int in 3:
			for inning: int in [1, 9]:
				var s := _state(bases, outs)
				s.inning = inning
				for left: bool in [false, true]:
					for bunt: bool in [false, true]:
						var at := alignment.positions(s, FenceProfile.symmetric(100.0, 116.0, 122.0, 2.6), left, bunt)
						assert_true(FieldingAlignment.legal(at), "bases %s outs %d inning %d" % [bases, outs, inning])


func test_the_first_baseman_holds_the_runner_at_the_bag() -> void:
	var at := alignment.positions(_state([1]), null, false)
	assert_lt(at[Position.Kind.B1].distance_to(PlaySim.base_xy(1)), 1.0)


func test_outfielders_stay_well_inside_a_short_fence() -> void:
	var fence := FenceProfile.symmetric(90.0, 100.0, 105.0, 3.0)
	var at := alignment.positions(_state(), fence, false)
	for kind: Position.Kind in Position.OUTFIELD:
		var p := at[kind]
		assert_lt(p.length(), fence.distance_at(rad_to_deg(atan2(p.x, p.y))) - 7.9)


# --- Fielding (S5-4) ---


func test_a_grounder_at_the_shortstop_is_his_and_he_throws_the_batter_out() -> void:
	var outs := 0
	for seed_value: int in 20:
		var r := _run(_hit(125.0, -6.0, -15.0), [], 0, seed_value)
		assert_eq(r.direction, 6, "the shortstop fields it")
		if r.result == PaResult.Kind.GROUND_OUT:
			outs += 1
			assert_eq(r.fielders, "6-3")
	assert_gt(outs, 17, "a routine grounder is an out")


func test_a_fly_between_centre_and_right_is_the_centre_fielder_s() -> void:
	# Halfway between where the two stand against a right-handed batter.
	var r := _run(_fly_to(91.0, 10.0, 36.0))
	assert_eq(r.result, PaResult.Kind.FLY_OUT)
	assert_eq(r.fielders, "8")


func test_the_pitcher_covers_first_when_the_first_baseman_fields_the_ball() -> void:
	# Grounders to the first baseman's right take him away from the bag.
	var found := false
	for spray: float in [12.0, 16.0, 20.0, 24.0]:
		for seed_value: int in 6:
			var r := _run(_hit(80.0, -8.0, spray), [], 0, seed_value)
			if r.direction == 3 and r.result == PaResult.Kind.GROUND_OUT and r.fielders != "3":
				found = true
				assert_eq(r.fielders, "3-1", "spray %d" % int(spray))
	assert_true(found, "some grounder to the first baseman was played to the pitcher covering")


func test_a_routine_grounder_to_short_beats_an_average_runner_by_a_comfortable_margin() -> void:
	# Fielded at normal depth and thrown across: time it against the runner.
	var c := _context(_hit(125.0, -6.0, -15.0))
	var sim := PlaySim.new()
	sim._setup(c, Rng.new(1))
	var ss := c.fielders[Position.Kind.SS]
	var chance := sim._ground_chance(ss)
	assert_not_null(chance)
	var at := Vector2(chance.at.x, chance.at.y)
	var release := chance.t + motion.transfer_for(Position.Kind.SS, 50.0)
	var arrives := release + motion.throw_time(at.distance_to(PlaySim.base_xy(1)), motion.throw_speed(Position.Kind.SS, 50.0))
	var margin := motion.batter_to_first(50.0, false) - arrives
	assert_between(margin, 0.3, 1.0, "routine play margin (s)")


func test_the_deepest_ball_in_the_hole_is_a_close_play_at_first() -> void:
	# Move the grounder toward third until the shortstop can only just get to it.
	var margin := INF
	for spray: float in range(-16, -36, -1):
		var c := _context(_hit(120.0, -6.0, float(spray)))
		var sim := PlaySim.new()
		sim._setup(c, Rng.new(1))
		var chance := sim._ground_chance(c.fielders[Position.Kind.SS])
		if chance == null or chance.dive or Position.OUTFIELD.has(chance.f.kind):
			break
		var at := Vector2(chance.at.x, chance.at.y)
		var release := chance.t + motion.transfer_for(Position.Kind.SS, 50.0) + (0.15 if chance.on_run else 0.0)
		var arrives := release + motion.throw_time(at.distance_to(PlaySim.base_xy(1)), motion.throw_speed(Position.Kind.SS, 50.0))
		margin = motion.batter_to_first(50.0, false) - arrives
	assert_between(margin, -0.2, 0.3, "deep in the hole: bang-bang at first")


func test_a_grounder_with_a_runner_on_first_is_often_turned_into_two() -> void:
	var doubles := 0
	for seed_value: int in 40:
		var r := _run(_hit(130.0, -6.0, -12.0), [1], 0, seed_value)
		if r.result == PaResult.Kind.DOUBLE_PLAY:
			doubles += 1
			assert_eq(r.fielders, "6-4-3")
	assert_gt(doubles, 20)


# --- Runners (S5-6) ---


func test_with_two_out_a_runner_on_second_tries_to_score_on_a_single() -> void:
	var tries := 0
	var n := 0
	for spray: float in [-30.0, -20.0, 20.0, 30.0]:
		var path := _hit(130.0, 12.0, spray)
		var r := _run(path, [2], 2, 3)
		if PaResult.is_hit(r.result) and r.result == PaResult.Kind.SINGLE:
			n += 1
			var m := _move_of(r, 2)
			if m != null and (m.to == 4 or (m.is_out() and m.out_at == 4)):
				tries += 1
	assert_gt(n, 0, "some of these are singles")
	assert_gt(tries, 0, "the runner goes home on contact with two out")


func test_a_runner_on_third_does_not_tag_on_a_shallow_fly() -> void:
	var r := _run(_fly_to(75.0, -3.0, 45.0), [3], 0)
	assert_eq(r.result, PaResult.Kind.FLY_OUT)
	assert_null(_move_of(r, 3), "he stays at third")


func test_a_runner_on_third_scores_on_a_deep_fly() -> void:
	var r := _run(_fly_to(95.0, 0.0), [3], 1)
	assert_eq(r.result, PaResult.Kind.SAC_FLY)
	assert_eq(_move_of(r, 3).to, 4)


func test_two_runners_never_end_on_the_same_base() -> void:
	var rng := Rng.new(99)
	var bad := 0
	for i: int in 300:
		var bases: Array[int] = []
		for b: int in [1, 2, 3]:
			if rng.chance(0.5):
				bases.append(b)
		var path := _hit(rng.next_range(60.0, 175.0), rng.next_range(-20.0, 50.0), rng.next_range(-44.0, 44.0), rng.next_range(-1500.0, 2500.0))
		var r := _run(path, bases, rng.next_int(3), i)
		if r.foul:
			continue
		var taken := {}
		var after: Array[int] = []
		for b: int in bases:
			after.append(b)
		for m: RunnerMove in r.moves:
			if m.from > 0:
				after.erase(m.from)
		for m: RunnerMove in r.moves:
			if not m.is_out() and m.to < 4:
				after.append(m.to)
		for b: int in after:
			if taken.has(b):
				bad += 1
			taken[b] = true
	assert_eq(bad, 0)


func test_the_same_seed_gives_the_same_play() -> void:
	var path := _hit(140.0, 12.0, -10.0)
	var a := _run(path, [1, 2], 1, 7)
	var b := _run(path, [1, 2], 1, 7)
	assert_eq(a.result, b.result)
	assert_eq(a.fielders, b.fielders)
	assert_eq(a.moves.size(), b.moves.size())


# --- Calls (S5-7) ---


func test_a_home_run_scores_everyone() -> void:
	var r := _run(_hit(175.0, 28.0, 0.0, 2200.0), [1, 2, 3])
	assert_eq(r.result, PaResult.Kind.HOME_RUN)
	var scored := 0
	for m: RunnerMove in r.moves:
		if m.scores():
			scored += 1
	assert_eq(scored, 4)


static func _line(points: Array[Vector3], times: Array[float], events: Array[BallEvent]) -> Trajectory:
	var t := Trajectory.new()
	for i: int in points.size():
		t.points.append(points[i])
		t.times.append(times[i])
	t.events = events
	return t


func test_a_grounder_that_rolls_foul_before_third_base_is_foul() -> void:
	var stop := BallEvent.make(BallEvent.Kind.STOP, 2.0, Vector3(-17.0, 16.0, 0.0), &"dirt", 0.0)
	var land := BallEvent.make(BallEvent.Kind.BOUNCE, 0.5, Vector3(-6.0, 7.0, 0.0), &"dirt", 10.0)
	var path := _line([Vector3(0, 0.3, 0.9), Vector3(-6.0, 7.0, 0.0), Vector3(-17.0, 16.0, 0.0)] as Array[Vector3], [0.0, 0.5, 2.0] as Array[float], [land, stop] as Array[BallEvent])
	assert_eq(Umpire.judge(path), Umpire.Call.FOUL)


func test_a_grounder_over_the_bag_that_then_rolls_foul_is_fair() -> void:
	var land := BallEvent.make(BallEvent.Kind.BOUNCE, 0.4, Vector3(-8.0, 9.0, 0.0), &"dirt", 30.0)
	var stop := BallEvent.make(BallEvent.Kind.STOP, 3.0, Vector3(-40.0, 30.0, 0.0), &"grass", 0.0)
	var path := _line([Vector3(0, 0.3, 0.9), Vector3(-8.0, 9.0, 0.0), Vector3(-19.3, 19.5, 0.0), Vector3(-40.0, 30.0, 0.0)] as Array[Vector3], [0.0, 0.4, 1.0, 3.0] as Array[float], [land, stop] as Array[BallEvent])
	assert_eq(Umpire.judge(path), Umpire.Call.FAIR)


func test_a_ball_off_the_first_base_bag_is_fair() -> void:
	var land := BallEvent.make(BallEvent.Kind.BOUNCE, 0.3, Vector3(8.0, 9.0, 0.0), &"dirt", 30.0)
	var stop := BallEvent.make(BallEvent.Kind.STOP, 3.0, Vector3(45.0, 30.0, 0.0), &"grass", 0.0)
	var bag := Field.base_centre(1)
	var path := _line([Vector3(0, 0.3, 0.9), Vector3(8.0, 9.0, 0.0), bag, Vector3(45.0, 30.0, 0.0)] as Array[Vector3], [0.0, 0.3, 0.9, 3.0] as Array[float], [land, stop] as Array[BallEvent])
	assert_eq(Umpire.judge(path), Umpire.Call.FAIR)


func test_a_fly_that_lands_on_the_line_is_fair() -> void:
	var land := BallEvent.make(BallEvent.Kind.BOUNCE, 3.0, Vector3(50.0, 49.97, 0.0), &"grass", 20.0)
	var path := _line([Vector3(0, 0.3, 0.9), Vector3(50.0, 49.97, 0.0)] as Array[Vector3], [0.0, 3.0] as Array[float], [land] as Array[BallEvent])
	assert_eq(Umpire.judge(path), Umpire.Call.FAIR)


func test_a_bounce_into_the_stands_is_a_ground_rule_double() -> void:
	# High over the centre fielder, down on the warning track, and over the fence.
	var land := BallEvent.make(BallEvent.Kind.BOUNCE, 3.6, Vector3(0.0, 118.0, 0.0), &"track", 25.0)
	var gone := BallEvent.make(BallEvent.Kind.OUT_OF_PLAY, 3.9, Vector3(0.0, 123.0, 3.0), &"", 20.0)
	var path := _line([Vector3(0, 0.3, 0.9), Vector3(0.0, 60.0, 30.0), Vector3(0.0, 112.0, 6.0), Vector3(0.0, 118.0, 0.0), Vector3(0.0, 123.0, 3.0)] as Array[Vector3], [0.0, 1.8, 3.4, 3.6, 3.9] as Array[float], [land, gone] as Array[BallEvent])
	assert_eq(Umpire.judge(path), Umpire.Call.GROUND_RULE_DOUBLE)
	var r := _run(path, [1])
	assert_eq(r.result, PaResult.Kind.DOUBLE)
	assert_eq(_move_of(r, 1).to, 3, "two bases for the runner too")


func test_plays_are_quick_to_work_out() -> void:
	var rng := Rng.new(5)
	var paths: Array[Trajectory] = []
	for i: int in 40:
		paths.append(_hit(rng.next_range(80.0, 170.0), rng.next_range(-15.0, 45.0), rng.next_range(-40.0, 40.0)))
	var start := Time.get_ticks_usec()
	for i: int in paths.size():
		_run(paths[i], [1, 2], 1, i)
	var per := float(Time.get_ticks_usec() - start) / paths.size() / 1000.0
	assert_lt(per, 8.0, "ms per play")
