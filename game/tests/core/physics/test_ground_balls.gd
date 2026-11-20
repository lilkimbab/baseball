extends PhysicsTest
## Ground balls: bounce losses and rolling resistance (docs/04 section 8.2).
## The target ranges are estimates from how long infielders and outfielders have on such
## balls; the surface constants in data/physics.json were tuned to meet them.

var field: AnalyticField


func before_all() -> void:
	super.before_all()
	field = standard_field()


func _grounder(ev_kmh: float, launch_deg: float, on: AnalyticField = null) -> Trajectory:
	var ball := batted_ball(ev_kmh, launch_deg, -1500.0, 0.0, 0.8)
	ball.pos = Vector3(0.0, 0.6, 0.8)
	return BallFlight.run(ball, field if on == null else on, 20.0)


func _rest(path: Trajectory) -> float:
	return Trajectory.ground_distance(path.end_point())


func test_hard_grounder_150_kmh_reaches_shortstop_depth_in_about_1_25_s() -> void:
	var path := _grounder(150.0, -5.0)
	assert_between(path.time_at_distance(40.0), 1.15, 1.35, "time to 40 m (s)")
	assert_between(path.time_at_distance(70.0), 2.6, 3.3, "time to 70 m (s)")
	assert_between(_rest(path), 85.0, 100.0, "comes to rest (m)")


func test_scorched_grounder_165_kmh() -> void:
	var path := _grounder(165.0, -3.0)
	assert_between(path.time_at_distance(40.0), 1.0, 1.2, "time to 40 m (s)")
	assert_between(_rest(path), 95.0, 112.0, "comes to rest (m)")


func test_routine_grounder_120_kmh() -> void:
	var path := _grounder(120.0, -10.0)
	assert_between(path.time_at_distance(40.0), 1.6, 1.9, "time to 40 m (s)")
	assert_between(_rest(path), 60.0, 80.0, "comes to rest (m)")


func test_weak_roller_80_kmh_dies_in_the_shallow_outfield() -> void:
	assert_between(_rest(_grounder(80.0, -20.0)), 35.0, 55.0, "comes to rest (m)")


func test_harder_hit_balls_go_farther_and_arrive_sooner() -> void:
	var speeds: Array[float] = [80.0, 100.0, 120.0, 135.0, 150.0, 165.0]
	var previous_rest := 0.0
	var previous_time := INF
	for ev: float in speeds:
		var path := _grounder(ev, -8.0)
		var rest := _rest(path)
		var t30 := path.time_at_distance(30.0)
		assert_gt(rest, previous_rest, "%d km/h rolls farther than the slower one" % int(ev))
		assert_lt(t30, previous_time, "%d km/h gets to 30 m sooner" % int(ev))
		previous_rest = rest
		previous_time = t30


func test_grounders_up_the_middle_never_reach_the_fence() -> void:
	for ev: float in [120.0, 150.0, 165.0] as Array[float]:
		var path := _grounder(ev, -4.0)
		assert_null(path.first_event(BallEvent.Kind.WALL), "%d km/h" % int(ev))
		assert_not_null(path.first_event(BallEvent.Kind.STOP), "%d km/h stops" % int(ev))


func test_ball_bounces_a_few_times_then_rolls() -> void:
	var path := _grounder(150.0, -5.0)
	assert_between(path.count_events(BallEvent.Kind.BOUNCE), 2, 8)
	assert_eq(path.count_events(BallEvent.Kind.ROLL_START), 1)
	var roll := path.first_event(BallEvent.Kind.ROLL_START)
	assert_lt(roll.time, 1.5, "rolling well before it reaches the outfield")


func test_artificial_turf_plays_faster_than_grass() -> void:
	var turf := AnalyticField.create(FenceProfile.symmetric(100.0, 116.0, 122.0, 2.6), 16.5, 14.0, 4.0, &"turf")
	var on_grass := _grounder(140.0, -6.0)
	var on_turf := _grounder(140.0, -6.0, turf)
	assert_gt(_rest(on_turf), _rest(on_grass) + 5.0)
	assert_lt(on_turf.time_at_distance(60.0), on_grass.time_at_distance(60.0))


func test_rolling_ball_spins_in_the_direction_of_travel() -> void:
	var ball := batted_ball(120.0, -10.0, -1500.0, 20.0, 0.8)
	var guard := 0
	while not ball.rolling and guard < 5000:
		ball.advance(BallFlight.DT, field)
		guard += 1
	ball.advance(BallFlight.DT, field)
	assert_true(ball.rolling)
	assert_almost_eq(ball.pos.z, cfg.ball_radius, 0.001, "sits on the ground")
	assert_almost_eq(ball.spin.length() * cfg.ball_radius, ball.vel.length(), 0.01, "rolls without slipping")
	assert_almost_eq(ball.spin.dot(ball.vel), 0.0, 0.01, "spin axis is across the path")
