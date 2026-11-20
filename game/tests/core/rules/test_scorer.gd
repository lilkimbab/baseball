extends GutTest
## Official scoring: runs batted in, earned runs, and the winning, losing, saving and holding
## pitchers (docs/12 section 5.3, docs/13 S4-7).

const F := preload("res://tests/core/rules/rules_fixture.gd")
const FORCE := RunnerMove.OutKind.FORCE
const FLY := RunnerMove.OutKind.FLY


var state: GameState
var scorer: Scorer


func _new_game(rules: RuleSet = null) -> void:
	state = F.game(rules)
	scorer = Scorer.new()
	scorer.start(state)


func _play(e: GameEvent) -> FlowOutcome:
	var out := GameFlow.apply(state, e)
	scorer.record(state, e, out)
	return out


func _outs(n: int) -> void:
	for i: int in n:
		_play(F.pa(PaResult.Kind.STRIKEOUT, [F.move(0, -1, RunnerMove.OutKind.STRIKEOUT)] as Array[RunnerMove]))


func _half() -> void:
	F.three_outs(state, scorer)


func _change_pitcher(team: int, reliever: String) -> void:
	var t := state.teams[team]
	_play(GameEvent.substitution(team, GameEvent.Change.PITCHER, t.pitcher_id, reliever, Position.Kind.P))


func _run_scores(scored: int = 1) -> void:
	# Solo home runs.
	for i: int in scored:
		_play(F.pa(PaResult.Kind.HOME_RUN, [F.move(0, 4)] as Array[RunnerMove]))


func test_no_rbi_on_a_ground_ball_double_play() -> void:
	_new_game()
	F.put_runners(state, [1, 3])
	var batter := state.batter_id()
	_play(F.pa(PaResult.Kind.DOUBLE_PLAY, [F.move(3, 4), F.move(1, -1, FORCE), F.move(0, -1, FORCE)] as Array[RunnerMove]))
	assert_eq(state.score[0], 1, "the run scores")
	assert_eq(scorer.book.bat(batter).rbi, 0, "but the batter who hit into the double play gets no RBI")
	assert_eq(scorer.book.bat(batter).double_plays, 1)


func test_no_rbi_for_a_run_that_scores_on_an_error() -> void:
	_new_game()
	F.put_runners(state, [2])
	var batter := state.batter_id()
	_play(F.pa(PaResult.Kind.REACHED_ON_ERROR, [F.move(2, 4, RunnerMove.OutKind.NONE, true), F.move(0, 1)] as Array[RunnerMove]))
	assert_eq(scorer.book.bat(batter).rbi, 0)
	assert_eq(scorer.book.bat(batter).ab, 1, "reaching on an error is an at-bat")
	assert_eq(scorer.book.errors[1], 1, "the error is charged to the home team, in the field")


func test_a_sacrifice_fly_is_not_an_at_bat_but_counts_for_on_base() -> void:
	_new_game()
	F.put_runners(state, [3])
	var batter := state.batter_id()
	_play(F.pa(PaResult.Kind.SAC_FLY, [F.move(0, -1, FLY), F.move(3, 4)] as Array[RunnerMove]))
	var b := scorer.book.bat(batter)
	assert_eq(b.ab, 0)
	assert_eq(b.sac_flies, 1)
	assert_eq(b.rbi, 1)
	assert_eq(b.pa, 1)


func test_runs_of_inherited_runners_are_charged_to_the_pitcher_who_let_them_on() -> void:
	_new_game()
	var starter := state.pitcher_id()
	_play(F.pa(PaResult.Kind.WALK, [F.move(0, 1)] as Array[RunnerMove]))
	var reliever := state.fielding_team().bullpen[0]
	_change_pitcher(1, reliever)
	_play(F.pa(PaResult.Kind.HOME_RUN, [F.move(1, 4), F.move(0, 4)] as Array[RunnerMove]))
	assert_eq(scorer.book.pitch(starter).runs, 1, "the walked runner's run is the starter's")
	assert_eq(scorer.book.pitch(reliever).runs, 1)
	assert_eq(scorer.book.pitch(reliever).home_runs, 1)


func test_runs_after_two_outs_and_an_error_are_unearned() -> void:
	_new_game()
	var starter := state.pitcher_id()
	_outs(2)
	_play(F.pa(PaResult.Kind.REACHED_ON_ERROR, [F.move(0, 1)] as Array[RunnerMove]))
	_play(F.pa(PaResult.Kind.HOME_RUN, [F.move(1, 4), F.move(0, 4)] as Array[RunnerMove]))
	var p := scorer.book.pitch(starter)
	assert_eq(p.runs, 2)
	assert_eq(p.earned_runs, 0)


func test_a_starter_who_goes_five_innings_with_the_lead_gets_the_win() -> void:
	_new_game()
	_run_scores()
	var away_starter := state.teams[0].starter_id
	_half()
	for i: int in 5:
		_half()
		_half()
	# The away starter has pitched the bottom of the first five innings with a 1-0 lead; the
	# bullpen finishes.
	assert_eq(scorer.book.pitch(away_starter).outs, 15)
	_change_pitcher(0, state.teams[0].bullpen[0])
	while not state.over:
		_half()
	scorer.finish(state)
	assert_eq(state.winner, GameState.AWAY)
	assert_eq(scorer.book.winner_id, away_starter)
	assert_eq(scorer.book.loser_id, state.teams[1].starter_id)


func test_a_starter_short_of_five_innings_cannot_win() -> void:
	_new_game()
	_run_scores()
	_half()
	_half()
	_half()
	# Starter leaves after two innings with the lead.
	var long_man := state.teams[0].bullpen[0]
	_change_pitcher(0, long_man)
	while not state.over:
		_half()
	scorer.finish(state)
	assert_ne(scorer.book.winner_id, state.teams[0].starter_id)
	assert_eq(scorer.book.winner_id, long_man, "the reliever who got the most outs after the lead")


func test_a_closer_protecting_three_runs_for_an_inning_gets_the_save() -> void:
	_new_game()
	_run_scores(3)
	_half()
	for i: int in 8:
		_half()
		_half()
	# Top of the ninth is over at 3-0; bottom of the ninth, the closer comes in.
	assert_eq(state.inning, 9)
	assert_false(state.top)
	var closer := state.teams[0].bullpen[1]
	_change_pitcher(0, closer)
	_half()
	scorer.finish(state)
	assert_eq(scorer.book.save_id, closer)
	assert_eq(scorer.book.pitch(closer).saves, 1)


func test_no_save_for_a_four_run_lead_and_one_inning() -> void:
	_new_game()
	_run_scores(4)
	_half()
	for i: int in 8:
		_half()
		_half()
	var closer := state.teams[0].bullpen[1]
	_change_pitcher(0, closer)
	_half()
	scorer.finish(state)
	assert_eq(scorer.book.save_id, "")


func test_a_set_up_man_who_holds_the_lead_gets_a_hold() -> void:
	_new_game()
	_run_scores(2)
	_half()
	for i: int in 7:
		_half()
		_half()
	# Bottom of the 8th: set-up man; bottom of the 9th: closer.
	var setup := state.teams[0].bullpen[2]
	_change_pitcher(0, setup)
	_half()
	_half()
	var closer := state.teams[0].bullpen[1]
	_change_pitcher(0, closer)
	_half()
	scorer.finish(state)
	assert_true(scorer.book.hold_ids.has(setup))
	assert_eq(scorer.book.save_id, closer)


func test_a_box_score_adds_up() -> void:
	_new_game()
	_play(F.pa(PaResult.Kind.SINGLE, [F.move(0, 1)] as Array[RunnerMove]))
	_play(F.pa(PaResult.Kind.DOUBLE, [F.move(1, 4), F.move(0, 2)] as Array[RunnerMove]))
	_half()
	_half()
	var batting := scorer.book.team_batting(0)
	assert_eq(batting.hits, 2)
	assert_eq(scorer.book.hits[0], 2)
	assert_eq(batting.runs, 1)
	assert_eq(scorer.book.left_on_base[0], 1)
	var text := scorer.book.box_score(state)
	assert_string_contains(text, "R  H  E  B")


func test_a_strikeout_finished_by_a_pinch_hitter_with_two_strikes_is_the_first_batter_s() -> void:
	_new_game()
	var first := state.batter_id()
	_play(GameEvent.pitch(GameEvent.Call.CALLED_STRIKE))
	_play(GameEvent.pitch(GameEvent.Call.CALLED_STRIKE))
	var pinch := state.batting_team().bench[0]
	_play(GameEvent.substitution(0, GameEvent.Change.PINCH_HITTER, first, pinch, Position.Kind.PH))
	_play(F.pa(PaResult.Kind.STRIKEOUT, [F.move(0, -1, RunnerMove.OutKind.STRIKEOUT)] as Array[RunnerMove]))
	assert_eq(scorer.book.bat(first).strikeouts, 1)
	assert_eq(scorer.book.bat(first).ab, 1)
	assert_eq(scorer.book.bat(pinch).strikeouts, 0)


func test_a_walk_after_relieving_in_a_batter_s_count_is_the_first_pitcher_s() -> void:
	_new_game()
	var starter := state.pitcher_id()
	_play(GameEvent.pitch(GameEvent.Call.BALL))
	_play(GameEvent.pitch(GameEvent.Call.BALL))
	_play(GameEvent.pitch(GameEvent.Call.BALL))
	var reliever := state.fielding_team().bullpen[0]
	_change_pitcher(1, reliever)
	_play(F.pa(PaResult.Kind.WALK, [F.move(0, 1)] as Array[RunnerMove]))
	assert_eq(scorer.book.pitch(starter).walks, 1, "the walk is the starter's")
	assert_eq(scorer.book.pitch(reliever).walks, 0)
	assert_eq(state.runner_on(1).responsible_pitcher_id, starter, "and so is the runner")


func test_a_save_for_coming_in_with_the_tying_run_on_deck() -> void:
	_new_game()
	_run_scores(4)
	_half()
	for i: int in 8:
		_half()
		_half()
	# Bottom of the ninth, 4-0, two out and the bases loaded: the tying run is on deck.
	_outs(2)
	F.put_runners(state, [1, 2, 3])
	var closer := state.teams[0].bullpen[1]
	_change_pitcher(0, closer)
	_outs(1)
	scorer.finish(state)
	assert_eq(scorer.book.save_id, closer, "one out, but the tying run was on deck")


func test_a_save_for_three_innings_with_any_lead() -> void:
	_new_game()
	_run_scores(8)
	_half()
	for i: int in 6:
		_half()
		_half()
	# Bottom of the seventh, 8-0: the long man finishes three innings.
	var long_man := state.teams[0].bullpen[3]
	_change_pitcher(0, long_man)
	while not state.over:
		_half()
	scorer.finish(state)
	assert_eq(scorer.book.save_id, long_man)
