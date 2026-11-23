extends GutTest
## A career's story and its end (CareerLegacy): the moments kept, the flashback chosen from them,
## the farewell tour, the grade and the number retired, saved and loaded.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func after_each() -> void:
	CareerSession.career_season = null
	CareerSession.season = null
	CareerSession.career = null


func _pro(seed_value: int = 71) -> CareerSeason:
	var spec := PlayerCreator.Spec.new()
	spec.name = "레거시%d" % seed_value
	spec.position = "CF"
	spec.type_id = "contact"
	var c := PlayerCreator.create(spec, CareerIO.load_default(), F.catalog())
	CareerSession.start(c, LeagueSession.league_clubs()[1].id, 36, seed_value)
	return CareerSession.career_season


func test_the_moments_are_kept_as_they_happen() -> void:
	var cs := _pro()
	var c := cs.career
	c.first_team = false
	cs.season.teams[c.team_id].registered.erase(c.player.id)
	cs.call_up()
	assert_eq(str(c.moments[-1][1]), "debut", "the first call-up")
	var before := CareerContract.totals(c, cs)
	var mine := cs.season.book.bat(c.player.id)
	mine.pa = 4
	mine.hits = 1
	var g := ScheduledGame.new()
	g.away = c.team_id
	g.home = cs.season.divisions[0][3] if cs.season.divisions[0][3] != c.team_id else cs.season.divisions[0][4]
	cs._milestones(before, g)
	assert_true(c.moments.any(func(m: Array) -> bool: return str(m[1]) == "milestone" and str(m[2]) == "데뷔 첫 안타"))
	cs.extension = FreeAgency.terms(80000, 4)
	CareerFA.accept_extension(cs)
	assert_eq(str(c.moments[-1][1]), "deal")
	assert_eq(c.deals.size(), 1)


func test_the_flashback_keeps_the_best_in_order() -> void:
	var c := CareerPlayer.new()
	c.team_id = "t01"
	for y: int in 20:
		CareerLegacy.note(c, 2027 + y, "milestone", "기념구 %d" % y, "", "t01")
	CareerLegacy.note(c, 2040, "title", "홈런왕", "", "t01")
	CareerLegacy.note(c, 2027, "draft", "1라운드 1순위", "", "t01")
	var shown := CareerLegacy.flashback(c)
	assert_eq(shown.size(), CareerLegacy.FLASHBACK_MOST)
	assert_eq(str(shown[0][1]), "draft", "the draft first")
	assert_true(shown.any(func(m: Array) -> bool: return str(m[1]) == "title"), "a title is kept over the balls")
	for i: int in range(1, shown.size()):
		assert_gte(int(shown[i][0]), int(shown[i - 1][0]), "in order of the years")
	# A career from before the moments were kept: its debut and its balls.
	var old := CareerPlayer.new()
	old.team_id = "t02"
	old.seasons = [[2027, "다솜 팰컨스", 100, ""], [2028, "다솜 팰컨스", 120, ""]]
	old.milestones = [["hit_1", 2027, 12, "늘봄"]]
	assert_eq(CareerLegacy.flashback(old).size(), 2)
	assert_eq(CareerLegacy.clubs(old), [["다솜 팰컨스", 2027, 2028]])


func test_a_great_career_grades_as_a_legend_and_a_short_one_does_not() -> void:
	var c := CareerPlayer.new()
	c.position = "CF"
	c.pro_years = 16
	c.titles_won = [[2030, "홈런왕"], [2031, "홈런왕"], [2033, "타격왕"], [2035, "타점왕"]]
	c.all_stars = 9
	c.championships = [2031, 2034]
	var bat := BattingLine.new()
	bat.hits = 2350
	bat.home_runs = 340
	var value := CareerLegacy.score(c, bat, PitchingLine.new(), 144, true)
	assert_eq(str(CareerLegacy.grade_of(value)[1]), "레전드")
	var short := CareerPlayer.new()
	short.position = "CF"
	short.pro_years = 4
	var little := BattingLine.new()
	little.hits = 180
	assert_eq(str(CareerLegacy.grade_of(CareerLegacy.score(short, little, PitchingLine.new(), 144, false))[1]), "저니맨")


func test_his_number_is_retired_only_after_long_years_with_a_great_career() -> void:
	var cs := _pro()
	var c := cs.career
	var club: Team = cs.season.teams[c.team_id]
	var bat := BattingLine.new()
	bat.hits = 2300
	bat.home_runs = 320
	for y: int in 9:
		c.seasons.append([2027 + y, club.name, 140, ""])
	c.pro_years = 9
	CareerLegacy.settle(cs, bat, PitchingLine.new(), true)
	assert_false(c.number_retired, "nine seasons with the club are not enough")
	assert_ne(c.legacy_grade, "")
	var paid := c.legacy_reward
	c.legacy_grade = ""
	c.seasons.append([2036, club.name, 140, ""])
	c.pro_years = 10
	CareerLegacy.settle(cs, bat, PitchingLine.new(), true)
	assert_true(c.number_retired, "ten seasons and a hall of famer")
	assert_gte(c.legacy_reward, paid)


func test_the_farewell_tour_brings_a_gift_from_each_club_once() -> void:
	var cs := _pro()
	var c := cs.career
	c.player.born = cs.season.season_year - 37
	assert_true(CareerLegacy.should_retire(cs), "at 38 his club suggests it")
	assert_eq(CareerLegacy.tour_gift(cs, cs.season.divisions[0][0]), "", "no tour announced")
	CareerLegacy.announce(cs)
	assert_true(c.final_season)
	var other := str(cs.season.divisions[0][0]) if str(cs.season.divisions[0][0]) != c.team_id else str(cs.season.divisions[0][1])
	var pop := c.popularity
	assert_ne(CareerLegacy.tour_gift(cs, other), "")
	assert_eq(CareerLegacy.tour_gift(cs, other), "", "once a club")
	assert_eq(CareerLegacy.tour_gift(cs, c.team_id), "", "not from his own")
	assert_almost_eq(c.popularity, pop + 3.0, 1e-6)
	var young := _pro(72)
	young.career.player.born = young.season.season_year - 27
	assert_false(CareerLegacy.should_retire(young))


func test_the_story_is_saved() -> void:
	var cs := _pro()
	var c := cs.career
	CareerLegacy.note(c, 2027, "draft", "1라운드", "계약금", c.team_id)
	c.titles_won = [[2029, "홈런왕"]]
	c.all_stars = 3
	c.championships = [2030]
	c.deals = [[2031, "FA 잔류"]]
	c.best_salary = 120000
	c.final_season = true
	c.tour_gifts = [["t03", "기념 현판"]]
	c.legacy_grade = "프랜차이즈 스타"
	c.number_retired = true
	var back := SaveIO.career_from(SaveIO.career_to(cs), cs.season).career
	assert_eq(back.moments.size(), 1)
	assert_eq(back.titles_won, [[2029, "홈런왕"]])
	assert_eq(back.all_stars, 3)
	assert_eq(back.best_salary, 120000)
	assert_true(back.final_season)
	assert_eq(back.legacy_grade, "프랜차이즈 스타")
	assert_true(back.number_retired)
