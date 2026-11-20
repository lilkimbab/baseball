class_name PlayTest
extends PhysicsTest
## Shared set-up for the play tests: a standard park, the movement model, fielders where they
## stand, and batted balls by exit speed, launch and direction.

var field: AnalyticField
var motion: MotionModel
var alignment: FieldingAlignment


func before_all() -> void:
	super.before_all()
	field = standard_field()
	motion = MotionIO.load_default()
	alignment = MotionIO.alignment()


func _state(bases: Array[int] = [], outs: int = 0) -> GameState:
	var s := GameState.new()
	s.rules = RuleSet.kbo_2026()
	s.outs = outs
	for b: int in bases:
		s.bases[b - 1] = BaseRunner.make("r%d" % b, "p")
	return s


func _context(path: Trajectory, bases: Array[int] = [], outs: int = 0) -> PlayContext:
	var s := _state(bases, outs)
	var at := alignment.positions(s, null, false)
	var c := PlayContext.new()
	c.path = path
	c.field = field
	c.motion = motion
	c.outs = outs
	for kind: Position.Kind in Position.FIELD:
		c.fielders[kind] = PlayFielder.make(kind, at[kind])
	for b: int in bases:
		c.runners[b - 1] = PlayRunner.make("r%d" % b, b)
	c.batter = PlayRunner.make("b", 0)
	return c


## A batted ball from the plate: exit speed, launch angle, direction (+ toward first).
func _hit(ev_kmh: float, launch_deg: float, spray_deg: float, backspin: float = 1500.0) -> Trajectory:
	var ball := batted_ball(ev_kmh, launch_deg, backspin, spray_deg, 0.9)
	ball.pos = Vector3(0.0, 0.3, 0.9)
	return BallFlight.run(ball, field)


## A fly ball that first comes down about `distance` metres out at `spray_deg`.
func _fly_to(distance: float, spray_deg: float, launch_deg: float = 32.0) -> Trajectory:
	var lo := 60.0
	var hi := 200.0
	var path: Trajectory = null
	for i: int in 30:
		var ev := (lo + hi) * 0.5
		path = _hit(ev, launch_deg, spray_deg, 2000.0)
		var land := Trajectory.ground_distance(path.events[0].pos)
		if land < distance:
			lo = ev
		else:
			hi = ev
	return path


func _run(path: Trajectory, bases: Array[int] = [], outs: int = 0, seed_value: int = 1) -> PlayResult:
	return PlaySim.run(_context(path, bases, outs), Rng.new(seed_value))


func _move_of(result: PlayResult, from: int) -> RunnerMove:
	for m: RunnerMove in result.moves:
		if m.from == from:
			return m
	return null
