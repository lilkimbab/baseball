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


func test_fly_ball_160_kmh_28_deg_carries_about_121_m() -> void:
	var r := _fly(160.0, 28.0, 2000.0)
	assert_between(r.x, 118.0, 124.0, "carry (m)")
	assert_between(r.y, 4.8, 5.4, "hang time (s)")


func test_fly_ball_170_kmh_28_deg() -> void:
	assert_between(_fly(170.0, 28.0, 2200.0).x, 126.0, 134.0, "carry (m)")


func test_fly_ball_150_kmh_30_deg() -> void:
	assert_between(_fly(150.0, 30.0, 2200.0).x, 108.0, 116.0, "carry (m)")


func test_pop_up_130_kmh_45_deg() -> void:
	var r := _fly(130.0, 45.0, 3000.0)
	assert_between(r.x, 81.0, 89.0, "carry (m)")
	assert_between(r.y, 5.2, 5.8, "hang time (s)")


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
