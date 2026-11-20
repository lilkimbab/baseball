class_name BallFlight
extends RefCounted
## Runs a ball to the end of its trajectory in one call. Used to predict where a batted or
## thrown ball goes (fielding AI, cameras, home-run calls) with the same code that moves it.

const DT := 1.0 / 240.0


## Simulates `ball` (modified in place) until it stops, leaves play or max_time passes.
## Longest step taken where nothing can be hit: high in the air, or rolling (rolling is a
## smooth slow-down that a longer step follows just as well).
const COARSE_DT := 1.0 / 60.0
## Height the ball must stay above during a coarse step in the air.
const COARSE_CLEARANCE := 1.5


## Flies the ball until it stops, leaves the field or max_time passes. Steps of `dt` near
## the ground and walls; with `adaptive`, longer steps where nothing can be hit, which gives
## the same landing points (to about a centimetre) at a quarter of the cost.
static func run(ball: BallSim, field: CollisionProvider, max_time: float = 15.0, dt: float = DT, adaptive: bool = true) -> Trajectory:
	var path := Trajectory.new()
	path.times.append(ball.time)
	path.points.append(ball.pos)
	var start := ball.time
	while ball.time - start < max_time:
		var was_rolling := ball.rolling
		var step := dt
		if adaptive:
			if ball.rolling:
				step = COARSE_DT
			elif ball.pos.z + minf(ball.vel.z, 0.0) * COARSE_DT > COARSE_CLEARANCE and _clear_of_walls(ball, field):
				step = COARSE_DT
		var hit := ball.advance(step, field)
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


## True when a coarse step cannot carry the ball into a wall: it stays well inside the
## boundary in the direction it is travelling.
static func _clear_of_walls(ball: BallSim, field: CollisionProvider) -> bool:
	var analytic := field as AnalyticField
	if analytic == null:
		return false
	var ahead := ball.pos + ball.vel * COARSE_DT
	var reach := Vector2(ahead.x, ahead.y).length()
	return reach + 3.0 < analytic.boundary_distance(rad_to_deg(Field.azimuth(ahead)))
