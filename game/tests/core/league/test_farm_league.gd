extends GutTest
## The second teams' league and the moves between the teams (docs/08 R6): each day of the
## season every second team plays, its men's numbers are kept, those who play grow faster,
## the computer clubs call up a second-team man who has become better, the player's club is
## told instead, and all of it is saved and goes on the same after loading.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func before_each() -> void:
	LeagueSession.season = null


func after_all() -> void:
	LeagueSession.season = null


func _league() -> Season:
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	# A league of three divisions (an old save's): its second teams' league.
	return LeagueSession.start(clubs[24].id, 36, 9, clubs)


func test_every_second_team_plays_each_day_of_the_season() -> void:
	var s := _league()
	assert_not_null(s.farm)
	var today := s.games_today().size()
	assert_gt(today, 0)
	s.play_day(true)
	assert_eq(s.farm.results.size(), today, "one second-team game for each first-team game")
	s.play_day(true)
	assert_eq(s.farm.results.size(), today, "a day is played once")
	var team: Team = s.teams[s.my_team]
	var farm_hitters := 0
	for p: Player in team.second_team():
		if s.farm.book.batting.has(p.id) or s.farm.book.pitching.has(p.id):
			farm_hitters += 1
		assert_false(s.book.batting.has(p.id), "second-team numbers are kept apart")
	assert_gt(farm_hitters, 3, "the prospects play")
	var d := s.division_of(s.my_team)
	assert_eq(s.farm.standings[d].row(s.my_team).games(), 1)
	# The second team is made up to a side with fillers, the same every time.
	var side := s.farm.futures_team(s, s.my_team)
	assert_eq(side.players.size(), team.second_team().size() + FarmLeague.FILLERS.size())
	assert_eq(s.farm.fillers(s, s.my_team)[0], s.farm.fillers(s, s.my_team)[0])


func test_those_who_played_grew_more() -> void:
	var s := _league()
	var before: Dictionary[String, float] = {}
	for t: Team in s.teams.values():
		for p: Player in t.players:
			before[p.id] = p.potential
	for i: int in 6:
		s.play_day(true)
		s.advance()
	var played_gain := 0.0
	var played_n := 0
	var idle_gain := 0.0
	var idle_n := 0
	for t: Team in s.teams.values():
		for p: Player in t.second_team():
			if s.season_year - p.born > 24 or before[p.id] < 3.0:
				continue
			var gain := before[p.id] - p.potential
			var games := 0
			if s.farm.book.batting.has(p.id):
				games = s.farm.book.batting[p.id].games
			elif s.farm.book.pitching.has(p.id):
				games = s.farm.book.pitching[p.id].games
			if games >= 5:
				played_gain += gain / before[p.id]
				played_n += 1
			elif games == 0:
				idle_gain += gain / before[p.id]
				idle_n += 1
	assert_gt(played_n, 10)
	if idle_n > 0:
		assert_gt(played_gain / played_n, idle_gain / idle_n * 1.5, "the regulars of the second team grew faster")
	assert_gt(s.grown.size(), 100, "growth is noted for the winter's report")


func test_a_computer_club_calls_up_a_man_who_has_become_better() -> void:
	var s := _league()
	var other_id := s.divisions[2][3] if s.divisions[2][3] != s.my_team else s.divisions[2][4]
	var other: Team = s.teams[other_id]
	var star: Player = null
	for p: Player in other.second_team():
		if p.is_pitcher() and p.role() == &"RP":
			star = p
			break
	assert_not_null(star)
	star.pitching.control = 95.0
	for a: ArsenalPitch in star.pitching.arsenal:
		a.movement = 92.0
		a.command = 92.0
		a.velo_avg += 8.0
		a.velo_max += 8.0
	# The same in the player's own club: advice only.
	var mine: Team = s.teams[s.my_team]
	var my_star: Player = null
	for p: Player in mine.second_team():
		if p.is_pitcher() and p.role() == &"RP":
			my_star = p
			break
	my_star.pitching.control = 95.0
	for a: ArsenalPitch in my_star.pitching.arsenal:
		a.movement = 92.0
		a.command = 92.0
	for i: int in RosterMoves.EVERY_DAYS:
		s.play_day(true)
		s.advance()
	assert_true(other.is_registered(star.id), "called up within the week")
	assert_eq(other.registered.size(), s.rules.registered_roster, "someone went down for him")
	assert_false(mine.is_registered(my_star.id), "the player's club decides for itself")
	var advice := RosterMoves.advice(s, mine)
	assert_gt(advice.size(), 0)
	assert_eq(advice[0].up, my_star, "but is told")
	assert_eq(RosterMoves.kind_of(advice[0].down), "RP", "a reliever for a reliever")


func test_a_league_with_its_second_teams_goes_on_the_same_after_loading() -> void:
	var s := _league()
	for i: int in 4:
		s.play_day(true)
		s.advance()
	s.play_day(true)
	var back := SaveIO.season_from(SaveIO.season_to(s))
	assert_eq(back.farm.results.size(), s.farm.results.size())
	for i: int in 5:
		s.advance()
		s.play_day(true)
		back.advance()
		back.play_day(true)
	assert_eq(back.farm.results.size(), s.farm.results.size())
	for i: int in s.farm.results.size():
		assert_eq(back.farm.results[i].home_score, s.farm.results[i].home_score)
		assert_eq(back.farm.results[i].away_score, s.farm.results[i].away_score)
	var team_id := s.divisions[1][2]
	for p: Player in (s.teams[team_id] as Team).players:
		var q := (back.teams[team_id] as Team).player(p.id)
		assert_almost_eq(q.batting.eye, p.batting.eye, 1e-4, "the same growth")
		assert_almost_eq(q.potential, p.potential, 1e-4)


func test_the_winter_comes_between_seasons() -> void:
	var s := _league()
	s.games_per_team = 36
	s.play_to_end()
	var old_ids: Dictionary[String, bool] = {}
	for t: Team in s.teams.values():
		for p: Player in t.players:
			old_ids[p.id] = true
	var next := LeagueSession.next_season(10)
	assert_not_null(next.last_winter)
	assert_eq(next.season_year, 2027)
	assert_not_null(next.farm, "the new season has its second teams' league")
	var newcomers := 0
	for t: Team in next.teams.values():
		for p: Player in t.players:
			if not old_ids.has(p.id):
				newcomers += 1
	assert_eq(newcomers, next.last_winter.rookies.size())
	assert_gt(newcomers, 0)
