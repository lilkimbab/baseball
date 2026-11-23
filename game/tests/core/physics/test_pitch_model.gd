extends PhysicsTest
## Pitch flight (docs/03 section 5.3). Expected values are the engine-independent reference
## calculation in prototypes/physics-check (with the seam-shifted wake of the sinker, changeup
## and splitter since the approved proposal 1, 2026-11-21: the totals were kept, the spin's
## share lowered).

## id -> [flight time s, plate speed km/h, horizontal movement cm, vertical movement cm]
const EXPECTED := {
	&"four_seam": [0.428, 131.2, -9.4, 45.5],
	&"two_seam": [0.437, 128.7, -34.3, 28.5],
	&"cutter": [0.450, 124.9, 15.9, 30.2],
	&"slider": [0.471, 119.5, 29.0, 6.5],
	&"sweeper": [0.486, 115.9, 44.2, 3.4],
	&"curve": [0.519, 108.8, 19.7, -47.1],
	&"changeup": [0.477, 118.3, -35.9, 20.5],
	&"splitter": [0.469, 120.4, -8.4, 13.2],
}

var catalog: Dictionary[StringName, PitchType]


func before_all() -> void:
	super.before_all()
	catalog = PitchCatalogIO.load_default()


func test_catalog_has_the_eight_pitch_types_four_evolved_ones_and_six_more() -> void:
	# The eight, the four a pitch can grow into, and the six more KBO pitchers throw (sinker,
	# forkball, knuckle curve, slurve, screwball, knuckleball: the user, 2026-11-23).
	assert_eq(catalog.size(), 18)
	for id: StringName in [&"sinker", &"forkball", &"knuckle_curve", &"slurve", &"screwball", &"knuckleball"]:
		assert_true(catalog.has(id), "missing %s" % id)
	for id: StringName in EXPECTED:
		assert_true(catalog.has(id), "missing %s" % id)


func test_each_pitch_matches_the_reference_calculation() -> void:
	for id: StringName in EXPECTED:
		var want: Array = EXPECTED[id]
		var flight := PitchModel.throw_type(cfg, catalog[id], RELEASE, PLATE_TARGET)
		assert_almost_eq(flight.flight_time, float(want[0]), 0.004, "%s flight time" % id)
		assert_almost_eq(flight.plate_speed_kmh(), float(want[1]), 0.6, "%s speed at plate" % id)
		assert_almost_eq(flight.movement.x * 100.0, float(want[2]), 2.0, "%s horizontal movement (cm)" % id)
		assert_almost_eq(flight.movement.y * 100.0, float(want[3]), 2.0, "%s vertical movement (cm)" % id)


func test_four_seam_meets_the_design_targets() -> void:
	var flight := PitchModel.throw_type(cfg, catalog[&"four_seam"], RELEASE, PLATE_TARGET)
	assert_between(flight.flight_time, 0.41, 0.45, "flight time (s)")
	var loss := 1.0 - flight.plate_speed_kmh() / flight.release_speed_kmh()
	assert_between(loss, 0.08, 0.10, "speed lost on the way to the plate")
	assert_between(flight.movement.y * 100.0, 38.0, 52.0, "rise from backspin (cm)")


func test_aim_solver_puts_every_pitch_on_target() -> void:
	var targets: Array[Vector3] = [
		PLATE_TARGET,
		Vector3(-0.25, Field.PLATE_FRONT_Y, 0.45),
		Vector3(0.3, Field.PLATE_FRONT_Y, 1.15),
	]
	for id: StringName in EXPECTED:
		for target: Vector3 in targets:
			var flight := PitchModel.throw_type(cfg, catalog[id], RELEASE, target)
			var miss := Vector2(flight.plate_pos.x - target.x, flight.plate_pos.z - target.z).length()
			assert_lt(miss, PitchModel.AIM_TOLERANCE, "%s residual miss (m)" % id)


func test_left_hander_mirrors_the_break() -> void:
	var slider := catalog[&"slider"]
	var right := PitchModel.throw_type(cfg, slider, RELEASE, PLATE_TARGET, false)
	var left_release := Vector3(-RELEASE.x, RELEASE.y, RELEASE.z)
	var left := PitchModel.throw_type(cfg, slider, left_release, PLATE_TARGET, true)
	assert_almost_eq(left.movement.x, -right.movement.x, 0.005, "horizontal break flips")
	assert_almost_eq(left.movement.y, right.movement.y, 0.005, "vertical break is the same")
	assert_almost_eq(left.flight_time, right.flight_time, 0.001)


func test_spin_vector_has_the_requested_rate_and_efficiency() -> void:
	var dir := (PLATE_TARGET - RELEASE).normalized()
	var spin := PitchModel.spin_vector(dir, 2400.0, 0.35, 75.0, false)
	assert_almost_eq(spin.length(), rpm(2400.0), 0.01)
	var active := (spin - dir * spin.dot(dir)).length()
	assert_almost_eq(active / spin.length(), 0.35, 0.001)


func test_execution_error_spreads_with_sigma_and_is_reproducible() -> void:
	var rng := Rng.new(404)
	var n := 4000
	var sum := Vector2.ZERO
	var sum_sq := 0.0
	var plane_ok := true
	for i: int in n:
		var p := PitchModel.apply_execution_error(PLATE_TARGET, 0.20, rng)
		plane_ok = plane_ok and is_equal_approx(p.y, PLATE_TARGET.y)
		var off := Vector2(p.x - PLATE_TARGET.x, p.z - PLATE_TARGET.z)
		sum += off
		sum_sq += off.x * off.x
	assert_true(plane_ok, "the miss stays in the plane of the plate")
	assert_almost_eq(sum.x / n, 0.0, 0.015, "no horizontal bias")
	assert_almost_eq(sqrt(sum_sq / n), 0.20, 0.015, "horizontal spread equals sigma")
	var again := PitchModel.apply_execution_error(PLATE_TARGET, 0.20, Rng.new(404))
	var first := PitchModel.apply_execution_error(PLATE_TARGET, 0.20, Rng.new(404))
	assert_eq(again, first)


func test_better_command_means_a_smaller_miss() -> void:
	assert_almost_eq(PitchModel.command_sigma(0.0), 0.26, 0.001)
	assert_almost_eq(PitchModel.command_sigma(100.0), 0.09, 0.001)
	assert_gt(PitchModel.command_sigma(40.0), PitchModel.command_sigma(80.0))


func test_the_seam_shifted_wake_adds_what_spin_does_not_explain() -> void:
	# Two pitchers, the same changeup: the one with more feel for the seams gets more run and
	# sink from the same spin.
	var change := catalog[&"changeup"]
	var little := PitchModel.throw_type(cfg, change, RELEASE, PLATE_TARGET, false, 0.6)
	var plenty := PitchModel.throw_type(cfg, change, RELEASE, PLATE_TARGET, false, 1.4)
	assert_lt(plenty.movement.x, little.movement.x - 0.04, "more run to the arm side (cm)")
	assert_lt(plenty.movement.y, little.movement.y - 0.01, "and more sink")
	# Without it the spin alone moves the ball less than the measured totals.
	var none := PitchModel.throw_type(cfg, change, RELEASE, PLATE_TARGET, false, 0.0)
	assert_gt(none.movement.x, -0.30, "the spin alone runs it less than the total")
	# A four-seamer has none, whatever the pitcher.
	var four := catalog[&"four_seam"]
	assert_almost_eq(PitchModel.throw_type(cfg, four, RELEASE, PLATE_TARGET, false, 1.5).movement.x, PitchModel.throw_type(cfg, four, RELEASE, PLATE_TARGET, false, 0.5).movement.x, 1e-6)
	# A left-hander's runs the other way.
	var lefty := PitchModel.throw_type(cfg, change, Vector3(-RELEASE.x, RELEASE.y, RELEASE.z), PLATE_TARGET, true, 1.0)
	assert_gt(lefty.movement.x, 0.25)
