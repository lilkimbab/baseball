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
