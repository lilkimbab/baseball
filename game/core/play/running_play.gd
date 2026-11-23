class_name RunningPlay
extends RefCounted
## Steals and pickoffs laid out as plays to show. The game settles them between
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
## A loose ball rolls this far behind the plate (m, the backstop) in LOOSE_ROLL s.
const BACKSTOP := 16.5
const LOOSE_ROLL := 1.6


## A steal of the base after `base` by `runner_id`. `margin` is by how much the runner was
## expected to beat the throw (s, PhysicalResolver.steal_margin); `safe` is how it came out.
## `cover_from` is where the fielder who takes the throw stood.
## `with_pitch` false starts at the catch, for a pitch already shown (the player's steal).
static func steal(base: int, runner_id: String, safe: bool, margin: float, cover: Position.Kind, cover_from: Vector2, motion: MotionModel, with_pitch: bool = true) -> PlayResult:
	var play := PlayResult.new()
	var tl := play.timeline
	var bag := PlaySim.base_xy(base + 1)
	var target := Vector3(bag.x, bag.y, 1.2)
	# The pitch.
	var caught := STEAL_LEAD_IN + PITCH_FLIGHT if with_pitch else 0.0
	tl.add("ball", 0.0, RELEASE_AT if with_pitch else CATCH_AT)
	if with_pitch:
		tl.add("ball", STEAL_LEAD_IN, RELEASE_AT)
		tl.add("ball", caught, CATCH_AT)
		tl.add_throw(STEAL_LEAD_IN, RELEASE_AT, caught, CATCH_AT)
	_stay(tl, "F:P", Vector2(0.0, Field.RUBBER_Y), maxf(caught, 0.1))
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
	var breaks := STEAL_LEAD_IN if with_pitch else 0.0
	tl.add(key, breaks, Vector3(cover_from.x, cover_from.y, 0.0))
	tl.add(key, maxf(arrive - 0.25, breaks + 0.3), Vector3(bag.x, bag.y, 0.0))
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


## A pitch that gets past the catcher (a wild pitch or a passed ball): it rolls to the
## backstop, the catcher turns and chases it, and each runner moves up a base. `runners` are
## the ids on first, second and third ("" where empty); `side` (−1 or 1) which way it kicks.
static func loose_ball(runners: Array[String], from: Vector3, side: float, motion: MotionModel) -> PlayResult:
	var play := PlayResult.new()
	var tl := play.timeline
	var rest := Vector2(side * 5.0, -BACKSTOP + 1.0)
	tl.add("ball", 0.0, from)
	tl.add("ball", 0.5, Vector3(lerpf(from.x, rest.x, 0.4), lerpf(from.y, rest.y, 0.4), 0.05))
	tl.add("ball", LOOSE_ROLL, Vector3(rest.x, rest.y, 0.04))
	# The catcher turns, goes after it and has it a moment after it stops.
	var picked := LOOSE_ROLL + 0.9
	tl.add("F:C", 0.0, Vector3(CATCHER_AT.x, CATCHER_AT.y, 0.0))
	tl.add("F:C", 0.4, Vector3(CATCHER_AT.x, CATCHER_AT.y, 0.0))
	tl.add("F:C", picked, Vector3(rest.x, rest.y + 0.8, 0.0))
	tl.add("ball", picked, Vector3(rest.x, rest.y + 0.6, 0.8))
	var last := picked
	for i: int in 3:
		if runners[i] == "":
			continue
		var start := PlaySim.base_xy(i + 1)
		var bag := PlaySim.base_xy(i + 2)
		var spot := start + (bag - start).normalized() * motion.leads[i]
		var reach := 0.6 + spot.distance_to(bag) / RUNNER_SPEED
		var key := "R:%s" % runners[i]
		tl.add(key, 0.0, Vector3(spot.x, spot.y, 0.0))
		tl.add(key, 0.6, Vector3(spot.x, spot.y, 0.0))
		tl.add(key, reach, Vector3(bag.x, bag.y, 0.0))
		last = maxf(last, reach)
	tl.duration = last + 0.3
	return play


static func _stay(tl: PlayTimeline, key: String, at: Vector2, until: float) -> void:
	tl.add(key, 0.0, Vector3(at.x, at.y, 0.0))
	tl.add(key, until, Vector3(at.x, at.y, 0.0))


## A runner from his lead off `from` to `to`, getting there at `reach` at full stride.
static func _runner(tl: PlayTimeline, id: String, from: int, lead: float, to: int, reach: float) -> void:
	var start := PlaySim.base_xy(from)
	var bag := PlaySim.base_xy(to)
	var spot := start + (bag - start).normalized() * lead
	var leave := reach - spot.distance_to(bag) / RUNNER_SPEED
	var key := "R:%s" % id
	if leave < 0.1:
		# Already on his way when the play opens.
		var on := bag + (spot - bag).normalized() * minf(spot.distance_to(bag), reach * RUNNER_SPEED)
		tl.add(key, 0.0, Vector3(on.x, on.y, 0.0))
		tl.add(key, reach, Vector3(bag.x, bag.y, 0.0))
		return
	tl.add(key, 0.0, Vector3(spot.x, spot.y, 0.0))
	tl.add(key, leave, Vector3(spot.x, spot.y, 0.0))
	tl.add(key, reach, Vector3(bag.x, bag.y, 0.0))
