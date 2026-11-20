extends GutTest
## A rookie's season (docs/13 S8-3): second team first, called up, plays every day after.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func _career(position: String, type_id: String, seed_value: int) -> CareerSeason:
	var r := CareerIO.load_default()
	var spec := PlayerCreator.Spec.new()
	spec.name = "신인%d" % seed_value
	spec.position = position
	spec.type_id = type_id
	var c := PlayerCreator.create(spec, r, F.catalog())
	var gen := LeagueGenerator.new(RosterIO.load_names(), F.catalog(), seed_value)
	var clubs: Array[Team] = []
	for i: int in 10:
		clubs.append(gen.team(i, 50.0))
	var season := Season.create(clubs, 10, 36, seed_value, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), ClubIO.load_default())
	c.join(clubs[4])
	return CareerSeason.start(season, c, r)


func _play_out(cs: CareerSeason) -> Array[CareerSeason.Report]:
	var reports: Array[CareerSeason.Report] = []
	var guard := 0
	while not cs.season.finished() and guard < 400:
		if cs.has_game():
			reports.append(cs.quick())
		cs.next_day()
		guard += 1
	return reports


func test_a_rookie_hitter_starts_down_is_called_up_and_plays_every_day() -> void:
	var cs := _career("SS", "contact", 31)
	assert_false(cs.career.first_team)
	var reports := _play_out(cs)
	assert_true(cs.season.finished())
	assert_gt(cs.futures_games, 0, "second-team games first")
	assert_true(cs.career.first_team, "called up during the season: %s" % ", ".join(cs.log))
	var id := cs.career.player.id
	var first: BattingLine = cs.season.book.batting.get(id)
	assert_not_null(first)
	# Once up he plays every game of his club: about four plate appearances a game.
	var up_games := 0
	for r: CareerSeason.Report in reports:
		if r.first_team:
			up_games += 1
	assert_gt(up_games, 5)
	assert_between(float(first.pa) / up_games, 3.4, 5.0)
	var total := 0.0
	for field: String in cs.career.gp:
		total += cs.career.gp[field]
	assert_gt(total, 0.0, "growth points earned")
	assert_eq(cs.career.gp["pitching"], 0.0, "none on the mound for a shortstop")
	assert_gt(cs.career.popularity, 0.0)


func test_a_rookie_starter_takes_his_turn_once_up() -> void:
	var cs := _career("SP", "power_arm", 32)
	_play_out(cs)
	assert_true(not cs.log.is_empty() and cs.log[0].contains("1군"), "called up at some point: %s" % ", ".join(cs.log))
	var line: PitchingLine = cs.season.book.pitching.get(cs.career.player.id)
	assert_not_null(line)
	assert_gt(line.starts, 0, "a starter starts")
	assert_gt(cs.career.gp["pitching"], 0.0)


func test_fielding_credit_reads_the_scorebook() -> void:
	var cs := _career("SS", "defence", 33)
	var e := GameEvent.plate_appearance(PaResult.Kind.GROUND_OUT, [], 1)
	e.fielders = "6-3"
	assert_eq(cs.fielding_credit(e), Vector2i(1, 0))
	e.fielders = "E6"
	assert_eq(cs.fielding_credit(e), Vector2i(0, 1))
	e.fielders = "4-3"
	assert_eq(cs.fielding_credit(e), Vector2i.ZERO)
