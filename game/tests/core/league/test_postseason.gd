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


func _table(wins: Dictionary) -> Standings:
	var ids := PackedStringArray()
	for id: String in wins:
		ids.append(id)
	var table := Standings.of(ids)
	for id: String in wins:
		for i: int in 10:
			table.record(_game(0, id, "zz", 1, 0) if i < int(wins[id]) else _game(0, id, "zz", 0, 1))
	return table


func test_the_kbo_format_is_five_clubs_from_the_wild_card_to_the_korean_series() -> void:
	var table := _table({"a": 9, "b": 8, "c": 6, "d": 4, "e": 3, "f": 1})
	var p := Postseason.from_standings(table, 10, Postseason.kbo())
	assert_eq(p.seeds, PackedStringArray(["a", "b", "c", "d", "e"]))
	assert_eq(p.round_name(), "와일드카드 결정전")
	var wild := p.series()
	assert_eq([wild.high, wild.low], ["d", "e"])
	assert_eq(wild.length(), 2, "two games at most")
	assert_eq(wild.high_won(), 0, "the head start is not a game won")
	# The fifth wins the first: a second game, at the fourth's park again.
	var g := p.game_on(10)
	assert_eq(g.home, "d")
	g.finish(4, 2)
	p.record(g, 10)
	assert_eq(p.current, 0, "the fifth needs two")
	g = p.game_on(11)
	assert_eq(g.home, "d")
	g.finish(3, 1)
	p.record(g, 11)
	assert_eq(p.round_name(), "준플레이오프")
	assert_eq([p.series().high, p.series().low], ["c", "e"])
	assert_eq(p.series().length(), 5)
	# The fifth goes on: three more to the 플레이오프 against the second.
	var day := 13
	for n: int in 3:
		g = p.game_on(day)
		g.finish(1, 0) if g.away == "e" else g.finish(0, 1)
		p.record(g, day)
		day += 1
	assert_eq(p.round_name(), "플레이오프")
	assert_eq([p.series().high, p.series().low], ["b", "e"])
	day += 1
	for n: int in 3:
		g = p.game_on(day)
		g.finish(1, 0) if g.away == "b" else g.finish(0, 1)
		p.record(g, day)
		day += 1
	assert_eq(p.round_name(), "한국시리즈")
	assert_eq([p.series().high, p.series().low], ["a", "b"])
	assert_eq(p.series().length(), 7)
	assert_false(p.finished())
	day += 1
	for n: int in 4:
		g = p.game_on(day)
		g.finish(1, 0) if g.away == "a" else g.finish(0, 1)
		p.record(g, day)
		day += 1
	assert_true(p.finished())
	assert_eq(p.champion(), "a")
	assert_eq(p.runner_up(), "b")
	assert_null(p.game_on(day))


func test_the_fourth_goes_through_the_wild_card_on_one_win_or_a_tie() -> void:
	for score: Array in [[1, 3], [2, 2]]:
		var p := Postseason.from_standings(_table({"a": 9, "b": 8, "c": 6, "d": 4, "e": 3}), 0, Postseason.kbo())
		var g := p.game_on(0)
		g.finish(int(score[0]), int(score[1]))
		p.record(g, 0)
		assert_eq(p.current, 1, "one game is enough for the fourth (%d-%d)" % score)
		assert_eq(p.rounds[0].winner(), "d")
		assert_eq(p.series().low, "d")


func test_a_small_league_plays_the_last_rounds_of_the_format() -> void:
	var p := Postseason.from_standings(_table({"a": 9, "b": 8, "c": 6, "d": 4}), 0, Postseason.kbo())
	assert_eq(p.seeds.size(), 4)
	assert_eq(p.round_name(), "준플레이오프")
	assert_eq(p.format.size(), 3)
	var two := Postseason.from_standings(_table({"a": 9, "b": 8}), 0, Postseason.kbo())
	assert_eq(two.round_name(), "한국시리즈")
	assert_eq([two.series().high, two.series().low], ["a", "b"])


func test_a_pack_gives_its_years_rounds() -> void:
	var rounds := Postseason.format_from([{"name": "준플레이오프", "wins": 2}, {"name": "플레이오프", "wins": 4}, {"name": "한국시리즈", "wins": 4}])
	assert_eq(rounds.size(), 3)
	assert_eq(rounds[1].wins, 4)
	assert_eq(rounds[0].head_start, 0)
	var back := Postseason.format_from(Postseason.format_to(Postseason.kbo()))
	assert_eq(back[0].head_start, 1)
	assert_eq(back[3].name, "한국시리즈")


func test_a_season_runs_to_its_champions_and_the_movements_add_up() -> void:
	var s := _played()
	assert_true(s.finished())
	assert_eq(s.postseasons[0].seeds.size(), 5, "the top division plays the KBO's five")
	assert_eq(s.postseasons[0].round_name(3), "한국시리즈")
	assert_eq(s.postseasons[1].seeds.size(), 4, "the division under it the ladder of four")
	for p: Postseason in s.postseasons:
		assert_true(p.finished())
		assert_eq(p.rounds.size(), p.format.size())
		assert_ne(p.champion(), "")
		assert_ne(p.champion(), p.runner_up())
		for r: PlayoffSeries in p.rounds:
			assert_between(r.games.size(), r.wins_needed - r.head_start, r.length() + 3)
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
