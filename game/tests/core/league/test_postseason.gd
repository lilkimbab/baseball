extends GutTest
## The postseason ladder, promotion and relegation (docs/13 S7-7, S7-8).

const F := preload("res://tests/core/rules/rules_fixture.gd")

static var _season: Season


func _game(day: int, away: String, home: String, a: int, h: int) -> ScheduledGame:
	var g := ScheduledGame.make(day, away, home, 0, 1)
	g.finish(a, h)
	return g


## Two divisions of ten, 36 games, played through the postseason once for the tests.
func _played() -> Season:
	if _season == null:
		var gen := LeagueGenerator.new(RosterIO.load_names(), F.catalog(), 8)
		var clubs: Array[Team] = []
		for i: int in 20:
			clubs.append(gen.team(i, 52.0 if i < 10 else 46.0))
		_season = Season.create(clubs, 10, 36, 3, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall())
		_season.play_to_end()
	return _season


func test_series_lengths_and_home_parks() -> void:
	var s := PlayoffSeries.make("hi", "lo", 4)
	assert_eq(s.length(), 7)
	var hosts: Array[String] = []
	for n: int in range(1, 8):
		hosts.append(s.host_of(n))
	assert_eq(hosts, ["hi", "hi", "lo", "lo", "lo", "hi", "hi"] as Array[String], "2-3-2")
	var five := PlayoffSeries.make("hi", "lo", 3)
	assert_eq([five.host_of(1), five.host_of(3), five.host_of(5)], ["hi", "lo", "hi"])
	assert_eq(PlayoffSeries.make("hi", "lo", 2).host_of(3), "hi", "a best-of-three stays at the higher seed")


func test_a_series_ends_at_the_wins_needed_and_a_tie_does_not_count() -> void:
	var s := PlayoffSeries.make("hi", "lo", 2)
	var g1 := s.next_game(0, 0)
	assert_null(s.next_game(0, 0) if g1.played else null)
	g1.finish(2, 2)
	s.record(g1)
	assert_null(s.next_game(0, 0), "one game a day")
	var g2 := s.next_game(1, 0)
	g2.finish(1, 3)
	s.record(g2)
	var g3 := s.next_game(2, 0)
	g3.finish(0, 5)
	s.record(g3)
	assert_true(s.finished())
	assert_eq(s.winner(), "hi")
	assert_eq(s.games.size(), 3, "the tie made it three games for two wins")
	assert_null(s.next_game(3, 0))


func test_the_ladder_seeds_fourth_against_third_and_climbs() -> void:
	var table := Standings.of(PackedStringArray(["a", "b", "c", "d", "e"]))
	# a best, then b, c, d, e.
	var wins := {"a": 9, "b": 7, "c": 5, "d": 3, "e": 1}
	# Each against an outside club ("zz", not in the table), ten games apiece.
	for id: String in wins:
		for i: int in 10:
			table.record(_game(0, id, "zz", 1, 0) if i < int(wins[id]) else _game(0, id, "zz", 0, 1))
	var p := Postseason.from_standings(table, 10)
	assert_eq(p.seeds, PackedStringArray(["a", "b", "c", "d"]))
	assert_null(p.game_on(9), "not before it starts")
	var g := p.game_on(10)
	assert_eq(g.home, "c")
	assert_eq(g.away, "d")
	# d wins twice.
	for day: int in [10, 11]:
		var game := p.game_on(day)
		game.finish(5, 1)
		p.record(game, day)
	assert_eq(p.current, 1)
	assert_eq(p.series().high, "b")
	assert_eq(p.series().low, "d")
	assert_null(p.game_on(12), "a day off between rounds")
	assert_not_null(p.game_on(13))
	assert_eq(Postseason.rules(RuleSet.kbo_2026()).extra_inning_limit, 15)


func test_a_season_runs_to_its_champions_and_the_movements_add_up() -> void:
	var s := _played()
	assert_true(s.finished())
	for p: Postseason in s.postseasons:
		assert_true(p.finished())
		assert_eq(p.rounds.size(), 3)
		assert_ne(p.champion(), "")
		assert_ne(p.champion(), p.runner_up())
		for r: PlayoffSeries in p.rounds:
			assert_between(r.games.size(), r.wins_needed, r.length() + 3)
	var moves := s.movements()
	assert_eq((moves[0][0] as PackedStringArray).size(), 0, "nobody goes up from the top")
	assert_eq((moves[0][1] as PackedStringArray).size(), 2)
	assert_eq((moves[1][0] as PackedStringArray).size(), 2)
	assert_eq((moves[1][1] as PackedStringArray).size(), 0, "nobody goes down from the bottom")
	var next := s.next_divisions()
	assert_eq(next[0].size(), 10)
	assert_eq(next[1].size(), 10)
	for id: String in moves[1][0]:
		assert_true(next[0].has(id), "%s goes up" % id)
	for id: String in moves[0][1]:
		assert_true(next[1].has(id), "%s goes down" % id)
	# Postseason records are kept apart.
	assert_false(s.postseason_book.batting.is_empty())
	var regular_games := 0
	for row: StandingsRow in s.standings[0].rows.values():
		regular_games += row.games()
	assert_eq(regular_games, 360, "the table counts only the regular season")


func test_awards_go_to_the_most_valuable_and_the_title_holders_lead() -> void:
	var s := _played()
	var a := SeasonAwards.for_division(s, 0)
	assert_not_null(a.mvp)
	assert_not_null(a.pitcher)
	for id: String in s.book.batting:
		if a._team_of.has(id):
			assert_true(a.war(id) <= a.mvp.value + 1e-6, "nobody is worth more than the MVP")
	assert_eq(a.best.size(), 10, "pitcher, catcher, four infielders, three outfielders, designated hitter")
	var names: Array[String] = []
	for t: SeasonAwards.Award in a.titles:
		names.append(t.title)
	for title: String in SeasonAwards.BATTING_TITLES + SeasonAwards.PITCHING_TITLES:
		assert_true(names.has(title), title)
	var hr_title: SeasonAwards.Award = a.titles[names.find("홈런")]
	for id: String in s.book.batting:
		if a._team_of.has(id):
			assert_true(s.book.batting[id].home_runs <= s.book.batting[hr_title.player_id].home_runs)
	if a.rookie != null:
		assert_true(2026 - a._players[a.rookie.player_id].born <= SeasonAwards.ROOKIE_AGE)
	assert_string_contains(a.line(a.mvp), "MVP")
	gut.p(a.line(a.mvp))
	gut.p(a.line(a.pitcher))


func test_woba_of_a_league_average_line_is_near_point_three_two() -> void:
	var b := BattingLine.new()
	# KBO 2025-ish per 600 plate appearances.
	b.pa = 600
	b.ab = 530
	b.walks = 55
	b.hit_by_pitch = 9
	b.sac_flies = 6
	b.hits = 139
	b.doubles = 25
	b.triples = 2
	b.home_runs = 13
	assert_between(SeasonAwards.woba(b), 0.30, 0.35)
