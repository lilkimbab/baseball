extends GutTest
## The league's all-star break (queue stage 4): at the season's middle, the picked, the game,
## the derby, what it pays, and its place in a save.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func _season() -> Season:
	var clubs := LeagueSession.league_clubs()
	var s := Season.create(clubs, clubs.size(), 36, 5, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), ClubIO.load_default())
	s.manage(clubs[3].id)
	return s


func _to_the_break(s: Season) -> void:
	var guard := 0
	while not LeagueAllStar.due(s) and guard < 200:
		s.play_day(true)
		s.advance()
		guard += 1


func test_the_break_comes_at_the_middle_once() -> void:
	var s := _season()
	assert_false(LeagueAllStar.due(s), "not on the first day")
	_to_the_break(s)
	assert_true(LeagueAllStar.due(s))
	assert_almost_eq(float(s.day) / s.total_days(), 0.5, 0.05)
	var points := s.club.points
	LeagueAllStar.hold(s)
	assert_false(LeagueAllStar.due(s), "held once")
	assert_true(LeagueAllStar.on(s))
	assert_eq((s.all_star["selected"] as Array).size(), LeagueAllStar.PICKED)
	assert_eq((s.all_star["field"] as Array).size(), LeagueAllStar.DERBY_FIELD)
	assert_eq(s.club.points, points + LeagueAllStar.CLUB_PER_MAN * LeagueAllStar.of_my_club(s).size(), "club points for his men")
	var sides := LeagueAllStar.teams(s)
	assert_eq(sides.size(), 2)
	for t: Team in sides:
		assert_gte(t.players.size(), AllStar.HITTERS)
		assert_false(t.first_team().is_empty())


func test_settled_at_once_and_saved() -> void:
	var s := _season()
	_to_the_break(s)
	LeagueAllStar.settle(s)
	assert_true(LeagueAllStar.done(s))
	assert_false(LeagueAllStar.on(s))
	assert_ne(LeagueAllStar.winner(s), "")
	var game: Array = s.all_star["game"]
	assert_eq(game.size(), 3, "its score kept")
	var back := SaveIO.season_from(SaveIO.season_to(s))
	assert_true(LeagueAllStar.done(back), "the break stays over after loading")
	assert_eq(LeagueAllStar.winner(back), LeagueAllStar.winner(s))
	# The season goes on.
	for i: int in 3:
		back.play_day(true)
		back.advance()
	assert_false(LeagueAllStar.due(back))


func test_his_derby_turn_counts_and_pays() -> void:
	var s := _season()
	_to_the_break(s)
	LeagueAllStar.hold(s)
	# His club's man in the field, for the test.
	var team: Team = s.teams[s.my_team]
	var hitter: Player = null
	for p: Player in team.first_team():
		if not p.is_pitcher():
			hitter = p
			break
	(s.all_star["field"] as Array)[0] = hitter.id
	var before := Profile.points
	LeagueAllStar.swung_derby(s, 30, Difficulty.Level.PRO)
	assert_true(LeagueAllStar.derby_over(s))
	assert_eq(LeagueAllStar.winner(s), hitter.id, "thirty home runs win it")
	assert_eq(Profile.points, before + LeagueAllStar.DERBY_PER_HOME_RUN * 30 + LeagueAllStar.DERBY_WIN)
	Profile.points = before
