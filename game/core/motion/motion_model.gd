class_name MotionModel
extends RefCounted
## How fast players run, react, field and throw (data/motion.json). Times come from a simple
## acceleration curve: v(t) = v_max (1 - e^(-t / tau)).

var top_speed := Vector2(7.0, 9.3)
var tau := 0.6
## Contact to the batter's first running step: (right-handed, left-handed).
var leave_box := Vector2(0.40, 0.42)
var to_first := Vector2(26.8, 25.8)
var path_factor := 1.045
var rounding := 0.25
var slide_gain := 0.6
var leads := Vector3(3.7, 4.5, 3.0)
var secondary_lead := 1.2
var runner_read := Vector2(0.30, 0.12)
var two_out_jump := 0.25
var steal_jump := Vector2(0.22, 0.04)
var delivery := Vector2(1.50, 1.20)
var reaction := Vector2(0.32, 0.12)
var outfield_reaction := Vector2(0.70, 0.32)
var efficiency := Vector2(0.86, 0.98)
var backward := 0.88
var warning_track := 0.7
var reach_standing := 1.0
var reach_running := 1.1
var reach_diving := 2.0
var reach_high := 2.3
var reach_jump := 2.9
var transfer := Vector2(0.95, 0.55)
var catcher_transfer := Vector2(0.85, 0.55)
var outfield_transfer := 0.35
var throw_infield := Vector2(112.0, 146.0)
var throw_outfield := Vector2(120.0, 156.0)
var throw_catcher := Vector2(110.0, 142.0)
var throw_pitcher := Vector2(105.0, 135.0)
var throw_kept := 0.88
var one_hop_beyond := 55.0
var relay_beyond := 65.0
var pivot := Vector2(0.65, 0.35)
var tag := 0.18
var bang_bang_sd := 0.06
var judgment_sd := 0.25
var routine_slack := 0.5
## Time to spare that lets a fielder set himself: a ground ball fielded in front of him, a
## fly caught with ordinary effort (infield fly rule), the man who calls for a fly ball.
var comfortable_slack := 0.25
var running_catch := Vector2(0.92, 0.45)
var diving_catch := Vector2(0.50, 0.10)
var diving_slack := -0.15
## A ball in the air (the approved proposal 2, after Statcast's Catch Probability): the
## chance is an S-curve of the time to spare — half the catches at air_half_slack s, the
## curve as steep as air_width s — rather than straight lines. Statcast's own inputs are
## the distance he must go and the time he has, harder going back and at the wall; the time
## to spare already holds the first three (his speed, his reaction, slower going back), and
## within wall_reach m of the fence a catch is wall_cost s harder at the wall itself.
var air_half_slack := 0.10
var air_width := 0.10
var wall_reach := 3.0
var wall_cost := 0.25
var fly_drop := 0.010
var ground_bobble := 0.040
var hard_bobble_extra := 0.03
var bad_throw := 0.024
var rushed_throw := 2.0
var aggression := Vector2(0.20, -0.05)
var long_throw_scatter := 0.12
## What the catcher catches cleanly: sideways from the target, lowest and highest point.
var catcher_side := 0.9
var catcher_low := 0.1
var catcher_high := 1.9
## Chance the catcher keeps a pitch outside that in front of him, by his hands rating.
var block := Vector2(0.95, 0.995)
## How long a pitch that gets by the catcher takes to retrieve.
var wild_get_away := 2.2
## The batter's body for hit-by-pitch: a standing cylinder.
var body_radius := 0.22
var body_offset := 0.72
var body_ankle := 0.12
var body_shoulder_share := 0.80
var dodge_chance := 0.25


static func lerp_rating(range_pair: Vector2, rating: float) -> float:
	return lerpf(range_pair.x, range_pair.y, RatingScale.norm(rating))


func top_speed_for(speed_rating: float) -> float:
	return lerp_rating(top_speed, speed_rating)


## Seconds before a fielder's first step. A ball in the air has to be read first, by an
## infielder as much as an outfielder; a ground ball an infielder reacts to at once.
func reaction_for(range_rating: float, kind: Position.Kind = Position.Kind.SS, in_air: bool = false) -> float:
	var read := in_air or Position.OUTFIELD.has(kind)
	return lerp_rating(outfield_reaction if read else reaction, range_rating)


func efficiency_for(range_rating: float) -> float:
	return lerp_rating(efficiency, range_rating)


func transfer_for(kind: Position.Kind, hands_rating: float) -> float:
	if kind == Position.Kind.C:
		return lerp_rating(catcher_transfer, hands_rating)
	var t := lerp_rating(transfer, hands_rating)
	if Position.OUTFIELD.has(kind):
		t += outfield_transfer
	return t


func pivot_for(hands_rating: float) -> float:
	return lerp_rating(pivot, hands_rating)


func runner_read_for(speed_rating: float) -> float:
	return lerp_rating(runner_read, speed_rating)


func steal_jump_for(speed_rating: float) -> float:
	return lerp_rating(steal_jump, speed_rating)


func delivery_for(hold_rating: float) -> float:
	return lerp_rating(delivery, hold_rating)


## Release speed of a throw in m/s.
func throw_speed(kind: Position.Kind, arm_rating: float) -> float:
	var kmh := throw_infield
	if Position.OUTFIELD.has(kind):
		kmh = throw_outfield
	elif kind == Position.Kind.C:
		kmh = throw_catcher
	elif kind == Position.Kind.P:
		kmh = throw_pitcher
	return lerp_rating(kmh, arm_rating) / 3.6


## Seconds a throw of `distance` metres takes. Long throws go on one hop, a little slower.
func throw_time(distance: float, speed_ms: float) -> float:
	var average := speed_ms * throw_kept
	var t := distance / maxf(average, 1.0)
	if distance > one_hop_beyond:
		t *= 1.08
	return t + 0.05


## Distance covered after running t seconds from a standstill.
func distance_after(t: float, v_max: float) -> float:
	if t <= 0.0:
		return 0.0
	return v_max * (t - tau * (1.0 - exp(-t / tau)))


## Seconds to run `distance` metres from a standstill.
func time_to_cover(distance: float, v_max: float) -> float:
	if distance <= 0.0:
		return 0.0
	# Start from the cruising estimate and refine with Newton's method.
	var t := distance / v_max + tau
	for i: int in 8:
		var f := distance_after(t, v_max) - distance
		var df := v_max * (1.0 - exp(-t / tau))
		if absf(df) < 1e-6:
			break
		t -= f / df
		if absf(f) < 1e-4:
			break
	return maxf(t, 0.0)


## Seconds from contact until the batter reaches first base (crossing it at full speed).
func batter_to_first(speed_rating: float, bats_left: bool) -> float:
	var side := 1 if bats_left else 0
	return leave_box[side] + time_to_cover(to_first[side], top_speed_for(speed_rating))


## Seconds from contact until the batter reaches base `bases` (1..4), rounding the ones before.
func batter_to_base(speed_rating: float, bats_left: bool, bases: int) -> float:
	var side := 1 if bats_left else 0
	var d := to_first[side] + Field.BASE_DISTANCE * float(bases - 1) * path_factor
	return leave_box[side] + time_to_cover(d, top_speed_for(speed_rating)) + rounding * float(bases - 1)


## Seconds a runner takes from `start_gap` metres off his base (toward the next one) to reach
## the base `bases` ahead, once he starts running.
func runner_to_base(speed_rating: float, start_gap: float, bases: int) -> float:
	var d := Field.BASE_DISTANCE * float(bases) * (path_factor if bases > 1 else 1.0) - start_gap
	return time_to_cover(maxf(d, 0.0), top_speed_for(speed_rating)) + rounding * float(bases - 1)


## Seconds for a fielder to get within `reach` of `target`, reacting first and running at his
## route efficiency, a little slower when going back.
func fielder_time(from: Vector2, target: Vector2, reach: float, speed_rating: float, range_rating: float, kind: Position.Kind = Position.Kind.SS, in_air: bool = false) -> float:
	var d := maxf(from.distance_to(target) - reach, 0.0)
	var v := top_speed_for(speed_rating)
	# Going back (away from home plate) costs speed.
	if target.length() > from.length() + 2.0:
		v *= backward
	return reaction_for(range_rating, kind, in_air) + time_to_cover(d / efficiency_for(range_rating), v)


## Chance of a catch in the air with this much time to spare (Statcast-shaped S-curve).
func air_catch_chance(slack: float) -> float:
	return 1.0 / (1.0 + exp(-(slack - air_half_slack) / maxf(air_width, 0.01)))


## Chance of holding on to a catch with this much time to spare (negative: he dives).
func catch_chance(slack: float) -> float:
	if slack >= routine_slack:
		return 1.0
	if slack >= 0.0:
		return lerpf(running_catch.y, running_catch.x, slack / routine_slack)
	if slack >= diving_slack:
		return lerpf(diving_catch.x, diving_catch.y, slack / diving_slack)
	return 0.0
