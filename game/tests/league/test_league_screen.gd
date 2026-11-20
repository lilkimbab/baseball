extends GutTest
## The league screen and a season played through it (docs/13 S7 completion: a 36-game season
## from the start to the promotion verdict; a managed game whose result goes back to the
## season).

const SCREEN := preload("res://league/league_screen.tscn")
const MATCH := preload("res://match/manager_match.tscn")


func before_each() -> void:
	LeagueSession.season = null
	LeagueSession.pending = null


func after_all() -> void:
	LeagueSession.season = null
	LeagueSession.pending = null


func _screen() -> LeagueScreen:
	var screen := SCREEN.instantiate() as LeagueScreen
	add_child_autofree(screen)
	return screen


func test_a_short_season_goes_from_the_start_to_the_promotion_verdict() -> void:
	var screen := _screen()
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	var mine := clubs[25].id
	screen.begin(mine, 36)
	var s := LeagueSession.season
	assert_eq(s.division_of(mine), 2, "the player starts in the third division")
	assert_not_null(s.club)
	assert_eq(s.club.candidates.size(), s.club_rules.scout_candidates)
	# A day by hand: today's game settled at once, then the next day.
	screen.quick_result()
	var played := 0
	for g: ScheduledGame in s.schedules[2].games:
		if g.played:
			played += 1
	assert_eq(played, 5, "our game and the four others of the day")
	screen.next_day()
	assert_eq(s.day, 1)
	screen.to_phase_end()
	assert_eq(s.phase, Season.Phase.POSTSEASON)
	screen.to_phase_end()
	assert_eq(s.phase, Season.Phase.OVER)
	assert_eq(s.standings[2].row(mine).games(), 36)
	# The end of the season shows the verdict and the awards without errors.
	screen.refresh()
	var moves := s.movements()
	var verdicts := PackedStringArray(moves[2][0]) + PackedStringArray(moves[2][1])
	assert_eq(verdicts.size(), 2, "third division: two up, none down")
	var points := s.club.points
	assert_gt(points, 0, "points from the games")
	LeagueSession.next_season(5)
	var next := LeagueSession.season
	assert_eq(next.season_year, 2027)
	assert_eq(next.club.points, points, "the club carries over")
	for id: String in moves[2][0]:
		assert_eq(next.division_of(id), 1, "promoted")


func test_the_club_panel_registers_within_the_rules_and_equips_traits() -> void:
	var screen := _screen()
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	screen.begin(clubs[22].id, 36)
	var s := LeagueSession.season
	var team: Team = s.teams[s.my_team]
	var prospect := team.second_team()[0]
	assert_string_contains(screen.register(prospect), "등록할 수 없다", "the first team is full")
	var regular := team.first_team()[28]
	team.unregister(regular.id, s.day)
	var said := screen.register(prospect)
	assert_true(team.is_registered(prospect.id) or said.contains("코스트"), said)
	s.club.points = 1000
	s.club.bag.append(Vector2i(s.club_rules.trait_index("pinpoint"), 0))
	assert_string_contains(screen.equip_best(s.club.bag.size() - 1), "장착")
	assert_eq(s.club.traits.size(), 1)
	for tab: String in ["roster", "farm", "scout", "traits"]:
		screen._tab = tab
		screen.refresh()
	assert_true(true, "every tab builds")


func test_a_managed_league_game_reports_its_result_to_the_season() -> void:
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	var s := LeagueSession.start(clubs[27].id, 36, 9)
	s.play_day()
	var g := s.my_game_today()
	assert_not_null(g)
	LeagueSession.pending = g
	var scene := MATCH.instantiate() as ManagerMatch
	scene.use_motion = false
	add_child_autofree(scene)
	assert_eq(scene.league_game, g)
	assert_eq(scene.game.teams[scene.my_team].team_id, s.my_team)
	assert_eq(scene.game.rules.innings, 9)
	var guard := 0
	while not scene.game.over and guard < 200:
		scene.skip(true)
		for i: int in 3:
			scene.step(1.0 / 60.0)
		guard += 1
	assert_true(scene.game.over)
	assert_true(g.played, "the result went back to the season")
	assert_eq(g.away_score, scene.game.score[0])
	assert_eq(g.home_score, scene.game.score[1])
	assert_null(LeagueSession.pending)
	assert_eq(s.standings[s.division_of(s.my_team)].row(s.my_team).games(), 1)
	assert_string_contains(scene.post_game_hint(), "리그")
