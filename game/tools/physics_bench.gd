extends SceneTree
## Measures how fast ball trajectories simulate, collisions included. Batch simulation of
## whole games depends on this number.
##
##   godot --headless --path game --script res://tools/physics_bench.gd

func _initialize() -> void:
	var cfg := PhysicsConfigIO.load_file(PhysicsConfigIO.DEFAULT_PATH)
	var field := AnalyticField.create(FenceProfile.symmetric(100.0, 116.0, 122.0, 2.6))
	var catalog := PitchCatalogIO.load_file(PitchCatalogIO.DEFAULT_PATH)
	var release := Vector3(-0.55, 16.76, 1.80)
	var target := Vector3(0.0, Field.PLATE_FRONT_Y, 0.75)

	var started := Time.get_ticks_usec()
	var pitches := 300
	for i: int in pitches:
		PitchModel.throw_type(cfg, catalog[&"slider"], release, target)
	var pitch_ms := float(Time.get_ticks_usec() - started) / 1000.0 / pitches

	var steps := 0
	var flights := 200
	started = Time.get_ticks_usec()
	for i: int in flights:
		var ball := BallSim.new(cfg)
		var la := deg_to_rad(-8.0 + float(i % 40))
		var az := deg_to_rad(-40.0 + float(i % 9) * 10.0)
		var speed := (110.0 + float(i % 7) * 10.0) / 3.6
		ball.pos = Vector3(0.0, 0.6, 0.9)
		ball.vel = Vector3(sin(az) * cos(la), cos(az) * cos(la), sin(la)) * speed
		ball.spin = Vector3(cos(az), -sin(az), 0.0) * (1800.0 * TAU / 60.0)
		steps += BallFlight.run(ball, field).points.size()
	var total_us := float(Time.get_ticks_usec() - started)
	print("physics_bench: aimed pitch %.2f ms | batted ball %.2f ms each, %.2f us/step (%d steps over %d balls)" % [
		pitch_ms, total_us / 1000.0 / flights, total_us / steps, steps, flights,
	])
	quit()
