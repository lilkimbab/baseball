extends GutTest
## The bullpen (docs/08 R4): relievers get ready by throwing while the game goes on, cool off
## when they stop, and one who comes in before he is ready is wild and a little slow for his
## first batters. The computer manager warms the right man before he needs him.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func _pitch(state: GameState, call: GameEvent.Call = GameEvent.Call.BALL) -> void:
	GameFlow.apply(state, GameEvent.pitch(call))
	if state.balls >= 3:
		state.balls = 0


func test_a_reliever_is_ready_after_about_fifteen_pitches_and_cools_off_after() -> void:
	var state := F.game()
	var t := state.fielding()
	var id := state.teams[t].bullpen[0]
	state.set_warming(t, PackedStringArray([id]))
	for i: int in 7:
		_pitch(state)
	assert_between(state.warmth_of(t, id), 0.4, 0.55, "half way")
	for i: int in 10:
		_pitch(state)
	assert_almost_eq(state.warmth_of(t, id), 1.0, 1e-6, "ready")
	state.set_warming(t, PackedStringArray())
	for i: int in 30:
		_pitch(state)
	assert_between(state.warmth_of(t, id), 0.4, 0.6, "cooling once he stops")


func test_no_more_than_two_throw_at_once_and_never_the_man_pitching() -> void:
	var state := F.game()
	var t := state.fielding()
	var team := state.teams[t]
	var ids := PackedStringArray([team.pitcher_id, team.bullpen[0], team.bullpen[1], team.bullpen[2]])
	state.set_warming(t, ids)
	assert_eq(state.warming[t], PackedStringArray([team.bullpen[0], team.bullpen[1]]))


func test_a_cold_reliever_is_wild_at_first_and_himself_after_a_dozen_pitches() -> void:
	var state := F.game()
	var t := state.fielding()
	var cold_id := state.teams[t].bullpen[0]
	GameFlow.apply(state, SubstitutionOptions.pitcher_change(state, t, cold_id))
	# Cold from the bullpen, his warm-up throws on the mound only.
	assert_almost_eq(float(state.entered_warmth[cold_id]), GameState.MOUND_WARMUP, 1e-6)
	var first := state.cold(cold_id)
	assert_almost_eq(first, 1.0 - GameState.MOUND_WARMUP, 1e-6)
	var team := state.fielding_team()
	var p := team.player(cold_id)
	assert_gt(StatResolver.fatigue(state, team, p), 0.7, "pitches as if tired")
	for i: int in 12:
		_pitch(state)
	assert_almost_eq(state.cold(cold_id), 0.0, 1e-6, "settled")
	# The starter was never cold.
	assert_eq(state.cold(state.teams[t].starter_id), 0.0)


func test_a_warm_reliever_comes_in_ready() -> void:
	var state := F.game()
	var t := state.fielding()
	var id := state.teams[t].bullpen[1]
	state.set_warming(t, PackedStringArray([id]))
	for i: int in 16:
		_pitch(state)
	GameFlow.apply(state, SubstitutionOptions.pitcher_change(state, t, id))
	assert_eq(state.cold(id), 0.0)
	assert_false(state.warming[t].has(id), "off the bullpen list once he is in")


func test_a_cold_reliever_walks_more_batters() -> void:
	var state := F.game()
	var resolver := StatResolver.new(F.env(), F.catalog(), F.manager(), Rng.new(1))
	var t := state.fielding()
	var id := state.teams[t].bullpen[0]
	GameFlow.apply(state, SubstitutionOptions.pitcher_change(state, t, id))
	var cold := resolver.outcome_probabilities(state)
	state.entered_warmth[id] = 1.0
	var ready := resolver.outcome_probabilities(state)
	assert_gt(cold[LeagueEnv.Outcome.BB], ready[LeagueEnv.Outcome.BB] * 1.05, "more walks")
	assert_lt(cold[LeagueEnv.Outcome.OUT], ready[LeagueEnv.Outcome.OUT], "fewer outs")


func test_the_computer_warms_the_next_man_when_the_starter_tires_and_the_closer_for_a_save() -> void:
	var state := F.game()
	var ai := F.manager()
	ai.start_game(state)
	var t := state.fielding()
	var team := state.teams[t]
	ai.plan_bullpen(state, t)
	assert_true(state.warming[t].is_empty(), "nobody early in a quiet game")
	var starter := team.player(team.pitcher_id)
	state.pitch_counts[team.pitcher_id] = int(starter.pitching.starter_limit() * 0.8)
	ai.plan_bullpen(state, t)
	assert_eq(state.warming[t].size(), 1, "the next man warms as the starter tires")
	# The ninth, a two-run lead: the closer.
	var close := F.game()
	ai.start_game(close)
	var ct := close.fielding()
	close.inning = 9
	close.top = ct == GameState.HOME
	close.score[ct] = 3
	close.score[1 - ct] = 1
	ai.plan_bullpen(close, ct)
	assert_true(close.warming[ct].has(ai._closer[ct]), "the closer is up")


func test_a_ready_man_comes_in_before_a_cold_first_choice() -> void:
	var state := F.game()
	var ai := F.manager()
	ai.start_game(state)
	var t := state.fielding()
	var team := state.teams[t]
	var first := ai._pick_reliever(state, t, false)
	var other := ""
	for id: String in team.bullpen:
		if id != first and id != ai._closer[t]:
			other = id
			break
	state.warmth[t][other] = 1.0
	assert_eq(ai._pick_reliever(state, t), other, "the warm one")
	state.warmth[t][first] = 1.0
	assert_eq(ai._pick_reliever(state, t), first, "both warm: the first choice")
