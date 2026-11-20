extends GutTest
## The rules of play: the count, forced runners, when runs count, the end of innings and of
## the game (docs/13 S4-6).

const F := preload("res://tests/core/rules/rules_fixture.gd")
const NONE := RunnerMove.OutKind.NONE
const FORCE := RunnerMove.OutKind.FORCE
const TAG := RunnerMove.OutKind.TAG
const FLY := RunnerMove.OutKind.FLY


func _apply(state: GameState, e: GameEvent) -> FlowOutcome:
	return GameFlow.apply(state, e)


func test_rules_default_to_the_kbo_in_2026() -> void:
	var r := RuleSet.kbo_2026()
	assert_eq(r.innings, 9)
	assert_eq(r.extra_inning_limit, 11, "regular season ends in a tie after 11")
	assert_true(r.designated_hitter)
	assert_almost_eq(r.zone_top_ratio, 0.5575, 1e-6)
	assert_almost_eq(r.zone_bottom_ratio, 0.2704, 1e-6)
	assert_eq(r.pitch_clock_empty, 18)
	assert_eq(r.pitch_clock_runners, 23)
	assert_eq(r.between_batters, 33)
	assert_eq(r.batter_ready, 8)
	assert_eq(r.inning_break, 130)
	assert_eq(r.batter_timeouts, 2)
	assert_eq(r.active_roster, 28)
	var short := RuleSet.short_game(3)
	assert_eq(short.innings, 3)
	assert_eq(short.extra_inning_limit, 5, "a short game goes two extra innings at most")
	assert_eq(short.designated_hitter, r.designated_hitter)
	assert_eq(r.starter_win_innings(), 5)


func test_four_balls_walk_and_three_strikes_strike_out() -> void:
	var s := F.game()
	for i: int in 3:
		assert_eq(_apply(s, GameEvent.pitch(GameEvent.Call.BALL)).completes, PaResult.Kind.NONE)
	assert_eq(_apply(s, GameEvent.pitch(GameEvent.Call.BALL)).completes, PaResult.Kind.WALK)
	s = F.game()
	_apply(s, GameEvent.pitch(GameEvent.Call.CALLED_STRIKE))
	_apply(s, GameEvent.pitch(GameEvent.Call.SWINGING_STRIKE))
	assert_eq(_apply(s, GameEvent.pitch(GameEvent.Call.CALLED_STRIKE)).completes, PaResult.Kind.STRIKEOUT)


func test_a_foul_with_two_strikes_keeps_the_count_but_a_foul_bunt_strikes_out() -> void:
	var s := F.game()
	_apply(s, GameEvent.pitch(GameEvent.Call.FOUL))
	_apply(s, GameEvent.pitch(GameEvent.Call.FOUL))
	assert_eq(s.strikes, 2)
	for i: int in 5:
		assert_eq(_apply(s, GameEvent.pitch(GameEvent.Call.FOUL)).completes, PaResult.Kind.NONE)
	assert_eq(s.strikes, 2)
	assert_eq(_apply(s, GameEvent.pitch(GameEvent.Call.FOUL_BUNT)).completes, PaResult.Kind.STRIKEOUT)


func test_a_bases_loaded_walk_forces_in_a_run_but_first_and_third_does_not() -> void:
	var s := F.game()
	F.put_runners(s, [1, 2, 3])
	var walk: Array[RunnerMove] = [F.move(3, 4), F.move(2, 3), F.move(1, 2), F.move(0, 1)]
	var out := _apply(s, F.pa(PaResult.Kind.WALK, walk))
	assert_eq(out.scored.size(), 1)
	assert_true(out.scored[0].rbi, "a run forced in by a walk is batted in")
	s = F.game()
	F.put_runners(s, [1, 3])
	var third := s.runner_on(3).player_id
	out = _apply(s, F.pa(PaResult.Kind.WALK, [F.move(1, 2), F.move(0, 1)] as Array[RunnerMove]))
	assert_eq(out.scored.size(), 0)
	assert_eq(s.runner_on(3).player_id, third, "the runner on third is not forced and stays")


func test_no_run_scores_when_the_third_out_is_a_force() -> void:
	var s := F.game()
	s.outs = 2
	F.put_runners(s, [1, 3])
	var moves: Array[RunnerMove] = [F.move(3, 4), F.move(1, -1, FORCE), F.move(0, 1)]
	var out := _apply(s, F.pa(PaResult.Kind.FIELDERS_CHOICE, moves))
	assert_eq(out.scored.size(), 0, "the runner crossed the plate, but the inning ended on a force")
	assert_eq(s.score[0], 0)
	assert_true(out.half_over)


func test_a_run_counts_when_it_scores_before_a_third_out_made_by_tag() -> void:
	var s := F.game()
	s.outs = 2
	F.put_runners(s, [2, 3])
	# Single: the runner from third scores, the runner from second is thrown out at home.
	var moves: Array[RunnerMove] = [F.move(3, 4), F.move(2, -1, TAG), F.move(0, 1)]
	var out := _apply(s, F.pa(PaResult.Kind.SINGLE, moves))
	assert_eq(out.scored.size(), 1)
	assert_eq(s.score[0], 1)


func test_no_run_scores_when_the_batter_is_the_third_out_before_reaching_first() -> void:
	var s := F.game()
	s.outs = 2
	F.put_runners(s, [3])
	var out := _apply(s, F.pa(PaResult.Kind.GROUND_OUT, [F.move(3, 4), F.move(0, -1, FORCE)] as Array[RunnerMove]))
	assert_eq(out.scored.size(), 0)


func test_a_run_counts_when_the_batter_is_thrown_out_stretching_for_the_third_out() -> void:
	var s := F.game()
	s.outs = 2
	F.put_runners(s, [3])
	# Single; the run scores, then the batter is thrown out trying for second.
	var moves: Array[RunnerMove] = [F.move(3, 4), RunnerMove.out_at_base(0, 2, TAG)]
	var out := _apply(s, F.pa(PaResult.Kind.SINGLE, moves))
	assert_eq(out.scored.size(), 1, "he had reached first: a timing play, the run counts")
	var again := F.game()
	again.outs = 2
	F.put_runners(again, [3])
	var at_first: Array[RunnerMove] = [F.move(3, 4), RunnerMove.out_at_base(0, 1, TAG)]
	assert_eq(_apply(again, F.pa(PaResult.Kind.GROUND_OUT, at_first)).scored.size(), 0, "out before first: no run")


func test_a_double_play_that_ends_the_inning_scores_no_run() -> void:
	var s := F.game()
	s.outs = 1
	F.put_runners(s, [1, 2, 3])
	var dp: Array[RunnerMove] = [F.move(3, 4), F.move(2, 3), F.move(1, -1, FORCE), F.move(0, -1, FORCE)]
	var out := _apply(s, F.pa(PaResult.Kind.DOUBLE_PLAY, dp))
	assert_eq(out.scored.size(), 0)
	assert_eq(out.outs_made, 2)
	assert_true(out.half_over)


func test_the_batting_order_carries_over_to_the_next_inning() -> void:
	var s := F.game()
	for i: int in 4:
		_apply(s, F.pa(PaResult.Kind.SINGLE, [F.move(0, 1)] as Array[RunnerMove]))
	F.three_outs(s)
	assert_false(s.top)
	F.three_outs(s)
	assert_eq(s.inning, 2)
	assert_eq(s.order[0], 7, "four singles and three outs: the eighth batter leads off the 2nd")


func test_a_runner_caught_stealing_for_the_third_out_leaves_the_batter_to_lead_off() -> void:
	var s := F.game()
	s.outs = 2
	F.put_runners(s, [1])
	var batter := s.batter_id()
	var out := _apply(s, GameEvent.running(GameEvent.Kind.STEAL, [F.move(1, -1, TAG)] as Array[RunnerMove]))
	assert_true(out.half_over)
	F.three_outs(s)
	assert_eq(s.batter_id(), batter, "his turn at bat never finished, so he leads off")


func test_the_home_team_does_not_bat_in_the_ninth_when_it_is_already_ahead() -> void:
	var s := F.game()
	for i: int in 8:
		F.three_outs(s)
		F.three_outs(s)
	s.score[1] = 2
	F.three_outs(s)
	assert_true(s.over, "game over after the top of the ninth")
	assert_eq(s.winner, GameState.HOME)
	assert_eq(s.line[1].size(), 8, "the bottom of the ninth is not played (X)")


func test_a_walk_off_hit_ends_the_game_and_counts_only_the_winning_run() -> void:
	var s := F.game()
	for i: int in 8:
		F.three_outs(s)
		F.three_outs(s)
	F.three_outs(s)
	assert_eq(s.inning, 9)
	assert_false(s.top)
	F.put_runners(s, [1, 2, 3])
	# Tied game, bases loaded: a ball into the gap would be a double, but the game ends as
	# soon as the runner from third scores.
	var hit: Array[RunnerMove] = [F.move(3, 4), F.move(2, 4), F.move(1, 3), F.move(0, 2)]
	var out := _apply(s, F.pa(PaResult.Kind.DOUBLE, hit))
	assert_true(s.over)
	assert_true(out.walk_off)
	assert_eq(s.score[1], 1, "only the winning run counts")
	assert_eq(out.credited_bases, 1, "the batter is credited with as many bases as the winning run advanced")


func test_a_walk_off_home_run_counts_every_run() -> void:
	var s := F.game()
	for i: int in 8:
		F.three_outs(s)
		F.three_outs(s)
	F.three_outs(s)
	F.put_runners(s, [1, 2])
	var hr: Array[RunnerMove] = [F.move(2, 4), F.move(1, 4), F.move(0, 4)]
	var out := _apply(s, F.pa(PaResult.Kind.HOME_RUN, hr))
	assert_true(s.over)
	assert_eq(s.score[1], 3)
	assert_eq(out.credited_bases, 4)


func test_a_tie_after_eleven_innings_is_a_draw() -> void:
	var s := F.game()
	for i: int in 11:
		F.three_outs(s)
		F.three_outs(s)
	assert_true(s.over)
	assert_eq(s.winner, -1)
	assert_eq(s.inning, 11)
	var limitless := RuleSet.kbo_2026()
	limitless.extra_inning_limit = 0
	s = F.game(limitless)
	for i: int in 12:
		F.three_outs(s)
		F.three_outs(s)
	assert_false(s.over, "without a limit the game goes on")


func test_runs_after_an_error_would_have_ended_the_inning_are_unearned() -> void:
	var s := F.game()
	s.outs = 2
	# A routine grounder is booted: it should have been the third out.
	_apply(s, F.pa(PaResult.Kind.REACHED_ON_ERROR, [F.move(0, 1)] as Array[RunnerMove]))
	assert_eq(s.phantom_outs, 1)
	var out := _apply(s, F.pa(PaResult.Kind.HOME_RUN, [F.move(1, 4), F.move(0, 4)] as Array[RunnerMove]))
	assert_eq(out.scored.size(), 2)
	assert_false(out.scored[0].earned)
	assert_false(out.scored[1].earned, "the inning should already have been over")


func test_a_batter_who_forces_out_an_inherited_runner_inherits_his_pitcher() -> void:
	var s := F.game()
	F.put_runners(s, [1])
	var old_pitcher := s.pitcher_id()
	var reliever := s.fielding_team().bullpen[0]
	_apply(s, GameEvent.substitution(s.fielding(), GameEvent.Change.PITCHER, old_pitcher, reliever, Position.Kind.P))
	_apply(s, F.pa(PaResult.Kind.FIELDERS_CHOICE, [F.move(1, -1, FORCE), F.move(0, 1)] as Array[RunnerMove]))
	assert_eq(s.runner_on(1).responsible_pitcher_id, old_pitcher, "the runner on first is still the old pitcher's")


func test_a_pinch_runner_takes_the_runner_s_place_and_his_pitcher() -> void:
	var s := F.game()
	F.put_runners(s, [2])
	var runner := s.runner_on(2)
	var team := s.batting_team()
	var fast := team.bench[0]
	_apply(s, GameEvent.substitution(s.batting(), GameEvent.Change.PINCH_RUNNER, runner.player_id, fast, Position.Kind.PR))
	assert_eq(s.runner_on(2).player_id, fast)
	assert_eq(s.runner_on(2).responsible_pitcher_id, runner.responsible_pitcher_id)
	assert_true(team.removed.has(runner.player_id))


func test_a_copy_of_the_state_is_independent() -> void:
	var s := F.game()
	F.put_runners(s, [1])
	var copy := s.duplicate_state()
	_apply(copy, F.pa(PaResult.Kind.HOME_RUN, [F.move(1, 4), F.move(0, 4)] as Array[RunnerMove]))
	copy.teams[1].change_pitcher(copy.teams[1].bullpen[0])
	assert_eq(s.score[0], 0, "the original's score is untouched")
	assert_not_null(s.runner_on(1), "and its runner is still on first")
	assert_eq(s.teams[1].pitcher_id, s.teams[1].starter_id)
	assert_eq(s.order[0], 0)


func test_events_survive_a_round_trip_through_a_dictionary() -> void:
	var events: Array[GameEvent] = [
		F.pa(PaResult.Kind.DOUBLE_PLAY, [F.move(3, 4), F.move(1, -1, FORCE), F.move(0, -1, FORCE)] as Array[RunnerMove]),
		GameEvent.pitch(GameEvent.Call.FOUL_BUNT),
		GameEvent.substitution(1, GameEvent.Change.DEFENSE, "a", "b", Position.Kind.SS),
		GameEvent.running(GameEvent.Kind.STEAL, [F.move(1, 2)] as Array[RunnerMove]),
		F.pa(PaResult.Kind.REACHED_ON_ERROR, [F.move(2, 4, NONE, true), F.move(0, 1)] as Array[RunnerMove]),
	]
	events[0].fielders = "6-4-3"
	events[0].direction = 6
	for e: GameEvent in events:
		var back := EventIO.from_dictionary(JSON.parse_string(JSON.stringify(EventIO.to_dictionary(e))))
		assert_eq(back.kind, e.kind)
		assert_eq(back.result, e.result)
		assert_eq(back.call, e.call)
		assert_eq(back.change, e.change)
		assert_eq(back.in_id, e.in_id)
		assert_eq(back.position, e.position)
		assert_eq(back.fielders, e.fielders)
		assert_eq(back.direction, e.direction)
		assert_eq(back.moves.size(), e.moves.size())
		for i: int in e.moves.size():
			assert_eq([back.moves[i].from, back.moves[i].to, back.moves[i].out_kind, back.moves[i].on_error], [e.moves[i].from, e.moves[i].to, e.moves[i].out_kind, e.moves[i].on_error])


func test_a_replayed_game_ends_the_same() -> void:
	var t := F.teams(8)
	var sim := GameSim.create(t[0], t[1], RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), Rng.new(5))
	var saved: Array = []
	var start := sim.state.duplicate_state()
	while not sim.state.over:
		var e := sim.resolver.next_event(sim.state)
		saved.append(EventIO.to_dictionary(e))
		var out := GameFlow.apply(sim.state, e)
		sim.scorer.record(sim.state, e, out)
		sim.manager.note_change(sim.state, e)
	for d: Dictionary in saved:
		GameFlow.apply(start, EventIO.from_dictionary(d))
	assert_true(start.over)
	assert_eq(start.score, sim.state.score)
	assert_eq(start.line, sim.state.line)


func test_a_batter_may_run_on_a_dropped_third_strike_only_with_first_open_or_two_out() -> void:
	var s := F.game()
	assert_true(GameFlow.third_strike_can_run(s), "first base open")
	F.put_runners(s, [1])
	assert_false(GameFlow.third_strike_can_run(s), "first occupied, less than two out")
	s.outs = 2
	assert_true(GameFlow.third_strike_can_run(s), "two out")


func test_the_infield_fly_rule_needs_runners_on_first_and_second_and_less_than_two_out() -> void:
	var s := F.game()
	F.put_runners(s, [1])
	assert_false(GameFlow.infield_fly_applies(s))
	F.put_runners(s, [1, 2])
	assert_true(GameFlow.infield_fly_applies(s))
	s.outs = 2
	assert_false(GameFlow.infield_fly_applies(s))


func test_a_runner_tags_up_and_scores_on_a_caught_fly() -> void:
	var s := F.game()
	F.put_runners(s, [3])
	var out := _apply(s, F.pa(PaResult.Kind.SAC_FLY, [F.move(0, -1, FLY), F.move(3, 4)] as Array[RunnerMove]))
	assert_eq(out.scored.size(), 1)
	assert_eq(s.outs, 1)
	# With two out the catch ends the inning first: no run.
	s = F.game()
	s.outs = 2
	F.put_runners(s, [3])
	out = _apply(s, F.pa(PaResult.Kind.FLY_OUT, [F.move(0, -1, FLY), F.move(3, 4)] as Array[RunnerMove]))
	assert_eq(out.scored.size(), 0)


func test_the_zone_follows_the_rule_set() -> void:
	var rules := RuleSet.kbo_2026()
	rules.zone_top_ratio = 0.6
	rules.zone_side_margin = 0.0
	var zone := StrikeZone.for_batter(1.8, rules)
	assert_almost_eq(zone.top, 1.08, 1e-6)
	assert_almost_eq(zone.half_width * 2.0, Field.PLATE_WIDTH, 1e-6)


func test_nothing_counts_after_the_third_out() -> void:
	var s := F.game()
	s.outs = 2
	F.put_runners(s, [1, 2])
	# Two out: both runners are thrown out trying for an extra base on the same single.
	var moves: Array[RunnerMove] = [F.move(2, -1, TAG), F.move(1, -1, TAG), F.move(0, 1)]
	var out := _apply(s, F.pa(PaResult.Kind.SINGLE, moves))
	assert_eq(out.outs_made, 1, "the inning ended with the first of them")
	assert_true(out.half_over)
	assert_eq(s.outs, 0, "and the next half-inning starts clean")


func test_a_runner_who_takes_an_extra_base_on_an_error_scores_an_unearned_run() -> void:
	var s := F.game()
	F.put_runners(s, [2])
	# He reaches third only because of a throwing error, then scores on a fly ball.
	_apply(s, F.pa(PaResult.Kind.GROUND_OUT, [F.move(2, 3, NONE, true), F.move(0, -1, FORCE)] as Array[RunnerMove]))
	var out := _apply(s, F.pa(PaResult.Kind.SAC_FLY, [F.move(0, -1, FLY), F.move(3, 4)] as Array[RunnerMove]))
	assert_eq(out.scored.size(), 1)
	assert_false(out.scored[0].earned)


func test_a_run_that_scores_on_a_passed_ball_is_unearned() -> void:
	var s := F.game()
	F.put_runners(s, [3])
	var out := _apply(s, GameEvent.running(GameEvent.Kind.PASSED_BALL, [F.move(3, 4)] as Array[RunnerMove]))
	assert_eq(out.scored.size(), 1)
	assert_false(out.scored[0].earned)
	assert_false(out.scored[0].rbi)
