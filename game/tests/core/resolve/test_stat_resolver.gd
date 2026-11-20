extends GutTest
## The stat resolver, the computer manager and the league generator (docs/13 S4-9 to S4-12).

const F := preload("res://tests/core/rules/rules_fixture.gd")


func _average_player(id: String, pitcher: bool = false) -> Player:
	var p := Player.new()
	p.id = id
	p.name = id
	p.positions["SS"] = 100.0
	if pitcher:
		p.pitching = PitchingRatings.new()
		var fb := ArsenalPitch.new()
		fb.type = &"four_seam"
		fb.velo_avg = F.catalog()[&"four_seam"].speed_kmh
		fb.usage = 1.0
		p.pitching.arsenal.append(fb)
	return p


func _resolver(seed_value: int = 1) -> StatResolver:
	return StatResolver.new(F.env(), F.catalog(), F.manager(), Rng.new(seed_value))


func test_probabilities_add_up_to_one() -> void:
	var state := F.game()
	var p := _resolver().outcome_probabilities(state)
	var total := 0.0
	for x: float in p:
		assert_gte(x, 0.0)
		total += x
	assert_almost_eq(total, 1.0, 1e-9)


func test_two_average_players_give_the_league_rates() -> void:
	var state := F.game()
	var batter := state.batting_team().player(state.batter_id())
	var pitcher := state.fielding_team().player(state.pitcher_id())
	var avg_b := _average_player("b")
	avg_b.bats = &"S"
	var avg_p := _average_player("p", true)
	batter.batting = avg_b.batting
	batter.bats = &"R"
	pitcher.pitching = avg_p.pitching
	pitcher.throws = &"L"
	var env := F.env()
	var p := _resolver().outcome_probabilities(state)
	# Opposite hands; correct for the platoon and calibration factors, which are separate.
	for o: int in [LeagueEnv.Outcome.K, LeagueEnv.Outcome.BB, LeagueEnv.Outcome.HR] as Array[int]:
		var key := LeagueEnv.OUTCOME_KEYS[o]
		var expected := env.rates[o] * float(env.opposite_hand.get(key, 1.0)) * float(env.calibration.get(key, 1.0))
		assert_almost_eq(p[o], expected, expected * 0.02, key)


func test_a_strikeout_hitter_against_a_strikeout_pitcher_multiplies() -> void:
	var state := F.game()
	var batter := state.batting_team().player(state.batter_id())
	var pitcher := state.fielding_team().player(state.pitcher_id())
	var r := _resolver()
	batter.batting.contact_r = 50.0
	batter.batting.contact_l = 50.0
	var base := r.outcome_probabilities(state)[LeagueEnv.Outcome.K]
	batter.batting.contact_r = 35.0
	batter.batting.contact_l = 35.0
	var weak := r.outcome_probabilities(state)[LeagueEnv.Outcome.K]
	assert_almost_eq(weak / base, exp(0.28), 0.03, "one standard deviation less contact: 32% more strikeouts")


func test_the_same_seed_plays_the_same_game() -> void:
	var results: Array[String] = []
	for attempt: int in 2:
		var t := F.teams(3)
		var sim := GameSim.create(t[0], t[1], RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), Rng.new(42))
		sim.play()
		results.append("%d-%d %s" % [sim.state.score[0], sim.state.score[1], sim.scorer.book.winner_id])
	assert_eq(results[0], results[1])


func test_games_keep_their_books_straight() -> void:
	var t := F.teams(4)
	for g: int in 300:
		var sim := GameSim.create(t[g % 2], t[1 - g % 2], RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), Rng.new(1000 + g))
		sim.play()
		var s := sim.state
		var book := sim.scorer.book
		assert_true(s.over, "game %d finished" % g)
		for team: int in 2:
			var runs := 0
			for r: int in s.line[team]:
				runs += r
			assert_eq(runs, s.score[team], "line score adds up")
			var b := book.team_batting(team)
			assert_eq(b.runs, s.score[team], "batters' runs add up")
			assert_eq(book.team_pitching(1 - team).runs, s.score[team], "runs charged to the other side's pitchers")
			assert_eq(b.hits, book.hits[team])
			assert_eq(b.pa, b.ab + b.walks + b.intentional_walks + b.hit_by_pitch + b.sac_bunts + b.sac_flies, "plate appearances")
			assert_eq(s.teams[team].validate(), PackedStringArray(), "line-up still legal")
		# Every top half ends with three outs; the home side's last half may end early.
		var tops := s.line[0].size()
		assert_eq(book.team_pitching(1).outs, tops * 3, "outs recorded by the home pitchers")
		assert_lte(book.team_pitching(0).outs, s.line[1].size() * 3)
		if s.winner >= 0:
			assert_ne(book.winner_id, "", "a decided game has a winning pitcher")
			assert_ne(book.loser_id, "")
		if g > 40:
			break


func test_the_manager_takes_out_a_tired_starter() -> void:
	var state := F.game()
	var ai := F.manager()
	ai.start_game(state)
	var starter := state.pitcher_id()
	state.pitch_counts[starter] = 130
	var change := ai.next_change(state)
	assert_not_null(change)
	assert_eq(change.change, GameEvent.Change.PITCHER)
	assert_eq(change.out_id, starter)


func test_no_closer_with_a_fifteen_run_lead() -> void:
	var state := F.game()
	var ai := F.manager()
	ai.start_game(state)
	for i: int in 8:
		F.three_outs(state)
		F.three_outs(state)
	F.three_outs(state)
	state.score[0] = 15
	# Bottom of the ninth, away team ahead by 15: a reliever may come in, but not the closer.
	var relievers: Array[String] = state.teams[0].bullpen.duplicate()
	relievers.sort_custom(func(a: String, b: String) -> bool:
		return Overall.pitcher(state.teams[0].player(a), F.catalog()) > Overall.pitcher(state.teams[0].player(b), F.catalog()))
	var closer := relievers[0]
	var change := ai.next_change(state)
	assert_not_null(change, "the tired starter comes out")
	assert_eq(change.change, GameEvent.Change.PITCHER)
	assert_ne(change.in_id, closer, "but the closer is saved for a close game")


func test_the_last_catcher_is_never_batted_for() -> void:
	var state := F.game()
	var ai := F.manager()
	ai.start_game(state)
	var team := state.batting_team()
	# Make the catcher the batter, late and close, with a man on second.
	var catcher := team.fielder_at(Position.Kind.C)
	state.order[0] = team.slot_of(catcher)
	state.inning = 8
	F.put_runners(state, [2])
	for id: String in team.bench:
		team.player(id).positions.erase("C")
		team.player(id).batting.contact_r = 99.0
		team.player(id).batting.power_r = 99.0
	var change := ai.next_change(state)
	assert_true(change == null or change.change != GameEvent.Change.PINCH_HITTER, "nobody else can catch")


func test_no_intentional_walk_in_the_first_inning() -> void:
	var state := F.game()
	F.put_runners(state, [2])
	state.outs = 1
	assert_false(F.manager().wants_intentional_walk(state))


func test_the_same_seed_makes_the_same_league_and_every_club_is_legal() -> void:
	var names := RosterIO.load_names()
	var a := LeagueGenerator.new(names, F.catalog(), 9).league()
	var b := LeagueGenerator.new(names, F.catalog(), 9).league()
	assert_eq(a.size(), 30)
	for i: int in a.size():
		assert_eq(a[i].name, b[i].name)
		assert_eq(a[i].players[0].name, b[i].players[0].name)
	var ai := F.manager()
	for t: Team in a:
		assert_eq(t.players.size(), 28)
		var numbers: Dictionary[int, bool] = {}
		for p: Player in t.players:
			assert_false(numbers.has(p.number), "%s: numbers are unique" % t.name)
			numbers[p.number] = true
			if p.throws == &"L":
				for code: String in p.positions:
					assert_false(Position.needs_right_hand(Position.from_code(code)), "left-handed %s at %s" % [p.name, code])
		var lineup := ai.make_lineup(t, RuleSet.kbo_2026(), t.rotation()[0].id)
		assert_eq(lineup.validate(true), PackedStringArray(), t.name)


func test_a_small_batch_lands_near_the_league_targets() -> void:
	var gen := LeagueGenerator.new(RosterIO.load_names(), F.catalog(), 2026)
	var teams: Array[Team] = []
	for i: int in 30:
		teams.append(gen.team(i, 50.0))
	var report := BatchReport.run(teams, 600, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), Rng.new(3))
	var env := F.env()
	var pa := float(report.batting.pa)
	assert_almost_eq(report.batting.average(), env.targets["avg"], 0.015, "batting average")
	assert_almost_eq(report.runs / (report.games * 2.0), env.targets["runs_per_team_game"], 0.45, "runs per team per game")
	assert_almost_eq(report.batting.strikeouts / pa, env.rates[LeagueEnv.Outcome.K], 0.015, "strikeouts")
	assert_almost_eq((report.batting.walks + report.batting.intentional_walks) / pa, env.rates[LeagueEnv.Outcome.BB], 0.012, "walks")
	assert_almost_eq(report.batting.home_runs / pa, env.rates[LeagueEnv.Outcome.HR], 0.005, "home runs")


func test_a_roster_pack_reads_back_the_same() -> void:
	var gen := LeagueGenerator.new(RosterIO.load_names(), F.catalog(), 12)
	var teams: Array[Team] = [gen.team(0, 50.0), gen.team(1, 50.0)]
	var path := "user://roster_test.json"
	assert_eq(RosterIO.save_pack(path, "test", "시험", 2026, teams), OK)
	var back := RosterIO.load_pack(path)
	assert_eq(back.size(), 2)
	assert_eq(back[0].name, teams[0].name)
	assert_eq(back[0].players.size(), 28)
	for i: int in 28:
		var a := teams[0].players[i]
		var b := back[0].players[i]
		assert_eq(b.id, a.id)
		assert_eq(b.name, a.name)
		assert_eq(b.bats, a.bats)
		assert_eq(b.throws, a.throws)
		assert_eq(b.positions.keys(), a.positions.keys())
		assert_almost_eq(b.batting.eye, roundf(a.batting.eye), 0.001)
		assert_eq(b.is_pitcher(), a.is_pitcher())
		if a.is_pitcher():
			assert_eq(b.pitching.arsenal.size(), a.pitching.arsenal.size())
			assert_almost_eq(b.pitching.arsenal[0].velo_avg, a.pitching.arsenal[0].velo_avg, 0.06)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_an_all_average_player_is_fifty_overall() -> void:
	var p := _average_player("x")
	for kind: Position.Kind in [Position.Kind.C, Position.Kind.SS, Position.Kind.CF, Position.Kind.DH] as Array[Position.Kind]:
		p.positions[Position.code(kind)] = 100.0
		assert_almost_eq(F.overall().batter(p, kind), 50.0, 0.01, Position.code(kind))


func test_a_switch_hitter_bats_from_the_other_side() -> void:
	var p := _average_player("x")
	p.bats = &"S"
	assert_eq(p.batting_side(&"R"), &"L")
	assert_eq(p.batting_side(&"L"), &"R")
	p.bats = &"L"
	assert_eq(p.batting_side(&"L"), &"L")


func test_league_environments_load_by_name_and_add_up() -> void:
	var env := LeagueEnvIO.load_default("kbo_2025")
	assert_eq(env.name, "kbo_2025")
	var total := 0.0
	for r: float in env.rates:
		total += r
	assert_almost_eq(total, 1.0, 1e-9)
	assert_almost_eq(env.rates[LeagueEnv.Outcome.K], 0.198, 1e-6)
	assert_almost_eq(env.targets["era"], 4.31, 1e-6)


func test_a_thousand_games_keep_every_invariant() -> void:
	var gen := LeagueGenerator.new(RosterIO.load_names(), F.catalog(), 31)
	var teams: Array[Team] = []
	for i: int in 6:
		teams.append(gen.team(i, 50.0))
	var bad := PackedStringArray()
	for g: int in 1000:
		var sim := GameSim.create(teams[g % 6], teams[(g + 1 + g / 6) % 6] if (g + 1 + g / 6) % 6 != g % 6 else teams[(g + 2) % 6], RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), Rng.new(7000 + g))
		var reached := PackedInt32Array([0, 0])
		var runner_outs := PackedInt32Array([0, 0])
		var uncounted := PackedInt32Array([0, 0])
		var guard := 0
		while not sim.state.over and guard < GameSim.MAX_EVENTS:
			var event := sim.resolver.next_event(sim.state)
			var batting := sim.state.batting()
			var out := GameFlow.apply(sim.state, event)
			sim.scorer.record(sim.state, event, out)
			sim.manager.note_change(sim.state, event)
			var crossed := 0
			for i: int in event.moves.size():
				var m := event.moves[i]
				if out.applied.size() > i and out.applied[i] == 0:
					continue
				if m.from == 0 and m.to >= 1:
					reached[batting] += 1
				elif m.from > 0 and m.is_out():
					runner_outs[batting] += 1
				if m.scores():
					crossed += 1
			# A runner who crossed the plate on a play that ended with a force for the third out
			# is neither a run nor left on base.
			uncounted[batting] += crossed - out.scored.size()
			guard += 1
		sim.scorer.finish(sim.state)
		var s := sim.state
		var book := sim.scorer.book
		for t: int in 2:
			var line_runs := 0
			for r: int in s.line[t]:
				line_runs += r
			if line_runs != s.score[t]:
				bad.append("game %d: line score" % g)
			# Every runner who reaches either scores, is put out on the bases, or is left on.
			# The last half-inning of a walk-off leaves its runners neither out nor left on.
			var left := reached[t] - s.score[t] - runner_outs[t] - uncounted[t]
			if t == 0 or not (s.winner == GameState.HOME and s.inning >= s.rules.innings and s.line[1].size() == s.inning):
				if left != book.left_on_base[t]:
					bad.append("game %d team %d: reached %d - runs %d - outs on bases %d - uncounted %d = %d, box says %d left on" % [g, t, reached[t], s.score[t], runner_outs[t], uncounted[t], left, book.left_on_base[t]])
			if book.team_batting(t).pa != book.team_batting(t).ab + book.team_batting(t).walks + book.team_batting(t).intentional_walks + book.team_batting(t).hit_by_pitch + book.team_batting(t).sac_bunts + book.team_batting(t).sac_flies:
				bad.append("game %d: plate appearances" % g)
		if book.team_pitching(1).outs != s.line[0].size() * 3:
			bad.append("game %d: home pitchers' outs %d for %d top halves" % [g, book.team_pitching(1).outs, s.line[0].size()])
		if s.winner >= 0 and (book.winner_id == "" or book.loser_id == ""):
			bad.append("game %d: no decision" % g)
		if bad.size() > 5:
			break
	assert_eq(bad, PackedStringArray())
