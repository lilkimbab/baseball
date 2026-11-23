extends SceneTree
## Prints how ground balls travel with the current surface constants, for tuning
## data/physics.json against the targets in docs/03 section 8.2.
##
##   godot --headless --path game --script res://tools/ground_ball_report.gd

func _initialize() -> void:
	var cfg := PhysicsConfigIO.load_file(PhysicsConfigIO.DEFAULT_PATH)
	var field := AnalyticField.create(FenceProfile.symmetric(100.0, 116.0, 122.0, 2.6))
	print("EV km/h  LA   t@20m  t@30m  t@40m  t@70m  bounces  speed@40m  rest m  rest s")
	var cases: Array[Vector2] = [
		Vector2(165.0, -3.0), Vector2(150.0, -5.0), Vector2(150.0, 3.0), Vector2(135.0, -8.0),
		Vector2(120.0, -10.0), Vector2(100.0, -15.0), Vector2(80.0, -20.0),
	]
	for c: Vector2 in cases:
		var ball := BallSim.new(cfg)
		var la := deg_to_rad(c.y)
		var speed := c.x / 3.6
		ball.pos = Vector3(0.0, 0.6, 0.8)
		ball.vel = Vector3(0.0, speed * cos(la), speed * sin(la))
		ball.spin = Vector3(-1500.0 * TAU / 60.0, 0.0, 0.0)
		var path := BallFlight.run(ball, field, 20.0)
		var t40 := path.time_at_distance(40.0)
		var v40 := -1.0
		if t40 > 0.0:
			v40 = (path.position_at(t40 + 0.05) - path.position_at(t40 - 0.05)).length() / 0.1 * 3.6
		print("%7.0f %4.0f  %5.2f  %5.2f  %5.2f  %5.2f  %7d  %9.0f  %6.1f  %6.1f" % [
			c.x, c.y, path.time_at_distance(20.0), path.time_at_distance(30.0), t40, path.time_at_distance(70.0),
			path.count_events(BallEvent.Kind.BOUNCE), v40, Trajectory.ground_distance(path.end_point()), path.duration(),
		])
	quit()
