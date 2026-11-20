class_name BallFlight
extends RefCounted
## Runs a ball to the end of its trajectory in one call. Used to predict where a batted or
## thrown ball goes (fielding AI, cameras, home-run calls) with the same code that moves it.

const DT := 1.0 / 240.0


## Simulates `ball` (modified in place) until it stops, leaves play or max_time passes.
static func run(ball: BallSim, field: CollisionProvider, max_time: float = 15.0, dt: float = DT) -> Trajectory:
	var path := Trajectory.new()
	path.times.append(ball.time)
	path.points.append(ball.pos)
	var start := ball.time
	while ball.time - start < max_time:
		var was_rolling := ball.rolling
		var hit := ball.advance(dt, field)
		path.times.append(ball.time)
		path.points.append(ball.pos)
		if hit != null:
			var kind := BallEvent.Kind.BOUNCE if hit.normal.z > 0.5 else BallEvent.Kind.WALL
			path.events.append(BallEvent.make(kind, ball.time, hit.point, hit.surface, ball.vel.length()))
		if ball.rolling and not was_rolling:
			path.events.append(BallEvent.make(BallEvent.Kind.ROLL_START, ball.time, ball.pos, field.surface_at(ball.pos), ball.vel.length()))
		if ball.stopped:
			path.events.append(BallEvent.make(BallEvent.Kind.STOP, ball.time, ball.pos, field.surface_at(ball.pos), 0.0))
			break
		if field.is_out_of_play(ball.pos):
			path.events.append(BallEvent.make(BallEvent.Kind.OUT_OF_PLAY, ball.time, ball.pos, &"", ball.vel.length()))
			break
	return path
