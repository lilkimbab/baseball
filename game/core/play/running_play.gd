class_name RunningPlay
extends RefCounted
## Steals and pickoffs laid out as plays to show (docs/13 S12). The game settles them between
## pitches (PhysicalResolver.before_pitch); this says who goes where and when, so the match
## scene can play them like a batted ball: the pitch or the pickoff throw, the catcher's throw,
## the man covering the bag, the runner's slide and the umpire's call.

## The play opens with the pitcher's arm on its way: the pickoff throw leaves his hand this
## long in, which leaves room for the throwing motion before it. On a steal the runner breaks
## with the pitcher's first move, STEAL_LEAD_IN before the pitch leaves his hand.
const LEAD_IN := 0.5
const STEAL_LEAD_IN := 1.0
## Seconds from the pitcher's hand to the catcher's mitt.
const PITCH_FLIGHT := 0.45
## Runners in full stride (m/s): about a 4.1 s runner from home to first.
const RUNNER_SPEED := 7.6
## The closest a shown play is: it never looks like a dead heat that went the other way.
const MIN_MARGIN := 0.05
## The catcher at his crouch, where he takes the pitch, and the pitcher's release point.
const CATCHER_AT := Vector2(0.0, -1.15)
const CATCH_AT := Vector3(0.0, -0.9, 0.8)
const RELEASE_AT := Vector3(0.0, Field.RUBBER_Y - 1.6, 1.8)


## A steal of the base after `base` by `runner_id`. `margin` is by how much the runner was
## expected to beat the throw (s, PhysicalResolver.steal_margin); `safe` is how it came out.
## `cover_from` is where the fielder who takes the throw stood.
static func steal(base: int, runner_id: String, safe: bool, margin: float, cover: Position.Kind, cover_from: Vector2, motion: MotionModel) -> PlayResult:
	var play := PlayResult.new()
	var tl := play.timeline
	var bag := PlaySim.base_xy(base + 1)
	var target := Vector3(bag.x, bag.y, 1.2)
	# The pitch.
	var caught := STEAL_LEAD_IN + PITCH_FLIGHT
	tl.add("ball", 0.0, RELEASE_AT)
	tl.add("ball", STEAL_LEAD_IN, RELEASE_AT)
	tl.add("ball", caught, CATCH_AT)
	tl.add_throw(STEAL_LEAD_IN, RELEASE_AT, caught, CATCH_AT)
	_stay(tl, "F:P", Vector2(0.0, Field.RUBBER_Y), caught)
	# The catcher's throw to the bag.
	var release := caught + motion.transfer_for(Position.Kind.C, 50.0)
	var from := Vector3(CATCHER_AT.x, CATCHER_AT.y + 0.4, 1.8)
	var arrive := release + motion.throw_time(Vector2(from.x, from.y).distance_to(bag), motion.throw_speed(Position.Kind.C, 50.0))
	_stay(tl, "F:C", CATCHER_AT, release)
	tl.add("ball", release, from)
	tl.add("ball", arrive, target)
	tl.add_throw(release, from, arrive, target)
	# The cover man breaks for the bag as the runner goes and is there before the ball.
	var key := "F:%s" % Position.code(cover)
	tl.add(key, STEAL_LEAD_IN, Vector3(cover_from.x, cover_from.y, 0.0))
	tl.add(key, maxf(arrive - 0.25, STEAL_LEAD_IN + 0.3), Vector3(bag.x, bag.y, 0.0))
	# The runner, from his lead, at full stride, to the bag.
	var shown := maxf(absf(margin), MIN_MARGIN) * (1.0 if safe else -1.0)
	var need := arrive + motion.tag
	var reach := need - shown
	var call_at := maxf(need, reach)
	_runner(tl, runner_id, base, motion.leads[base - 1], base + 1, reach)
	tl.add("ball", call_at, Vector3(bag.x, bag.y, 0.4))
	play.calls.append(PlayCall.make(call_at, base + 1, not safe, absf(shown), true))
	play.fielders = "" if safe else "2-%d" % (int(cover) + 1)
	tl.duration = call_at + 0.2
	return play


## A pickoff at first: the pitcher throws over, the runner dives back and is tagged.
static func pickoff(runner_id: String, first_from: Vector2, motion: MotionModel) -> PlayResult:
	var play := PlayResult.new()
	var tl := play.timeline
	var bag := PlaySim.base_xy(1)
	var target := Vector3(bag.x, bag.y, 1.0)
	var hand := Vector3(0.6, Field.RUBBER_Y - 0.3, 1.6)
	var arrive := LEAD_IN + motion.throw_time(Vector2(hand.x, hand.y).distance_to(bag), motion.throw_speed(Position.Kind.P, 50.0))
	tl.add("ball", 0.0, hand)
	tl.add("ball", LEAD_IN, hand)
	tl.add("ball", arrive, target)
	tl.add_throw(LEAD_IN, hand, arrive, target)
	_stay(tl, "F:P", Vector2(0.0, Field.RUBBER_Y), arrive)
	tl.add("F:1B", 0.0, Vector3(first_from.x, first_from.y, 0.0))
	tl.add("F:1B", maxf(arrive - 0.2, 0.1), Vector3(bag.x, bag.y, 0.0))
	# Back to the bag he left, a little too late.
	var need := arrive + motion.tag
	var lead := bag + (PlaySim.base_xy(2) - bag).normalized() * motion.leads[0]
	var key := "R:%s" % runner_id
	tl.add(key, 0.0, Vector3(lead.x, lead.y, 0.0))
	tl.add(key, LEAD_IN - 0.1, Vector3(lead.x, lead.y, 0.0))
	tl.add(key, need + 0.1, Vector3(bag.x, bag.y, 0.0))
	tl.add("ball", need, Vector3(bag.x + 0.3, bag.y + 0.3, 0.3))
	play.calls.append(PlayCall.make(need, 1, true, 0.1, true))
	play.fielders = "1-3"
	tl.duration = need + 0.4
	return play


static func _stay(tl: PlayTimeline, key: String, at: Vector2, until: float) -> void:
	tl.add(key, 0.0, Vector3(at.x, at.y, 0.0))
	tl.add(key, until, Vector3(at.x, at.y, 0.0))


## A runner from his lead off `from` to `to`, getting there at `reach` at full stride.
static func _runner(tl: PlayTimeline, id: String, from: int, lead: float, to: int, reach: float) -> void:
	var start := PlaySim.base_xy(from)
	var bag := PlaySim.base_xy(to)
	var spot := start + (bag - start).normalized() * lead
	var leave := maxf(reach - spot.distance_to(bag) / RUNNER_SPEED, 0.1)
	var key := "R:%s" % id
	tl.add(key, 0.0, Vector3(spot.x, spot.y, 0.0))
	tl.add(key, leave, Vector3(spot.x, spot.y, 0.0))
	tl.add(key, reach, Vector3(bag.x, bag.y, 0.0))
