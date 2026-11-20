class_name PlayContext
extends RefCounted
## Everything a play needs to know when the ball is put in play: its path, the fielders where
## they stand, the runners, and the situation.

var path: Trajectory
var field: AnalyticField
var motion: MotionModel
var outs := 0
var fielders: Dictionary[Position.Kind, PlayFielder] = {}
## Runners on first, second and third (null where empty).
var runners: Array[PlayRunner] = [null, null, null]
var batter: PlayRunner
var bunt := false
## A run from third would tie or win the game late: the defence plays for it.
var run_matters := false
## The infield is drawn in to cut off the run at the plate.
var infield_in := false
## Full count with two out: forced runners go with the pitch.
var running_with_pitch := false


## A context for the batter now up in `state`, with the fielders at `positions`.
static func from_state(state: GameState, ball_path: Trajectory, analytic: AnalyticField, positions: Dictionary[Position.Kind, Vector2], model: MotionModel, is_bunt: bool = false) -> PlayContext:
	var c := PlayContext.new()
	c.path = ball_path
	c.field = analytic
	c.motion = model
	c.outs = state.outs
	c.bunt = is_bunt
	var defence := state.fielding_team()
	var offence := state.batting_team()
	for kind: Position.Kind in Position.FIELD:
		var id := defence.fielder_at(kind)
		var p := defence.player(id)
		var where: Vector2 = positions.get(kind, Vector2.ZERO)
		if p == null:
			c.fielders[kind] = PlayFielder.make(kind, where)
			continue
		var fit := p.aptitude(kind)
		if kind == Position.Kind.C and fit <= 0.0:
			fit = 0.3
		var scale := lerpf(0.5, 1.0, clampf(fit, 0.0, 1.0))
		var f := PlayFielder.make(kind, where, p.batting.speed, p.fielding.range * scale, p.fielding.hands * scale, p.fielding.arm * scale, p.fielding.accuracy * scale)
		f.id = id
		c.fielders[kind] = f
	for i: int in 3:
		var on := state.bases[i]
		if on == null:
			continue
		var p := offence.player(on.player_id)
		c.runners[i] = PlayRunner.make(on.player_id, i + 1, p.batting.speed if p != null else 50.0, p.batting.baserunning if p != null else 50.0)
	var hitter := offence.player(state.batter_id())
	var pitcher := defence.player(state.pitcher_id())
	c.batter = PlayRunner.make(state.batter_id(), 0, hitter.batting.speed if hitter != null else 50.0, hitter.batting.baserunning if hitter != null else 50.0)
	if hitter != null:
		c.batter.bats_left = hitter.batting_side(pitcher.throws if pitcher != null else &"R") == &"L"
	var late := state.inning >= state.rules.innings - 1
	var lead := state.lead_of(state.fielding())
	c.run_matters = late and lead >= 0 and lead <= 1
	c.infield_in = state.outs < 2 and not state.base_empty(3) and late and absi(lead) <= 1
	c.running_with_pitch = state.outs == 2 and state.balls == 3 and state.strikes == 2
	return c
