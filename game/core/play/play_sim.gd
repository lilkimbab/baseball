class_name PlaySim
extends RefCounted
## What happens once the ball is in play (docs/02 sections 8.3-8.4).
##
## The batted ball's whole path is known at contact. Every fielder's earliest chance at it is
## worked out from the movement model; the one who gets there first (on a fly, by priority)
## plays it. Runners and fielders are then timed to the bases: the ball beats the runner or it
## does not. Choices (where to throw, whether to take the extra base) are made the way players
## make them, from what they can see, with some misjudgement.

const SAMPLE_DT := 1.0 / 30.0
## A runner rounding a base swings ROUND_OUT m wide of the line, ROUND_FROM m before it.
const ROUND_FROM := 4.5
const ROUND_OUT := 1.2
## Seconds a runner takes to ease up after he is put out (shown after the play is over).
const EASE_UP := 0.8
## A play on a lead runner is worth making when the ball should beat him by this much.
const SURE_MARGIN := 0.15
## Balls fielded farther out than this are outfield plays, even by an infielder.
const INFIELD_PLAY_DISTANCE := 50.0
## Jogging speed round the bases on a home run (m/s).
const JOG := 6.5
## Seconds a runner takes to see that a ball in the air will fall in for a hit.
const HIT_READ := 0.9
## A runner shuffling in his secondary lead at contact is this much ahead of a standing start.
const ROLLING_START := 0.15
## Metres a runner on third has gone toward home on a squeeze when the bunt is down (A).
const SQUEEZE_BREAK := 7.0
## Throws shorter than this are a flip or a feed, quicker to let go of than a full throw.
const SHORT_THROW := 18.0
const SHORT_THROW_RELEASE := 0.6
## Extra margin the batter wants before stretching a hit (seconds).
const BATTER_CAUTION := 0.25
## A batter safe at first runs this far (m) past the bag; a runner who scores walks (m/s)
## toward the dugout on the third-base side (field x, y of where he heads).
const OVERRUN := 4.5
## The height (m) a fly ball is shown caught at by a man waiting under it.
const SHOWN_CATCH_HEIGHT := 1.5
const WALK_OFF := 1.8
const RUN_OFF := Vector2(12.0, 1.0)
## A fielder at full stretch (a dive) is this far (m) from the ball when he gets it, and on
## his feet where it was UP_AGAIN s later. One who comes up short is at least MISSED_BY m off.
const STRETCH := 1.15
const UP_AGAIN := 0.45
const MISSED_BY := 1.6


## A fielder's best chance at the ball.
class Chance:
	extends RefCounted
	var f: PlayFielder
	var t := 0.0
	var at := Vector3.ZERO
	## Seconds to spare when he gets there (negative: he has to dive).
	var slack := 0.0
	var on_run := false
	var dive := false
	## Extra seconds before he can throw (getting up from a dive).
	var extra := 0.0

	static func make(fielder: PlayFielder, time: float, where: Vector3, spare: float) -> Chance:
		var c := Chance.new()
		c.f = fielder
		c.t = time
		c.at = where
		c.slack = spare
		return c


## When and by whom the ball can be held on a base.
class BallAt:
	extends RefCounted
	var time := INF
	var receiver: PlayFielder
	## The fielder carries it there himself instead of throwing.
	var by_self := false
	var distance := 0.0
	var base := 0


var ctx: PlayContext
var m: MotionModel
var rng: Rng
var out := PlayResult.new()

var _ts := PackedFloat64Array()
var _ps := PackedVector3Array()
## When the ball first touches anything, and when it leaves play.
var _land := INF
var _gone := INF
var _launch_deg := 0.0
## Lead runner first, the batter last.
var _runners: Array[PlayRunner] = []
var _batter: PlayRunner
var _outs := 0
var _chain := PackedStringArray()
## Who has the ball, from when and where (for a fielder who then covers a base himself).
var _holder: PlayFielder
var _held_at := 0.0
var _held_where := Vector2.ZERO
var _ball_framed := false
## Someone had a chance to catch the ball in the air (so the runners had to wait and see).
var _catchable := false
## Bases the batter took because of errors (not credited as a hit).
var _batter_error_bases := 0
## The fielder the player moves himself (PlayContext.manual_fielder), null when there is none.
var _own: PlayFielder


static func run(context: PlayContext, random: Rng) -> PlayResult:
	var sim := PlaySim.new()
	sim._setup(context, random)
	sim._play()
	sim._finish()
	return sim.out


static func base_xy(base: int) -> Vector2:
	if base <= 0 or base >= 4:
		return Vector2.ZERO
	var c := Field.base_centre(base)
	return Vector2(c.x, c.y)


func _setup(context: PlayContext, random: Rng) -> void:
	ctx = context
	m = context.motion
	rng = random
	_outs = context.outs
	var path := context.path
	_land = path.events[0].time if not path.events.is_empty() else INF
	var gone := path.first_event(BallEvent.Kind.OUT_OF_PLAY)
	_gone = gone.time if gone != null else INF
	var end := minf(path.duration(), _gone)
	var t := 0.0
	while t < end:
		_ts.append(t)
		_ps.append(path.position_at(t))
		t += SAMPLE_DT
	_ts.append(end)
	_ps.append(path.position_at(end))
	if path.points.size() >= 2:
		var d := path.points[1] - path.points[0]
		_launch_deg = rad_to_deg(atan2(d.z, Vector2(d.x, d.y).length()))

	var on_first := context.runners[0] != null
	var on_second := context.runners[1] != null
	for base: int in [3, 2, 1]:
		var r := context.runners[base - 1]
		if r == null:
			continue
		r.from = base
		r.to = base
		r.forced = base == 1 or (base == 2 and on_first) or (base == 3 and on_first and on_second)
		r.gap = _lead(base) + m.secondary_lead
		# He is already moving in his secondary lead when the ball is hit.
		r.start = MotionModel.lerp_rating(m.runner_read, r.baserunning) - ROLLING_START
		if _outs == 2:
			r.start = -m.two_out_jump
		if (context.running_with_pitch and r.forced) or context.stealing == base:
			r.gap += 6.0
			r.start = 0.0
		elif context.squeeze and base == 3:
			r.gap += SQUEEZE_BREAK
			r.start = 0.0
		_runners.append(r)
	_batter = context.batter
	_batter.from = 0
	_batter.to = 0
	_batter.gap = 0.0
	_batter.start = -0.25 if context.bunt else 0.0
	_runners.append(_batter)
	for kind: Position.Kind in ctx.fielders:
		var f := ctx.fielders[kind]
		out.timeline.add(_fielder_key(f), 0.0, Vector3(f.pos.x, f.pos.y, 0.0))
	# Where the player has taken his own fielder.
	_own = ctx.fielders.get(ctx.manual_fielder)
	if _own != null:
		for at: Vector3 in ctx.manual_track:
			out.timeline.add(_fielder_key(_own), at.x, Vector3(at.y, at.z, 0.0))
		if ctx.manual_time < 0.0:
			out.timeline.bystanders.append(_fielder_key(_own))


func _lead(base: int) -> float:
	return m.leads[clampi(base, 1, 3) - 1]


# --- The ball and who gets to it ---


func _play() -> void:
	if Umpire.is_home_run(ctx.path):
		_home_run()
		return
	## A man who dropped it or came up short: when he is up again and where he is.
	var failed: Dictionary[Position.Kind, Vector3] = {}
	var touch := -1.0
	var dropped_by: PlayFielder = null
	var air := _air_catch()
	_catchable = air != null
	if air != null:
		var fair := Umpire.is_fair(air.at)
		out.infield_fly = _infield_fly(air, fair)
		if not fair and not _wants_foul_catch(air):
			air = null
	_note_flight(air)
	if _own != null and ctx.manual_time >= 0.0 and ctx.manual_time < _land:
		# The player's own fielder caught it in the air.
		_caught(_own_chance())
		return
	if air != null and air.f == _own:
		# It was his to catch and he has not: nobody else was going for it.
		if out.infield_fly:
			_infield_fly_dropped(air)
			return
		air = null
	if air != null:
		if air.slack >= m.routine_slack:
			if not rng.chance(m.fly_drop * _hands_factor(air.f)):
				_caught(air)
				return
			# A routine fly dropped: an error.
			touch = air.t
			dropped_by = air.f
			failed[air.f.kind] = Vector3(air.t + 0.8, air.at.x, air.at.y)
		else:
			var odds := m.air_catch_chance(air.slack - _wall_cost(air.at))
			var held := rng.chance(odds)
			_note_hard(air, odds, held, true)
			if held:
				_caught(air)
				return
			if air.slack >= 0.0:
				touch = air.t
			# At full stretch and not enough: off the end of the glove, or by him.
			_fielder_stretch(air.f, air.t, air.at, false, STRETCH + 0.2 if air.slack >= 0.0 else MISSED_BY)
			var lies := _last_spot(air.f)
			failed[air.f.kind] = Vector3(air.t + (0.6 if air.slack >= 0.0 else 1.0), lies.x, lies.y)
		if out.infield_fly:
			_infield_fly_dropped(air)
			return

	var g := _own_chance() if _own != null and ctx.manual_time >= 0.0 else _ground_play(failed)
	var touch_time := g.t if g != null else -1.0
	if touch >= 0.0 and (touch_time < 0.0 or touch < touch_time):
		touch_time = touch
	match Umpire.judge(ctx.path, touch_time):
		Umpire.Call.FOUL:
			out.foul = true
			_ball_frames(touch_time if touch_time >= 0.0 else ctx.path.duration())
			return
		Umpire.Call.GROUND_RULE_DOUBLE:
			_ground_rule_double()
			return
		Umpire.Call.HOME_RUN:
			_home_run()
			return
	if g == null:
		g = _retrieve_anyway()
	if dropped_by != null:
		out.errors += 1
		_chain.append("E%d" % dropped_by.number())
	if not Position.OUTFIELD.has(g.f.kind) and Trajectory.ground_distance(g.at) < INFIELD_PLAY_DISTANCE:
		_infield_play(g, dropped_by != null)
	else:
		_outfield_play(g, dropped_by != null)


## The player's own fielder with the ball, when and where he got it.
func _own_chance() -> Chance:
	var c := Chance.make(_own, ctx.manual_time, ctx.manual_at, m.routine_slack)
	c.extra = 0.6 if ctx.manual_dive else 0.0
	return c


## The earliest fielder f can let a throw go that he could otherwise make at `release`: the
## player's own fielder waits for the player to say where.
func _ready_at(f: PlayFielder, release: float) -> float:
	return maxf(release, ctx.manual_ready) if f == _own else release


## Notes a chance that could have gone either way (PlayResult.hard_*): the first of the play.
func _note_hard(c: Chance, odds: float, held: bool, in_air: bool) -> void:
	if out.has_hard_chance():
		return
	out.hard_fielder = c.f.kind
	out.hard_time = c.t
	out.hard_at = c.at
	out.hard_odds = odds
	out.hard_made = held
	out.hard_air = in_air


## Notes how far short of the fence a ball in the air came down (or would be caught).
func _note_flight(air: Chance) -> void:
	if ctx.field == null or _land == INF or _launch_deg < 15.0:
		return
	var at := air.at if air != null else ctx.path.position_at(_land)
	var az := rad_to_deg(atan2(at.x, at.y))
	if absf(az) <= 45.0:
		out.short_of_fence = ctx.field.boundary_distance(az) - Vector2(at.x, at.y).length()


## Seconds a fielder needs to get within `reach` of a spot, slower on the warning track.
func _time_to(f: PlayFielder, target: Vector2, reach: float, in_air: bool = false) -> float:
	var t := m.fielder_time(f.pos, target, reach, f.speed, f.reach, f.kind, in_air)
	if _in_track(target):
		t += 0.25
	return t


func _in_track(p: Vector2) -> bool:
	if ctx.field == null or p.y < absf(p.x):
		return false
	var az := rad_to_deg(atan2(p.x, p.y))
	return p.length() > ctx.field.boundary_distance(az) - ctx.field.warning_track_width


## The best catch in the air: the most time to spare over all the points he can reach.
func _air_chance(f: PlayFielder) -> Chance:
	var best: Chance = null
	var react := m.reaction_for(f.reach, f.kind, true)
	var v := m.top_speed_for(f.speed)
	for i: int in _ts.size():
		var t := _ts[i]
		if t >= _land:
			break
		var p := _ps[i]
		if p.z > m.reach_jump or t <= react:
			continue
		var reach := m.reach_running if p.z <= m.reach_high else 0.4
		var target := Vector2(p.x, p.y)
		var lower := react + maxf(f.pos.distance_to(target) - reach, 0.0) / v
		var need := m.diving_slack if best == null else maxf(best.slack, m.diving_slack)
		if t - lower < need:
			continue
		var slack := t - _time_to(f, target, reach, true)
		if slack < 0.0 and p.z > 1.8:
			continue
		if best == null or slack > best.slack:
			best = Chance.make(f, t, p, slack)
	return best


## Who catches the ball in the air, if anyone can: the centre fielder over the corners, the
## outfielders over the infielders, when more than one has it comfortably.
func _air_catch() -> Chance:
	var options: Array[Chance] = []
	for kind: Position.Kind in ctx.fielders:
		var c := _air_chance(ctx.fielders[kind])
		if c != null and c.slack >= m.diving_slack:
			options.append(c)
	if options.is_empty():
		return null
	var best: Chance = null
	for c: Chance in options:
		if c.slack < m.comfortable_slack:
			continue
		if best == null or _priority(c.f.kind) > _priority(best.f.kind) \
				or (_priority(c.f.kind) == _priority(best.f.kind) and c.slack > best.slack):
			best = c
	if best != null:
		return best
	for c: Chance in options:
		if best == null or c.slack > best.slack:
			best = c
	# An outfielder dives only when he has a fair chance: a miss lets the ball roll.
	if best.slack < 0.0 and Position.OUTFIELD.has(best.f.kind) and m.air_catch_chance(best.slack - _wall_cost(best.at)) < 0.25:
		return null
	return best


## How much harder a catch is this close to the fence (seconds off the time to spare): none
## more than wall_reach m off it, wall_cost at the wall.
func _wall_cost(at: Vector3) -> float:
	if ctx.field == null:
		return 0.0
	var az := rad_to_deg(atan2(at.x, at.y))
	if absf(az) > 45.0:
		return 0.0
	var off := ctx.field.boundary_distance(az) - Vector2(at.x, at.y).length()
	if off >= m.wall_reach:
		return 0.0
	return m.wall_cost * (1.0 - maxf(off, 0.0) / m.wall_reach)


static func _priority(kind: Position.Kind) -> int:
	match kind:
		Position.Kind.CF:
			return 6
		Position.Kind.LF, Position.Kind.RF:
			return 5
		Position.Kind.SS, Position.Kind.B2:
			return 4
		Position.Kind.B3, Position.Kind.B1:
			return 3
		Position.Kind.C:
			return 2
	return 1


## The first point a fielder can play the ball after it comes down: charging it if that
## leaves him time to set, otherwise on the run or diving (infielders only).
## `down`: one who has just dropped it or missed it — (time he is up again, where he is): he
## goes from there, and plays the ball where it has rolled to by the time he can reach it.
func _ground_chance(f: PlayFielder, down: Vector3 = Vector3(-1.0, 0.0, 0.0)) -> Chance:
	var outfielder := Position.OUTFIELD.has(f.kind)
	var recovering := down.x >= 0.0
	var may_dive := not outfielder and f.kind != Position.Kind.C and not recovering
	var react := m.reaction_for(f.reach, f.kind) if not recovering else down.x
	var v := m.top_speed_for(f.speed)
	var first: Chance = null
	for i: int in _ts.size():
		var t := _ts[i]
		if t < _land or t <= react:
			continue
		if first != null and t > first.t + 0.6:
			break
		var p := _ps[i]
		if p.z > m.reach_high:
			continue
		var target := Vector2(p.x, p.y)
		var start := Vector2(down.y, down.z) if recovering else f.pos
		var lower := react + maxf(start.distance_to(target) - m.reach_running, 0.0) / v
		var want := m.comfortable_slack if first != null else (m.diving_slack if may_dive else 0.0)
		if t - lower < want:
			continue
		var needs := _time_to(f, target, m.reach_running) if not recovering else down.x + m.fielder_time(start, target, m.reach_running, f.speed, f.reach, f.kind)
		var slack := t - needs
		if first == null:
			if slack >= 0.0 or (may_dive and slack >= m.diving_slack and p.z < 1.0):
				first = Chance.make(f, t, p, slack)
				if slack >= m.comfortable_slack:
					return first
			continue
		if slack >= m.comfortable_slack:
			# Waiting to set up is worth a moment, not more: an outfielder cuts the ball off on
			# the run rather than let it roll toward the wall.
			if t - first.t <= (0.6 if outfielder else 0.35):
				return Chance.make(f, t, p, slack)
			break
	if first == null and outfielder and _gone == INF:
		# The ball has stopped somewhere: he walks over and picks it up.
		var end := _ps[_ps.size() - 1]
		var when := maxf(_ts[_ts.size() - 1], _time_to(f, Vector2(end.x, end.y), m.reach_standing))
		first = Chance.make(f, when, end, 0.0)
		return first
	if first != null:
		first.on_run = first.slack < m.comfortable_slack
		first.dive = first.slack < 0.0
	return first


## The fielder who plays the ball on the ground. A diving try that misses lets it go on to the
## next man.
func _ground_play(failed: Dictionary[Position.Kind, Vector3]) -> Chance:
	var plans: Array[Chance] = []
	for kind: Position.Kind in ctx.fielders:
		# The player's own fielder has not got it (or the play would not have come here).
		if ctx.fielders[kind] == _own:
			continue
		# One who has just dropped it goes after it from where he is, a moment later (adding the
		# moment to his time while keeping the spot had the ball fly back to him from where it
		# had rolled: tools/play_audit.gd "ball jump").
		var c := _ground_chance(ctx.fielders[kind], failed.get(kind, Vector3(-1.0, 0.0, 0.0)))
		if c == null:
			continue
		plans.append(c)
	plans.sort_custom(func(a: Chance, b: Chance) -> bool: return a.t < b.t)
	for c: Chance in plans:
		if c.dive:
			var odds := m.catch_chance(c.slack)
			var held := rng.chance(odds)
			_note_hard(c, odds, held, false)
			if held:
				c.extra = 0.6
				return c
			_fielder_stretch(c.f, c.t, c.at, false, MISSED_BY)
			continue
		return c
	return null


## Nobody had a plan (the ball died somewhere odd): the nearest fielder walks to it.
func _retrieve_anyway() -> Chance:
	var end := _ps[_ps.size() - 1]
	var best: Chance = null
	for kind: Position.Kind in ctx.fielders:
		var f := ctx.fielders[kind]
		if f == _own:
			continue
		var when := maxf(_ts[_ts.size() - 1], _time_to(f, Vector2(end.x, end.y), m.reach_standing))
		if best == null or when < best.t:
			best = Chance.make(f, when, end, 0.0)
	return best


func _hands_factor(f: PlayFielder) -> float:
	return exp(-(f.hands - 50.0) / 40.0)


func _accuracy_factor(f: PlayFielder) -> float:
	return exp(-(f.accuracy - 50.0) / 40.0)


## The infield fly rule: fewer than two out, first and second occupied, a fair fly (not a
## line drive or a bunt) an infielder catches with ordinary effort.
func _infield_fly(c: Chance, fair: bool) -> bool:
	if not fair or ctx.bunt or _outs >= 2 or ctx.runners[0] == null or ctx.runners[1] == null:
		return false
	if Position.OUTFIELD.has(c.f.kind) or _launch_deg < 25.0:
		return false
	return c.slack >= m.comfortable_slack


## A deep foul fly with the tying or winning run on third and fewer than two out is better
## left to drop than caught for a sacrifice fly.
func _wants_foul_catch(c: Chance) -> bool:
	if ctx.runners[2] != null and _outs < 2 and ctx.run_matters:
		return Trajectory.ground_distance(c.at) < 45.0
	return true


## Where a fielder's track ends (where he is after his last move).
func _last_spot(f: PlayFielder) -> Vector2:
	var track: PackedVector4Array = out.timeline.tracks.get(_fielder_key(f), PackedVector4Array())
	if track.is_empty():
		return f.pos
	var last := track[track.size() - 1]
	return Vector2(last.y, last.z)


# --- Outs in the air ---


func _caught(c: Chance) -> void:
	var f := c.f
	# Shown taken at chest height by a man waiting under it; the play goes on from c.t.
	var shown := _shown_catch(c)
	_ball_frames(shown.t)
	_fielded(f, shown.t)
	if c.slack < 0.0:
		_fielder_stretch(f, c.t, c.at, true)
	else:
		_fielder_run(f, shown.t, shown.at)
	_hold(f, c.t, Vector2(c.at.x, c.at.y))
	_batter.put_out(1, RunnerMove.OutKind.FLY, c.t)
	_outs += 1
	out.direction = f.number()
	_chain.append(str(f.number()))
	out.result = _air_out_kind(f)
	if _outs >= 3:
		return
	# With the batter out nobody is forced: runners tag up or get back.
	for r: PlayRunner in _runners:
		r.forced = false
	var at := Vector2(c.at.x, c.at.y)
	var release := _ready_at(f, c.t + c.extra + m.transfer_for(f.kind, f.hands))
	var quick := _launch_deg < 20.0 and c.t < 1.6
	var limit := 5
	var tagging: Array[PlayRunner] = []
	for r: PlayRunner in _runners:
		if r == _batter:
			continue
		if quick:
			# A line drive: he froze off his base and has to get back before the ball does.
			var back := c.t + 0.2 + m.time_to_cover(_lead(r.from) + m.secondary_lead, m.top_speed_for(r.speed))
			var b := _ball_at(f, at, c.t, _ready_at(f, c.t + c.extra + m.transfer_for(f.kind, f.hands) * 0.8), r.from)
			if b.time + rng.next_normal() * m.bang_bang_sd < back:
				_throw_frames(f, at, c.t, b)
				r.put_out(r.from, RunnerMove.OutKind.FORCE, b.time)
				_outs += 1
				if not b.by_self:
					_chain.append(str(b.receiver.number()))
				if _outs >= 3:
					return
			limit = r.from
			continue
		var next := r.from + 1
		if next >= limit and next < 4:
			limit = r.from
			continue
		# Tag up: back to the base for the catch, then go if the throw will not beat him.
		r.gap = 0.0
		r.start = c.t + 0.1
		var a := _ball_at(f, at, c.t, release, next).time + m.tag
		var guess := _arrive(r, next) + _aggression() + rng.next_normal() * _judgment(r)
		if guess < a:
			r.to = next
			tagging.append(r)
		limit = r.to
	if not tagging.is_empty():
		var lead := tagging[0]
		var b := _ball_at(f, at, c.t, release, lead.to)
		if _arrive(lead, lead.to) - (b.time + m.tag) > -0.3:
			_play_on(lead, f, at, c.t, release)
	for r: PlayRunner in tagging:
		if not r.is_out():
			r.time = _arrive(r, r.to)
			if r.to == 4 and ctx.outs < 2 and out.result == PaResult.Kind.FLY_OUT:
				out.result = PaResult.Kind.SAC_FLY


func _air_out_kind(f: PlayFielder) -> PaResult.Kind:
	if _launch_deg < 20.0:
		return PaResult.Kind.LINE_OUT
	if Position.OUTFIELD.has(f.kind):
		return PaResult.Kind.FLY_OUT
	return PaResult.Kind.POP_OUT


## An infield fly that was not caught: the batter is out all the same and the runners stay.
func _infield_fly_dropped(c: Chance) -> void:
	_ball_frames(c.t + 0.5)
	# (The player's own fielder is wherever the player has taken him.)
	if c.f != _own:
		_fielder_run(c.f, c.t, c.at)
	_batter.put_out(1, RunnerMove.OutKind.FLY, c.t)
	_outs += 1
	out.direction = c.f.number()
	_chain.append(str(c.f.number()))
	out.result = PaResult.Kind.POP_OUT


# --- Plays on the ground in the infield ---


func _infield_play(g: Chance, after_drop: bool) -> void:
	var f := g.f
	var at := Vector2(g.at.x, g.at.y)
	var held := g.t + g.extra
	_ball_frames(g.t)
	_fielded(f, g.t)
	if g.dive:
		_fielder_stretch(f, g.t, g.at, true)
	else:
		_fielder_run(f, g.t, g.at)
	_hold(f, held, at)
	out.direction = f.number()
	if not after_drop:
		_chain.append(str(f.number()))
	var clean := _ready_at(f, held + m.transfer_for(f.kind, f.hands) + (0.15 if g.on_run else 0.0))
	var release := clean
	var bobbled := not after_drop and rng.chance(_bobble_chance(g))
	if bobbled:
		release += 0.9
	_ground_ball_running(f, at, held, release)
	_batter.to = 1

	var target := _choose_target(f, at, held, release)
	var batter_would_be_out := _margin(_batter, f, at, held, clean) > 0.0
	if target == null:
		_settle_runners()
		if bobbled and batter_would_be_out:
			_error(f, false)
			out.result = PaResult.Kind.REACHED_ON_ERROR
		else:
			out.result = PaResult.Kind.REACHED_ON_ERROR if after_drop else PaResult.Kind.SINGLE
		return
	var first_out := _play_on(target, f, at, held, release)
	# Turn two: the man taking the force throws on to first.
	if first_out and target != _batter and _outs < 3 and _batter.to == 1 and not _batter.is_out():
		var b := _ball_at(f, at, held, release, target.out_at)
		var pivot := b.receiver
		var turn := b.time + m.pivot_for(pivot.hands) * (0.8 if b.by_self else 1.0)
		_play_on(_batter, pivot, base_xy(target.out_at), b.time, turn)
	_settle_runners()

	var made := _outs - ctx.outs
	if made >= 3:
		out.result = PaResult.Kind.TRIPLE_PLAY
	elif made == 2:
		out.result = PaResult.Kind.DOUBLE_PLAY
	elif _batter.is_out():
		var advanced := false
		for r: PlayRunner in _runners:
			advanced = advanced or (r != _batter and not r.is_out() and r.to > r.from)
		out.result = PaResult.Kind.SAC_BUNT if ctx.bunt and advanced and ctx.outs < 2 else PaResult.Kind.GROUND_OUT
	elif after_drop:
		out.result = PaResult.Kind.FIELDERS_CHOICE if made > 0 else PaResult.Kind.REACHED_ON_ERROR
	elif out.errors > 0 and target == _batter:
		out.result = PaResult.Kind.REACHED_ON_ERROR
	elif bobbled and target == _batter and batter_would_be_out:
		_error(f, false)
		out.result = PaResult.Kind.REACHED_ON_ERROR
	elif target != _batter:
		out.result = PaResult.Kind.FIELDERS_CHOICE
	else:
		out.result = PaResult.Kind.SINGLE


func _bobble_chance(g: Chance) -> float:
	var p := m.ground_bobble * _hands_factor(g.f) * (1.5 if g.on_run else 1.0)
	var i := mini(int(g.t / SAMPLE_DT), _ts.size() - 2)
	if i >= 0 and i + 1 < _ps.size():
		var speed := (_ps[i + 1] - _ps[i]).length() / maxf(_ts[i + 1] - _ts[i], 1e-3)
		if speed > 30.0:
			p += m.hard_bobble_extra
	return p


## Who runs on a ground ball. Forced runners must; with two out everyone goes. A runner on
## second goes when the ball is hit to the right side, one on third when the infield is back
## (the defence gives up the run for the out) or when he can beat the throw home.
func _ground_ball_running(f: PlayFielder, at: Vector2, held: float, release: float) -> void:
	var limit := 5
	for r: PlayRunner in _runners:
		if r == _batter:
			continue
		var go := r.forced or _outs == 2
		if not go and r.from == 3:
			r.to = 4
			var margin := _margin(r, f, at, held, release)
			r.to = 3
			go = not ctx.infield_in or margin < -_aggression()
		elif not go and r.from == 2:
			go = at.x > 2.0
		var next := r.from + 1
		if go and (next < limit or next == 4):
			r.to = next
		limit = r.to


## The runner to play on: the run at the plate when it matters, else the lead forced runner
## if he is sure to be out, else the batter at first. With two out, the surest out.
func _choose_target(f: PlayFielder, at: Vector2, held: float, release: float) -> PlayRunner:
	if ctx.throw_to > 0:
		return _going_to(ctx.throw_to)
	if _outs == 2:
		var best: PlayRunner = null
		var best_margin := -INF
		for r: PlayRunner in _runners:
			if r.to <= r.from:
				continue
			var margin := _margin(r, f, at, held, release)
			if margin > best_margin:
				best = r
				best_margin = margin
		return best if best_margin > -0.3 else null
	for r: PlayRunner in _runners:
		if r == _batter or r.to <= r.from:
			continue
		var margin := _margin(r, f, at, held, release)
		if r.to == 4 and not r.forced:
			if (ctx.run_matters or ctx.infield_in) and margin >= 0.2:
				return r
			continue
		if r.forced and margin >= SURE_MARGIN:
			return r
	if _margin(_batter, f, at, held, release) > -0.3:
		return _batter
	return null


## The runner heading for `base` (the batter for first), or null when nobody is: the player
## threw where there was no play.
func _going_to(base: int) -> PlayRunner:
	for r: PlayRunner in _runners:
		if not r.is_out() and r.to == base and r.to > r.from:
			return r
	return null


## How much sooner the ball is on runner r's base than he is (positive: he is out).
func _margin(r: PlayRunner, f: PlayFielder, at: Vector2, held: float, release: float) -> float:
	var b := _ball_at(f, at, held, release, r.to)
	return _arrive(r, r.to) - (b.time + (0.0 if _is_force(r, r.to) else m.tag))


## A force play: the next base for a runner the batter pushes on, or first for the batter.
func _is_force(r: PlayRunner, base: int) -> bool:
	return (r.forced and base == r.from + 1) or (r == _batter and base == 1)


## Plays on runner r at the base he is running to. True if he is out.
func _play_on(r: PlayRunner, thrower: PlayFielder, from: Vector2, held: float, release: float) -> bool:
	var base := r.to
	var b := _ball_at(thrower, from, held, release, base)
	# A force is only at the next base: a forced runner who goes on past it is tagged.
	var forced := _is_force(r, base)
	var need := b.time + (0.0 if forced else m.tag)
	if not b.by_self and b.distance > 40.0:
		# A long throw is sometimes off line or on a bad hop.
		need += absf(rng.next_normal()) * m.long_throw_scatter * (b.distance - 40.0) / 40.0
	var runner_at := _arrive(r, base)
	var margin := runner_at - need
	_throw_frames(thrower, from, release, b)
	if not b.by_self:
		var wild := m.bad_throw * _accuracy_factor(thrower) * (m.rushed_throw if absf(margin) < 0.3 else 1.0) * ctx.throw_wild
		if rng.chance(wild):
			r.time = runner_at
			_error(thrower, true)
			return false
		_chain.append(str(b.receiver.number()))
	_hold(b.receiver, b.time, base_xy(base))
	var judged := margin + rng.next_normal() * m.bang_bang_sd
	# The call comes as the play is made: a force out when the ball is held on the bag, a tag
	# or a safe call when the runner gets there.
	var call_at := need if judged > 0.0 and forced else maxf(need, runner_at)
	out.calls.append(PlayCall.make(call_at, base, judged > 0.0, absf(judged), not forced))
	if judged > 0.0:
		r.put_out(base, RunnerMove.OutKind.FORCE if forced else RunnerMove.OutKind.TAG, need)
		_outs += 1
		# The force is off for the runners behind him once the batter is out.
		if r == _batter:
			for other: PlayRunner in _runners:
				other.forced = false
		return true
	r.time = runner_at
	return false


## An error: a wild throw lets every runner take one more base; a fumble just costs time.
func _error(f: PlayFielder, wild_throw: bool) -> void:
	out.errors += 1
	_chain.append("E%d" % f.number())
	if not wild_throw:
		return
	var limit := 5
	for r: PlayRunner in _runners:
		if r.is_out():
			continue
		var next := mini(r.to + 1, 4)
		if r.to < 4 and (next < limit or next == 4):
			r.to = next
			r.on_error = true
			r.time = _arrive(r, r.to) + 0.5
			if r == _batter:
				_batter_error_bases += 1
		limit = r.to


## Runners nobody played on reach the bases they were going to.
func _settle_runners() -> void:
	for r: PlayRunner in _runners:
		if not r.is_out() and r.to > r.from and r.time <= 0.0:
			r.time = _arrive(r, r.to)


# --- Balls through to the outfield ---


func _outfield_play(g: Chance, after_drop: bool) -> void:
	var f := g.f
	var at := Vector2(g.at.x, g.at.y)
	var held := g.t + g.extra + (0.15 if g.on_run else 0.0)
	_ball_frames(g.t)
	_fielded(f, g.t)
	_fielder_run(f, g.t, g.at)
	out.direction = f.number()
	if not after_drop:
		_chain.append(str(f.number()))
	var release := _ready_at(f, held + m.transfer_for(f.kind, f.hands))
	var fumbled := not after_drop and rng.chance(m.ground_bobble * 0.5 * _hands_factor(f))
	if fumbled:
		release += 1.0
	_hold(f, release, at)
	_hit_starts()

	# Each runner, lead first, takes as many bases as he thinks the throw will allow.
	var limit := 5
	for r: PlayRunner in _runners:
		var best := r.from + 1
		for b: int in range(r.from + 2, 5):
			if b >= limit and b < 4:
				break
			var throw_there := _ball_at(f, at, held, release, b).time + m.tag
			# The batter stretching a hit is more careful than a runner going for home.
			var caution := BATTER_CAUTION if r == _batter else 0.0
			var guess := _arrive(r, b) + _aggression() + caution + rng.next_normal() * _judgment(r)
			if guess < throw_there:
				best = b
			else:
				break
		if best >= limit and best < 4:
			best = limit - 1
		r.to = best
		limit = r.to

	# The throw goes where it can get someone; otherwise to the cut-off man.
	var target: PlayRunner = null
	var target_margin := -INF
	for r: PlayRunner in _runners:
		if r == _batter and r.to == 1:
			continue
		var margin := _arrive(r, r.to) - (_ball_at(f, at, held, release, r.to).time + m.tag)
		if margin > target_margin:
			target = r
			target_margin = margin
	var chosen := ctx.throw_to > 0
	if chosen:
		target = _going_to(ctx.throw_to)
	if target != null and (chosen or target_margin > -0.25):
		var thrown_at := _ball_at(f, at, held, release, target.to).time
		_play_on(target, f, at, held, release)
		# The runners behind take another base on the throw.
		var behind := false
		var ahead_base := 5
		for r: PlayRunner in _runners:
			if r == target:
				behind = true
				ahead_base = r.to if not r.is_out() else r.out_at
				continue
			if behind and not r.is_out() and r.to < 3:
				var next := r.to + 1
				if next < ahead_base and _arrive(r, next) < thrown_at + 0.5:
					r.to = next
			if behind:
				ahead_base = r.to
	_settle_runners()
	if fumbled:
		_error(f, true)

	if after_drop:
		# The batter reached on the error; the inning is rebuilt with him out (phantom out).
		_batter.on_error = true
		out.result = PaResult.Kind.FIELDERS_CHOICE if _outs > ctx.outs else PaResult.Kind.REACHED_ON_ERROR
		return
	var reached := _batter.to - _batter_error_bases if not _batter.is_out() else _batter.out_at - 1
	out.result = PaResult.hit_of_bases(clampi(reached, 1, 4))


## On a fly that drops with fewer than two out, runners waited part way to see whether it
## was caught. One nobody could reach they read as a hit and run on soon after contact.
func _hit_starts() -> void:
	if _outs == 2 or _launch_deg < 15.0 or _land < 1.0:
		return
	if not _catchable:
		for r: PlayRunner in _runners:
			if r != _batter:
				r.start = maxf(r.start, minf(_land, HIT_READ))
		return
	for r: PlayRunner in _runners:
		if r == _batter:
			continue
		match r.from:
			1:
				r.gap = _lead(1) + m.secondary_lead + 8.0
			2:
				r.gap = _lead(2) + m.secondary_lead + 5.0
			3:
				r.gap = 0.0
		r.start = maxf(r.start, _land + 0.15)


func _aggression() -> float:
	return (m.aggression.y if _outs == 2 else m.aggression.x) + ctx.running_shift


func _judgment(r: PlayRunner) -> float:
	return m.judgment_sd * lerpf(1.4, 0.6, RatingScale.norm(r.baserunning))


# --- Balls that end the play at once ---


func _home_run() -> void:
	out.result = PaResult.Kind.HOME_RUN
	out.direction = _direction_of(ctx.path.end_point())
	_ball_frames(ctx.path.duration())
	for r: PlayRunner in _runners:
		r.to = 4
		var bases := 4 - r.from
		r.time = 1.0 + Field.BASE_DISTANCE * bases / JOG
		r.start = 1.0


func _ground_rule_double() -> void:
	out.result = PaResult.Kind.DOUBLE
	out.direction = _direction_of(ctx.path.end_point())
	_ball_frames(minf(_gone, ctx.path.duration()))
	for r: PlayRunner in _runners:
		r.to = mini(r.from + 2, 4)
		r.time = _arrive(r, r.to)


static func _direction_of(p: Vector3) -> int:
	var az := rad_to_deg(atan2(p.x, p.y))
	if az < -15.0:
		return 7
	if az > 15.0:
		return 9
	return 8


# --- Timing ---


## Seconds after contact until runner r reaches `base`.
func _arrive(r: PlayRunner, base: int) -> float:
	if base <= r.from:
		return r.start
	if r.from == 0:
		return r.start + m.batter_to_base(r.speed, r.bats_left, base)
	var slide := m.slide_gain if base > 1 else 0.0
	return r.start + m.runner_to_base(r.speed, r.gap + slide, base - r.from)


## When the ball can be held on `base`: thrown to whoever covers it, or carried there by the
## fielder himself when that is quicker.
func _ball_at(thrower: PlayFielder, from: Vector2, held: float, release: float, base: int) -> BallAt:
	var target := base_xy(base)
	var d := from.distance_to(target)
	var b := BallAt.new()
	b.distance = d
	b.base = base
	var carry := INF
	if d < 12.0:
		carry = held + m.time_to_cover(maxf(d - 0.5, 0.0), m.top_speed_for(thrower.speed))
	var receiver := _coverer(base, thrower)
	var let_go := release
	if d < SHORT_THROW:
		let_go = held + (release - held) * SHORT_THROW_RELEASE
	var throw := maxf(let_go + _throw_time(thrower, d), _cover_time(receiver, base))
	if carry <= throw or receiver == thrower:
		b.time = minf(carry, held + m.time_to_cover(maxf(d - 0.5, 0.0), m.top_speed_for(thrower.speed)))
		b.receiver = thrower
		b.by_self = true
	else:
		b.time = throw
		b.receiver = receiver
	return b


func _throw_time(thrower: PlayFielder, d: float) -> float:
	var t := m.throw_time(d, m.throw_speed(thrower.kind, thrower.arm) * ctx.throw_power)
	if d > m.relay_beyond:
		# Through the cut-off man.
		t += 0.2
	return t


## Who covers a base when `thrower` has the ball.
func _coverer(base: int, thrower: PlayFielder) -> PlayFielder:
	var k := thrower.kind
	var pick := Position.Kind.C
	match base:
		1:
			pick = Position.Kind.B1
			if k == Position.Kind.B1:
				pick = Position.Kind.P
			elif ctx.bunt and k != Position.Kind.B2:
				pick = Position.Kind.B2
		2:
			var right_side := k == Position.Kind.B2 or k == Position.Kind.B1 or k == Position.Kind.P \
				or k == Position.Kind.RF or k == Position.Kind.C
			pick = Position.Kind.SS if right_side else Position.Kind.B2
		3:
			pick = Position.Kind.SS if k == Position.Kind.B3 else Position.Kind.B3
		_:
			pick = Position.Kind.P if k == Position.Kind.C else Position.Kind.C
	return ctx.fielders[pick]


## Seconds after contact until fielder c is on `base` ready for a throw.
func _cover_time(c: PlayFielder, base: int) -> float:
	var target := base_xy(base)
	if c == _holder:
		return _held_at + m.time_to_cover(maxf(_held_where.distance_to(target) - 0.3, 0.0), m.top_speed_for(c.speed))
	return m.reaction_for(c.reach, c.kind) + m.time_to_cover(maxf(c.pos.distance_to(target) - 0.3, 0.0), m.top_speed_for(c.speed))


func _hold(f: PlayFielder, at_time: float, where: Vector2) -> void:
	_holder = f
	_held_at = at_time
	_held_where = where


# --- Key frames for the scene ---


static func _fielder_key(f: PlayFielder) -> String:
	return "F:%s" % Position.code(f.kind)


## Fielder f is at `where` at `at_time`. His first move starts once he has read the ball. A
## later one (the first baseman who fielded the ball and then takes a throw on the bag) goes on
## from where the last left him, no sooner than he can run it: he was shown jumping to the bag
## before he had let go of his throw. The player's own fielder goes on from where the player
## took him. A move that comes later than the play would end does not make it longer.
func _fielder_run(f: PlayFielder, at_time: float, where: Vector3) -> void:
	var key := _fielder_key(f)
	var track := out.timeline.tracks[key]
	var to := Vector3(where.x, where.y, 0.0)
	if track.size() == 1 and f != _own:
		out.timeline.add(key, minf(m.reaction_for(f.reach, f.kind), at_time), Vector3(f.pos.x, f.pos.y, 0.0))
		out.timeline.add(key, at_time, to)
		return
	var last := track[track.size() - 1]
	var d := Vector2(where.x - last.y, where.y - last.z).length()
	if d < 0.05:
		return
	var arrive := maxf(at_time, last.x + d / m.top_speed_for(f.speed))
	if arrive > at_time + 0.01:
		var length := out.timeline.duration
		out.timeline.add(key, arrive, to)
		out.timeline.duration = length
	else:
		out.timeline.add(key, at_time, to)


## Fielder f stays where he is until `at_time` (a thrower until he lets go).
func _fielder_waits(f: PlayFielder, at_time: float) -> void:
	var key := _fielder_key(f)
	var track := out.timeline.tracks[key]
	var last := track[track.size() - 1]
	if last.x < at_time:
		out.timeline.add(key, at_time, Vector3(last.y, last.z, 0.0))


## Where a catch in the air is shown made: a man with time to wait takes the ball as it comes
## down past his chest, not at the last moment before it lands (the chance with the most time
## to spare is the lowest point of the ball's path he can reach, a few centimetres off the
## grass). The result of the play is worked out from the chance itself.
func _shown_catch(c: Chance) -> Chance:
	if c.slack <= 0.05 or c.at.z >= SHOWN_CATCH_HEIGHT:
		return c
	var i := clampi(roundi(c.t / SAMPLE_DT), 0, _ts.size() - 1)
	var earliest := c.t - c.slack + 0.05
	# Back along the ball's path while it is coming down past his chest and he could already
	# be there (a line drive stays low for metres: without the second test the catch was
	# shown ten metres short of him, and he slid there at thirty metres a second).
	while i > 0 and _ts[i - 1] >= earliest and _ps[i - 1].z <= SHOWN_CATCH_HEIGHT and _ps[i - 1].z >= _ps[i].z \
			and _time_to(c.f, Vector2(_ps[i - 1].x, _ps[i - 1].y), m.reach_running, true) <= _ts[i - 1] - 0.05:
		i -= 1
	return Chance.make(c.f, _ts[i], _ps[i], c.slack - (c.t - _ts[i]))


## Notes who first had the ball and when, for the scene (PlayMoves reads the catch from it).
func _fielded(f: PlayFielder, at_time: float) -> void:
	if out.timeline.fielded_key == "":
		out.timeline.fielded_key = _fielder_key(f)
		out.timeline.fielded_time = at_time


## A fielder at full stretch for the ball at `at`: he gets no nearer than a dive's length, and
## is up where it was a moment later if he has it. If he has not, the try is noted (the scene
## shows the dive) and he is left where he fell.
func _fielder_stretch(f: PlayFielder, at_time: float, at: Vector3, got: bool, short: float = STRETCH) -> void:
	var key := _fielder_key(f)
	var track := out.timeline.tracks[key]
	var from := Vector2(track[track.size() - 1].y, track[track.size() - 1].z)
	var to := Vector2(at.x, at.y)
	var where := to - (to - from).normalized() * minf(short, from.distance_to(to))
	_fielder_run(f, at_time, Vector3(where.x, where.y, 0.0))
	if got:
		var now := out.timeline.tracks[key]
		var last := now[now.size() - 1].x
		out.timeline.add(key, maxf(at_time + UP_AGAIN, last + 0.05), Vector3(at.x, at.y, 0.0))
	else:
		out.timeline.add_miss(key, at_time, at)


## The batted ball's own path, up to when it is caught, fielded or dead.
func _ball_frames(until: float) -> void:
	if _ball_framed:
		return
	_ball_framed = true
	for i: int in _ts.size():
		if _ts[i] > until:
			break
		out.timeline.add("ball", _ts[i], _ps[i])
	out.timeline.add("ball", until, ctx.path.position_at(until))


func _throw_frames(thrower: PlayFielder, from: Vector2, release: float, b: BallAt) -> void:
	var start := Vector3(from.x, from.y, 1.5)
	var target := base_xy(b.base)
	if b.by_self:
		out.timeline.add("ball", b.time, Vector3(target.x, target.y, 1.0))
		_fielder_run(thrower, b.time, Vector3(target.x, target.y, 0.0))
		return
	# Shown leaving his hand as long before it gets there as a throw that far takes: a short
	# one is let go sooner than a full throw (_ball_at), and it was drawn from the full throw's
	# release, crossing ten metres in a few hundredths of a second.
	var shown_release := minf(maxf(b.time - _throw_time(thrower, b.distance), 0.0), b.time - 0.05)
	_fielder_waits(thrower, shown_release)
	# Taken in front of the bag, in the glove held out toward the throw (the first baseman's
	# stretch reaches furthest): the receiver stands on the bag, the ball ends where his glove
	# is. (Thrown to the bag itself, it flew into his chest while his glove was out in front.)
	var toward := (from - target).normalized() if from.distance_to(target) > 0.1 else Vector2.ZERO
	var reach := STRETCH_REACH if b.base == 1 else CATCH_IN_FRONT
	var catch_at := Vector3(target.x + toward.x * reach, target.y + toward.y * reach, 1.05 if b.base == 1 else 1.2)
	out.timeline.add("ball", shown_release, start)
	out.timeline.add("ball", b.time, catch_at)
	out.timeline.add_throw(shown_release, start, b.time, catch_at)
	_fielder_run(b.receiver, minf(_cover_time(b.receiver, b.base), b.time), Vector3(target.x, target.y, 0.0))


## How far in front of the bag (m, toward the thrower) a throw is caught: at first base the
## first baseman's stretch, elsewhere a glove held out in front of the chest.
const STRETCH_REACH := 1.2
const CATCH_IN_FRONT := 0.45


func _runner_frames(r: PlayRunner) -> void:
	var key := "R:%s" % r.id
	var from := base_xy(r.from)
	var toward := (base_xy(r.from + 1) - from).normalized() if r.from < 4 else Vector2.ZERO
	var spot := from + toward * r.gap
	out.timeline.add(key, 0.0, Vector3(spot.x, spot.y, 0.0))
	out.timeline.add(key, maxf(r.start, 0.0), Vector3(spot.x, spot.y, 0.0))
	var last := r.out_at if r.is_out() else r.to
	var prev_time := maxf(r.start, 0.0)
	var prev := spot
	for base: int in range(r.from + 1, last + 1):
		var p := base_xy(base)
		var when := _arrive(r, base)
		if r.is_out() and base == last:
			_out_frames(key, prev, prev_time, p, when, r.time)
			return
		if base < last and base < 4:
			# Rounding the bag: he swings out a little before it, toward foul ground or the
			# outfield, to take it at an angle.
			var into := (p - prev).normalized()
			var outward := (p - Vector2(0.0, Field.BASE_DISTANCE * sqrt(0.5))).normalized()
			var share := ROUND_FROM / maxf(prev.distance_to(p), ROUND_FROM)
			var swing := p - into * ROUND_FROM + outward * ROUND_OUT
			out.timeline.add(key, lerpf(prev_time, when, 1.0 - share), Vector3(swing.x, swing.y, 0.0))
		out.timeline.add(key, when, Vector3(p.x, p.y, 0.0))
		prev = p
		prev_time = when
	_after_the_bag(r, key, last)


## What a runner does once he is safe where he stopped, shown after the play without making it
## longer: the batter safe at first runs through the bag and comes back to it; one who scored
## walks off toward the dugout. (They stood on the bag inside the first baseman, and on the
## plate inside each other.)
func _after_the_bag(r: PlayRunner, key: String, last: int) -> void:
	if r.is_out() or last < 1:
		return
	var length := out.timeline.duration
	var when := _arrive(r, last)
	if last == 4:
		# Each to his own spot (the batter and the runners would stand inside each other).
		var off := Vector2(-RUN_OFF.x - float(r.from) * 1.6, RUN_OFF.y + float(r.from) * 1.1)
		out.timeline.add(key, when + 0.7, Vector3(-1.2, -2.0, 0.0))
		out.timeline.add(key, when + 0.7 + off.distance_to(Vector2(-1.2, -2.0)) / WALK_OFF, Vector3(off.x, off.y, 0.0))
	elif last == 1 and r.from == 0:
		var line := base_xy(1).normalized()
		var past := base_xy(1) + line * OVERRUN
		out.timeline.add(key, when + 0.6, Vector3(past.x, past.y, 0.0))
		var back := base_xy(1) + line * 0.6 + Vector2(line.y, -line.x) * 0.8
		out.timeline.add(key, when + 0.6 + 1.2 + OVERRUN / WALK_OFF, Vector3(back.x, back.y, 0.0))
	out.timeline.duration = length


## A runner put out on his way from `from` (left at `left`) to the bag at `bag` (which he would
## reach at `arrive`): where he is at the out, at his own pace, no nearer than a stride short;
## then he eases up over the next moment, which the play's length does not wait for.
func _out_frames(key: String, from: Vector2, left: float, bag: Vector2, arrive: float, out_time: float) -> void:
	var path := bag - from
	var stride_short := maxf(1.0 - 1.0 / maxf(path.length(), 1.0), 0.0)
	var f := clampf((out_time - left) / maxf(arrive - left, 0.01), 0.0, stride_short)
	var at := from + path * f
	out.timeline.add(key, out_time, Vector3(at.x, at.y, 0.0))
	var pace := path.length() / maxf(arrive - left, 0.01)
	var ease_to := from + path * minf(f + pace * EASE_UP * 0.5 / maxf(path.length(), 1.0), stride_short)
	var length := out.timeline.duration
	out.timeline.add(key, out_time + EASE_UP, Vector3(ease_to.x, ease_to.y, 0.0))
	out.timeline.duration = length


func _finish() -> void:
	if out.foul:
		return
	var timed: Array[PlayRunner] = []
	for r: PlayRunner in _runners:
		if r.is_out() or r.to != r.from:
			timed.append(r)
		if r.is_out() or r.to > r.from:
			_runner_frames(r)
	# In the order things happened; the lead runner first when two are at the same moment.
	var order := {}
	for i: int in _runners.size():
		order[_runners[i]] = i
	timed.sort_custom(func(a: PlayRunner, b: PlayRunner) -> bool:
		if absf(a.time - b.time) > 1e-6:
			return a.time < b.time
		return int(order[a]) < int(order[b]))
	for r: PlayRunner in timed:
		out.moves.append(r.move())
	out.fielders = "-".join(_chain)
