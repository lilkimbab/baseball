class_name PlayMoves
extends RefCounted
## What each fielder and runner does at each moment of a play (docs/13 S12), read off the
## play's timeline: who first gets to the ball and at what height, who throws when and where
## to, who receives each throw, which runner slides into which base. MatchScene turns these
## into poses.

enum Kind { CATCH, THROW, SLIDE }

## Seconds around each moment that its pose takes: a catch from just before the ball arrives
## to just after, a throw from the wind-up to the follow-through, a slide from the drop.
const WINDOW := {Kind.CATCH: Vector2(-0.3, 0.25), Kind.THROW: Vector2(-0.35, 0.45), Kind.SLIDE: Vector2(-0.35, 0.6)}
## How near (m, on the ground) a fielder must be to the ball to be the one who gets it.
const REACH := 1.2
## A play this close (s between runner and ball) gets a slide, and it is down this far (m)
## from the bag.
const CLOSE := 1.2
const SLIDE_FROM := 1.5
const STEP := 0.04
## Seconds after contact before anyone can field the ball.
const LEAVES_BAT := 0.2


class Moment:
	var kind := Kind.CATCH
	var time := 0.0
	## Where the ball is (a catch), where it goes (a throw), or the base (a slide).
	var at := Vector3.ZERO

	static func make(k: Kind, t: float, where: Vector3) -> Moment:
		var m := Moment.new()
		m.kind = k
		m.time = t
		m.at = where
		return m


## Track key ("F:SS", "R:<id>") → its moments in time order.
var by_key: Dictionary[String, Array] = {}


static func read(tl: PlayTimeline, calls: Array[PlayCall]) -> PlayMoves:
	var moves := PlayMoves.new()
	var fielders: Array[String] = []
	for key: String in tl.tracks:
		if key.begins_with("F:"):
			fielders.append(key)
	# The first fielder to reach the ball in play.
	var first_throw := tl.throws[0][0].x if not tl.throws.is_empty() else tl.duration
	# Not at the bat itself, where the ball starts beside the catcher.
	var t := LEAVES_BAT
	var caught := false
	while t <= first_throw and not caught:
		var ball := tl.position("ball", t)
		if ball.z < 2.7:
			for key: String in fielders:
				var f := tl.position(key, t)
				if Vector2(f.x - ball.x, f.y - ball.y).length() < REACH:
					moves._add(key, Moment.make(Kind.CATCH, t, ball))
					caught = true
					break
		t += STEP
	# Throws: from the fielder nearest the release point, to the one nearest the target.
	for throw: PackedVector4Array in tl.throws:
		var release := throw[0].x
		var from := Vector3(throw[0].y, throw[0].z, throw[0].w)
		var arrive := throw[1].x
		var to := Vector3(throw[1].y, throw[1].z, throw[1].w)
		var thrower := _nearest(tl, fielders, release, from)
		if thrower != "":
			moves._add(thrower, Moment.make(Kind.THROW, release, to))
		var receiver := _nearest(tl, fielders, arrive, to)
		if receiver != "" and receiver != thrower:
			moves._add(receiver, Moment.make(Kind.CATCH, arrive, to))
	# Runners slide into a base where the play on them is close.
	for key: String in tl.tracks:
		if not key.begins_with("R:"):
			continue
		for c: PlayCall in calls:
			# A runner going to first runs through the bag; at the other bases he slides
			# whenever there is a play on him, unless it is not close at all.
			if absf(c.margin) > CLOSE or c.base == 1:
				continue
			var base := PlaySim.base_xy(c.base)
			var when := c.time - 2.0
			while when <= c.time + 1.5:
				var at := tl.position(key, when)
				if Vector2(at.x - base.x, at.y - base.y).length() < SLIDE_FROM:
					moves._add(key, Moment.make(Kind.SLIDE, when, Vector3(base.x, base.y, 0.0)))
					break
				when += STEP
	return moves


static func _nearest(tl: PlayTimeline, keys: Array[String], time: float, point: Vector3) -> String:
	var best := ""
	var best_d := 3.0
	for key: String in keys:
		var f := tl.position(key, time)
		var d := Vector2(f.x - point.x, f.y - point.y).length()
		if d < best_d:
			best_d = d
			best = key
	return best


func _add(key: String, m: Moment) -> void:
	if not by_key.has(key):
		by_key[key] = []
	by_key[key].append(m)
	(by_key[key] as Array).sort_custom(func(a: Moment, b: Moment) -> bool: return a.time < b.time)


## The moment whose pose is on at time t for a track, or null.
func now(key: String, t: float) -> Moment:
	for m: Moment in by_key.get(key, []):
		var w: Vector2 = WINDOW[m.kind]
		if t >= m.time + w.x and t <= m.time + w.y:
			return m
	return null
