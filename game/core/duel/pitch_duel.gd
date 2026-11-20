class_name PitchDuel
extends RefCounted
## One pitch from release to its result: flight to the plate, the batter's swing, contact,
## and the batted ball. The scene feeds it decisions and reads the ball back every tick.

enum Phase { READY, FLIGHT, IN_PLAY, DONE }
enum Result { NONE, BALL, CALLED_STRIKE, SWINGING_STRIKE, FOUL, IN_PLAY, HOME_RUN }

## The catcher receives the ball this far behind the apex of the plate.
const CATCH_Y := -0.9
## Seconds a foul ball is followed before the pitch is over.
const FOUL_FOLLOW_TIME := 2.5

var cfg: PhysicsConfig
var field: CollisionProvider
var settings: DuelSettings
var zone: StrikeZone

var phase: Phase = Phase.READY
var result: Result = Result.NONE
## Seconds since release.
var time := 0.0
var ball: BallSim
var decision: PitchDecision
var pitch: PitchFlight
## Time after release at which the ball reaches the ideal contact point, and where that is.
var ideal_contact_time := 0.0
var ideal_contact_pos := Vector3.ZERO
var swing: SwingAttempt
var contact: ContactResult
## Forecast of the batted ball, made at contact.
var path: Trajectory
## Where the batted ball first comes down (m from home), or where it left the park.
var hit_distance := 0.0
## How far the batted ball would fly with nothing in its way (m from home): the distance
## quoted for a home run.
var carry_distance := 0.0

var _rng: Rng
var _contact_at := 0.0


func _init(config: PhysicsConfig, collision: CollisionProvider, duel_settings: DuelSettings, rng: Rng) -> void:
	cfg = config
	field = collision
	settings = duel_settings
	zone = StrikeZone.for_batter(settings.batter_height)
	_rng = rng
	ball = BallSim.new(cfg)


## Releases the pitch. Execution error from command and quality is applied here; pass
## exact = true to put the pitch precisely on its target (tests, practice mode).
func throw_pitch(choice: PitchDecision, exact: bool = false) -> void:
	decision = choice
	var actual := choice.target
	if not exact:
		var sigma := PitchModel.command_sigma(settings.command) * lerpf(2.0, 0.5, clampf(choice.quality, 0.0, 1.0))
		actual = PitchModel.apply_execution_error(choice.target, sigma, _rng)
	var type := choice.type
	pitch = PitchModel.throw_at(cfg, settings.release(), actual, type.speed_kmh * choice.effort,
		type.spin_rpm, type.efficiency, type.tilt_deg, settings.throws_left)
	ball = BallSim.new(cfg)
	ball.pos = pitch.release_pos
	ball.vel = pitch.release_vel
	ball.spin = pitch.spin
	ideal_contact_time = _time_to_plane(SwingModel.CONTACT_PLANE_Y)
	swing = null
	contact = null
	path = null
	time = 0.0
	result = Result.NONE
	phase = Phase.FLIGHT


## The batter starts a swing now. Returns false if it is too late or one is already under way.
func start_swing(kind: SwingAttempt.Kind, aim: Vector2 = Vector2.ZERO, has_aim: bool = false) -> bool:
	return swing_at(time + SwingModel.swing_time(kind), kind, aim, has_aim)


## Schedules a swing whose barrel arrives at contact_time (used by the AI batter).
func swing_at(contact_time: float, kind: SwingAttempt.Kind, aim: Vector2 = Vector2.ZERO, has_aim: bool = false) -> bool:
	if phase != Phase.FLIGHT or swing != null:
		return false
	swing = SwingAttempt.new()
	swing.kind = kind
	swing.contact_time = maxf(contact_time, time)
	swing.aim = aim
	swing.has_aim = has_aim
	return true


func is_over() -> bool:
	return phase == Phase.DONE


func tick(dt: float) -> void:
	match phase:
		Phase.FLIGHT:
			_tick_flight(dt)
		Phase.IN_PLAY:
			_tick_in_play(dt)


func _tick_flight(dt: float) -> void:
	ball.advance(dt, field)
	time += dt
	if swing != null and not swing.resolved and time >= swing.contact_time:
		_resolve_swing()
		if phase != Phase.FLIGHT:
			return
	if ball.pos.y <= CATCH_Y or ball.rolling or time > 3.0:
		if swing != null:
			if not swing.resolved:
				swing.resolved = true
				swing.tau = (swing.contact_time - ideal_contact_time) / SwingModel.timing_window(settings, swing.kind)
				swing.judgment = &"miss"
			result = Result.SWINGING_STRIKE
		else:
			result = Result.CALLED_STRIKE if zone.is_strike(pitch) else Result.BALL
		phase = Phase.DONE


func _tick_in_play(dt: float) -> void:
	ball.advance(dt, field)
	time += dt
	var since_contact := time - _contact_at
	var foul_done := result == Result.FOUL and since_contact > FOUL_FOLLOW_TIME
	if ball.stopped or field.is_out_of_play(ball.pos) or foul_done or since_contact > 20.0:
		phase = Phase.DONE


func _resolve_swing() -> void:
	swing.resolved = true
	var window := SwingModel.timing_window(settings, swing.kind)
	swing.tau = (swing.contact_time - ideal_contact_time) / window
	swing.judgment = SwingModel.judge(swing.tau)
	if absf(swing.tau) > 1.0:
		return

	# Aim is judged against the pitch's path at the contact plane, not against where the ball
	# happens to be at this instant: the swing plane follows the pitch, so being early or
	# late changes direction (yaw), not whether the barrel is on the ball's line.
	var ball_at := Vector2(ideal_contact_pos.x, ideal_contact_pos.z)
	if not SwingModel.reachable(zone, ball_at):
		swing.judgment = &"miss"
		return
	var aim := swing.aim
	if not swing.has_aim:
		var read := SwingModel.read_sigma(settings, decision.type.family)
		aim = ball_at + Vector2(_rng.next_normal(), _rng.next_normal()) * read

	# Swinging above the ball tops it (negative offset), below it lifts it.
	var error := aim - ball_at
	var offset_up := SwingModel.intended_offset(swing.kind) \
		- error.y * SwingModel.error_scale(error.y, settings.aim_scale) \
		+ _rng.next_normal() * SwingModel.barrel_sigma(settings, swing.kind)
	var along := cfg.sweet_spot_from_tip + absf(error.x) * SwingModel.error_scale(error.x, settings.aim_scale)
	if along > SwingModel.BAT_LENGTH_USABLE:
		return

	contact = ContactModel.resolve(cfg, ball.vel, ball.spin, SwingModel.bat_speed(settings, swing.kind),
		deg_to_rad(SwingModel.ATTACK_DEG), SwingModel.yaw_for(swing.tau), offset_up, along, settings.bats_left)
	if not contact.made_contact:
		return

	swing.made_contact = true
	ball.vel = contact.velocity
	ball.spin = contact.spin
	ball.rolling = false
	ball.stopped = false
	_contact_at = time
	path = BallFlight.run(ball.clone(), field)
	result = _classify(path)
	hit_distance = _first_landing_distance(path)
	carry_distance = _open_air_carry()
	phase = Phase.IN_PLAY


## Simplified fair/foul call for this stage: judged where the ball first touches something.
func _classify(forecast: Trajectory) -> Result:
	if forecast.is_home_run():
		return Result.HOME_RUN
	if forecast.events.is_empty():
		return Result.IN_PLAY
	return Result.IN_PLAY if Field.is_fair(forecast.events[0].pos) else Result.FOUL


static func _first_landing_distance(forecast: Trajectory) -> float:
	if forecast.events.is_empty():
		return Trajectory.ground_distance(forecast.end_point())
	return Trajectory.ground_distance(forecast.events[0].pos)


## Flies a copy of the ball with no field in the way until it returns to the ground.
func _open_air_carry() -> float:
	var probe := ball.clone()
	var t := 0.0
	while t < 12.0 and (probe.pos.z > cfg.ball_radius or probe.vel.z > 0.0):
		probe.pos = probe.integrate(BallFlight.DT)
		t += BallFlight.DT
	return Trajectory.ground_distance(probe.pos)


func _time_to_plane(plane_y: float) -> float:
	var probe := ball.clone()
	var t := 0.0
	while t < 3.0:
		var prev := probe.pos
		var next := probe.integrate(PitchModel.DT)
		if next.y <= plane_y:
			var f := (prev.y - plane_y) / (prev.y - next.y)
			ideal_contact_pos = prev.lerp(next, f)
			return t + PitchModel.DT * f
		probe.pos = next
		t += PitchModel.DT
	return t
