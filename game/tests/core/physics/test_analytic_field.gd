extends PhysicsTest
## Field geometry and collisions: ground, outfield fence, foul-territory walls, backstop.

var field: AnalyticField


func before_all() -> void:
	super.before_all()
	field = standard_field()


func test_fence_profile_passes_through_its_control_points() -> void:
	var fence := FenceProfile.symmetric(100.0, 116.0, 122.0, 2.6)
	assert_almost_eq(fence.distance_at(-45.0), 100.0, 0.01)
	assert_almost_eq(fence.distance_at(-22.5), 116.0, 0.01)
	assert_almost_eq(fence.distance_at(0.0), 122.0, 0.01)
	assert_almost_eq(fence.distance_at(45.0), 100.0, 0.01)
	assert_between(fence.distance_at(10.0), 116.0, 122.5, "smooth between points")
	assert_almost_eq(fence.distance_at(-30.0), fence.distance_at(30.0), 0.01, "symmetric")
	assert_almost_eq(fence.min_distance(), 100.0, 0.01)


func test_fence_height_is_constant_per_section() -> void:
	var fence := FenceProfile.new()
	fence.add_point(-45.0, 99.0, 3.2).add_point(0.0, 122.0, 2.6).add_point(20.0, 112.0, 7.0).add_point(45.0, 95.0, 7.0)
	assert_almost_eq(fence.height_at(-30.0), 3.2, 0.001)
	assert_almost_eq(fence.height_at(10.0), 2.6, 0.001)
	assert_almost_eq(fence.height_at(30.0), 7.0, 0.001)
	assert_almost_eq(fence.height_at(45.0), 7.0, 0.001)


func test_boundary_follows_fence_side_walls_and_backstop() -> void:
	assert_almost_eq(field.boundary_distance(0.0), 122.0, 0.05, "centre field")
	assert_almost_eq(field.boundary_distance(-45.0), 100.0, 0.05, "left-field pole")
	assert_almost_eq(field.boundary_distance(180.0), 16.5, 0.05, "backstop")
	assert_almost_eq(field.boundary_distance(90.0), field.boundary_distance(-90.0), 0.01, "symmetric foul territory")
	assert_between(field.boundary_distance(90.0), 16.5, 60.0, "side wall")
	assert_almost_eq(field.boundary_height(0.0), 2.6, 0.001)
	assert_gt(field.boundary_height(180.0), 5.0, "backstop net is tall")


func test_ground_surface_zones() -> void:
	assert_eq(field.surface_at(Vector3(0.0, 80.0, 0.0)), &"grass", "outfield")
	assert_eq(field.surface_at(Vector3(0.0, 8.0, 0.0)), &"grass", "infield grass")
	assert_eq(field.surface_at(Vector3(0.0, 1.0, 0.0)), &"dirt", "around home plate")
	assert_eq(field.surface_at(Vector3(0.0, 18.0, 0.0)), &"dirt", "mound")
	assert_eq(field.surface_at(Vector3(13.0, 28.0, 0.0)), &"dirt", "infield skin")
	assert_eq(field.surface_at(Vector3(0.0, 120.0, 0.0)), &"track", "warning track")
	var turf := AnalyticField.create(FenceProfile.symmetric(99.0, 114.0, 122.0, 4.0), 16.5, 14.0, 4.0, &"turf")
	assert_eq(turf.surface_at(Vector3(0.0, 80.0, 0.0)), &"turf")


func test_sweep_finds_the_ground() -> void:
	var hit := field.sweep(Vector3(0.0, 50.0, 1.0), Vector3(0.0, 50.4, -0.5), cfg.ball_radius)
	assert_not_null(hit)
	assert_eq(hit.normal, Vector3(0.0, 0.0, 1.0))
	assert_almost_eq(hit.point.z, cfg.ball_radius, 0.0001)
	assert_eq(hit.surface, &"grass")
	assert_null(field.sweep(Vector3(0.0, 50.0, 1.0), Vector3(0.0, 50.4, 0.9), cfg.ball_radius), "still in the air")


func test_sweep_hits_the_fence_below_its_top_and_clears_above() -> void:
	var low := field.sweep(Vector3(0.0, 121.0, 1.5), Vector3(0.0, 123.0, 1.5), cfg.ball_radius)
	assert_not_null(low, "line drive into the wall")
	assert_eq(low.surface, &"wall_pad")
	assert_almost_eq(low.normal.y, -1.0, 0.01, "normal points back toward home")
	assert_almost_eq(low.point.y, 122.0 - cfg.ball_radius, 0.05)
	assert_null(field.sweep(Vector3(0.0, 121.0, 4.0), Vector3(0.0, 123.0, 4.0), cfg.ball_radius), "over the wall")


func test_out_of_play_is_beyond_the_boundary() -> void:
	assert_false(field.is_out_of_play(Vector3(0.0, 121.0, 5.0)))
	assert_true(field.is_out_of_play(Vector3(0.0, 123.0, 5.0)))
	assert_true(field.is_out_of_play(Vector3(0.0, -20.0, 3.0)), "behind the backstop")


func test_a_long_fly_ball_is_a_home_run() -> void:
	var path := BallFlight.run(batted_ball(170.0, 28.0, 2200.0), field)
	assert_true(path.is_home_run())
	assert_between(path.end_point().y, 122.0, 123.5, "leaves play just past the centre-field fence")


func test_a_fly_ball_short_of_the_fence_lands_and_stops_in_play() -> void:
	var path := BallFlight.run(batted_ball(150.0, 30.0, 2200.0), field)
	assert_false(path.is_home_run())
	var landing := path.first_event(BallEvent.Kind.BOUNCE)
	assert_not_null(landing)
	# Statcast: 93 mph at 30 degrees carries about 350 ft (107 m).
	assert_between(Trajectory.ground_distance(landing.pos), 102.0, 110.0)
	assert_not_null(path.first_event(BallEvent.Kind.STOP), "comes to rest")
	assert_false(field.is_out_of_play(path.end_point()))


func test_a_ball_driven_into_the_wall_comes_back_slower() -> void:
	var ball := BallSim.new(cfg)
	ball.pos = Vector3(0.0, 112.0, 1.6)
	ball.vel = Vector3(0.0, 35.0, 1.0)
	var path := BallFlight.run(ball, field)
	var wall := path.first_event(BallEvent.Kind.WALL)
	assert_not_null(wall, "hits the centre-field fence")
	assert_eq(wall.surface, &"wall_pad")
	assert_eq(path.events[0].kind, BallEvent.Kind.WALL, "the wall is the first thing it touches")
	assert_lt(wall.speed, 35.0 * 0.6, "padding takes most of the speed")
	assert_false(path.is_home_run())
	assert_false(field.is_out_of_play(path.end_point()), "stays in play")
	assert_lt(path.end_point().y, 122.0 - 1.0, "ends up in front of the wall")


func test_a_ball_rolling_into_the_wall_stops_there() -> void:
	var ball := BallSim.new(cfg)
	ball.pos = Vector3(0.0, 118.0, cfg.ball_radius)
	ball.vel = Vector3(0.0, 12.0, 0.0)
	ball.rolling = true
	var path := BallFlight.run(ball, field)
	assert_not_null(path.first_event(BallEvent.Kind.WALL))
	assert_not_null(path.first_event(BallEvent.Kind.STOP))
	assert_false(field.is_out_of_play(path.end_point()))


func test_a_foul_pop_behind_the_plate_goes_out_of_play_or_stays_short() -> void:
	var ball := batted_ball(120.0, 60.0, 3000.0, 170.0)
	var path := BallFlight.run(ball, field)
	assert_false(path.is_home_run(), "never a home run in foul territory")


func test_prediction_equals_the_real_flight() -> void:
	var real := batted_ball(155.0, 18.0, 1500.0, -12.0)
	var predicted := BallFlight.run(real.clone(), field, 15.0, BallFlight.DT, false)
	var steps := 0
	while not real.stopped and steps < 5000:
		real.advance(BallFlight.DT, field)
		steps += 1
	assert_eq(real.pos, predicted.end_point(), "the forecast is the same code as the flight")


func test_trajectory_lookup_by_time_and_distance() -> void:
	var path := BallFlight.run(batted_ball(150.0, -5.0, -1500.0, 0.0, 0.8), field)
	var t40 := path.time_at_distance(40.0)
	assert_gt(t40, 0.0)
	# Rolling balls are sampled every 1/60 s, so within one step of 40 m.
	assert_almost_eq(Trajectory.ground_distance(path.position_at(t40)), 40.0, 0.7)
	assert_eq(path.time_at_distance(500.0), -1.0)
	assert_eq(path.position_at(-1.0), path.points[0])


func test_longer_steps_where_nothing_can_be_hit_land_in_the_same_place() -> void:
	var worst := 0.0
	for speed_kmh: float in [100.0, 140.0, 170.0] as Array[float]:
		for launch: float in [-5.0, 10.0, 25.0, 45.0] as Array[float]:
			for spray: float in [-35.0, 0.0, 30.0] as Array[float]:
				var fine := BallFlight.run(batted_ball(speed_kmh, launch, 1800.0, spray), field, 15.0, BallFlight.DT, false)
				var quick := BallFlight.run(batted_ball(speed_kmh, launch, 1800.0, spray), field)
				if fine.events.is_empty() or quick.events.is_empty():
					continue
				worst = maxf(worst, fine.events[0].pos.distance_to(quick.events[0].pos))
	# Over flights of up to 130 m this is a thousandth of the distance: far below anything a
	# fielder or a ruling could notice.
	assert_lt(worst, 0.15, "first landing within 15 cm of the fine-step flight")
