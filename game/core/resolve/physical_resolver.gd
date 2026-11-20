class_name PhysicalResolver
extends Resolver
## Plays a game pitch by pitch with the physics (docs/03 section 7, docs/13 S5-9). Every pitch
## is flown and every swing met with the contact model; balls in play go through PlaySim. It
## sends the same events as the stat resolver, so GameFlow and the Scorer are shared.
##
## Headless (AI against AI) next_event() does everything. A scene with a person playing calls
## before_pitch(), new_duel(), plays the pitch out itself, then hands it to after_pitch().

const DT := 1.0 / 240.0
## A clean catch still gets by a catcher this rarely (a passed ball), at average hands.
const PASSED_CLEAN := 0.0018
## Spread of the time on a steal: the pitcher's delivery, the catcher's throw, the tag (s).
const STEAL_SPREAD := 0.13
## Rating points a batter gains at home (docs/12 8.1: the home side wins about 53 %).
const HOME_EDGE := 5.0
## How much of the computer batter's misread of the pitch becomes a bat-ball offset. A person's
## small aiming errors are forgiven (DuelSettings.aim_scale); the computer's are its whole skill.
const AI_AIM_SCALE := 0.14

var cfg: PhysicsConfig
var field: AnalyticField
var fence: FenceProfile
var motion: MotionModel
var alignment: FieldingAlignment
var catalog: Dictionary[StringName, PitchType]
var env: LeagueEnv
var manager: AiManager
var rng: Rng
## Who decides for the away team and the home team.
var controllers: Array[Controller] = []

## The last pitch and play, for the scene and the checks.
var last_duel: PitchDuel
var last_play: PlayResult
## Pitch-by-pitch counts for the calibration report (null: not kept).
var tally: PitchTally

var _queue: Array[GameEvent] = []
## Which plate appearance is under way: inning, half and batter.
var _pa_key := ""
var _bunting := false
## How the coming strikeout ends: the batter out, or reaching on a dropped third strike.
var _third_strike: PaResult.Kind = PaResult.Kind.STRIKEOUT
var _third_fielders := "2"
## Steals planned for this plate appearance: base -> the pitch (0, 1, 2...) he goes on.
var _steal_plan: Dictionary[int, int] = {}
var _pitch_in_pa := 0


func _init(league: LeagueEnv, pitch_catalog: Dictionary[StringName, PitchType], ai: AiManager, random: Rng,
		park: FenceProfile = null, physics: PhysicsConfig = null) -> void:
	env = league
	catalog = pitch_catalog
	manager = ai
	rng = random
	fence = park if park != null else default_fence()
	cfg = physics if physics != null else PhysicsConfigIO.load_default()
	field = AnalyticField.create(fence)
	motion = MotionIO.load_default()
	alignment = MotionIO.alignment()
	controllers = [AiController.new(ai, pitch_catalog, random), AiController.new(ai, pitch_catalog, random)]


## The greybox park until stadiums come in (S13): 100 m lines, 116 m alleys, 122 m centre.
static func default_fence() -> FenceProfile:
	return FenceProfile.symmetric(100.0, 116.0, 122.0, 2.6)


func next_event(state: GameState) -> GameEvent:
	if not _queue.is_empty():
		return _queue.pop_front()
	var before := before_pitch(state)
	if before != null:
		return before
	var duel := new_duel(state)
	duel.throw_pitch(tire(state, controllers[state.fielding()].choose_pitch(state, duel)))
	if _bunting and controllers[state.batting()] is AiController:
		AiBatter.bunt(duel, rng)
	else:
		controllers[state.batting()].react(state, duel)
	while duel.phase == PitchDuel.Phase.FLIGHT:
		duel.tick(DT)
	_queue.append_array(after_pitch(state, duel))
	return _queue.pop_front()


# --- Before the pitch ---


## Whatever happens before the next pitch: the end of a plate appearance whose count is
## complete, substitutions, an intentional walk, a pickoff or a steal. Null when it is time
## to pitch.
func before_pitch(state: GameState) -> GameEvent:
	if state.balls >= 4:
		_close_plate_appearance()
		return GameEvent.plate_appearance(PaResult.Kind.WALK, GameFlow.forced_moves(state), 0)
	if state.strikes >= 3:
		var moves: Array[RunnerMove] = []
		if _third_strike == PaResult.Kind.DROPPED_THIRD_STRIKE:
			moves = GameFlow.forced_moves(state)
		else:
			moves.append(RunnerMove.out_at_base(0, 1, RunnerMove.OutKind.STRIKEOUT))
		var e := GameEvent.plate_appearance(_third_strike, moves, 0)
		e.fielders = _third_fielders
		e.direction = 2
		_close_plate_appearance()
		return e
	var key := "%d%s%s" % [state.inning, state.top, state.batter_id()]
	if key != _pa_key:
		var change := manager.next_change(state)
		if change != null:
			return change
		_pa_key = key
		_bunting = false
		var pickoff := _pickoff(state)
		if pickoff != null:
			return pickoff
		if manager.wants_intentional_walk(state):
			_close_plate_appearance()
			return GameEvent.plate_appearance(PaResult.Kind.INTENTIONAL_WALK, GameFlow.forced_moves(state), 0 if state.rules.auto_intentional_walk else 4)
		_bunting = controllers[state.batting()].wants_bunt(state)
		_plan_steals(state)
	if _bunting and state.strikes == 2:
		# Two strikes: a foul bunt would be strike three, so he swings away.
		_bunting = false
	return _steal(state)


## The batter is squared to bunt in this plate appearance.
func is_bunting() -> bool:
	return _bunting


func _close_plate_appearance() -> void:
	_pa_key = ""
	_bunting = false
	_steal_plan.clear()
	_pitch_in_pa = 0
	_third_strike = PaResult.Kind.STRIKEOUT
	_third_fielders = "2"


## A pickoff throw catches the runner on first (once per plate appearance at most).
func _pickoff(state: GameState) -> GameEvent:
	var lead := state.runner_on(1)
	if lead == null or not state.base_empty(2):
		return null
	var pitcher := state.fielding_team().player(state.pitcher_id())
	var runner := state.batting_team().player(lead.player_id)
	var speed := runner.batting.speed if runner != null else 50.0
	var hold := pitcher.pitching.hold if pitcher != null and pitcher.pitching != null else 50.0
	if rng.chance(env.value("pickoff") * exp(0.2 * (hold - 50.0) / 15.0 + 0.15 * (speed - 50.0) / 15.0)):
		var m := RunnerMove.out_at_base(1, 1, RunnerMove.OutKind.TAG)
		var e := GameEvent.running(GameEvent.Kind.PICKOFF, [m] as Array[RunnerMove])
		e.fielders = "1-3"
		return e
	return null


## At the start of a plate appearance each runner with an open base ahead decides whether
## he will run in it, reading his jump and speed against the pitcher's time to the plate and
## the catcher's pop time, and on which pitch.
func _plan_steals(state: GameState) -> void:
	_steal_plan.clear()
	_pitch_in_pa = 0
	for base: int in [2, 1]:
		if not _can_steal(state, base):
			continue
		if controllers[state.batting()].wants_steal(state, base, steal_margin(state, base)):
			_steal_plan[base] = rng.next_int(3)
			return


func _can_steal(state: GameState, base: int) -> bool:
	if state.base_empty(base) or not state.base_empty(base + 1):
		return false
	return not (base == 2 and state.outs == 2)


func _steal(state: GameState) -> GameEvent:
	for base: int in [2, 1]:
		if not _steal_plan.has(base) or _steal_plan[base] > _pitch_in_pa:
			continue
		_steal_plan.erase(base)
		if not _can_steal(state, base):
			continue
		var margin := steal_margin(state, base)
		var actual := margin + rng.next_normal() * STEAL_SPREAD
		var catcher := _catcher(state)
		if rng.chance(motion.bad_throw * 2.0 * exp(-(catcher.fielding.accuracy - 50.0) / 40.0)):
			# The throw gets away: on to the next base on the error.
			var through := RunnerMove.make(base, base + 2, RunnerMove.OutKind.NONE, true)
			var e := GameEvent.running(GameEvent.Kind.STEAL, [through] as Array[RunnerMove])
			e.fielders = "E2"
			return e
		var safe := actual > 0.0
		var m := RunnerMove.make(base, base + 1) if safe else RunnerMove.out_at_base(base, base + 1, RunnerMove.OutKind.TAG)
		var steal := GameEvent.running(GameEvent.Kind.STEAL, [m] as Array[RunnerMove])
		steal.fielders = "" if safe else ("2-6" if base == 1 else "2-5")
		return steal
	return null


## Seconds by which the runner on `base` would beat the throw to the next base (negative: he
## would be out), on average.
func steal_margin(state: GameState, base: int) -> float:
	var on := state.runner_on(base)
	var runner := state.batting_team().player(on.player_id)
	var pitcher := state.fielding_team().player(state.pitcher_id())
	var catcher := _catcher(state)
	var speed := runner.batting.speed if runner != null else 50.0
	var reads := runner.batting.baserunning if runner != null else 50.0
	var hold := pitcher.pitching.hold if pitcher != null and pitcher.pitching != null else 50.0
	var lead := motion.leads[base - 1]
	var run := MotionModel.lerp_rating(motion.steal_jump, reads) \
		+ motion.time_to_cover(Field.BASE_DISTANCE - lead - motion.slide_gain, motion.top_speed_for(speed))
	var target := PlaySim.base_xy(base + 1)
	var arm := catcher.fielding.arm * _catcher_fit(catcher)
	var hands := catcher.fielding.hands * _catcher_fit(catcher)
	var battery := motion.delivery_for(hold) + motion.transfer_for(Position.Kind.C, hands) \
		+ motion.throw_time(target.length(), motion.throw_speed(Position.Kind.C, arm)) + motion.tag
	return battery - run


func _catcher(state: GameState) -> Player:
	var team := state.fielding_team()
	return team.player(team.fielder_at(Position.Kind.C))


func _catcher_fit(catcher: Player) -> float:
	var fit := catcher.aptitude(Position.Kind.C)
	return lerpf(0.5, 1.0, clampf(fit if fit > 0.0 else 0.3, 0.0, 1.0))


# --- The pitch ---


## A pitch ready to throw between the batter and pitcher now up.
func new_duel(state: GameState) -> PitchDuel:
	var batter := state.batting_team().player(state.batter_id())
	var pitcher := state.fielding_team().player(state.pitcher_id())
	var s := DuelSettings.new()
	s.rules = state.rules
	var throws: StringName = pitcher.throws if pitcher != null else &"R"
	s.throws_left = throws == &"L"
	if batter != null:
		s.batter_height = batter.height_cm / 100.0
		s.bats_left = batter.batting_side(throws) == &"L"
		s.contact = batter.batting.contact_vs(throws)
		s.power = batter.batting.power_vs(throws)
		s.eye = batter.batting.eye
		if state.batting() == GameState.HOME:
			# At home a batter sees the ball a little better (the backdrop, the routine).
			s.contact += HOME_EDGE
			s.eye += HOME_EDGE
	if pitcher != null and pitcher.pitching != null:
		# A tired pitcher loses command.
		s.command = maxf(pitcher.pitching.control - 12.0 * _tiredness(state), 1.0)
		s.release_point.z = 1.80 * clampf(pitcher.height_cm / 185.0, 0.9, 1.1)
	s.body_offset = motion.body_offset
	s.body_radius = motion.body_radius
	s.body_ankle = motion.body_ankle
	s.body_shoulder_share = motion.body_shoulder_share
	if controllers[state.batting()] is AiController:
		s.dodge = motion.dodge_chance
		s.aim_scale = AI_AIM_SCALE
		s.aim_forgiving = false
		s.yaw_spread = SwingModel.YAW_SPREAD_DEG
	last_duel = PitchDuel.new(cfg, field, s, rng)
	return last_duel


## A tired pitcher also loses a little speed (about 2.5 km/h at the end of his limit).
func tire(state: GameState, decision: PitchDecision) -> PitchDecision:
	decision.effort *= 1.0 - 0.017 * _tiredness(state)
	return decision


func _tiredness(state: GameState) -> float:
	var team := state.fielding_team()
	var pitcher := team.player(state.pitcher_id())
	if pitcher == null or pitcher.pitching == null:
		return 0.0
	return StatResolver.fatigue(state, team, pitcher)


# --- After the pitch ---


## The events a finished pitch makes: the pitch itself, a wild pitch or passed ball, or the
## end of the plate appearance (hit by pitch, ball in play).
func after_pitch(state: GameState, duel: PitchDuel) -> Array[GameEvent]:
	if tally != null:
		tally.add(state, duel)
	_pitch_in_pa += 1
	var events: Array[GameEvent] = []
	var strike_three := state.strikes == 2
	var can_run := GameFlow.third_strike_can_run(state)
	var bunt := duel.swing != null and duel.swing.kind == SwingAttempt.Kind.BUNT
	match duel.result:
		PitchDuel.Result.BALL:
			events.append(GameEvent.pitch(GameEvent.Call.BALL))
			_loose_ball(state, duel, events)
		PitchDuel.Result.CALLED_STRIKE, PitchDuel.Result.SWINGING_STRIKE:
			var call := GameEvent.Call.CALLED_STRIKE if duel.result == PitchDuel.Result.CALLED_STRIKE else GameEvent.Call.SWINGING_STRIKE
			events.append(GameEvent.pitch(call))
			var loose := _loose_ball(state, duel, events)
			if strike_three:
				_third_strike = PaResult.Kind.STRIKEOUT
				_third_fielders = "2"
				if loose > 0 and can_run:
					if loose == 2:
						_third_strike = PaResult.Kind.DROPPED_THIRD_STRIKE
						_third_fielders = ""
					else:
						_third_fielders = "2-3"
		PitchDuel.Result.FOUL_TIP:
			events.append(GameEvent.pitch(GameEvent.Call.SWINGING_STRIKE))
			_third_strike = PaResult.Kind.STRIKEOUT
			_third_fielders = "2"
		PitchDuel.Result.HIT_BY_PITCH:
			var hbp := GameEvent.plate_appearance(PaResult.Kind.HIT_BY_PITCH, GameFlow.forced_moves(state), 1)
			events.append(hbp)
			_close_plate_appearance()
		_:
			var play := play_ball(state, duel, bunt)
			last_play = play
			if tally != null:
				tally.add_play(duel, play)
			if play.foul:
				events.append(GameEvent.pitch(GameEvent.Call.FOUL_BUNT if bunt else GameEvent.Call.FOUL))
			else:
				var e := GameEvent.plate_appearance(play.result, play.moves, 1)
				e.fielders = play.fielders
				e.direction = play.direction
				events.append(e)
				_close_plate_appearance()
	return events


## The ball in play, fielded and run out.
func play_ball(state: GameState, duel: PitchDuel, bunt: bool = false) -> PlayResult:
	var positions := alignment.positions(state, fence, duel.settings.bats_left, bunt)
	var ctx := PlayContext.from_state(state, duel.path, field, positions, motion, bunt)
	return PlaySim.run(ctx, rng)


## Whether the catcher held the pitch: 0 caught, 1 blocked in front of him, 2 got away (a
## wild pitch, or a passed ball if he should have had it). Runners move up when it gets away.
func _loose_ball(state: GameState, duel: PitchDuel, events: Array[GameEvent]) -> int:
	var catcher := _catcher(state)
	var hands := catcher.fielding.hands * _catcher_fit(catcher) if catcher != null else 40.0
	var p := duel.ball.pos
	var target := duel.decision.target
	var excess := maxf(absf(p.x - target.x) - motion.catcher_side, 0.0) \
		+ maxf(motion.catcher_low - p.z, 0.0) + maxf(p.z - motion.catcher_high, 0.0)
	var clean := not duel.bounced and excess <= 0.0
	var kind := GameEvent.Kind.WILD_PITCH
	if clean:
		if not rng.chance(PASSED_CLEAN * exp(-(hands - 50.0) / 25.0)):
			return 0
		kind = GameEvent.Kind.PASSED_BALL
	else:
		var keep := MotionModel.lerp_rating(motion.block, hands) * exp(-excess / 0.6)
		if rng.chance(keep):
			return 1
	if state.runners_on() > 0:
		events.append(GameEvent.running(kind, GameFlow.everyone_advances(state)))
	return 2
