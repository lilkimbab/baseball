extends PlayTest
## Catches in the air (approved proposal 2): an S-curve of the time to spare, after Statcast's
## Catch Probability, harder near the wall.


func test_the_chance_rises_smoothly_with_the_time_to_spare() -> void:
	var last := 0.0
	for i: int in 41:
		var slack := -0.4 + i * 0.025
		var p := motion.air_catch_chance(slack)
		assert_gte(p, last, "never lower with more time")
		last = p
	assert_almost_eq(motion.air_catch_chance(motion.air_half_slack), 0.5, 1e-6, "half at the midpoint")
	# Statcast's bands: a dive at the last moment is a five-star play (25% or less); a ball he
	# reaches with a quarter second to spare is a two-star one (80 to 90%); with half a second
	# it is routine (95% or more).
	assert_lt(motion.air_catch_chance(-0.1), 0.25)
	assert_between(motion.air_catch_chance(0.25), 0.78, 0.92)
	assert_gt(motion.air_catch_chance(0.45), 0.95)


func test_a_catch_at_the_wall_is_harder() -> void:
	var c := _context(_fly_to(95.0, 0.0))
	var sim := PlaySim.new()
	sim._setup(c, Rng.new(1))
	var fence := c.field.boundary_distance(0.0)
	assert_almost_eq(sim._wall_cost(Vector3(0.0, fence, 3.0)), motion.wall_cost, 1e-6, "at the wall")
	assert_almost_eq(sim._wall_cost(Vector3(0.0, fence - motion.wall_reach * 0.5, 3.0)), motion.wall_cost * 0.5, 1e-6)
	assert_eq(sim._wall_cost(Vector3(0.0, fence - 10.0, 3.0)), 0.0, "nothing in the open")
	assert_eq(sim._wall_cost(Vector3(-30.0, 10.0, 3.0)), 0.0, "nor in foul ground")
