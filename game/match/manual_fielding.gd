class_name ManualFielding
extends RefCounted
## The player's own fielder during a ball in play (docs/05 2.3): moved by the player at the
## fielder's own speed, he takes the ball when it is within his reach and the player has put
## the glove up for it (the catch key, C: the glove stays up CATCH_HOLD s, so the key may come
## a little early; a ball he does not reach for goes by). A dive (or a leap for one over his
## head) is a try for it in itself: it reaches further for a moment and leaves him on the
## ground. What he did is handed to the play (PlayChoice.manual_*), which goes on from there.

## Seconds between the positions kept for the play's timeline.
const SAMPLE := 0.1
## A dive: he is off his feet from DIVE_FROM s after the key to DIVE_UNTIL s, and down until
## DIVE_DOWN s.
const DIVE_FROM := 0.06
const DIVE_UNTIL := 0.36
const DIVE_DOWN := 0.95
## The ball cannot be taken off the bat itself (the catcher stands right behind it).
const LEAVES_BAT := 0.25
## Steps the ball's flight is checked in (s): a line drive covers a metre in a fortieth.
const CHECK := 1.0 / 240.0
## How far inside the wall he stays (m).
const WALL_ROOM := 0.6
## After the catch key the glove is up this long (s): pressed this much before the ball
## reaches him, it is still a catch; pressed sooner, the glove is down again when it comes.
const CATCH_HOLD := 0.6
## The catch prompt shows when the ball will be in his reach within this long (s).
const CATCH_SOON := 0.5

var kind: Position.Kind = Position.Kind.SS
var pos := Vector2.ZERO
var velocity := Vector2.ZERO
var top_speed := 8.0
## Metres a second each second: a rangy fielder is at full speed sooner.
var quickness := 12.0
var backward := 0.88
## How near the ball has to come (m, on the ground) and how high he can take it; diving or
## leaping, `dive_reach` further and up to `leap`.
var reach := 1.1
var high := 2.3
var dive_reach := 0.9
var leap := 2.9
var field: AnalyticField

## (time, x, y) samples of where he has been.
var track := PackedVector3Array()
var got := false
var got_time := -1.0
var got_at := Vector3.ZERO
var got_dive := false
## When he left his feet (−1: he has not), and which way.
var dive_time := -1.0
var dive_toward := Vector2.ZERO
## When the catch key was last pressed (−INF: not yet).
var catch_pressed := -INF
## Takes the ball without the key (tools that drive him, and the old way).
var auto_catch := false
var _sampled := -INF


static func make(f: PlayFielder, m: MotionModel, analytic: AnalyticField = null) -> ManualFielding:
	var mf := ManualFielding.new()
	mf.kind = f.kind
	mf.pos = f.pos
	mf.top_speed = m.top_speed_for(f.speed)
	mf.quickness = lerpf(9.0, 15.0, clampf(f.reach / 99.0, 0.0, 1.0))
	mf.backward = m.backward
	# Sure hands take a ball a little further off.
	mf.reach = m.reach_running * lerpf(0.92, 1.08, clampf(f.hands / 99.0, 0.0, 1.0))
	mf.high = m.reach_high
	mf.dive_reach = m.reach_diving - m.reach_running
	mf.leap = m.reach_jump
	mf.field = analytic
	return mf


## He is in the air or on the ground at `t`: the keys do not move him.
func diving(t: float) -> bool:
	return dive_time >= 0.0 and t < dive_time + DIVE_DOWN


## Off his feet and reaching: the part of a dive that can take the ball.
func stretched(t: float) -> bool:
	return dive_time >= 0.0 and t >= dive_time + DIVE_FROM and t <= dive_time + DIVE_UNTIL


## Leaves his feet toward where the ball will be nearest him while he is in the air and it is
## low enough to take (or the way he is running, when it is nowhere near). False when he
## cannot (he has the ball, or is already down).
func dive(t: float, path: Trajectory) -> bool:
	if got or diving(t) or t < LEAVES_BAT:
		return false
	var best := INF
	var toward := Vector2.ZERO
	var when := t + DIVE_FROM
	while when <= t + DIVE_UNTIL:
		var ball := path.position_at(when)
		# Where he will be by then if he does not lunge at all.
		var to_ball := Vector2(ball.x, ball.y) - (pos + velocity * (when - t))
		var off := to_ball.length() + (0.0 if ball.z <= leap else 4.0)
		if off < best:
			best = off
			toward = to_ball
		when += 0.02
	dive_toward = toward.normalized() if best < 8.0 and toward.length() > 0.05 else velocity.normalized()
	dive_time = t
	return true


## The glove goes up for the ball (the catch key).
func press_catch(t: float) -> void:
	catch_pressed = t


## The glove is up at `t`.
func glove_up(t: float) -> bool:
	return auto_catch or (t >= catch_pressed and t <= catch_pressed + CATCH_HOLD)


## The ball will come within his reach soon if he keeps going as he is (for the prompt).
func catch_soon(t: float, path: Trajectory) -> bool:
	if got or diving(t):
		return false
	var when := t
	while when <= t + CATCH_SOON:
		var ball := path.position_at(when)
		var me := pos + velocity * (when - t)
		if when >= LEAVES_BAT and ball.z <= high and Vector2(ball.x, ball.y).distance_to(me) <= reach + 0.4:
			return true
		when += 0.03
	return false


## Moves him on by `dt` to time `t` (seconds after contact). `wish` is where the player pushes
## (field x, y; no longer than 1). True in the step he gets the ball.
func step(t: float, dt: float, wish: Vector2, path: Trajectory) -> bool:
	if got or dt <= 0.0:
		return false
	var from := pos
	var before := t - dt
	if diving(t):
		# The lunge carries him on the way he was going and `dive_reach` further; then he lies.
		var lunge := DIVE_UNTIL - DIVE_FROM
		var a := clampf((before - dive_time - DIVE_FROM) / lunge, 0.0, 1.0)
		var b := clampf((t - dive_time - DIVE_FROM) / lunge, 0.0, 1.0)
		pos += dive_toward * dive_reach * (b - a)
		if t <= dive_time + DIVE_UNTIL:
			pos += velocity * dt
		else:
			velocity = velocity.move_toward(Vector2.ZERO, 30.0 * dt)
			pos += velocity * dt
	else:
		if dive_time >= 0.0:
			dive_time = -1.0
		var push := wish.limit_length(1.0)
		var limit := top_speed
		# Going back on a ball costs speed, as it does the others.
		if push.length() > 0.01 and pos.length() > 1.0 and push.normalized().dot(pos.normalized()) > 0.5:
			limit *= backward
		var want := push * limit
		# Stopping and turning are quicker than getting going.
		var rate := quickness * (1.6 if want.length() < velocity.length() or want.dot(velocity) < 0.0 else 1.0)
		velocity = velocity.move_toward(want, rate * dt)
		pos += velocity * dt
	_stay_in_the_park()
	# The ball against him, along the step.
	var steps := maxi(ceili(dt / CHECK), 1)
	for i: int in range(1, steps + 1):
		var f := float(i) / steps
		var when := before + dt * f
		if when < LEAVES_BAT:
			continue
		var ball := path.position_at(when)
		var me := from.lerp(pos, f)
		var off := stretched(when)
		if diving(when) and not off:
			continue
		if ball.z > (leap if off else high):
			continue
		# Within reach, he has it if he is reaching for it: diving, or the glove up.
		if not off and not glove_up(when):
			continue
		if Vector2(ball.x, ball.y).distance_to(me) <= reach:
			pos = me
			got = true
			got_time = when
			got_at = ball
			got_dive = off
			velocity = Vector2.ZERO
			track.append(Vector3(when, pos.x, pos.y))
			return true
	if t - _sampled >= SAMPLE:
		_sampled = t
		track.append(Vector3(t, pos.x, pos.y))
	return false


func _stay_in_the_park() -> void:
	if field == null or pos.length() < 1.0:
		return
	var edge := field.boundary_distance(rad_to_deg(atan2(pos.x, pos.y))) - WALL_ROOM
	if pos.length() > edge:
		pos = pos.normalized() * edge
		# He runs along the wall, not through it.
		velocity -= pos.normalized() * maxf(velocity.dot(pos.normalized()), 0.0)


## The choice this makes of the play: the fielder and where he has been, and the ball if he
## has it. `ready`: the earliest he can throw (PlayContext.manual_ready).
func write(choice: PlayChoice, ready: float = 0.0) -> void:
	choice.manual_fielder = kind
	choice.manual_track = track.duplicate()
	choice.manual_time = got_time if got else -1.0
	choice.manual_at = got_at
	choice.manual_dive = got_dive
	choice.manual_ready = ready
