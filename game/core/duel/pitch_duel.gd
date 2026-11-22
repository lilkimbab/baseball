class_name PitchDuel
extends RefCounted
## One pitch from release to its result: flight to the plate, the batter's swing, contact,
## and the batted ball. The scene feeds it decisions and reads the ball back every tick.

enum Phase { READY, FLIGHT, IN_PLAY, DONE }
enum Result { NONE, BALL, CALLED_STRIKE, SWINGING_STRIKE, FOUL, IN_PLAY, HOME_RUN, HIT_BY_PITCH, FOUL_TIP }

## The catcher receives the ball this far behind the apex of the plate.
const CATCH_Y := -0.9
## Seconds a foul ball is followed before the pitch is over.
const FOUL_FOLLOW_TIME := 2.5
## A ball tipped straight back within this angle of the pitch's line is a foul tip...
const FOUL_TIP_DEG := 12.0
## ...when the catcher holds on to it, as he usually does.
const FOUL_TIP_HELD := 0.75

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
## The pitch hit the ground before reaching the catcher.
var bounced := false
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
	zone = StrikeZone.for_batter(settings.batter_height, settings.rules)
	_rng = rng
	ball = BallSim.new(cfg)


## Releases the pitch. Execution error from command and quality is applied here; pass
## exact = true to put the pitch precisely on its target (tests, practice mode).
func throw_pitch(choice: PitchDecision, exact: bool = false) -> void:
	decision = choice
	var actual := choice.target
	if not exact:
		var quality := clampf(choice.quality, 0.0, 1.0)
		# By hand: let go at the right moment, the pitch goes where it was aimed, as near as the
		# pitcher's control allows (perfect_share: an ace on the spot, a wild arm a ball's width
		# off); the difficulty (hand_scatter) grows only what the timing was off.
		var by_hand := perfect_share(settings.command) + (player_scatter(quality) - PLAYER_BEST) * settings.hand_scatter
		var sigma := PitchModel.command_sigma(settings.command) * (by_hand if choice.by_hand else lerpf(2.0, 0.5, quality))
		sigma *= 1.0 + COLD_SCATTER * choice.cold
		actual = PitchModel.apply_execution_error(choice.target, sigma, _rng)
	var type := choice.type
	pitch = PitchModel.throw_at(cfg, settings.release(), actual, type.speed_kmh * choice.effort,
		type.spin_rpm, type.efficiency, type.tilt_deg, settings.throws_left, SwingModel.CONTACT_PLANE_Y, false,
		type.ssw_accel * settings.ssw_scale, type.ssw_deg)
	ball = BallSim.new(cfg)
	ball.pos = pitch.release_pos
	ball.vel = pitch.release_vel
	ball.spin = pitch.spin
	ball.ssw = pitch.ssw
	ideal_contact_time = pitch.contact_time
	ideal_contact_pos = pitch.contact_pos
	swing = null
	contact = null
	path = null
	time = 0.0
	bounced = false
	result = Result.NONE
	phase = Phase.FLIGHT


## How much of his usual miss the player's own pitch has, from his timing on the gauge (0 to
## 1): let go at the right moment it is PLAYER_BEST of it (two or three centimetres for an
## average pitcher: the ball goes where he aimed), a twentieth of a second off about 0.45, a
## tenth 0.8, and missed altogether PLAYER_WORST. (It was the computer's scale, 0.5 to 2: a
## perfect pitch still missed by 12 cm on average and one a moment late by 22, and aiming
## felt like it did nothing.)
const PLAYER_BEST := 0.15
## A reliever not yet ready misses this much more (times how cold he is).
const COLD_SCATTER := 0.9
const PLAYER_WORST := 2.0


## The share of his usual miss a pitch let go at exactly the right moment still has, by his
## control (the user: "even a perfect release should move a little by the pitcher's control —
## other games do too"): per side, about 1 cm at command 95, 3 at 55, 6 at 30.
const PERFECT_WILD := 0.36
const PERFECT_ACE := 0.06


static func perfect_share(command: float) -> float:
	return lerpf(PERFECT_WILD, PERFECT_ACE, clampf(command / 100.0, 0.0, 1.0))


static func player_scatter(quality: float) -> float:
	return lerpf(PLAYER_WORST, PLAYER_BEST, pow(clampf(quality, 0.0, 1.0), 0.6))


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
	var hit := ball.advance(dt, field)
	if hit != null and hit.normal.z > 0.5:
		bounced = true
	time += dt
	if swing != null and not swing.resolved and time >= swing.contact_time:
		_resolve_swing()
		if phase != Phase.FLIGHT:
			return
	if _hits_batter():
		_hit_batter()
		return
	if ball.pos.y <= CATCH_Y or ball.rolling or time > 3.0:
		if swing != null:
			if not swing.resolved:
				swing.resolved = true
				swing.tau = (swing.contact_time - ideal_contact_time) / SwingModel.timing_window(settings, swing.kind)
				swing.judgment = &"miss"
				swing.miss_reason = &"timing"
			result = Result.SWINGING_STRIKE
		else:
			result = Result.CALLED_STRIKE if zone.is_strike(pitch) else Result.BALL
		phase = Phase.DONE


## After contact the ball follows the forecast exactly: what the fielders and the camera were
## told is what happens.
func _tick_in_play(dt: float) -> void:
	time += dt
	var since := time - _contact_at
	ball.pos = path.position_at(since)
	ball.time = time
	var finished := since >= path.duration()
	if finished:
		var last := path.events.back() as BallEvent if not path.events.is_empty() else null
		ball.stopped = last != null and last.kind == BallEvent.Kind.STOP
		ball.vel = Vector3.ZERO if ball.stopped else ball.vel
	var since_contact := time - _contact_at
	var foul_done := result == Result.FOUL and since_contact > FOUL_FOLLOW_TIME
	if ball.stopped or field.is_out_of_play(ball.pos) or foul_done or since_contact > 20.0:
		phase = Phase.DONE


## The pitch is touching the batter's body.
func _hits_batter() -> bool:
	var side := 1.0 if settings.bats_left else -1.0
	var centre := Vector2(side * settings.body_offset, StrikeZone.MID_PLANE_Y)
	if Vector2(ball.pos.x, ball.pos.y).distance_to(centre) > settings.body_radius + cfg.ball_radius:
		return false
	return ball.pos.z >= settings.body_ankle and ball.pos.z <= settings.batter_height * settings.body_shoulder_share


## A swing at it is a strike; a pitch in the zone is a strike; otherwise he takes his base,
## unless he got out of the way.
func _hit_batter() -> void:
	phase = Phase.DONE
	if swing != null:
		if not swing.resolved:
			swing.resolved = true
			swing.judgment = &"miss"
		result = Result.SWINGING_STRIKE
	elif zone.is_strike(pitch):
		result = Result.CALLED_STRIKE
	elif settings.dodge > 0.0 and _rng.chance(settings.dodge):
		result = Result.BALL
	else:
		result = Result.HIT_BY_PITCH
	ball.vel = Vector3.ZERO
	ball.stopped = true


func _resolve_swing() -> void:
	swing.resolved = true
	var window := SwingModel.timing_window(settings, swing.kind)
	swing.tau = (swing.contact_time - ideal_contact_time) / window
	swing.judgment = SwingModel.judge(swing.tau)
	if absf(swing.tau) > 1.0:
		swing.miss_reason = &"timing"
		return

	# Aim is judged against the pitch's path at the contact plane, not against where the ball
	# happens to be at this instant: the swing plane follows the pitch, so being early or
	# late changes direction (yaw), not whether the barrel is on the ball's line.
	var ball_at := Vector2(ideal_contact_pos.x, ideal_contact_pos.z)
	if not SwingModel.reachable(zone, ball_at):
		swing.judgment = &"miss"
		swing.miss_reason = &"reach"
		return
	var aim := swing.aim
	if not swing.has_aim:
		var read := SwingModel.read_sigma(settings, decision.type.family)
		aim = ball_at + Vector2(_rng.next_normal(), _rng.next_normal()) * read

	# Swinging above the ball tops it (negative offset), below it lifts it.
	var error := aim - ball_at
	var scale_y := SwingModel.error_scale(error.y, settings.aim_scale, settings.aim_forgiven) if settings.aim_forgiving else settings.aim_scale
	var scale_x := SwingModel.error_scale(error.x, settings.aim_scale, settings.aim_forgiven) if settings.aim_forgiving else settings.aim_across
	# Reaching for a pitch off the plate costs precision.
	var reach_spread := zone.distance_outside(ball_at.x, ball_at.y) * SwingModel.OUTSIDE_SPREAD
	var offset_up := SwingModel.intended_offset(swing.kind) - error.y * scale_y + swing.offset_bias \
		+ _rng.next_normal() * (SwingModel.barrel_sigma(settings, swing.kind) + reach_spread)
	swing.offset = offset_up
	var along := cfg.sweet_spot_from_tip + absf(error.x) * scale_x
	if along > SwingModel.BAT_LENGTH_USABLE:
		swing.miss_reason = &"end"
		return

	var bunt := swing.kind == SwingAttempt.Kind.BUNT
	# Early swings pull the ball and late ones push it; so does where the pitch is: an inside
	# pitch is met out in front and pulled, an outside one carried the other way.
	var inside := -ball_at.x if not settings.bats_left else ball_at.x
	var yaw := SwingModel.yaw_for(swing.tau) + deg_to_rad(SwingModel.LOCATION_YAW_DEG_PER_M * inside \
		+ (_rng.next_normal() * settings.yaw_spread if settings.yaw_spread > 0.0 else 0.0))
	var attack := deg_to_rad(SwingModel.ATTACK_DEG)
	if bunt:
		# The bat is held level and angled toward the line he wants. Toward first base is a
		# pull for a left-handed batter and a push for a right-handed one.
		yaw = deg_to_rad(swing.bunt_angle if settings.bats_left else -swing.bunt_angle)
		attack = 0.0
	var incoming := ball.vel
	# Met early or late, the barrel is not yet (or no longer) at full speed.
	var bat_speed := SwingModel.bat_speed(settings, swing.kind) * (1.0 - SwingModel.TIMING_SPEED_LOSS * swing.tau * swing.tau)
	contact = ContactModel.resolve(cfg, ball.vel, ball.spin, bat_speed,
		attack, yaw, offset_up, along, settings.bats_left)
	if not contact.made_contact:
		swing.miss_reason = &"under" if offset_up > 0.0 else &"over"
		return
	if not bunt and contact.velocity.normalized().dot(incoming.normalized()) > cos(deg_to_rad(FOUL_TIP_DEG)) \
			and _rng.chance(FOUL_TIP_HELD):
		# Straight back into the mitt.
		swing.made_contact = true
		result = Result.FOUL_TIP
		phase = Phase.DONE
		return

	swing.made_contact = true
	ball.vel = contact.velocity
	ball.spin = contact.spin
	ball.hit()
	ball.rolling = false
	ball.stopped = false
	_contact_at = time
	# The forecast's clock starts at contact, like the play that follows it.
	var probe := ball.clone()
	probe.time = 0.0
	path = BallFlight.run(probe, field)
	result = _classify(path)
	hit_distance = _first_landing_distance(path)
	# Only a home run's distance is announced.
	carry_distance = _open_air_carry() if result == Result.HOME_RUN else hit_distance
	phase = Phase.IN_PLAY


## The umpire's call with nobody touching the ball. The play (PlaySim) makes the final call,
## since a fielder touching a ball short of the bases decides it there.
func _classify(forecast: Trajectory) -> Result:
	match Umpire.judge(forecast):
		Umpire.Call.HOME_RUN:
			return Result.HOME_RUN
		Umpire.Call.FOUL:
			return Result.FOUL
	return Result.IN_PLAY


static func _first_landing_distance(forecast: Trajectory) -> float:
	if forecast.events.is_empty():
		return Trajectory.ground_distance(forecast.end_point())
	return Trajectory.ground_distance(forecast.events[0].pos)


## Flies a copy of the ball with no field in the way until it returns to the ground.
func _open_air_carry() -> float:
	var probe := ball.clone()
	var t := 0.0
	while t < 12.0 and (probe.pos.z > cfg.ball_radius or probe.vel.z > 0.0):
		probe.pos = probe.integrate(BallFlight.COARSE_DT)
		t += BallFlight.COARSE_DT
	return Trajectory.ground_distance(probe.pos)

