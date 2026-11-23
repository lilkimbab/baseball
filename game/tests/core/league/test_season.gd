extends GutTest
## A season played a day at a time.

const F := preload("res://tests/core/rules/rules_fixture.gd")

static var _played: Season


func _division(seed_value: int = 4) -> Array[Team]:
	var gen := LeagueGenerator.new(RosterIO.load_names(), F.catalog(), seed_value)
	var teams: Array[Team] = []
	for i: int in 10:
		teams.append(gen.team(i, 50.0))
	return teams


## One 36-game season, played once and shared by the tests that only read it.
func _short_season() -> Season:
	if _played == null:
		_played = Season.create(_division(), 10, 36, 5, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall())
		_played.play_to_end()
	return _played


func test_a_short_season_plays_every_game_and_the_table_adds_up() -> void:
	var s := _short_season()
	assert_true(s.finished())
	var wins := 0
	var losses := 0
	for row: StandingsRow in s.standings[0].ranked():
		assert_eq(row.games(), 36, row.team_id)
		wins += row.wins
		losses += row.losses
	assert_eq(wins, losses)
	var runs := 0
	for g: ScheduledGame in s.schedules[0].games:
		runs += g.away_score + g.home_score
		assert_true(g.innings <= RuleSet.kbo_2026().extra_inning_limit or not g.is_tie())
	var rf := 0
	for row: StandingsRow in s.standings[0].rows.values():
		rf += row.runs_for
	assert_eq(rf, runs)


func test_relievers_never_pitch_three_days_running_or_the_day_after_thirty_pitches() -> void:
	# Day by day, checking each outing against the ones before it.
	var fresh := Season.create(_division(), 10, 36, 6, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall())
	var pitched: Dictionary[String, Dictionary] = {}
	while fresh.day < fresh.total_days():
		for g: ScheduledGame in fresh.games_today():
			var sim := fresh.prepare(g)
			sim.play()
			fresh.record(g, sim.state, sim.scorer.book)
			for id: String in sim.scorer.book.pitching:
				if not pitched.has(id):
					pitched[id] = {}
				pitched[id][g.day] = sim.scorer.book.pitching[id].pitches
				var starter := sim.state.teams[0].starter_id == id or sim.state.teams[1].starter_id == id
				if starter:
					var days: Dictionary = pitched[id]
					for d: int in range(g.day - PitcherUsage.STARTER_REST, g.day):
						assert_false(days.has(d), "starter %s rested before day %d" % [id, g.day])
				else:
					var days: Dictionary = pitched[id]
					assert_false(days.has(g.day - 1) and days.has(g.day - 2), "%s three days running on day %d" % [id, g.day])
					assert_false(int(days.get(g.day - 1, 0)) >= PitcherUsage.HEAVY, "%s the day after %d pitches" % [id, days.get(g.day - 1, 0)])
		fresh.advance()
	assert_gt(pitched.size(), 60)


func test_second_team_players_never_play() -> void:
	var s := _short_season()
	for t: Team in s.teams.values():
		for p: Player in t.second_team():
			assert_false(s.book.batting.has(p.id), "%s is on the second team" % p.name)
			assert_false(s.book.pitching.has(p.id), "%s is on the second team" % p.name)


func test_the_rotation_turns_over_and_nobody_skips_a_turn_for_long() -> void:
	var s := _short_season()
	for t: Team in s.teams.values():
		for p: Player in t.rotation():
			var line: PitchingLine = s.book.pitching.get(p.id)
			assert_not_null(line, "%s started" % p.name)
			if line != null:
				# 36 games among five starters: about seven each.
				assert_between(line.starts, 5, 9, "%s %s starts" % [t.short_name, p.name])


func test_my_game_is_left_for_me_and_the_others_are_played() -> void:
	var s := Season.create(_division(), 10, 36, 2, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall())
	s.my_team = s.divisions[0][3]
	var mine := s.play_day()
	assert_not_null(mine)
	assert_true(mine.involves(s.my_team))
	assert_false(mine.played)
	for g: ScheduledGame in s.games_today():
		if g != mine:
			assert_true(g.played)
	# Played on screen and handed back.
	var sim := s.prepare(mine)
	sim.play()
	s.record(mine, sim.state, sim.scorer.book)
	assert_true(mine.played)
	assert_eq(s.standings[0].row(s.my_team).games(), 1)


func test_a_tired_reliever_plays_below_his_best_and_a_rested_one_sits() -> void:
	var s := Season.create(_division(), 10, 36, 2, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall())
	var team: Team = s.teams.values()[0]
	var relievers: Array[Player] = []
	for p: Player in team.first_team():
		if p.role() == &"RP":
			relievers.append(p)
	var worked := relievers[0]
	var twice := relievers[1]
	s.usage.note(worked.id, 9, 18)
	s.usage.note(twice.id, 8, 15)
	s.usage.note(twice.id, 9, 12)
	assert_eq(s.usage.reliever_status(worked.id, 10), PitcherUsage.Status.TIRED)
	assert_eq(s.usage.reliever_status(twice.id, 10), PitcherUsage.Status.REST)
	var squad := s.squad_for(team, 10, team.rotation()[0].id)
	assert_null(squad.player(twice.id), "third day running is not allowed")
	var tired := squad.player(worked.id)
	if tired != null:
		assert_lt(tired.pitching.control, worked.pitching.control)
		assert_ne(tired, worked, "a copy for the day; the club's player is untouched")


func test_pitcher_usage_rules() -> void:
	var u := PitcherUsage.new()
	u.note("a", 3, 20)
	assert_eq(u.reliever_status("a", 4), PitcherUsage.Status.TIRED)
	assert_eq(u.reliever_status("a", 5), PitcherUsage.Status.FRESH)
	u.note("a", 4, 10)
	assert_eq(u.reliever_status("a", 5), PitcherUsage.Status.REST, "two days running, then a day off")
	u.note("b", 3, PitcherUsage.HEAVY)
	assert_eq(u.reliever_status("b", 4), PitcherUsage.Status.REST, "30 pitches: rest the next day")
	u.note("c", 2, PitcherUsage.LONG)
	assert_eq(u.reliever_status("c", 4), PitcherUsage.Status.REST, "a long outing: two days")
	# Sunday then Tuesday is not two days running: Monday is off.
	u.note("d", 5, 15)
	assert_eq(u.reliever_status("d", 7), PitcherUsage.Status.FRESH)
	u.note("s", 0, 95)
	assert_false(u.can_start("s", 4))
	assert_true(u.can_start("s", 5))
	assert_eq(u.recent_pitches("a", 5), PackedInt32Array([0, 20, 10]))


func test_registration_follows_the_kbo_rules() -> void:
	var rules := RuleSet.kbo_2026()
	var team := _division()[0]
	assert_eq(team.registered.size(), rules.registered_roster)
	var down := team.second_team()[0]
	assert_ne(team.registration_problem(down.id, 0, rules), "", "the first team is full")
	var regular := team.first_team()[20]
	assert_true(team.unregister(regular.id, 3))
	assert_false(team.is_registered(regular.id))
	assert_ne(team.registration_problem(regular.id, 12, rules), "", "ten days before he can come back")
	assert_eq(team.registration_problem(regular.id, 13, rules), "")
	assert_true(team.register(down.id, 4, rules))
	assert_true(team.is_registered(down.id))
	# A fourth foreign player cannot be registered.
	var spare := LeagueGenerator.new(RosterIO.load_names(), F.catalog(), 3).player("RP", 50.0, &"foreign")
	spare.id = "spare"
	team.players.append(spare)
	assert_true(team.unregister(team.first_team()[25].id, 5))
	assert_string_contains(team.registration_problem(spare.id, 30, rules), "외국인")


func test_a_form_copy_scales_ratings_and_leaves_the_player_alone() -> void:
	var p := _division()[0].rotation()[0]
	var control := p.pitching.control
	var speed := p.pitching.arsenal[0].velo_avg
	var bad := p.with_form(0.94)
	assert_almost_eq(bad.pitching.control, control * 0.94, 0.001)
	assert_almost_eq(bad.pitching.arsenal[0].velo_avg, speed - 1.5, 0.001)
	assert_eq(bad.id, p.id)
	assert_eq(p.pitching.control, control)
	bad.pitching.arsenal[0].velo_avg = 100.0
	assert_eq(p.pitching.arsenal[0].velo_avg, speed)
