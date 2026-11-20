class_name GameFlow
extends RefCounted
## Applies events to a game state: the count, outs, runners and runs, half-innings and the
## end of the game. All the rules about when runs count and when a game ends are here.


## Gets a new game ready: line score started, starting pitchers recorded.
static func start(state: GameState) -> void:
	for team: TeamInGame in state.teams:
		team.starter_id = team.pitcher_id
		if not team.pitchers_used.has(team.pitcher_id):
			team.pitchers_used.append(team.pitcher_id)
	_open_half(state)


static func apply(state: GameState, event: GameEvent) -> FlowOutcome:
	var out := FlowOutcome.new()
	out.batting_before = state.batting()
	out.inning_before = state.inning
	out.top_before = state.top
	out.outs_before = state.outs
	out.batter_id = state.batter_id()
	out.pitcher_id = state.pitcher_id()
	out.score_before = state.score.duplicate()
	out.charged_batter_id = out.batter_id
	out.charged_pitcher_id = out.pitcher_id
	if state.over:
		return out
	match event.kind:
		GameEvent.Kind.PITCH:
			_pitch(state, event, out)
		GameEvent.Kind.SUBSTITUTION:
			_substitute(state, event)
		_:
			_play(state, event, out)
	return out


static func _pitch(state: GameState, event: GameEvent, out: FlowOutcome) -> void:
	var pitcher := state.pitcher_id()
	state.pitch_counts[pitcher] = int(state.pitch_counts.get(pitcher, 0)) + 1
	match event.call:
		GameEvent.Call.BALL:
			state.balls += 1
			if state.balls >= 4:
				out.completes = PaResult.Kind.WALK
		GameEvent.Call.CALLED_STRIKE, GameEvent.Call.SWINGING_STRIKE:
			state.strikes += 1
			if state.strikes >= 3:
				out.completes = PaResult.Kind.STRIKEOUT
		GameEvent.Call.FOUL:
			# A foul is a strike until there are two.
			state.strikes = mini(state.strikes + 1, 2)
		GameEvent.Call.FOUL_BUNT:
			# A bunt that goes foul is a strike even with two: the third is a strikeout.
			state.strikes += 1
			if state.strikes >= 3:
				out.completes = PaResult.Kind.STRIKEOUT


static func _substitute(state: GameState, event: GameEvent) -> void:
	var team := state.teams[event.team]
	var mid_count := state.balls > 0 or state.strikes > 0
	match event.change:
		GameEvent.Change.PITCHER:
			if mid_count and state.count_pitcher_id == "" and event.team == state.fielding():
				state.count_pitcher_id = event.out_id
				state.count_at_relief = Vector2i(state.balls, state.strikes)
			team.change_pitcher(event.in_id)
		GameEvent.Change.PINCH_HITTER:
			if state.strikes == 2 and state.count_batter_id == "" and event.out_id == state.batter_id():
				state.count_batter_id = event.out_id
			team.pinch(team.slot_of(event.out_id), event.in_id)
		GameEvent.Change.PINCH_RUNNER:
			team.pinch(team.slot_of(event.out_id), event.in_id, true)
			for i: int in 3:
				var r := state.bases[i]
				if r != null and r.player_id == event.out_id:
					var replacement := r.copy()
					replacement.player_id = event.in_id
					state.bases[i] = replacement
		GameEvent.Change.DEFENSE:
			team.replace_fielder(event.out_id, event.in_id, event.position)
		GameEvent.Change.POSITION:
			team.move(event.in_id, event.position)


## A plate appearance or a running play (steal, pickoff, wild pitch, passed ball).
static func _play(state: GameState, event: GameEvent, out: FlowOutcome) -> void:
	var is_pa := event.kind == GameEvent.Kind.PLATE_APPEARANCE
	var pitcher := state.pitcher_id()
	var result := event.result
	var batter_runner: BaseRunner = null
	if is_pa:
		if state.count_batter_id != "" and PaResult.is_strikeout(result):
			out.charged_batter_id = state.count_batter_id
		var relief := state.count_at_relief
		var batters_count := (relief.x >= 2 and relief.x > relief.y) or relief == Vector2i(3, 2)
		if state.count_pitcher_id != "" and batters_count and PaResult.is_walk(result):
			out.charged_pitcher_id = state.count_pitcher_id
		batter_runner = BaseRunner.make(state.batter_id(), out.charged_pitcher_id, result, result == PaResult.Kind.REACHED_ON_ERROR)
		if result == PaResult.Kind.REACHED_ON_ERROR:
			# Rebuild the inning as if the error had not happened: the batter was out.
			state.phantom_outs += 1
		if result == PaResult.Kind.FIELDERS_CHOICE:
			# A batter who reaches by putting out a runner the previous pitcher let on takes
			# over that pitcher's responsibility.
			for m: RunnerMove in event.moves:
				if m.from > 0 and m.is_out() and state.bases[m.from - 1] != null:
					batter_runner.responsible_pitcher_id = state.bases[m.from - 1].responsible_pitcher_id
					break

	# A third out by a force or on the batter before he reaches first means no run scores on
	# the play, even one that crossed the plate first.
	var outs_after := state.outs
	var no_runs := false
	for m: RunnerMove in event.moves:
		if m.is_out():
			outs_after += 1
			if outs_after == 3:
				no_runs = m.out_kind == RunnerMove.OutKind.FORCE or m.batter_out_before_first() or m.out_kind == RunnerMove.OutKind.FLY or m.out_kind == RunnerMove.OutKind.STRIKEOUT

	var start := state.bases.duplicate()
	var after: Array[BaseRunner] = state.bases.duplicate()
	var ends_game := false
	var winning_advance := 0
	out.runner_ids.resize(event.moves.size())
	out.applied.resize(event.moves.size())
	# Everyone who moves leaves his base at once; arrivals and outs then follow in order. (A
	# batter reaching first is often listed before the runner who left first long before.)
	for m: RunnerMove in event.moves:
		if m.from > 0 and start[m.from - 1] != null and after[m.from - 1] == start[m.from - 1]:
			after[m.from - 1] = null
	for i: int in event.moves.size():
		var m := event.moves[i]
		var runner: BaseRunner = batter_runner if m.from == 0 else start[m.from - 1]
		out.runner_ids[i] = runner.player_id if runner != null else ""
		if runner == null:
			continue
		# Nothing that happens after the third out counts: the half-inning is already over.
		# A runner still on his way is left on base, on the one he was heading for.
		if ends_game or state.outs >= 3:
			if m.from > 0 and not ends_game:
				_leave_on_base(after, runner, m)
			continue
		out.applied[i] = 1
		# A base gained through an error or a passed ball does not count toward earned runs:
		# if he scores from where he should not have been, the run is unearned.
		var excused := m.on_error or event.kind == GameEvent.Kind.PASSED_BALL
		if excused and not m.is_out():
			runner.unearned = true
		if m.is_out():
			state.outs += 1
			out.outs_made += 1
		elif m.scores():
			if no_runs or state.outs >= 3:
				continue
			var run := ScoredRun.new()
			run.runner = runner
			run.from = m.from
			run.earned = not runner.unearned and not m.on_error and state.outs + state.phantom_outs < 3
			run.rbi = is_pa and not m.on_error and result != PaResult.Kind.DOUBLE_PLAY and result != PaResult.Kind.TRIPLE_PLAY
			out.scored.append(run)
			_add_run(state)
			# The home team going ahead in its last turn at bat ends the game at once; only a
			# home run brings every runner round.
			if _walk_off_now(state) and result != PaResult.Kind.HOME_RUN:
				ends_game = true
				winning_advance = 4 - m.from if m.from > 0 else 4
		else:
			after[m.to - 1] = runner
	state.bases = after

	if is_pa:
		state.count_batter_id = ""
		state.count_pitcher_id = ""
		state.count_at_relief = Vector2i(-1, -1)
		var bases := PaResult.hit_bases(result)
		out.credited_bases = bases
		if ends_game and bases > 0 and bases < 4:
			out.credited_bases = clampi(winning_advance, 1, bases)
		state.balls = 0
		state.strikes = 0
		state.order[state.batting()] = (state.order[state.batting()] + 1) % state.batting_team().lineup.size()
		state.batters_faced[pitcher] = int(state.batters_faced.get(pitcher, 0)) + 1
		state.pitch_counts[pitcher] = int(state.pitch_counts.get(pitcher, 0)) + event.pitches

	if _walk_off_now(state):
		out.walk_off = true
		_finish(state, GameState.HOME)
	elif state.outs >= 3:
		out.half_over = true
		out.left_on_base = state.runners_on()
		_end_half(state)
	out.game_over = state.over


## Puts a runner whose move was cut off by the third out on a free base: the one he was
## running to if he can have it, else the nearest one behind it.
static func _leave_on_base(after: Array[BaseRunner], runner: BaseRunner, m: RunnerMove) -> void:
	var furthest := clampi(m.to if m.to > 0 else m.out_at, m.from, 3)
	for base: int in range(furthest, 0, -1):
		if after[base - 1] == null:
			after[base - 1] = runner
			return


static func _walk_off_now(state: GameState) -> bool:
	return not state.top and state.inning >= state.rules.innings and state.home_lead() > 0


static func _add_run(state: GameState) -> void:
	var team := state.batting()
	state.score[team] += 1
	state.line[team][state.inning - 1] += 1


static func _end_half(state: GameState) -> void:
	state.bases = [null, null, null]
	state.outs = 0
	state.balls = 0
	state.strikes = 0
	state.phantom_outs = 0
	var lead := state.home_lead()
	if state.top:
		if state.inning >= state.rules.innings and lead > 0:
			# The home team is already ahead: the bottom half is not played.
			_finish(state, GameState.HOME)
			return
		state.top = false
	else:
		if state.inning >= state.rules.innings and lead != 0:
			_finish(state, GameState.HOME if lead > 0 else GameState.AWAY)
			return
		var limit := state.rules.extra_inning_limit
		if state.inning >= state.rules.innings and limit > 0 and state.inning >= limit:
			_finish(state, -1)
			return
		state.inning += 1
		state.top = true
	_open_half(state)


static func _open_half(state: GameState) -> void:
	var team := state.batting()
	while state.line[team].size() < state.inning:
		state.line[team].append(0)


static func _finish(state: GameState, winner: int) -> void:
	state.over = true
	state.winner = winner


## Walk, hit batsman, dropped third strike: the batter to first and only the runners who are
## forced move up, lead runner first.
static func forced_moves(state: GameState) -> Array[RunnerMove]:
	var moves: Array[RunnerMove] = []
	if not state.base_empty(1):
		if not state.base_empty(2):
			if not state.base_empty(3):
				moves.append(RunnerMove.make(3, 4))
			moves.append(RunnerMove.make(2, 3))
		moves.append(RunnerMove.make(1, 2))
	moves.append(RunnerMove.make(0, 1))
	return moves


## Wild pitch, passed ball, balk: every runner moves up one base, lead runner first.
static func everyone_advances(state: GameState, on_error: bool = false) -> Array[RunnerMove]:
	var moves: Array[RunnerMove] = []
	for base: int in [3, 2, 1]:
		if not state.base_empty(base):
			moves.append(RunnerMove.make(base, base + 1, RunnerMove.OutKind.NONE, on_error))
	return moves


## A batter may run on a dropped third strike only with first base open or with two out.
static func third_strike_can_run(state: GameState) -> bool:
	return state.base_empty(1) or state.outs == 2


## The infield fly rule is on: fewer than two out with runners on first and second (or the
## bases loaded). A fair fly an infielder can catch with ordinary effort is then an out
## whether caught or not, and runners may advance at their own risk.
static func infield_fly_applies(state: GameState) -> bool:
	return state.outs < 2 and not state.base_empty(1) and not state.base_empty(2)
