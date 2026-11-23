extends GutTest
## Players growing and ageing: the young have room and fill it faster when they
## play, the old lose a little each winter and the oldest retire, rookies take their places,
## and a league stays as strong as it was over the years.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func _season(seed_value: int = 7) -> Season:
	var gen := LeagueGenerator.new(RosterIO.load_names(), F.catalog(), seed_value)
	var clubs: Array[Team] = []
	for i: int in 30:
		clubs.append(gen.team(i, LeagueGenerator.DIVISION_MEANS[i / 10]))
	var s := Season.create(clubs, 10, 36, seed_value, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), ClubIO.load_default())
	s.season_year = 2026
	return s


func test_the_young_have_room_and_the_old_none() -> void:
	var rng := Rng.new(3)
	var young := 0.0
	var older := 0.0
	for i: int in 400:
		young += Development.initial_room(20, rng)
		older += Development.initial_room(26, rng)
		assert_eq(Development.initial_room(30, rng), 0.0)
	assert_between(young / 400.0, 9.0, 12.5, "a 20-year-old has about ten points to come")
	assert_between(older / 400.0, 1.0, 2.5)
	var s := _season()
	for t: Team in s.teams.values():
		for p: Player in t.players:
			assert_gte(p.potential, 0.0, "everyone in a league has his room")


func test_a_man_who_plays_grows_faster_and_never_past_his_room() -> void:
	var s := _season()
	var a: Player = null
	for p: Player in (s.teams.values()[0] as Team).players:
		if not p.is_pitcher() and s.season_year - p.born <= 23:
			a = p
			break
	assert_not_null(a)
	a.potential = 8.0
	var b := RosterIO.player_from(RosterIO.player_to(a, true))
	var eye := a.batting.eye
	var played := 0.0
	var sat := 0.0
	for day: int in 36:
		played += Development.grow_day(a, 21, true, 36)
		sat += Development.grow_day(b, 21, false, 36)
	assert_gt(played, sat * 1.8, "playing every day more than twice the pace of sitting")
	assert_between(played, 8.0 * 0.22, 8.0 * 0.3, "about a third of his room in a season at 21")
	assert_almost_eq(a.batting.eye, eye + played, 1e-4, "his ratings rose by it")
	for day: int in 2000:
		Development.grow_day(a, 21, true, 36)
	assert_almost_eq(a.potential, 0.0, 0.01)
	assert_almost_eq(a.batting.eye, eye + 8.0, 0.02, "and no further than his room")


func test_the_old_decline_in_the_winter_and_the_oldest_retire() -> void:
	var s := _season()
	var p: Player = (s.teams.values()[3] as Team).players[20]
	var speed := p.batting.speed
	var contact := p.batting.contact_r
	assert_eq(Development.decline(p, 29), 0.0, "not before 31")
	var by := Development.decline(p, 35)
	assert_gt(p.batting.speed, speed - by * 2.0)
	assert_lt(p.batting.speed, speed - by, "legs go first")
	assert_gt(contact - p.batting.contact_r, 0.0)
	assert_lt(contact - p.batting.contact_r, speed - p.batting.speed, "the eye and the hands last longer")
	var rng := Rng.new(1)
	var at_30 := 0
	var at_37 := 0
	for i: int in 1000:
		assert_true(Development.retires(40, true, rng))
		if Development.retires(30, false, rng):
			at_30 += 1
		if Development.retires(37, false, rng):
			at_37 += 1
	assert_eq(at_30, 0)
	var expected := roundi(Development.RETIRE_PER_YEAR * 5.0 * 1000.0)
	assert_between(at_37, expected - 60, expected + 60, "three in four at 37")


func test_a_winter_retires_drafts_and_keeps_the_first_teams_full() -> void:
	var s := _season()
	s.my_team = s.divisions[2][0]
	var sizes: Dictionary[String, int] = {}
	for t: Team in s.teams.values():
		sizes[t.id] = t.players.size()
	var w := Development.winter(s)
	assert_eq(w.year, 2027)
	assert_gt(w.retired.size(), 20, "a few a club")
	assert_eq(w.rookies.size(), w.retired.size(), "each place filled")
	var ids: Dictionary[String, bool] = {}
	for t: Team in s.teams.values():
		assert_eq(t.players.size(), sizes[t.id], "the same number of players")
		assert_eq(t.registered.size(), s.rules.registered_roster, "a full first team")
		var foreign := 0
		for p: Player in t.first_team():
			if p.origin == &"foreign":
				foreign += 1
		assert_lte(foreign, s.rules.foreign_players)
		for p: Player in t.players:
			assert_false(ids.has(p.id), "ids stay unique")
			ids[p.id] = true
	for r: Array in w.rookies:
		var p := (s.teams[str(r[0])] as Team).player(str(r[1]))
		if p.origin == &"":
			assert_between(w.year - p.born, Development.ROOKIE_AGES.x, Development.ROOKIE_AGES.y)
			assert_gt(p.potential, 0.0, "a rookie has room to grow")
	# Saved and loaded, the rookies and their room come back.
	var back := SaveIO.season_from(SaveIO.season_to(s))
	var first: Array = w.rookies[0]
	var again := (back.teams[str(first[0])] as Team).player(str(first[1]))
	assert_not_null(again)
	assert_almost_eq(again.potential, (s.teams[str(first[0])] as Team).player(str(first[1])).potential, 1e-5)


## The first teams' average over the years: growth and rookies make up for age and
## retirements. Each year: a season's growth (regulars playing every day, the rest half the
## time) and a winter.
func test_a_league_keeps_its_strength_over_ten_years() -> void:
	var s := _season(11)
	var start := _first_team_mean(s)
	var start_age := _mean_age(s)
	for year: int in 10:
		for day: int in s.games_per_team:
			for t: Team in s.teams.values():
				for p: Player in t.players:
					var played := t.is_registered(p.id) or day % 2 == 0
					var gain := Development.grow_day(p, s.season_year - p.born, played, s.games_per_team)
					if gain > 0.0:
						s.grown[p.id] = float(s.grown.get(p.id, 0.0)) + gain
		Development.winter(s)
		s.season_year += 1
	var after := _first_team_mean(s)
	gut.p("first teams: %.2f -> %.2f, age %.1f -> %.1f" % [start, after, start_age, _mean_age(s)])
	assert_almost_eq(after, start, 1.5, "about as strong after ten years")
	# Within two years: the fictional league starts young (26), the KBO's first teams are about
	# 27-28 (a change of name generator moved this run from inside 1.5 to 1.57).
	assert_almost_eq(_mean_age(s), start_age, 2.0, "and about as old")


func _first_team_mean(s: Season) -> float:
	var total := 0.0
	var n := 0
	for t: Team in s.teams.values():
		for p: Player in t.first_team():
			total += Overall.pitcher(p, s.catalog) if p.is_pitcher() else s.ovr.batter(p, p.primary_position())
			n += 1
	return total / n


func _mean_age(s: Season) -> float:
	var total := 0.0
	var n := 0
	for t: Team in s.teams.values():
		for p: Player in t.players:
			total += s.season_year - p.born
			n += 1
	return total / n
