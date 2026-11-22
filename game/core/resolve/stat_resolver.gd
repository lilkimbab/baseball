class_name StatResolver
extends Resolver
## Plays a game a plate appearance at a time by drawing outcomes from probabilities
## (docs/03 section 6). Used for games nobody watches and for quick simulation.

var env: LeagueEnv
var catalog: Dictionary[StringName, PitchType]
var manager: AiManager
var rng: Rng

## The running play before this plate appearance has been considered.
var _running_checked := false
var _stuff: Dictionary[String, float] = {}


func _init(league: LeagueEnv, pitch_catalog: Dictionary[StringName, PitchType], ai: AiManager, random: Rng) -> void:
	env = league
	catalog = pitch_catalog
	manager = ai
	rng = random


func next_event(state: GameState) -> GameEvent:
	var change := manager.next_change(state)
	if change != null:
		return change
	if not _running_checked:
		_running_checked = true
		var play := _running_play(state)
		if play != null:
			return play
	_running_checked = false
	return _plate_appearance(state)


# --- Before the pitch: steals, pickoffs, wild pitches, passed balls ---


func _running_play(state: GameState) -> GameEvent:
	if state.runners_on() == 0:
		return null
	var batting := state.batting_team()
	var fielding := state.fielding_team()
	var pitcher := fielding.player(state.pitcher_id())
	var catcher := fielding.player(fielding.fielder_at(Position.Kind.C))
	var catcher_arm := catcher.fielding.arm * catcher.aptitude(Position.Kind.C) if catcher != null else 40.0
	var catcher_hands := catcher.fielding.hands * maxf(catcher.aptitude(Position.Kind.C), 0.3) if catcher != null else 40.0
	var lead := state.runner_on(1)
	if lead != null and state.base_empty(2):
		var runner := batting.player(lead.player_id)
		var speed := runner.batting.speed if runner != null else 50.0
		if rng.chance(env.value("pickoff") * exp(0.2 * (pitcher.pitching.hold - 50.0) / 15.0 + 0.15 * (speed - 50.0) / 15.0)):
			var m := RunnerMove.make(1, -1, RunnerMove.OutKind.TAG)
			return GameEvent.running(GameEvent.Kind.PICKOFF, [m] as Array[RunnerMove])
		if _wants_steal(state, 1, speed):
			return _steal(1, speed, catcher_arm, pitcher.pitching.hold)
	var second := state.runner_on(2)
	if second != null and state.base_empty(3) and state.outs < 2:
		var runner := batting.player(second.player_id)
		var speed := runner.batting.speed if runner != null else 50.0
		if _wants_steal(state, 2, speed):
			return _steal(2, speed, catcher_arm, pitcher.pitching.hold)
	if rng.chance(env.value("wild_pitch") * exp(-0.2 * (pitcher.pitching.control - 50.0) / 15.0)):
		return GameEvent.running(GameEvent.Kind.WILD_PITCH, _everyone_advances(state, false))
	if rng.chance(env.value("passed_ball") * exp(-0.5 * (catcher_hands - 50.0) / 15.0)):
		return GameEvent.running(GameEvent.Kind.PASSED_BALL, _everyone_advances(state, false))
	return null


func _wants_steal(state: GameState, base: int, speed: float) -> bool:
	var key := "steal_attempt_1st" if base == 1 else "steal_attempt_2nd"
	var chance := env.value(key) * state.batting_team().steal_style * exp(env.value("steal_speed_k", 0.6) * (speed - 50.0) / 15.0)
	# Not when far behind late, nor when a big lead makes it pointless.
	var lead := state.lead_of(state.batting())
	if absi(lead) >= 5 or (state.inning >= state.rules.innings - 1 and lead <= -3):
		chance *= 0.2
	return rng.chance(minf(chance, 0.6))


func _steal(base: int, speed: float, catcher_arm: float, hold: float) -> GameEvent:
	var s := env.value("steal_success", 0.75)
	var odds := s / (1.0 - s) * exp(0.55 * (speed - 50.0) / 15.0 - 0.3 * (catcher_arm - 50.0) / 15.0 - 0.15 * (hold - 50.0) / 15.0)
	var safe := rng.chance(odds / (1.0 + odds))
	var m := RunnerMove.make(base, base + 1 if safe else -1, RunnerMove.OutKind.NONE if safe else RunnerMove.OutKind.TAG)
	return GameEvent.running(GameEvent.Kind.STEAL, [m] as Array[RunnerMove])


func _everyone_advances(state: GameState, on_error: bool) -> Array[RunnerMove]:
	return GameFlow.everyone_advances(state, on_error)


# --- The plate appearance ---


func _plate_appearance(state: GameState) -> GameEvent:
	if manager.wants_intentional_walk(state):
		var walk := GameEvent.plate_appearance(PaResult.Kind.INTENTIONAL_WALK, _forced(state), 0 if state.rules.auto_intentional_walk else 4)
		return walk
	if manager.wants_bunt(state):
		return _bunt(state)
	var probabilities := outcome_probabilities(state)
	var outcome := rng.pick_weighted(probabilities) as LeagueEnv.Outcome
	var e := _resolve(state, outcome)
	e.pitches = _pitch_count(e.result)
	return e


## Chance of each LeagueEnv.Outcome for the batter now up against the pitcher now pitching.
## Batter and pitcher are combined by odds ratio: each scales the league rate by his own
## ratings, so two average players give the league average (docs/03 section 6.1).
func outcome_probabilities(state: GameState) -> PackedFloat64Array:
	var batting := state.batting_team()
	var fielding := state.fielding_team()
	var batter := batting.player(state.batter_id())
	var pitcher := fielding.player(state.pitcher_id())
	var throws := pitcher.throws
	var b_ratings: Dictionary[String, float] = {
		"contact": batter.batting.contact_vs(throws), "power": batter.batting.power_vs(throws),
		"eye": batter.batting.eye, "speed": batter.batting.speed,
	}
	var p_ratings: Dictionary[String, float] = {"stuff": _pitcher_stuff(pitcher), "control": pitcher.pitching.control}
	var side := batter.batting_side(throws)
	var platoon := env.same_hand if side == throws else env.opposite_hand
	var fatigue := _fatigue(state, fielding, pitcher)
	var defence := _defence(fielding)
	var scoring_position := state.runner_on(2) != null or state.runner_on(3) != null
	var pressure := 0.0
	if scoring_position:
		pressure = env.clutch * ((batter.batting.clutch - 50.0) - (pitcher.pitching.composure - 50.0)) / 15.0

	var out := PackedFloat64Array()
	out.resize(LeagueEnv.OUTCOME_KEYS.size())
	var total := 0.0
	for o: int in LeagueEnv.Outcome.OUT:
		var key := LeagueEnv.OUTCOME_KEYS[o]
		var league := env.rates[o]
		var x := env.scaled(key, env.batter_k, b_ratings) * env.scaled(key, env.pitcher_k, p_ratings) / league if league > 0.0 else 0.0
		x *= float(platoon.get(key, 1.0)) * float(env.calibration.get(key, 1.0))
		x *= 1.0 + float(env.fatigue.get(key, 0.0)) * fatigue
		if o == LeagueEnv.Outcome.SINGLE or o == LeagueEnv.Outcome.DOUBLE or o == LeagueEnv.Outcome.TRIPLE:
			x *= exp(env.defence_hits * (defence - 50.0) / 15.0)
		if o == LeagueEnv.Outcome.K:
			x *= exp(-pressure)
		elif o != LeagueEnv.Outcome.BB and o != LeagueEnv.Outcome.HBP:
			x *= exp(pressure * 0.5)
		if state.batting() == GameState.HOME and o >= LeagueEnv.Outcome.SINGLE:
			x *= env.home_hits
		out[o] = x
		total += x
	out[LeagueEnv.Outcome.OUT] = maxf(1.0 - total, 0.2)
	return out


func _pitcher_stuff(pitcher: Player) -> float:
	if not _stuff.has(pitcher.id):
		_stuff[pitcher.id] = pitcher.pitching.stuff(catalog)
	return _stuff[pitcher.id]


func _fatigue(state: GameState, team: TeamInGame, pitcher: Player) -> float:
	return fatigue(state, team, pitcher)


## 0 while fresh, 1 at the end of his limit, more beyond it. A reliever who came in before he
## was ready pitches his first few batters as if tired (GameState.cold, COLD_FATIGUE).
static func fatigue(state: GameState, team: TeamInGame, pitcher: Player, with_cold: bool = true) -> float:
	var pitches: int = state.pitch_counts.get(pitcher.id, 0)
	var limit := pitcher.pitching.starter_limit() if pitcher.id == team.starter_id else pitcher.pitching.reliever_limit()
	var fresh := limit * 0.7
	var tired := clampf((pitches - fresh) / (limit - fresh), 0.0, 1.5)
	return minf(tired + (COLD_FATIGUE * state.cold(pitcher.id) if with_cold else 0.0), 1.5)


## How tired a cold reliever's first pitches are (in the units of fatigue: 1 is a pitcher at
## the end of his limit).
const COLD_FATIGUE := 1.1


## Average fielding of the eight fielders behind the pitcher, at their positions.
func _defence(team: TeamInGame) -> float:
	var total := 0.0
	var count := 0
	for slot: LineupSlot in team.lineup:
		if Position.is_field(slot.position) and slot.position != Position.Kind.P:
			total += team.player(slot.player_id).fielding_at(slot.position)
			count += 1
	return total / count if count > 0 else 50.0


func _pitch_count(result: PaResult.Kind) -> int:
	var key := "in_play"
	if PaResult.is_strikeout(result):
		key = "K"
	elif result == PaResult.Kind.WALK:
		key = "BB"
	elif result == PaResult.Kind.HIT_BY_PITCH:
		key = "HBP"
	var mean: float = env.pitches_per_pa.get(key, 3.8)
	var least := 3 if key == "K" else (4 if key == "BB" else 1)
	return maxi(roundi(mean + rng.next_normal() * 1.5), least)


func _resolve(state: GameState, outcome: LeagueEnv.Outcome) -> GameEvent:
	match outcome:
		LeagueEnv.Outcome.K:
			var e := GameEvent.plate_appearance(PaResult.Kind.STRIKEOUT, [RunnerMove.make(0, -1, RunnerMove.OutKind.STRIKEOUT)] as Array[RunnerMove])
			e.direction = 2
			return e
		LeagueEnv.Outcome.BB:
			return GameEvent.plate_appearance(PaResult.Kind.WALK, _forced(state))
		LeagueEnv.Outcome.HBP:
			return GameEvent.plate_appearance(PaResult.Kind.HIT_BY_PITCH, _forced(state))
		LeagueEnv.Outcome.SINGLE, LeagueEnv.Outcome.DOUBLE, LeagueEnv.Outcome.TRIPLE, LeagueEnv.Outcome.HR:
			return _hit(state, outcome - LeagueEnv.Outcome.SINGLE + 1)
	return _out_in_play(state)


func _forced(state: GameState) -> Array[RunnerMove]:
	return GameFlow.forced_moves(state)


func _hit(state: GameState, bases: int) -> GameEvent:
	var moves: Array[RunnerMove] = []
	var two_outs := state.outs == 2
	var team := state.batting_team()
	var occupied: Array[bool] = [false, false, false]
	var direction := _outfield_direction() if bases > 1 else (_outfield_direction() if rng.chance(0.8) else _infield_direction())
	if bases == 4:
		for base: int in [3, 2, 1]:
			if not state.base_empty(base):
				moves.append(RunnerMove.make(base, 4))
		moves.append(RunnerMove.make(0, 4))
		return _with_direction(GameEvent.plate_appearance(PaResult.Kind.HOME_RUN, moves), direction)
	var error := rng.chance(env.value("extra_base_error_on_hit"))
	if bases == 1 and direction < 7:
		return _with_direction(GameEvent.plate_appearance(PaResult.Kind.SINGLE, _infield_hit(state)), direction)
	for base: int in [3, 2, 1]:
		var runner := state.runner_on(base)
		if runner == null:
			continue
		var speed := _speed(team, runner.player_id)
		var to := mini(base + bases, 4)
		if to < 4:
			var chance := 0.0
			if bases == 1 and base == 2:
				chance = env.value("single_runner_2nd_scores_two_outs" if two_outs else "single_runner_2nd_scores")
			elif bases == 1 and base == 1:
				chance = env.value("single_runner_1st_to_3rd_two_outs" if two_outs else "single_runner_1st_to_3rd")
			elif bases == 2 and base == 1:
				chance = env.value("double_runner_1st_scores_two_outs" if two_outs else "double_runner_1st_scores")
			chance = clampf(chance * exp(0.35 * (speed - 50.0) / 15.0), 0.0, 0.97)
			if chance > 0.0 and (to + 1 == 4 or not occupied[to]) and rng.chance(chance):
				if rng.chance(env.value("thrown_out_advancing")):
					moves.append(RunnerMove.make(base, -1, RunnerMove.OutKind.TAG))
					continue
				to += 1
		if error and to < 4:
			moves.append(RunnerMove.make(base, to + 1, RunnerMove.OutKind.NONE, true))
			to += 1
		else:
			moves.append(RunnerMove.make(base, to))
		if to < 4:
			occupied[to - 1] = true
	var batter_to := bases
	if error and bases < 3 and not occupied[bases]:
		moves.append(RunnerMove.make(0, bases + 1, RunnerMove.OutKind.NONE, true))
	else:
		moves.append(RunnerMove.make(0, batter_to))
	return _with_direction(GameEvent.plate_appearance(PaResult.hit_of_bases(bases), moves), direction)


## An infield hit: the ball never leaves the infield, so only forced runners move up, and a
## runner on second sometimes takes third.
func _infield_hit(state: GameState) -> Array[RunnerMove]:
	var moves: Array[RunnerMove] = []
	var forced := _forced_bases(state)
	if not state.base_empty(3) and forced[2]:
		moves.append(RunnerMove.make(3, 4))
	if not state.base_empty(2) and (forced[1] or (state.base_empty(3) and rng.chance(0.4))):
		moves.append(RunnerMove.make(2, 3))
	if forced[0]:
		moves.append(RunnerMove.make(1, 2))
	moves.append(RunnerMove.make(0, 1))
	return moves


func _speed(team: TeamInGame, id: String) -> float:
	var p := team.player(id)
	return p.batting.speed if p != null else 50.0


func _out_in_play(state: GameState) -> GameEvent:
	var team := state.batting_team()
	var batter := team.player(state.batter_id())
	var defence := _defence(state.fielding_team())
	var types := env.out_types.duplicate()
	# Power hitters lift the ball.
	var lift := clampf((batter.batting.power() - 50.0) / 15.0, -2.0, 2.0) * 0.04
	types[0] = maxf(types[0] - lift, 0.1)
	types[1] = types[1] + lift
	if rng.chance(env.value("reached_on_error") * exp(-0.4 * (defence - 50.0) / 15.0)):
		return _reached_on_error(state)
	match rng.pick_weighted(types):
		0:
			return _ground_out(state, batter)
		1:
			return _fly_out(state)
		2:
			return _line_out(state)
	var e := GameEvent.plate_appearance(PaResult.Kind.POP_OUT, [RunnerMove.make(0, -1, RunnerMove.OutKind.FLY)] as Array[RunnerMove])
	return _with_direction(e, _infield_direction())


func _reached_on_error(state: GameState) -> GameEvent:
	var moves: Array[RunnerMove] = []
	var forced := _forced_bases(state)
	for base: int in [3, 2, 1]:
		if state.base_empty(base):
			continue
		moves.append(RunnerMove.make(base, base + 1, RunnerMove.OutKind.NONE, not forced[base - 1]))
	moves.append(RunnerMove.make(0, 1))
	return _with_direction(GameEvent.plate_appearance(PaResult.Kind.REACHED_ON_ERROR, moves), _infield_direction())


## Which runners must move if the batter reaches first: forced[i] for base i + 1.
func _forced_bases(state: GameState) -> Array[bool]:
	var first := not state.base_empty(1)
	var second := first and not state.base_empty(2)
	var third := second and not state.base_empty(3)
	return [first, second, third]


func _ground_out(state: GameState, batter: Player) -> GameEvent:
	var moves: Array[RunnerMove] = []
	var forced := _forced_bases(state)
	var outs := state.outs
	var direction := _infield_direction()
	if forced[0] and outs < 2:
		var dp := env.value("double_play_on_ground_force") * exp(-0.3 * (batter.batting.speed - 50.0) / 15.0)
		if rng.chance(dp):
			# Lead runners who are forced move up; the runner from first and the batter are out.
			if forced[2]:
				moves.append(RunnerMove.make(3, 4))
			elif not state.base_empty(3) and rng.chance(0.5):
				moves.append(RunnerMove.make(3, 4))
			if forced[1]:
				moves.append(RunnerMove.make(2, 3))
			moves.append(RunnerMove.make(1, -1, RunnerMove.OutKind.FORCE))
			moves.append(RunnerMove.make(0, -1, RunnerMove.OutKind.FORCE))
			var e := GameEvent.plate_appearance(PaResult.Kind.DOUBLE_PLAY, moves)
			e.fielders = "%d-%d-3" % [direction, 4 if direction != 4 else 6]
			return _with_direction(e, direction)
		if rng.chance(env.value("fielders_choice_on_ground_force")):
			if forced[2]:
				moves.append(RunnerMove.make(3, 4))
			elif not state.base_empty(3) and rng.chance(env.value("runner_3rd_scores_on_ground")):
				moves.append(RunnerMove.make(3, 4))
			if forced[1]:
				moves.append(RunnerMove.make(2, 3))
			elif not state.base_empty(2) and state.base_empty(3) and rng.chance(env.value("runner_2nd_to_3rd_on_ground")):
				moves.append(RunnerMove.make(2, 3))
			moves.append(RunnerMove.make(1, -1, RunnerMove.OutKind.FORCE))
			moves.append(RunnerMove.make(0, 1))
			return _with_direction(GameEvent.plate_appearance(PaResult.Kind.FIELDERS_CHOICE, moves), direction)
	# Batter out at first; forced runners move up, the others may.
	if outs < 2:
		if not state.base_empty(3) and (forced[2] or rng.chance(env.value("runner_3rd_scores_on_ground"))):
			moves.append(RunnerMove.make(3, 4))
		if not state.base_empty(2) and (forced[1] or (state.base_empty(3) or _moved(moves, 3)) and rng.chance(env.value("runner_2nd_to_3rd_on_ground"))):
			moves.append(RunnerMove.make(2, 3))
		if forced[0]:
			moves.append(RunnerMove.make(1, 2))
	moves.append(RunnerMove.make(0, -1, RunnerMove.OutKind.FORCE))
	var out := GameEvent.plate_appearance(PaResult.Kind.GROUND_OUT, moves)
	out.fielders = "%d-3" % direction if direction != 3 else "3"
	return _with_direction(out, direction)


func _moved(moves: Array[RunnerMove], from_base: int) -> bool:
	for m: RunnerMove in moves:
		if m.from == from_base:
			return true
	return false


func _fly_out(state: GameState) -> GameEvent:
	var moves: Array[RunnerMove] = []
	var result := PaResult.Kind.FLY_OUT
	var direction := _outfield_direction()
	moves.append(RunnerMove.make(0, -1, RunnerMove.OutKind.FLY))
	if state.outs < 2:
		var scored := false
		if not state.base_empty(3) and rng.chance(env.value("sac_fly_runner_3rd")):
			moves.append(RunnerMove.make(3, 4))
			result = PaResult.Kind.SAC_FLY
			scored = true
		if not state.base_empty(2) and (state.base_empty(3) or scored) and rng.chance(env.value("runner_2nd_to_3rd_on_fly")):
			moves.append(RunnerMove.make(2, 3))
	return _with_direction(GameEvent.plate_appearance(result, moves), direction)


func _line_out(state: GameState) -> GameEvent:
	var moves: Array[RunnerMove] = [RunnerMove.make(0, -1, RunnerMove.OutKind.FLY)]
	if state.outs < 2 and state.runners_on() > 0 and rng.chance(env.value("doubled_off_on_line")):
		for base: int in [1, 2, 3]:
			if not state.base_empty(base):
				moves.append(RunnerMove.make(base, -1, RunnerMove.OutKind.TAG))
				break
	var direction := _outfield_direction() if rng.chance(0.6) else _infield_direction()
	return _with_direction(GameEvent.plate_appearance(PaResult.Kind.LINE_OUT, moves), direction)


func _bunt(state: GameState) -> GameEvent:
	var team := state.batting_team()
	var batter := team.player(state.batter_id())
	var roll := rng.next_float()
	var skill := clampf((batter.batting.bunt - 50.0) / 15.0, -2.0, 2.0)
	var moves: Array[RunnerMove] = []
	var forced := _forced_bases(state)
	if roll < 0.10 + 0.02 * skill:
		# Bunt for a hit.
		for base: int in [3, 2, 1]:
			if not state.base_empty(base):
				moves.append(RunnerMove.make(base, base + 1))
		moves.append(RunnerMove.make(0, 1))
		return _with_direction(GameEvent.plate_appearance(PaResult.Kind.SINGLE, moves, 2), 1)
	if roll < 0.26 - 0.03 * skill:
		# The lead runner is thrown out.
		var lead := 2 if forced[1] else 1
		for base: int in [3, 2, 1]:
			if state.base_empty(base):
				continue
			if base == lead:
				moves.append(RunnerMove.make(base, -1, RunnerMove.OutKind.FORCE))
			elif base < lead or forced[base - 1]:
				moves.append(RunnerMove.make(base, base + 1))
		moves.append(RunnerMove.make(0, 1))
		return _with_direction(GameEvent.plate_appearance(PaResult.Kind.FIELDERS_CHOICE, moves, 2), 1)
	for base: int in [3, 2, 1]:
		if not state.base_empty(base):
			moves.append(RunnerMove.make(base, base + 1))
	moves.append(RunnerMove.make(0, -1, RunnerMove.OutKind.FORCE))
	var e := GameEvent.plate_appearance(PaResult.Kind.SAC_BUNT, moves, 2)
	e.fielders = "1-3"
	return _with_direction(e, 1)


func _with_direction(e: GameEvent, direction: int) -> GameEvent:
	e.direction = direction
	return e


## Infielder who fields a ground ball or pop-up, by how often each does (A).
func _infield_direction() -> int:
	return [1, 3, 4, 5, 6][rng.pick_weighted(PackedFloat64Array([0.08, 0.16, 0.25, 0.21, 0.30]))]


func _outfield_direction() -> int:
	return [7, 8, 9][rng.pick_weighted(PackedFloat64Array([0.34, 0.33, 0.33]))]
