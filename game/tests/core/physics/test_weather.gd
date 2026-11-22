extends PhysicsTest
## The weather of a game (docs/08 R3): the wind carries a batted ball, warm air carries it
## farther, a dome has no wind, and the draw follows the season.

## Where a fly first comes down (m from the plate) in still air or with `wind` (field m/s).
func _carry(wind: Vector3, ev_kmh: float = 161.0, launch_deg: float = 28.0, config: PhysicsConfig = null) -> float:
	var c := config if config != null else cfg
	if wind != Vector3.ZERO:
		c = c.duplicate_config()
		c.wind = wind
		c.finalize()
	var ball := batted_ball(ev_kmh, launch_deg, 2200.0)
	ball.cfg = c
	var field := AnalyticField.create(FenceProfile.symmetric(300.0, 300.0, 300.0, 1.0))
	var path := BallFlight.run(ball, field)
	return Trajectory.ground_distance(path.events[0].pos)


func test_a_five_metre_wind_moves_a_hundred_mph_fly_about_ten_metres() -> void:
	# Nathan's calculator: a 100 mph, 28 degree fly carries some 120 m in still air at sea level;
	# a 5 m/s (11 mph) wind straight out adds about 10-14 m, straight in takes off a little
	# more (the ball meets the air faster).
	var still := _carry(Vector3.ZERO)
	var out := _carry(Vector3(0.0, 5.0, 0.0))
	var back := _carry(Vector3(0.0, -5.0, 0.0))
	assert_between(still, 112.0, 128.0, "still air")
	assert_between(out - still, 7.0, 15.0, "blowing out")
	assert_between(still - back, 6.0, 16.0, "blowing in")
	assert_gt(still - back, out - still, "a head wind costs more than a tail wind gives")


func test_a_cross_wind_pushes_the_ball_sideways_and_a_grounder_hardly_at_all() -> void:
	var c := cfg.duplicate_config()
	c.wind = Vector3(5.0, 0.0, 0.0)
	c.finalize()
	var fly := batted_ball(161.0, 28.0, 2200.0)
	fly.cfg = c
	var field := AnalyticField.create(FenceProfile.symmetric(300.0, 300.0, 300.0, 1.0))
	var land := BallFlight.run(fly, field).events[0].pos
	assert_between(land.x, 4.0, 16.0, "carried toward first base")
	var grounder := batted_ball(150.0, -5.0, 0.0)
	grounder.cfg = c
	var first := BallFlight.run(grounder, field).events[0].pos
	assert_lt(absf(first.x), 0.2, "a grounder is down before the wind can move it")


func test_a_pitch_is_not_blown_off_its_target() -> void:
	# Only batted balls feel the wind (a pitch is aimed in still air).
	var c := cfg.duplicate_config()
	c.wind = Vector3(6.0, -6.0, 0.0)
	c.finalize()
	var ball := BallSim.new(c)
	ball.pos = RELEASE
	ball.vel = Vector3(0.0, -kmh(145.0), 0.0)
	var still := BallSim.new(cfg)
	still.pos = RELEASE
	still.vel = ball.vel
	for i: int in 60:
		ball.pos = ball.integrate(1.0 / 240.0)
		still.pos = still.integrate(1.0 / 240.0)
	assert_lt(ball.pos.distance_to(still.pos), 1e-6)


func test_warm_damp_air_carries_farther_than_cold() -> void:
	var hot := Air.config_for(cfg, 32.0, 0.0, 80.0)
	var cold := Air.config_for(cfg, 8.0, 0.0, 40.0)
	var difference := _carry(Vector3.ZERO, 161.0, 28.0, hot) - _carry(Vector3.ZERO, 161.0, 28.0, cold)
	# About 1 m for every 4 degrees.
	assert_between(difference, 3.0, 10.0)


func test_a_dome_is_still_and_mild() -> void:
	var park := StadiumDef.standard()
	park.roof = &"dome"
	var w := Weather.for_game(park, 90, &"night", Rng.new(3))
	assert_true(w.indoor)
	assert_eq(w.wind_field(park.orientation_deg), Vector3.ZERO)
	assert_almost_eq(w.temp_c, Weather.DOME_TEMP, 0.01)
	assert_eq(w.physics(cfg, park.orientation_deg).wind, Vector3.ZERO)


func test_the_draw_follows_the_season_and_stays_mostly_light() -> void:
	var park := StadiumDef.standard()
	var april := 0.0
	var july := 0.0
	var winds := PackedFloat32Array()
	var n := 400
	for i: int in n:
		april += Weather.for_game(park, 5, &"night", Rng.new(i)).temp_c
		var w := Weather.for_game(park, 100, &"night", Rng.new(1000 + i))
		july += w.temp_c
		winds.append(w.wind_speed)
	april /= n
	july /= n
	assert_between(april, 10.0, 17.0, "an April night")
	assert_between(july, 22.0, 27.0, "a July night")
	var calm := 0
	var strong := 0
	for s: float in winds:
		if s < 3.0:
			calm += 1
		if s > 6.0:
			strong += 1
	assert_gt(calm, n * 0.6, "mostly light")
	assert_between(strong, 1, n / 10, "a real breeze now and then")


func test_the_wind_is_turned_with_the_park() -> void:
	var w := Weather.new()
	w.wind_speed = 4.0
	# From the south-west, blowing toward the north-east.
	w.wind_from_deg = 225.0
	# A park whose centre field is to the north-east: the wind blows straight out.
	var out := w.wind_field(45.0)
	assert_almost_eq(out.y, 4.0, 0.01)
	assert_almost_eq(out.x, 0.0, 0.01)
	assert_eq(w.wind_words(45.0), "외야 쪽으로")
	# Centre field to the south-west: straight in.
	assert_almost_eq(w.wind_field(225.0).y, -4.0, 0.01)
	assert_eq(w.wind_words(225.0), "홈 쪽으로")
	assert_string_contains(w.describe(45.0), "바람 4m/s 외야 쪽으로")
