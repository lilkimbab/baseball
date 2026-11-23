extends GutTest
## The commemorative balls (Milestones): what a game's numbers reach, kept on the career with
## its day and opponent, a ceremony cue, saved and loaded; the shelf's next ones; the
## achievements they count for.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func after_each() -> void:
	CareerSession.career_season = null
	CareerSession.season = null
	CareerSession.career = null


func _bat(hits: int, home_runs: int = 0, rbi: int = 0) -> Array:
	var b := BattingLine.new()
	b.hits = hits
	b.home_runs = home_runs
	b.rbi = rbi
	return [b, PitchingLine.new()]


func _pitch(wins: int, strikeouts: int, saves: int = 0) -> Array:
	var p := PitchingLine.new()
	p.wins = wins
	p.strikeouts = strikeouts
	p.saves = saves
	return [BattingLine.new(), p]


func _ids(list: Array) -> Array:
	return list.map(func(m: Array) -> String: return str(m[0]))


func test_a_first_hit_a_first_home_run_and_the_hundredth_hit() -> void:
	assert_eq(_ids(Milestones.crossed(_bat(0), _bat(1), false)), ["hit_1"])
	assert_eq(_ids(Milestones.crossed(_bat(0), _bat(1, 1, 1), false)), ["hit_1", "hr_1", "rbi_1"], "a home run in his first hit")
	assert_eq(_ids(Milestones.crossed(_bat(99, 5, 40), _bat(101, 5, 41), false)), ["hit_100"], "100 passed, not reached twice")
	assert_eq(Milestones.crossed(_bat(1), _bat(1), false), [], "nothing new")
	assert_eq(Milestones.crossed(_bat(0), _bat(1), true), [], "a pitcher's are a pitcher's")


func test_a_pitcher_s_first_win_strikeout_and_save() -> void:
	assert_eq(_ids(Milestones.crossed(_pitch(0, 0), _pitch(1, 6), true)), ["win_1", "k_1"])
	assert_eq(_ids(Milestones.crossed(_pitch(49, 98), _pitch(50, 101), true)), ["win_50", "k_100"])
	assert_eq(_ids(Milestones.crossed(_pitch(3, 40, 0), _pitch(3, 41, 1), true)), ["sv_1"])


func test_every_milestone_has_a_name_and_a_count() -> void:
	var seen := {}
	for m: Array in Milestones.LIST:
		assert_false(seen.has(m[0]), "one of each: %s" % m[0])
		seen[m[0]] = true
		assert_gt(int(m[3]), 0)
		assert_ne(Milestones.name_of(str(m[0])), str(m[0]))
		# Each reads a line's field that is there.
		var line: Object = PitchingLine.new() if bool(m[4]) else BattingLine.new()
		assert_true(str(m[2]) in line, "%s reads %s" % [m[0], m[2]])


func test_a_game_s_line_is_added_on_and_the_totals_left_alone() -> void:
	var totals := _bat(10, 2)
	var game := BattingLine.new()
	game.hits = 2
	game.home_runs = 1
	var now := Milestones.with_game(totals, game, null)
	assert_eq((now[0] as BattingLine).hits, 12)
	assert_eq((now[0] as BattingLine).home_runs, 3)
	assert_eq((totals[0] as BattingLine).hits, 10, "the totals stay as they were")


func test_the_next_balls_are_the_nearest_still_ahead() -> void:
	var next := Milestones.ahead(_bat(95, 3, 30), false, 2)
	assert_eq(next.size(), 2)
	assert_eq(str(next[0][0][0]), "hit_100", "95 of 100 hits is nearest")
	assert_eq(int(next[0][1]), 95)
	for a: Array in next:
		assert_ne(str(a[0][0]), "hit_1", "a ball he has is not ahead")


func test_a_first_team_game_keeps_the_ball_with_a_cue_and_a_save_keeps_it() -> void:
	var spec := PlayerCreator.Spec.new()
	spec.name = "기념구시험"
	spec.position = "CF"
	spec.type_id = "contact"
	var c := PlayerCreator.create(spec, CareerIO.load_default(), F.catalog())
	CareerSession.start(c, LeagueSession.league_clubs()[3].id, 36, 12)
	var cs := CareerSession.career_season
	cs.career.first_team = true
	var before := CareerContract.totals(cs.career, cs)
	var other := ""
	for id: String in cs.season.teams:
		if id != cs.career.team_id:
			other = id
			break
	var g := ScheduledGame.new()
	g.away = cs.career.team_id
	g.home = other
	var mine := cs.season.book.bat(cs.career.player.id)
	mine.pa = 4
	mine.ab = 4
	mine.hits = 1
	mine.rbi = 1
	cs.cues.clear()
	cs._milestones(before, g)
	assert_eq(cs.career.milestones.size(), 2, "first hit and first RBI: %s" % [cs.career.milestones])
	var ball: Array = cs.career.milestones[0]
	assert_eq(ball[0], "hit_1")
	assert_eq(int(ball[1]), cs.season.season_year)
	assert_eq(int(ball[2]), cs.season.day + 1)
	assert_eq(ball[3], cs.season.teams[other].name, "the opponent written on it")
	assert_eq(cs.cues.size(), 2)
	assert_eq(cs.cues[0][0], &"milestone")
	assert_eq(cs.cues[0][2], "데뷔 첫 안타")
	assert_true(Array(cs.log).any(func(l: String) -> bool: return l.contains("데뷔 첫 안타 달성")))
	# Only once.
	cs._milestones(CareerContract.totals(cs.career, cs), g)
	assert_eq(cs.career.milestones.size(), 2)
	# Saved and loaded.
	var back := SaveIO.career_from(SaveIO.career_to(cs), cs.season)
	assert_eq(back.career.milestones, cs.career.milestones)
	# The shelf shows his balls, the newest first, and the next ones.
	var shelf := BallShelf.new()
	shelf.fill(cs.career, CareerContract.totals(cs.career, cs))
	assert_eq(shelf.balls.size(), 4)
	assert_eq(shelf.balls[0][0], "데뷔 첫 타점")
	assert_true(bool(shelf.balls[1][2]))
	assert_false(bool(shelf.balls[3][2]), "the next ones are not his yet")
	shelf.free()


func test_the_balls_count_for_achievements() -> void:
	var book := AchievementBook.from_data(JsonIO.read_object(Achievements.DATA))
	var ids: Array = []
	for d: AchievementBook.Def in book.reach("milestone_balls", 1):
		ids.append(d.id)
	assert_true(ids.has("first_ball"))
	ids.clear()
	for d: AchievementBook.Def in book.reach("milestone_balls", 10):
		ids.append(d.id)
	assert_true(ids.has("ball_shelf"))
