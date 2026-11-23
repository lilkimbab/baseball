extends GutTest
## A career begun in high school (docs/08 R8-3): his school's weekend league, its playoff, the
## draft, and into the pros with the club that picked him.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func after_each() -> void:
	CareerSession.career_season = null
	CareerSession.season = null
	CareerSession.career = null
	CareerSession.draft = null


func _student(position: String, type_id: String, seed_value: int) -> CareerPlayer:
	var spec := PlayerCreator.Spec.new()
	spec.name = "고교생%d" % seed_value
	spec.position = position
	spec.type_id = type_id
	return PlayerCreator.create(spec, CareerIO.load_default(), F.catalog())


func _school(name: String) -> String:
	for s: Dictionary in SchoolLeague.schools():
		if str(s["name"]) == name:
			return str(s["id"])
	return ""


func test_the_schools_are_real_names_in_their_regions() -> void:
	var all := SchoolLeague.schools()
	assert_gt(all.size(), 40)
	assert_ne(_school("덕수고"), "")
	assert_ne(_school("북일고"), "")
	var seoul := SchoolLeague.league_of(_school("휘문고"))
	assert_true(seoul.any(func(s: Dictionary) -> bool: return str(s["name"]) == "충암고"), "휘문고 and 충암고 share a league")
	for s: Dictionary in all:
		assert_gte(SchoolLeague.league_of(str(s["id"])).size(), 5, "%s's league is big enough" % s["name"])


func test_students_are_younger_and_weaker_than_the_pros() -> void:
	var c := _student("SS", "contact", 1)
	var season := SchoolLeague.season_for(c, _school("덕수고"), 2026, 1, F.catalog())
	assert_true(season.school)
	var team: Team = season.teams[_school("덕수고")]
	assert_true(team.is_registered(c.player.id), "he plays from the first day")
	assert_true(c.first_team)
	assert_eq(2026 - c.player.born, 18)
	var school_ovr := 0.0
	var n := 0
	for t: Team in season.teams.values():
		for p: Player in t.players:
			if p.id == c.player.id:
				continue
			var age := 2026 - p.born
			assert_between(age, 16, 18, "a student")
			assert_false(p.is_foreign())
			school_ovr += ClubRules.player_ovr(p, F.overall(), F.catalog())
			n += 1
	school_ovr /= n
	# The pros' first teams (the fictional league's top ten) are well above.
	var pro := 0.0
	var m := 0
	for t: Team in LeagueSession.league_clubs():
		for p: Player in t.first_team():
			pro += ClubRules.player_ovr(p, F.overall(), F.catalog())
			m += 1
	pro /= m
	assert_lt(school_ovr, pro - 10.0, "students %.1f, pros %.1f" % [school_ovr, pro])


func test_a_school_season_then_the_draft_then_the_pros() -> void:
	var c := _student("CF", "speed", 2)
	CareerSession.start_school(c, _school("장충고"), 72, 2)
	var cs := CareerSession.career_season
	assert_true(cs.season.school)
	var guard := 0
	var games := 0
	while not cs.season.finished() and guard < 200:
		if cs.has_game():
			cs.quick()
			games += 1
		cs.next_day()
		guard += 1
	assert_true(cs.season.finished())
	assert_between(games, 12, 18, "a short season and maybe its playoff")
	assert_false(cs.all_star_done, "no all-star game in high school")
	var d := CareerSession.hold_draft()
	assert_not_null(d)
	assert_eq(d.picks.size(), Draft.ROUNDS * 10, "eleven rounds of ten")
	assert_eq(d.order.size(), 10)
	# The same order every round; the bonus goes down round by round.
	for i: int in d.picks.size():
		assert_eq(d.picks[i].team_id, d.order[i % 10])
	assert_gt(d.picks[0].bonus, d.picks[10].bonus)
	assert_gt(d.picks[10].bonus, d.picks[d.picks.size() - 1].bonus)
	assert_true(d.his != null or d.developmental_team != "", "picked, or offered a contract")
	# The same draft again for the same season.
	CareerSession.draft = null
	var again := CareerSession.hold_draft()
	assert_eq(again.team_id(), d.team_id())
	var club := d.team_id()
	CareerSession.turn_pro()
	cs = CareerSession.career_season
	assert_false(cs.season.school)
	assert_eq(cs.career.team_id, club)
	assert_false(cs.career.first_team, "a rookie starts in the second team")
	assert_true(cs.farm_mode(), "in the futures league")
	assert_eq(cs.season.season_year, d.year + 1)
	assert_ne(cs.career.drafted, "")
	assert_gt(cs.career.signing_bonus, 0)
	assert_eq(cs.pro_games, 72)
	assert_eq(cs.season.games_per_team, 72)
	assert_true(Array(cs.log).any(func(line: String) -> bool: return line.contains("입단")))


func test_a_good_season_gets_a_better_pick() -> void:
	# The clubs read his season: the same student drafted after a fine season and after a poor
	# one (his numbers set by hand) goes earlier after the fine one, on average.
	var better := 0
	for seed_value: int in [3, 4, 5, 6, 7, 8]:
		var picks: Array[int] = []
		for good: bool in [true, false]:
			var c := _student("1B", "power", seed_value)
			var season := SchoolLeague.season_for(c, _school("경남고"), 2026, seed_value, F.catalog())
			var line := season.book.bat(c.player.id)
			line.pa = 60
			line.ab = 52
			line.hits = 24 if good else 8
			line.home_runs = 6 if good else 0
			line.walks = 8
			var d := Draft.run(c, season, LeagueSession.league_clubs(), seed_value)
			picks.append(d.his.overall if d.his != null else 200)
		if picks[0] < picks[1]:
			better += 1
	assert_gte(better, 5, "a fine season moves him up")
