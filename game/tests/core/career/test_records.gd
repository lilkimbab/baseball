extends GutTest
## The records room (queue stage 5): each game's line of the men followed, a career's seasons
## and totals, retirement and the hall of fame; and what a full season of logs costs a save.

const F := preload("res://tests/core/rules/rules_fixture.gd")
const SLOT := "test_records"


func after_each() -> void:
	SaveIO.delete_slot(SLOT)
	CareerSession.career_season = null
	CareerSession.season = null
	CareerSession.career = null


func test_a_league_keeps_its_clubs_games_and_saves_them_small() -> void:
	var clubs := LeagueSession.league_clubs()
	var s := Season.create(clubs, clubs.size(), 144, 6, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), ClubIO.load_default())
	s.manage(clubs[0].id)
	while s.phase == Season.Phase.REGULAR:
		s.play_day(true)
		s.advance()
	var team: Team = s.teams[s.my_team]
	var logged := 0
	for p: Player in team.first_team():
		if s.game_logs.has(p.id):
			logged += 1
	assert_gt(logged, 20, "his first team's men have their games")
	for id: String in s.game_logs:
		assert_not_null(team.player(id), "only his club's men")
	var hitter := ""
	for id: String in s.game_logs:
		if not team.player(id).is_pitcher():
			hitter = id
			break
	var games := 0
	var pa := 0
	for e: Variant in s.game_logs[hitter]:
		games += 1
		pa += int((e as Array)[5][0])
	assert_eq(pa, s.book.batting[hitter].pa, "the log adds up to the season")
	# A whole season's save: its size and how long it takes to load.
	assert_eq(SaveIO.save_league(SLOT, s, 0.0), OK)
	var path := ProjectSettings.globalize_path(SaveIO.slot_path(SLOT) + "/league.json")
	var size := FileAccess.get_file_as_bytes(path).size()
	var start := Time.get_ticks_msec()
	var back := SaveIO.load_league(SLOT)
	var took := Time.get_ticks_msec() - start
	gut.p("a 144-game season with its game logs: %d KB, loaded in %d ms" % [size / 1024, took])
	assert_lt(size, 3 * 1024 * 1024, "a save stays small")
	assert_eq((back.game_logs[hitter] as Array).size(), games)


func test_a_career_keeps_his_games_seasons_and_totals_and_retires() -> void:
	var spec := PlayerCreator.Spec.new()
	spec.name = "기록시험"
	spec.position = "SS"
	spec.type_id = "contact"
	var c := PlayerCreator.create(spec, CareerIO.load_default(), F.catalog())
	CareerSession.start(c, LeagueSession.league_clubs()[5].id, 36, 8)
	var cs := CareerSession.career_season
	cs.pro_games = 36
	for season: int in 2:
		cs = CareerSession.career_season
		var guard := 0
		var played := 0
		while not cs.season.finished() and guard < 400:
			if cs.has_game():
				cs.quick()
				played += 1
			cs.next_day()
			guard += 1
		assert_eq((cs.season.game_logs.get(c.player.id, []) as Array).size(), played, "every game of his in the log")
		if season == 0:
			CareerSession.next_season()
	assert_eq(c.seasons.size(), 1, "the first season in his record")
	var sum := CareerContract.totals(c, CareerSession.career_season)
	var first := 0
	for row: Variant in c.seasons:
		first += int(((row as Array)[4] as Dictionary).get("pa", 0))
	first += CareerSession.career_season.season.book.batting.get(c.player.id, BattingLine.new()).pa
	assert_eq((sum[0] as BattingLine).pa, first, "totals of the seasons")
	var result := CareerSession.retire()
	assert_false(result.is_empty())
	assert_true(c.retired)
	assert_eq(c.seasons.size(), 2, "the last season too")
	assert_gt(c.game_log.size(), 0, "his games kept in the career")
	assert_true(CareerSession.retire().is_empty(), "once")


func test_the_hall_of_fame_marks() -> void:
	var c := CareerPlayer.new()
	c.position = "1B"
	var bat := BattingLine.new()
	bat.hits = 2100
	bat.home_runs = 120
	bat.ab = 7600
	assert_true(HallOfFame.marks(c, bat, PitchingLine.new(), 0, 144).has("2100안타"))
	bat.hits = 1200
	assert_true(HallOfFame.marks(c, bat, PitchingLine.new(), 0, 144).is_empty(), "not enough")
	assert_false(HallOfFame.marks(c, bat, PitchingLine.new(), 0, 72).is_empty(), "half-length seasons, half the hits")
	var p := CareerPlayer.new()
	p.position = "CL"
	var q := PitchingLine.new()
	q.saves = 260
	assert_false(HallOfFame.marks(p, BattingLine.new(), q, 0, 144).is_empty())
	assert_true(HallOfFame.marks(p, BattingLine.new(), PitchingLine.new(), 5, 144).has("타이틀 5개"))
