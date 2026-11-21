extends GutTest
## The native ball physics (approved proposal 5) flies the ball as the GDScript does.

var cfg: PhysicsConfig


func before_all() -> void:
	cfg = PhysicsConfigIO.load_file(PhysicsConfigIO.DEFAULT_PATH)


func after_each() -> void:
	NativePhysics.enabled = NativePhysics.available()


func _both(run: Callable) -> Array:
	if not NativePhysics.available():
		return []
	NativePhysics.enabled = false
	var script_result: Variant = run.call()
	NativePhysics.enabled = true
	var native_result: Variant = run.call()
	return [script_result, native_result]


func test_pitches_cross_the_plate_at_the_same_place() -> void:
	var catalog := PitchCatalogIO.load_file(PitchCatalogIO.DEFAULT_PATH)
	for id: StringName in [&"four_seam", &"slider", &"curve", &"two_seam", &"changeup", &"splitter"]:
		var type: PitchType = catalog[id]
		var flights := _both(func() -> PitchFlight:
			return PitchModel.throw_type(cfg, type, Vector3(-0.55, 16.76, 1.80), Vector3(0.1, Field.PLATE_FRONT_Y, 0.7)))
		if flights.is_empty():
			pass_test("native library not built (./dev native)")
			return
		var a: PitchFlight = flights[0]
		var b: PitchFlight = flights[1]
		assert_almost_eq(b.plate_pos, a.plate_pos, Vector3.ONE * 1e-3, "%s at the plate" % id)
		assert_almost_eq(b.plate_vel, a.plate_vel, Vector3.ONE * 1e-2, "%s speed at the plate" % id)
		assert_almost_eq(b.flight_time, a.flight_time, 1e-4, "%s time to the plate" % id)


func test_the_contact_point_is_found_the_same() -> void:
	var flights := _both(func() -> PitchFlight:
		var dir := Vector3(0.02, -1.0, -0.03).normalized()
		return PitchModel.fly_to_plate(cfg, Vector3(-0.5, 16.8, 1.8), dir * 40.0, Vector3(-200.0, 0.0, 40.0), 0.9))
	if flights.is_empty():
		pass_test("native library not built (./dev native)")
		return
	var a: PitchFlight = flights[0]
	var b: PitchFlight = flights[1]
	assert_almost_eq(b.contact_pos, a.contact_pos, Vector3.ONE * 1e-3)
	assert_almost_eq(b.contact_time, a.contact_time, 1e-4)


func test_batted_balls_land_in_the_same_place() -> void:
	var field := AnalyticField.create(FenceProfile.symmetric(100.0, 116.0, 122.0, 2.6))
	for i: int in 12:
		var runs := _both(func() -> Vector3:
			var ball := BallSim.new(cfg)
			var la := deg_to_rad(-5.0 + 5.0 * i)
			ball.pos = Vector3(0.0, 0.6, 0.9)
			ball.vel = Vector3(0.2 * cos(la), cos(la), sin(la)) * 45.0
			ball.spin = Vector3(1.0, -0.2, 0.0) * 250.0
			ball.hit()
			var path := BallFlight.run(ball, field)
			return path.events[0].pos if not path.events.is_empty() else path.end_point())
		if runs.is_empty():
			pass_test("native library not built (./dev native)")
			return
		assert_almost_eq(runs[1], runs[0], Vector3.ONE * 0.02, "launch %d degrees" % (-5 + 5 * i))
