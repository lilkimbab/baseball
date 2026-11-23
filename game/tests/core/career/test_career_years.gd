extends GutTest
## A pro career over several seasons: salary and money, the winter, the next
## season with his club, trades, release, free agency, pitches picked up.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func after_each() -> void:
	CareerSession.career_season = null
	CareerSession.season = null
	CareerSession.career = null


func _pro(position: String, type_id: String, seed_value: int, games: int = 36) -> CareerSeason:
	var spec := PlayerCreator.Spec.new()
	spec.name = "프로%d" % seed_value
	spec.position = position
	spec.type_id = type_id
	var c := PlayerCreator.create(spec, CareerIO.load_default(), F.catalog())
	CareerSession.start(c, LeagueSession.league_clubs()[2].id, games, seed_value)
	CareerSession.career_season.pro_games = games
	return CareerSession.career_season


func _season_out(cs: CareerSeason) -> void:
	var guard := 0
	while not cs.season.finished() and guard < 400:
		if cs.has_game():
			cs.quick()
		cs.next_day()
		guard += 1


func test_three_seasons_with_salary_winters_and_the_same_club() -> void:
	var cs := _pro("2B", "contact", 41)
	var club := cs.career.team_id
	var year := cs.season.season_year
	for i: int in 3:
		cs = CareerSession.career_season
		_season_out(cs)
		assert_true(cs.season.finished())
		assert_gt(cs.career.money, 0, "paid through the season")
		CareerSession.start_winter()
		assert_false(cs.winter_lines.is_empty(), "told about his contract")
		var told := cs.winter_lines.size()
		CareerSession.start_winter()
		assert_eq(cs.winter_lines.size(), told, "one winter a season")
		CareerSession.next_season()
	cs = CareerSession.career_season
	assert_eq(cs.season.season_year, year + 3)
	assert_eq(cs.career.pro_years, 3)
	assert_eq(cs.career.seasons.size(), 3)
	assert_eq(cs.career.first_days.size(), 3)
	assert_gte(cs.career.salary, CareerContract.MINIMUM)
	assert_true(cs.farm_mode(), "a futures league every season")
	assert_true(cs.season.teams[cs.career.team_id].player(cs.career.player.id) != null, "he is on his club")
	if not cs.career.released:
		assert_true(cs.career.team_id == club or Array(cs.log).any(func(l: String) -> bool: return l.contains("트레이드")), "the same club unless traded")
	# Saved and loaded, the career goes on as it was.
	var back := SaveIO.career_from(SaveIO.career_to(cs), cs.season)
	assert_eq(back.career.pro_years, 3)
	assert_eq(back.career.salary, cs.career.salary)
	assert_eq(back.career.first_days, cs.career.first_days)


func test_salary_follows_playing_time_and_play() -> void:
	var c := CareerPlayer.new()
	c.salary = 5000
	assert_lt(CareerContract.renewed(c, 0.05, 1.0), 5000, "a season in the second team: a cut")
	assert_gte(CareerContract.renewed(c, 0.05, 1.0), roundi(5000 * (1.0 - CareerContract.CUT_MOST)))
	assert_gt(CareerContract.renewed(c, 0.9, 1.6), 7000, "a fine full season: a big raise")
	c.salary = CareerContract.MINIMUM
	assert_eq(CareerContract.renewed(c, 0.0, 0.5), CareerContract.MINIMUM, "never below the minimum")


func test_free_agency_after_eight_full_seasons() -> void:
	var c := CareerPlayer.new()
	c.fa_years = 8
	for i: int in 7:
		c.first_days.append(180)
	c.first_days.append(40)
	assert_false(CareerContract.fa_ready(c, 190), "a short season does not count")
	c.first_days.append(170)
	assert_true(CareerContract.fa_ready(c, 190))
	c.free_agent_done = true
	assert_false(CareerContract.fa_ready(c, 190), "once")


func test_a_trade_moves_him_and_one_of_theirs_comes_back() -> void:
	var cs := _pro("LF", "power", 42)
	var s := cs.season
	var from := cs.career.team_id
	var counts := {}
	for id: String in s.teams:
		counts[id] = (s.teams[id] as Team).players.size()
	var line := CareerEvents.trade(cs, Rng.new(5))
	assert_ne(line, "")
	assert_ne(cs.career.team_id, from)
	assert_not_null(s.teams[cs.career.team_id].player(cs.career.player.id))
	assert_null(s.teams[from].player(cs.career.player.id))
	for id: String in s.teams:
		assert_eq((s.teams[id] as Team).players.size(), counts[id], "a man for a man")


func test_a_long_stay_in_the_second_team_is_talked_about_once() -> void:
	var cs := _pro("C", "defence", 43, 72)
	cs.futures_days = int(cs.season.total_days() * CareerEvents.LONG_STAY_SHARE) + 1
	CareerEvents.day(cs)
	CareerEvents.day(cs)
	var talks := Array(cs.log).filter(func(l: String) -> bool: return l.contains("구단 면담"))
	assert_eq(talks.size(), 1)


func test_a_pitcher_can_pick_up_a_pitch_by_himself() -> void:
	var cs := _pro("SP", "control", 44)
	var before := cs.career.player.pitching.arsenal.size()
	var report := CareerSeason.Report.new()
	report.rating = 9.5
	var learned := ""
	for day: int in 200:
		cs.season.day = day
		learned = CareerEvents.after_game(cs, report)
		if learned != "":
			break
	assert_ne(learned, "", "now and then after a fine game")
	assert_eq(cs.career.player.pitching.arsenal.size(), before + 1)


func test_a_lesson_costs_money_and_brings_a_pitch() -> void:
	var cs := _pro("RP", "control", 45)
	var c := cs.career
	var id: StringName = PitchEvolution.learnable(c, cs.rules)[0]
	assert_false(CareerContract.lesson(cs, id), "not without the money")
	c.money = CareerContract.LESSON_PRICE + 100
	var before := c.player.pitching.arsenal.size()
	assert_true(CareerContract.lesson(cs, id))
	assert_eq(c.money, 100)
	assert_eq(c.player.pitching.arsenal.size(), before + 1)


func test_a_league_leader_wins_the_title() -> void:
	var cs := _pro("1B", "power", 46)
	var s := cs.season
	var mine := s.book.bat(cs.career.player.id)
	mine.pa = 400
	mine.ab = 360
	mine.hits = 120
	mine.home_runs = 60
	mine.rbi = 150
	var titles := CareerContract.titles(cs)
	assert_true(titles.has("홈런"))
	assert_true(titles.has("타점"))
	var other := s.book.bat("someone_else")
	other.pa = 400
	other.home_runs = 61
	assert_false(CareerContract.titles(cs).has("홈런"), "only the leader")


func test_the_career_s_moments_wait_as_cutscenes() -> void:
	# A trade, a call-up, and the winter's awards and contract each leave a cue (Ceremony).
	var cs := _pro("1B", "power", 47)
	CareerEvents.trade(cs, Rng.new(9))
	assert_eq(cs.cues.size(), 1)
	assert_eq(cs.cues[0][0], &"trade")
	assert_ne(str(cs.cues[0][4]), cs.career.team_id, "the club he left")
	cs.cues.clear()
	cs.career.first_team = false
	cs.season.teams[cs.career.team_id].registered.erase(cs.career.player.id)
	cs.call_up()
	assert_eq(cs.cues.size(), 1)
	assert_eq(cs.cues[0][2], "첫 1군 등록")
	cs.cues.clear()
	_season_out(cs)
	var mine := cs.season.book.bat(cs.career.player.id)
	mine.pa = 700
	mine.ab = 600
	mine.hits = 250
	mine.home_runs = 90
	mine.rbi = 200
	CareerSession.start_winter()
	var kinds: Array = cs.cues.map(func(c: Array) -> StringName: return c[0])
	assert_true(kinds.has(&"award"), "titles at the awards: %s" % [kinds])
	var award: Array = cs.cues[kinds.find(&"award")]
	assert_eq(award[2], "홈런왕")
	# Played without a screen, they are just passed over.
	var over := [false]
	Ceremony.play_all(get_tree().root, [[&"award", "x", "y", PackedStringArray(), null, null, cs.career.player]], func() -> void: over[0] = true)
	assert_true(over[0])
	assert_eq(CareerSession.award_name("타율"), "타격왕")
	assert_eq(CareerSession.award_name("평균자책점"), "평균자책점 1위")
	assert_eq(CareerSession.award_name("도루"), "도루왕")
