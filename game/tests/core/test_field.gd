extends GutTest


func test_world_and_field_transforms_are_inverses() -> void:
	var f := Vector3(12.5, 80.25, 3.0)
	assert_eq(Field.to_field(Field.to_world(f)), f)


func test_field_up_maps_to_world_up_and_centre_field_to_world_forward() -> void:
	assert_eq(Field.to_world(Vector3(0.0, 0.0, 1.0)), Vector3.UP)
	assert_eq(Field.to_world(Vector3(0.0, 1.0, 0.0)), Vector3.FORWARD)
	assert_eq(Field.to_world(Vector3(1.0, 0.0, 0.0)), Vector3.RIGHT)


func test_bases_are_90_feet_apart() -> void:
	assert_almost_eq(Field.HOME.distance_to(Field.FIRST_BASE), Field.BASE_DISTANCE, 0.01)
	assert_almost_eq(Field.FIRST_BASE.distance_to(Field.SECOND_BASE), Field.BASE_DISTANCE, 0.01)
	assert_almost_eq(Field.SECOND_BASE.distance_to(Field.THIRD_BASE), Field.BASE_DISTANCE, 0.01)
	assert_almost_eq(Field.THIRD_BASE.distance_to(Field.HOME), Field.BASE_DISTANCE, 0.01)


func test_fair_territory_is_between_the_foul_lines() -> void:
	assert_true(Field.is_fair(Vector3(0.0, 50.0, 0.0)), "centre field")
	assert_true(Field.is_fair(Vector3(30.0, 30.0, 0.0)), "on the right-field line")
	assert_false(Field.is_fair(Vector3(31.0, 30.0, 0.0)), "just foul on the first-base side")
	assert_false(Field.is_fair(Vector3(0.0, -2.0, 0.0)), "behind the plate")


func test_azimuth_sign_matches_field_side() -> void:
	assert_almost_eq(Field.azimuth(Vector3(0.0, 100.0, 0.0)), 0.0, 0.0001)
	assert_gt(Field.azimuth(Vector3(40.0, 80.0, 0.0)), 0.0, "right-field side is positive")
	assert_lt(Field.azimuth(Vector3(-40.0, 80.0, 0.0)), 0.0, "left-field side is negative")


func test_the_mound_is_level_on_top_and_slopes_one_in_twelve_toward_the_plate() -> void:
	assert_almost_eq(Field.ground_height(0.0, Field.RUBBER_Y), Field.MOUND_HEIGHT, 1e-6, "at the rubber")
	assert_almost_eq(Field.ground_height(0.5, Field.RUBBER_Y + 0.4), Field.MOUND_HEIGHT, 1e-6, "behind and beside it")
	var front := Field.RUBBER_Y - Field.MOUND_TOP_FRONT
	var a := Field.ground_height(0.0, front - 0.5)
	var b := Field.ground_height(0.0, front - 1.5)
	assert_almost_eq(a - b, 1.0 / 12.0, 0.002, "drops an inch per foot")
	assert_almost_eq(Field.ground_height(0.0, front - 1.2192), Field.MOUND_HEIGHT - 0.1016, 0.002, "four feet out it is four inches down")


func test_the_ground_is_flat_off_the_mound() -> void:
	assert_eq(Field.ground_height(0.0, Field.MOUND_CENTER_Y - Field.MOUND_RADIUS - 0.01), 0.0)
	assert_eq(Field.ground_height(3.0, Field.MOUND_CENTER_Y), 0.0)
	assert_eq(Field.ground_height(0.0, 0.0), 0.0)
	assert_lt(Field.ground_height(0.0, Field.MOUND_CENTER_Y - Field.MOUND_RADIUS + 0.05), 0.01, "it meets the field without a step")
	for i: int in 40:
		var x := -3.0 + i * 0.15
		assert_between(Field.ground_height(x, Field.RUBBER_Y - 0.9), 0.0, Field.MOUND_HEIGHT)


func test_home_plate_is_the_regulation_pentagon() -> void:
	var outline := Field.PLATE_OUTLINE
	assert_eq(outline.size(), 5)
	assert_eq(outline[0], Vector2.ZERO, "the rear apex is the origin of the field")
	assert_almost_eq(outline[2].distance_to(outline[3]), 0.4318, 1e-4, "17 in across the front")
	assert_almost_eq(outline[1].distance_to(outline[2]), 0.2159, 1e-4, "8.5 in sides")
	assert_almost_eq(outline[0].distance_to(outline[1]), 0.3048, 0.001, "12 in edges to the apex")
	assert_almost_eq(outline[0].distance_to(outline[4]), 0.3048, 0.001)
	assert_almost_eq(outline[3].y, Field.PLATE_FRONT_Y, 1e-6)


func test_first_and_third_base_lie_inside_the_lines_and_second_on_its_point() -> void:
	var half_diagonal := Field.BASE_SIZE * 0.5 * sqrt(2.0)
	var first := Field.base_centre(1)
	var third := Field.base_centre(3)
	# The outer corner of the bag is the 90 ft point, so the whole bag is in fair territory.
	assert_almost_eq(first.x + half_diagonal, Field.FIRST_BASE.x, 1e-5)
	assert_almost_eq(first.y, Field.FIRST_BASE.y, 1e-5)
	assert_true(Field.is_fair(first + Vector3(half_diagonal - 0.001, 0.0, 0.0)), "outer corner on the line")
	assert_almost_eq(third.x, -first.x, 1e-6)
	assert_eq(Field.base_centre(2), Field.SECOND_BASE)
	assert_almost_eq(Field.BASE_SIZE, 0.4572, 1e-6, "18 in bases")
