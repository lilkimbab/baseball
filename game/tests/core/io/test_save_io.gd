extends GutTest
## Save games (docs/13 S9-1): a league season and a career saved mid-way load back and go on
## exactly as they would have.

const F := preload("res://tests/core/rules/rules_fixture.gd")
const SLOT := "test_slot"


func after_each() -> void:
	SaveIO.delete_slot(SLOT)


func _league(seed_value: int) -> Season:
	var gen := LeagueGenerator.new(RosterIO.load_names(), F.catalog(), seed_value)
	var clubs: Array[Team] = []
	for i: int in 20:
		clubs.append(gen.team(i, 50.0))
	var s := Season.create(clubs, 10, 36, seed_value, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), ClubIO.load_default())
	s.manage(clubs[3].id)
	return s


func _days(s: Season, n: int) -> void:
	for i: int in n:
		s.play_day(true)
		s.advance()


func _fingerprint(s: Season) -> String:
	var parts := PackedStringArray()
	for sched: Schedule in s.schedules:
		for g: ScheduledGame in sched.games:
			if g.played:
				parts.append("%d:%s-%s:%d-%d" % [g.day, g.away, g.home, g.away_score, g.home_score])
	var hr := 0
	for id: String in s.book.batting:
		hr += s.book.batting[id].home_runs
	parts.append("hr%d" % hr)
	return ",".join(parts)


func test_a_league_saved_mid_season_goes_on_the_same_after_loading() -> void:
	var a := _league(51)
	_days(a, 8)
	a.club.points = 345
	a.club.bag.append(Vector2i(2, 1))
	var team: Team = a.teams[a.my_team]
	team.unregister(team.first_team()[20].id, a.day)
	assert_eq(SaveIO.save_league(SLOT, a, 1000.0), OK)
	var b := SaveIO.load_league(SLOT)
	assert_not_null(b)
	assert_eq(b.day, a.day)
	assert_eq(b.my_team, a.my_team)
	assert_eq(b.club.points, 345)
	assert_eq(b.club.bag, [Vector2i(2, 1)] as Array[Vector2i])
	assert_eq((b.teams[b.my_team] as Team).registered, team.registered)
	assert_eq(_fingerprint(b), _fingerprint(a), "results so far")
	for d: int in a.divisions.size():
		for id: String in a.divisions[d]:
			assert_eq(b.standings[d].row(id).wins, a.standings[d].row(id).wins)
	# Both go on to the end of the season: the same games, the same scores.
	a.play_to_end()
	b.play_to_end()
	assert_eq(_fingerprint(b), _fingerprint(a), "the rest of the season")
	assert_eq(b.postseasons[0].champion(), a.postseasons[0].champion())
	var metas := SaveIO.slots()
	assert_true(metas.any(func(m: Dictionary) -> bool: return m["slot"] == SLOT and m["mode"] == "league"))


func test_ratings_keep_their_fractions() -> void:
	var a := _league(52)
	var p := (a.teams[a.my_team] as Team).first_team()[0]
	p.batting.contact_r = 47.37
	SaveIO.save_league(SLOT, a, 1.0)
	var b := SaveIO.load_league(SLOT)
	assert_almost_eq((b.teams[b.my_team] as Team).player(p.id).batting.contact_r, 47.37, 0.001)


func test_a_career_saved_and_loaded_carries_on() -> void:
	var r := CareerIO.load_default()
	var spec := PlayerCreator.Spec.new()
	spec.name = "저장신인"
	spec.position = "LF"
	spec.type_id = "power"
	var c := PlayerCreator.create(spec, r, F.catalog())
	var season := _league(53)
	season.club = null
	season.clubs.clear()
	c.join(season.teams[season.divisions[1][2]])
	var cs := CareerSeason.start(season, c, r)
	for i: int in 10:
		if cs.has_game():
			cs.quick()
		cs.next_day()
	cs.career.gp["batting"] = 77.5
	cs.career.pitch_uses[&"slider"] = 3
	assert_eq(SaveIO.save_career(SLOT, cs, 2.0), OK)
	var back := SaveIO.load_career(SLOT)
	assert_not_null(back)
	assert_eq(back.career.player.name, "저장신인")
	assert_eq(back.career.first_team, cs.career.first_team)
	assert_almost_eq(float(back.career.gp["batting"]), 77.5, 1e-6)
	assert_eq(back.futures_games, cs.futures_games)
	assert_eq(back.season.day, cs.season.day)
	assert_eq(back.log, cs.log)
	# And it plays on.
	for i: int in 5:
		if back.has_game():
			back.quick()
		back.next_day()
	assert_gt(back.season.day, cs.season.day)


func test_a_missing_slot_loads_nothing() -> void:
	assert_null(SaveIO.load_league("no_such_slot"))
	assert_eq(SaveIO.migrate({"format": SaveIO.FORMAT, "x": 1})["x"], 1)
