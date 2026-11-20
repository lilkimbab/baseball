extends PhysicsTest
## Free flight and bounces (docs/04 sections 4 and 8).


## Flies a batted ball until it comes down. Returns (carry m, hang time s).
func _fly(ev_kmh: float, launch_deg: float, backspin_rpm: float) -> Vector2:
	var ball := batted_ball(ev_kmh, launch_deg, backspin_rpm)
	var t := 0.0
	while t < 15.0:
		ball.pos = ball.integrate(BallFlight.DT)
		t += BallFlight.DT
		if ball.pos.z <= cfg.ball_radius:
			break
	return Vector2(ball.pos.y, t)


## Distance (ft) by launch angle and exit speed (80, 85 ... 115 mph) from A. Nathan's
## trajectory calculator, whose drag and lift were fitted to 2015 Statcast batted balls
## (baseball.physics.illinois.edu, TrajectoryCalculator-new.xlsx: sea level, 78 F, 50 %
## humidity, contact 3 ft up, backspin 2072 rpm x (mph / 100) x (angle - 7.2) / 20.3).
const STATCAST_CARRY := {
	15: [202, 224, 248, 273, 298, 325, 352, 381],
	20: [243, 269, 296, 324, 353, 382, 412, 443],
	25: [268, 295, 323, 351, 379, 408, 437, 466],
	30: [280, 306, 333, 359, 385, 412, 438, 464],
	35: [280, 305, 329, 352, 376, 399, 422, 444],
	40: [271, 293, 314, 335, 355, 374, 393, 411],
}
## Hang time (s) for 30 degrees at the same speeds.
const STATCAST_HANG_30: Array[float] = [4.23, 4.53, 4.83, 5.13, 5.44, 5.75, 6.06, 6.38]


func _statcast_ball(mph: float, launch_deg: float) -> BallSim:
	var air := PhysicsConfigIO.load_file(PhysicsConfigIO.DEFAULT_PATH)
	air.air_density = 1.175
	air.finalize()
	var ball := BallSim.new(air)
	var launch := deg_to_rad(launch_deg)
	var speed := mph * 0.44704
	ball.pos = Vector3(0.0, 0.0, 0.9144)
	ball.vel = Vector3(0.0, speed * cos(launch), speed * sin(launch))
	var spin := 2072.0 * (mph / 100.0) * (launch_deg - 7.2) / (27.5 - 7.2)
	ball.spin = Vector3(1.0, 0.0, 0.0) * rpm(spin)
	ball.hit()
	return ball


func _land(ball: BallSim) -> Vector2:
	var t := 0.0
	while t < 15.0:
		var before := ball.pos
		ball.pos = ball.integrate(BallFlight.DT)
		t += BallFlight.DT
		if ball.pos.z <= 0.0:
			var f := before.z / (before.z - ball.pos.z)
			return Vector2(lerpf(before.y, ball.pos.y, f), t - BallFlight.DT * (1.0 - f))
	return Vector2(ball.pos.y, t)


func test_batted_balls_carry_as_far_as_statcast_says() -> void:
	for angle: int in STATCAST_CARRY:
		for i: int in 8:
			var mph := 80.0 + 5.0 * i
			var feet := _land(_statcast_ball(mph, float(angle))).x / 0.3048
			var want: float = STATCAST_CARRY[angle][i]
			assert_almost_eq(feet, want, want * 0.02, "%d mph at %d deg (ft)" % [int(mph), angle])


func test_hang_times_match_statcast() -> void:
	for i: int in 8:
		var t := _land(_statcast_ball(80.0 + 5.0 * i, 30.0)).y
		assert_almost_eq(t, STATCAST_HANG_30[i], 0.12, "%d mph at 30 deg (s)" % (80 + 5 * i))


func test_a_hundred_mph_at_twenty_eight_degrees_goes_about_383_ft() -> void:
	var r := _fly(160.9, 28.0, 2100.0)
	assert_between(r.x / 0.3048, 370.0, 395.0, "carry (ft)")


func test_backspin_adds_carry() -> void:
	assert_gt(_fly(160.0, 28.0, 2000.0).x, _fly(160.0, 28.0, 0.0).x + 5.0)


func test_drag_shortens_flight_versus_vacuum() -> void:
	var speed := kmh(160.0)
	var vacuum_range := speed * speed * sin(deg_to_rad(56.0)) / cfg.gravity
	assert_lt(_fly(160.0, 28.0, 0.0).x, vacuum_range * 0.8)


func test_magnus_force_follows_spin_cross_velocity() -> void:
	var ball := BallSim.new(cfg)
	var v := Vector3(0.0, 40.0, 0.0)
	assert_gt(ball.aero(v, Vector3(rpm(2000.0), 0.0, 0.0)).z, 0.0, "backspin lifts")
	assert_lt(ball.aero(v, Vector3(-rpm(2000.0), 0.0, 0.0)).z, 0.0, "topspin sinks")
	assert_almost_eq(ball.aero(v, Vector3(0.0, rpm(2000.0), 0.0)).z, 0.0, 0.0001, "gyro spin does not bend the ball")
	assert_lt(ball.aero(v, Vector3.ZERO).y, 0.0, "drag opposes motion")


func test_same_input_gives_identical_result() -> void:
	assert_eq(_fly(155.0, 24.0, 1800.0), _fly(155.0, 24.0, 1800.0))


func test_clone_is_independent() -> void:
	var a := batted_ball(150.0, 20.0, 1500.0)
	var b := a.clone()
	a.pos = a.integrate(BallFlight.DT)
	assert_ne(a.pos, b.pos)
	assert_eq(b.pos, Vector3(0.0, 0.0, 1.0))


func test_bounce_reverses_normal_speed_and_loses_energy() -> void:
	var ball := BallSim.new(cfg)
	ball.vel = Vector3(0.0, 20.0, -10.0)
	var before := ball.vel.length()
	ball.bounce(Vector3(0.0, 0.0, 1.0), 0.45, 0.55)
	assert_almost_eq(ball.vel.z, 4.5, 0.001)
	assert_lt(ball.vel.length(), before)
	assert_gt(ball.vel.y, 0.0)


func test_bounce_ignores_a_ball_moving_away() -> void:
	var ball := BallSim.new(cfg)
	ball.vel = Vector3(0.0, 20.0, 3.0)
	ball.bounce(Vector3(0.0, 0.0, 1.0), 0.45, 0.55)
	assert_eq(ball.vel, Vector3(0.0, 20.0, 3.0))


func test_spin_changes_a_slow_bounce_but_not_a_fast_skid() -> void:
	var up := Vector3(0.0, 0.0, 1.0)
	# Slow ball: the surface grips, so spin decides whether it kicks forward or checks up.
	var top := BallSim.new(cfg)
	top.vel = Vector3(0.0, 8.0, -6.0)
	top.spin = Vector3(-rpm(2500.0), 0.0, 0.0)
	var back := BallSim.new(cfg)
	back.vel = Vector3(0.0, 8.0, -6.0)
	back.spin = Vector3(rpm(2500.0), 0.0, 0.0)
	top.bounce(up, 0.45, 0.55)
	back.bounce(up, 0.45, 0.55)
	assert_gt(top.vel.y, 8.0, "topspin kicks the ball forward")
	assert_lt(back.vel.y, 5.0, "backspin checks it up")

	# Hard-hit ball: it skids through the bounce, friction is at its limit either way.
	var fast_top := BallSim.new(cfg)
	fast_top.vel = Vector3(0.0, 30.0, -6.0)
	fast_top.spin = Vector3(-rpm(2500.0), 0.0, 0.0)
	var fast_back := BallSim.new(cfg)
	fast_back.vel = Vector3(0.0, 30.0, -6.0)
	fast_back.spin = Vector3(rpm(2500.0), 0.0, 0.0)
	fast_top.bounce(up, 0.45, 0.55)
	fast_back.bounce(up, 0.45, 0.55)
	assert_almost_eq(fast_top.vel.y, fast_back.vel.y, 0.001)
	assert_lt(fast_top.vel.y, 30.0)
