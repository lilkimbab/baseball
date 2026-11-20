extends PhysicsTest
## Air density from weather and elevation (Air).


func test_density_matches_the_trajectory_calculator() -> void:
	# Nathan's calculator: 78 F (25.6 C), sea level, 50 % humidity -> 1.1750 kg/m^3.
	assert_almost_eq(Air.density(25.5556, 0.0, 50.0), 1.17495, 0.0005)
	# Dry air at 20 C is the 1.20 the physics uses by default.
	assert_almost_eq(Air.density(20.0, 0.0, 0.0), 1.2046, 0.001)


func test_warm_humid_high_air_is_thinner() -> void:
	assert_lt(Air.density(30.0), Air.density(5.0), "a summer night against an April one")
	assert_lt(Air.density(20.0, 0.0, 90.0), Air.density(20.0, 0.0, 10.0), "humid air is lighter")
	assert_lt(Air.density(20.0, 1600.0), Air.density(20.0, 0.0) * 0.85, "a mile up")


func test_a_fly_ball_carries_farther_in_thin_air() -> void:
	var sea := Air.config_for(cfg, 20.0, 0.0)
	var mile := Air.config_for(cfg, 20.0, 1600.0)
	var near := _carry(sea)
	var far := _carry(mile)
	assert_between(far / near, 1.04, 1.08, "about 5 % farther a mile up")
	assert_almost_eq(cfg.air_density, 1.2, 1e-6, "the shared physics is untouched")


func _carry(c: PhysicsConfig) -> float:
	var ball := BallSim.new(c)
	var speed := 100.0 * 0.44704
	ball.pos = Vector3(0.0, 0.0, 0.9)
	ball.vel = Vector3(0.0, speed * cos(deg_to_rad(28.0)), speed * sin(deg_to_rad(28.0)))
	ball.spin = Vector3(rpm(2100.0), 0.0, 0.0)
	ball.hit()
	while ball.pos.z > 0.0:
		ball.pos = ball.integrate(1.0 / 240.0)
	return ball.pos.y
