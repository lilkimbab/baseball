class_name Umpire
extends RefCounted
## Calls on a batted ball (docs/13 S5-7, Official Baseball Rules 2.00 "fair ball" and "foul
## ball", 5.05(a), 5.06(b)(4)).
##
## - A ball that first lands beyond first or third base is fair or foul by where it lands.
## - Before the bases, the call waits: it is made where the ball is when it passes the base,
##   is touched by a fielder, or comes to rest.
## - A ball touched in the air is judged where it is touched.
## - The lines are fair: any part of the ball over the line is fair.
## - A fly that hits the top of the fence and goes over is a home run; one that bounces over
##   or out of play is a ground-rule double.

enum Call { FAIR, FOUL, HOME_RUN, GROUND_RULE_DOUBLE }

const BALL_RADIUS := 0.0366


## Fair territory including the lines: the ball's centre may be up to its radius outside them.
static func is_fair(p: Vector3) -> bool:
	return p.y - absf(p.x) >= -BALL_RADIUS * sqrt(2.0)


## How far along its foul line a point lies from home (m): past BASE_DISTANCE it is beyond
## first or third base.
static func along_line(p: Vector3) -> float:
	return (absf(p.x) + p.y) / sqrt(2.0)


static func past_the_bases(p: Vector3) -> bool:
	return along_line(p) > Field.BASE_DISTANCE


## Where the ball first touches anything (ground, wall or out of play); null if it never does.
static func first_touch(path: Trajectory) -> BallEvent:
	return null if path.events.is_empty() else path.events[0]


## A home run: out of play in fair territory on the fly, or off the top of the fence and over.
static func is_home_run(path: Trajectory) -> bool:
	if path.is_home_run():
		return true
	if path.events.size() >= 2 and path.events[0].kind == BallEvent.Kind.WALL:
		var next := path.events[1]
		return next.kind == BallEvent.Kind.OUT_OF_PLAY and is_fair(next.pos)
	return false


## The call on a batted ball. `touch_time` is when a fielder first touches it (seconds after
## contact), or negative if nobody does before it settles.
static func judge(path: Trajectory, touch_time: float = -1.0) -> Call:
	if is_home_run(path):
		return Call.HOME_RUN
	var first := first_touch(path)
	var touched := touch_time >= 0.0
	if first == null or (touched and touch_time <= first.time):
		var at := path.position_at(touch_time) if touched else path.end_point()
		return Call.FAIR if is_fair(at) else Call.FOUL
	var fair := false
	if past_the_bases(first.pos):
		fair = is_fair(first.pos)
	else:
		fair = _settled_before_bases(path, first.time, touch_time)
	if not fair:
		return Call.FOUL
	# Fair, then out of play after a bounce without a fielder touching it first.
	var out := path.first_event(BallEvent.Kind.OUT_OF_PLAY)
	if out != null and (not touched or touch_time > out.time):
		return Call.GROUND_RULE_DOUBLE
	return Call.FAIR


## Follows a ball that first came down in front of the bases until the call can be made.
static func _settled_before_bases(path: Trajectory, from_time: float, touch_time: float) -> bool:
	for i: int in path.times.size():
		var t := path.times[i]
		if t < from_time:
			continue
		var p := path.points[i]
		if touch_time >= 0.0 and t >= touch_time:
			return is_fair(path.position_at(touch_time))
		if past_the_bases(p):
			# Judge it where it passes the bases, between this sample and the one before.
			if i > 0:
				var q := path.points[i - 1]
				var a := along_line(q)
				var b := along_line(p)
				if b > a:
					p = q.lerp(p, clampf((Field.BASE_DISTANCE - a) / (b - a), 0.0, 1.0))
			return is_fair(p)
	for e: BallEvent in path.events:
		if e.kind == BallEvent.Kind.OUT_OF_PLAY:
			return false
	return is_fair(path.end_point())
