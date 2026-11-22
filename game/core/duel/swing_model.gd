class_name SwingModel
extends RefCounted
## Turns a swing (when, what kind, where aimed) into the contact parameters of ContactModel
## (docs/05, section 2.2).

## Distance in front of home plate's apex where a square swing meets the ball.
const CONTACT_PLANE_Y := 0.75
## Bat yaw at the edge of the timing window. Batted-ball direction is about 1.65 times the
## yaw, so the ball stays fair for roughly |tau| < 0.54; beyond that it is pulled or sliced
## foul, and past the window the swing misses.
const MAX_YAW_DEG := 55.0
## Extra pull per metre the pitch is inside (toward the batter), push per metre outside.
const LOCATION_YAW_DEG_PER_M := 80.0
## The bat's angle at contact varies a little from swing to swing (degrees, one sd).
const YAW_SPREAD_DEG := 11.0
const ATTACK_DEG := 8.0
## Furthest the barrel can be from the ball along the bat and still touch it (m from tip).
const BAT_LENGTH_USABLE := 0.6
## How far outside the strike zone a batter can still get the bat on the ball. Beyond this a
## swing meets nothing, however well it is timed.
const REACH_OUTSIDE_ZONE := 0.22
## Share of the bat speed lost at the edge of the timing window (|tau| = 1), falling off as
## tau squared: a mistimed swing meets the ball weakly.
const TIMING_SPEED_LOSS := 0.30
## Extra spread of the bat-ball offset per metre the pitch is outside the zone.
const OUTSIDE_SPREAD := 0.60


## Seconds from starting the swing to the barrel reaching the ball.
## True if a pitch crossing at (x across, y up) is somewhere a bat can get to.
static func reachable(zone: StrikeZone, crossing: Vector2) -> bool:
	return zone.distance_outside(crossing.x, crossing.y) <= REACH_OUTSIDE_ZONE


static func swing_time(kind: SwingAttempt.Kind) -> float:
	match kind:
		SwingAttempt.Kind.POWER:
			return 0.13
		SwingAttempt.Kind.BUNT:
			return 0.0
	return 0.11


## Half-width of the timing window for this swing. A bunt is the bat held out: timing hardly
## matters, only height and angle.
static func timing_window(settings: DuelSettings, kind: SwingAttempt.Kind) -> float:
	var by_kind := 1.15
	match kind:
		SwingAttempt.Kind.POWER:
			by_kind = 0.8
		SwingAttempt.Kind.BUNT:
			by_kind = 3.0
	return settings.timing_window * settings.timing_scale * by_kind * lerpf(0.85, 1.15, clampf(settings.contact / 100.0, 0.0, 1.0))


static func judge(tau: float) -> StringName:
	var a := absf(tau)
	if a > 1.0:
		return &"miss"
	if a < 0.15:
		return &"perfect"
	if a < 0.45:
		return &"good"
	return &"early" if tau < 0.0 else &"late"


## Bat yaw for a timing error: an early swing (negative tau) meets the ball out in front.
static func yaw_for(tau: float) -> float:
	return deg_to_rad(-tau * MAX_YAW_DEG)


## A bunt meets the ball with the bat nearly still (2-4 m/s, docs/13 S5-1).
const BUNT_BAT_SPEED := 3.0


static func bat_speed(settings: DuelSettings, kind: SwingAttempt.Kind) -> float:
	if kind == SwingAttempt.Kind.BUNT:
		return BUNT_BAT_SPEED
	var by_kind := 1.04 if kind == SwingAttempt.Kind.POWER else 0.96
	return ContactModel.bat_speed_from_power(settings.power) * by_kind


## Height of the ball above the bat's axis the batter is trying for: a line drive on a
## contact swing, a fly ball on a power swing.
static func intended_offset(kind: SwingAttempt.Kind) -> float:
	match kind:
		SwingAttempt.Kind.POWER:
			return 0.033
		SwingAttempt.Kind.BUNT:
			# On top of the ball, to put it on the ground.
			return -0.012
	return 0.021


## Random vertical error of the barrel (metres, one standard deviation).
static func barrel_sigma(settings: DuelSettings, kind: SwingAttempt.Kind) -> float:
	var by_kind := 0.8
	match kind:
		SwingAttempt.Kind.POWER:
			by_kind = 1.2
		SwingAttempt.Kind.BUNT:
			by_kind = 0.6
	return lerpf(0.016, 0.006, clampf(settings.contact / 100.0, 0.0, 1.0)) * by_kind * settings.barrel_scale


## How well the batter reads where the pitch will end up (metres, one standard deviation).
## Pitches that are slower or break more are harder to read.
static func read_sigma(settings: DuelSettings, family: StringName = &"fastball") -> float:
	var by_family := 1.0
	if family == &"breaking":
		by_family = 1.4
	elif family == &"offspeed":
		by_family = 1.25
	return lerpf(0.14, 0.04, clampf(settings.eye / 100.0, 0.0, 1.0)) * by_family


## Aiming errors smaller than this (m) are mostly forgiven...
const FORGIVEN_ERROR := 0.06
## ...and errors larger than this count in full: the batter was fooled and swings through.
const FOOLED_ERROR := 0.26


## Share of an aiming error that turns into bat-ball offset. Small errors are scaled down to
## aim_scale so play is not pixel-precise; large ones are real misses.
static func error_scale(error: float, aim_scale: float, forgiven: float = FORGIVEN_ERROR) -> float:
	return aim_scale + (1.0 - aim_scale) * smoothstep(forgiven, FOOLED_ERROR, absf(error))
