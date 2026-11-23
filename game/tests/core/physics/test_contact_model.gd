extends PhysicsTest
## Bat-ball collision (docs/03 section 7.3): pitch 128 km/h at the plate descending 6 degrees,
## bat 115 km/h, attack angle +8 degrees, contact at the sweet spot.

const ATTACK := deg_to_rad(8.0)


func _contact(offset_cm: float, yaw_deg: float = 0.0, bats_left: bool = false, along_bat: float = 0.15) -> ContactResult:
	var descent := deg_to_rad(6.0)
	var speed := kmh(128.0)
	var ball_vel := Vector3(0.0, -speed * cos(descent), -speed * sin(descent))
	var ball_spin := Vector3(-rpm(2000.0), 0.0, 0.0)
	return ContactModel.resolve(cfg, ball_vel, ball_spin, kmh(115.0), ATTACK, deg_to_rad(yaw_deg), offset_cm / 100.0, along_bat, bats_left)


func test_vertical_offset_sets_exit_speed_and_launch_angle() -> void:
	# offset cm -> [exit speed km/h, launch angle deg]
	var table := {
		-2.0: [153.0, -29.7],
		-1.0: [159.0, -16.2],
		0.0: [162.0, -3.2],
		1.0: [164.0, 9.6],
		1.5: [163.0, 16.1],
		2.0: [162.0, 22.7],
		2.5: [161.0, 29.5],
		3.0: [159.0, 36.5],
		4.0: [152.0, 51.9],
		5.0: [141.0, 70.1],
	}
	for offset: float in table:
		var want: Array = table[offset]
		var hit := _contact(offset)
		assert_true(hit.made_contact, "contact at %.1f cm" % offset)
		assert_almost_eq(hit.exit_speed_kmh(), float(want[0]), 1.5, "exit speed at %.1f cm" % offset)
		assert_almost_eq(hit.launch_deg(), float(want[1]), 1.0, "launch angle at %.1f cm" % offset)


func test_square_contact_exit_speed_is_in_the_design_range() -> void:
	assert_between(_contact(0.0).exit_speed_kmh(), 160.0, 166.0)
	assert_between(_contact(1.0).exit_speed_kmh(), 160.0, 166.0)


func test_getting_under_the_ball_gives_backspin_and_topping_it_gives_topspin() -> void:
	var under := _contact(2.5)
	assert_gt(under.spin.x, 0.0, "backspin for a ball travelling toward centre field")
	assert_almost_eq(under.spin_rpm(), 1564.0, 120.0)
	assert_lt(_contact(-2.0).spin.x, 0.0, "topspin on a topped ball")


func test_bat_yaw_sets_spray_direction() -> void:
	assert_almost_eq(_contact(1.5, 0.0).spray_deg(), 0.0, 0.2)
	assert_almost_eq(_contact(1.5, 10.0).spray_deg(), -16.8, 1.0, "early swing pulls toward third base")
	assert_almost_eq(_contact(1.5, 20.0).spray_deg(), -33.2, 1.0)
	assert_almost_eq(_contact(1.5, -20.0).spray_deg(), 33.2, 1.0, "late swing goes the other way")
	assert_gt(absf(_contact(1.5, 40.0).spray_deg()), 45.0, "far too early is foul")


func test_left_handed_batter_pulls_toward_first_base() -> void:
	assert_almost_eq(_contact(1.5, 20.0, true).spray_deg(), 33.2, 1.0)


func test_a_ball_beyond_the_reach_of_the_barrel_is_a_miss() -> void:
	assert_false(_contact(7.5).made_contact)
	assert_false(_contact(-7.5).made_contact)
	assert_true(_contact(6.5).made_contact)


func test_off_the_sweet_spot_costs_exit_speed() -> void:
	var sweet := _contact(1.5, 0.0, false, 0.15).exit_speed_kmh()
	var end_of_bat := _contact(1.5, 0.0, false, 0.02).exit_speed_kmh()
	var handle := _contact(1.5, 0.0, false, 0.45).exit_speed_kmh()
	assert_lt(end_of_bat, sweet - 5.0)
	assert_lt(handle, sweet - 20.0)


func test_bat_efficiency_peaks_at_the_sweet_spot_and_is_clamped() -> void:
	assert_almost_eq(cfg.bat_efficiency(cfg.sweet_spot_from_tip), cfg.efficiency_max, 0.0001)
	assert_lt(cfg.bat_efficiency(0.30), cfg.efficiency_max)
	assert_almost_eq(cfg.bat_efficiency(0.80), cfg.efficiency_min, 0.0001)


func test_more_power_means_a_faster_bat() -> void:
	assert_almost_eq(ContactModel.bat_speed_from_power(0.0) * 3.6, 104.5, 0.01)
	assert_almost_eq(ContactModel.bat_speed_from_power(100.0) * 3.6, 128.5, 0.01)
