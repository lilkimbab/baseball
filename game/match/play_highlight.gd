class_name PlayHighlight
extends RefCounted
## A moment of a play shown slowly and close up (docs/04 3.4): the bat meeting a ball hit out
## of the park or to the wall, and a catch that could have gone either way, made or missed.
## They are for the player at bat watching the other side field, and they are rare by design:
## only a ball that really was crushed, only a chance that really was in doubt, and not one
## soon after another. Seen every inning they would be a chore.

enum Kind { CONTACT, CHANCE }

## A ball in the air that came down within this (m) of the fence was nearly out.
const NEAR_FENCE := 4.0
## ... and was hit this hard (km/h); a home run needs no speed to be one.
const CRUSHED := 152.0
## A catch that was made is worth showing when he was this likely, at most, to make it; one
## that was missed when he was at least this likely.
const DOUBTFUL_CATCH := 0.55
const NEAR_MISS := 0.3
## Balls put in play that must pass after a highlight before a catch or a fly to the wall is
## shown again (a home run is always shown).
const REST := 6

## The contact: play seconds shown slowly from the moment of contact, how slowly, and how long
## (real seconds) the picture stands still on the ball against the bat first.
const CONTACT_SPAN := 0.16
const CONTACT_PACE := 0.09
const CONTACT_FREEZE := 0.22
## The chance: play seconds before and after the ball reaches the fielder, and how slowly.
const CHANCE_BEFORE := 0.42
const CHANCE_AFTER := 0.22
const CHANCE_PACE := 0.22
## Seconds (of the play) over which time slows down and picks up again.
const EASE := 0.07

var kind := Kind.CONTACT
## Seconds after contact that the slow part starts and ends.
var from := 0.0
var until := 0.0
var pace := 1.0
## Real seconds the picture stands still when it starts (the contact).
var freeze := 0.0
## Field coordinates: what is looked at; the fielder's key ("F:CF") for a chance.
var at := Vector3.ZERO
var key := ""


## The ball was crushed: out of the park, or in the air to the foot of the fence.
static func crushed(play: PlayResult, exit_kmh: float) -> bool:
	if play == null or play.foul:
		return false
	if play.result == PaResult.Kind.HOME_RUN:
		return true
	return exit_kmh >= CRUSHED and play.short_of_fence <= NEAR_FENCE


## The play had a chance in real doubt: a hard catch made, or one that was nearly made.
static func in_doubt(play: PlayResult) -> bool:
	if play == null or play.foul or not play.has_hard_chance():
		return false
	return play.hard_odds <= DOUBTFUL_CATCH if play.hard_made else play.hard_odds >= NEAR_MISS


## The highlights of a play, in the order they come (none, one or both). `rested`: balls put
## in play since the last one shown.
static func of(play: PlayResult, exit_kmh: float, rested: int) -> Array[PlayHighlight]:
	var found: Array[PlayHighlight] = []
	if play == null or play.foul:
		return found
	var out_of_the_park := play.result == PaResult.Kind.HOME_RUN
	if crushed(play, exit_kmh) and (out_of_the_park or rested >= REST):
		var h := PlayHighlight.new()
		h.kind = Kind.CONTACT
		h.from = 0.0
		h.until = CONTACT_SPAN
		h.pace = CONTACT_PACE
		h.freeze = CONTACT_FREEZE
		found.append(h)
	if in_doubt(play) and (rested >= REST or not found.is_empty()) and play.hard_time > CONTACT_SPAN + CHANCE_BEFORE + 0.3:
		var h := PlayHighlight.new()
		h.kind = Kind.CHANCE
		h.from = play.hard_time - CHANCE_BEFORE
		h.until = play.hard_time + CHANCE_AFTER
		h.pace = CHANCE_PACE
		h.at = play.hard_at
		h.key = "F:%s" % Position.code(play.hard_fielder)
		found.append(h)
	return found


## How fast the play runs at `t` (1 its own speed): slow inside the span, easing in and out.
func pace_at(t: float) -> float:
	if t < from - EASE or t > until + EASE:
		return 1.0
	var into := smoothstep(from - EASE, from, t) if from > 0.0 else 1.0
	var out_of := smoothstep(until, until + EASE, t)
	return lerpf(1.0, pace, into * (1.0 - out_of))


## The camera's share at `t`: 0 the play's own camera, 1 the close one. It cuts in a little
## before the slow part and stays a little after.
func showing(t: float) -> bool:
	return t >= from - EASE - 0.25 and t <= until + EASE + (0.1 if kind == Kind.CONTACT else 0.45)
