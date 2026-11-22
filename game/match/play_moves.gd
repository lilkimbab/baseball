class_name PlayMoves
extends RefCounted
## What each fielder and runner does at each moment of a play (docs/13 S12), read off the
## play's timeline: who first gets to the ball and at what height, who throws when and where
## to, who receives each throw, which runner slides into which base. MatchScene turns these
## into poses.

enum Kind { CATCH, THROW, SLIDE, TAG, MISS }

## Seconds around each moment that its pose takes: a catch from just before the ball arrives
## to just after, a throw from the wind-up to the follow-through, a slide from the drop.
const WINDOW := {Kind.CATCH: Vector2(-0.3, 0.25), Kind.THROW: Vector2(-0.35, 0.45), Kind.SLIDE: Vector2(-0.35, 0.6), Kind.TAG: Vector2(-0.25, 0.4), Kind.MISS: Vector2(-0.3, 0.6)}
## How near (m, on the ground) a fielder must be to the ball to be the one who gets it.
const REACH := 1.2
## A play this close (s between runner and ball) gets a slide, and it is down this far (m)
## from the bag.
const CLOSE := 1.2
const SLIDE_FROM := 1.5
## Throws shorter than TOSS_WITHIN (m) are flipped underhand; infielders snap them under
## SNAP_WITHIN; outfielders crow-hop beyond CROW_HOP_BEYOND.
const TOSS_WITHIN := 9.0
const SNAP_WITHIN := 32.0
const CROW_HOP_BEYOND := 35.0
## A runner who slides into a base he was this near (m) at the start is diving back to it.
const BACK_TO := 6.0
const STEP := 0.04
## Seconds after contact before anyone can field the ball.
const LEAVES_BAT := 0.2


class Moment:
	var kind := Kind.CATCH
	var time := 0.0
	## Where the ball is (a catch), where it goes (a throw), or the base (a slide).
	var at := Vector3.ZERO
	## A slide head first: diving back to the base he left.
	var head_first := false
	## How a throw is made (PuppetClips.throw_styled).
	var style: StringName = &"over"

	static func make(k: Kind, t: float, where: Vector3) -> Moment:
		var m := Moment.new()
		m.kind = k
		m.time = t
		m.at = where
		return m


## Track key ("F:SS", "R:<id>") → its moments in time order.
var by_key: Dictionary[String, Array] = {}


## `batted` false for a steal or a pickoff, where the play starts with a throw rather than a
## ball off the bat.
static func read(tl: PlayTimeline, calls: Array[PlayCall], batted: bool = true) -> PlayMoves:
	var moves := PlayMoves.new()
	var fielders: Array[String] = []
	for key: String in tl.tracks:
		if key.begins_with("F:"):
			fielders.append(key)
	# Tries that came up short: a dive at the ball as it goes by.
	for i: int in tl.miss_keys.size():
		var miss := tl.misses[i]
		moves._add(tl.miss_keys[i], Moment.make(Kind.MISS, miss.x, Vector3(miss.y, miss.z, miss.w)))
	# The first fielder to reach the ball in play.
	var first_throw := tl.throws[0][0].x if not tl.throws.is_empty() else tl.duration
	# Not at the bat itself, where the ball starts beside the catcher.
	var t := LEAVES_BAT
	var caught := not batted
	# The play says who had it and when: the catch is then, where the ball was. (Read off the
	# tracks, it was the first moment the ball came within REACH of a fielder, up to 1.2 m from
	# him and over his head, and the ball jumped into his glove.)
	if batted and tl.fielded_key != "" and tl.tracks.has(tl.fielded_key) and tl.fielded_time >= 0.0:
		moves._add(tl.fielded_key, Moment.make(Kind.CATCH, tl.fielded_time, tl.position("ball", tl.fielded_time)))
		caught = true
	while t <= first_throw and not caught:
		var ball := tl.position("ball", t)
		if ball.z < 2.7:
			for key: String in fielders:
				# (One who has just dived past it is not the man who has it.)
				if moves._missing(key, t) or tl.bystanders.has(key):
					continue
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
			var throw_m := Moment.make(Kind.THROW, release, to)
			throw_m.style = throw_style(thrower, Vector2(from.x, from.y).distance_to(Vector2(to.x, to.y)))
			moves._add(thrower, throw_m)
		var receiver := _nearest(tl, fielders, arrive, to)
		if receiver != "" and receiver != thrower:
			moves._add(receiver, Moment.make(Kind.CATCH, arrive, to))
	# On a tag play the fielder at the bag puts the glove down where the runner comes in.
	var runners: Array[String] = []
	for key: String in tl.tracks:
		if key.begins_with("R:"):
			runners.append(key)
	for c: PlayCall in calls:
		if not c.tag:
			continue
		var base := PlaySim.base_xy(c.base)
		var bag := Vector3(base.x, base.y, 0.0)
		var fielder := _nearest(tl, fielders, c.time, bag)
		var runner := _nearest(tl, runners, c.time, bag)
		if fielder == "":
			continue
		var at := bag
		if runner != "":
			var r := tl.position(runner, c.time)
			at = Vector3(r.x, r.y, 0.0).lerp(bag, 0.5)
		moves._add(fielder, Moment.make(Kind.TAG, c.time - 0.05, Vector3(at.x, at.y, 0.15)))
	# Runners slide into a base where the play on them is close.
	for key: String in tl.tracks:
		if not key.begins_with("R:"):
			continue
		var track := tl.tracks[key]
		var start := Vector2(track[0].y, track[0].z)
		for c: PlayCall in calls:
			# The batter runs through first base; elsewhere a runner slides whenever there is
			# a play on him, unless it is not close at all.
			if absf(c.margin) > CLOSE or (c.base == 1 and start.length() < 3.0):
				continue
			var base := PlaySim.base_xy(c.base)
			var when := c.time - 2.0
			while when <= c.time + 1.5:
				var at := tl.position(key, when)
				if Vector2(at.x - base.x, at.y - base.y).length() < SLIDE_FROM:
					var slide := Moment.make(Kind.SLIDE, when, Vector3(base.x, base.y, 0.0))
					slide.head_first = start.distance_to(base) < BACK_TO
					moves._add(key, slide)
					break
				when += STEP
	return moves


## How a fielder throws over `distance` m: a flip for a few metres, an infielder's snap
## across the infield, an outfielder's crow hop on a long one, otherwise overhand.
static func throw_style(key: String, distance: float) -> StringName:
	if distance < TOSS_WITHIN:
		return &"toss"
	var outfielder := key in ["F:LF", "F:CF", "F:RF"]
	if outfielder and distance > CROW_HOP_BEYOND:
		return &"crow_hop"
	if key in ["F:1B", "F:2B", "F:SS", "F:3B"] and distance < SNAP_WITHIN:
		return &"snap"
	return &"over"


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


## Fielder `key` is in a try that does not get the ball at `t` (or is still on the ground).
func _missing(key: String, t: float) -> bool:
	for m: Moment in by_key.get(key, []):
		if m.kind == Kind.MISS and t >= m.time - 0.5 and t <= m.time + 0.8:
			return true
	return false


func _add(key: String, m: Moment) -> void:
	if not by_key.has(key):
		by_key[key] = []
	by_key[key].append(m)
	(by_key[key] as Array).sort_custom(func(a: Moment, b: Moment) -> bool: return a.time < b.time)


## The moment whose pose is on at time t for a track, or null. Where two overlap the later
## one wins: the throw takes over from the catch, the tag from taking the throw.
func now(key: String, t: float) -> Moment:
	var on: Moment = null
	for m: Moment in by_key.get(key, []):
		var w: Vector2 = WINDOW[m.kind]
		if t >= m.time + w.x and t <= m.time + w.y:
			on = m
	return on
