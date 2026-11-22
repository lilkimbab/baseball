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


func test_the_manager_sets_the_order_and_the_rotation_on_the_line_up_tab() -> void:
	# docs/08 R5: two rows picked one after the other trade places; the plan is the club's.
	var screen := _screen()
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	screen.begin(clubs[4].id, 36)
	var s := LeagueSession.season
	var team: Team = s.teams[s.my_team]
	screen._tab = "lineup"
	screen.refresh()
	assert_true(team.batting_plan.is_empty(), "the computer's until something is changed")
	var before := LineupPlan.current(team, AiManager.new(s.env, s.catalog, s.ovr), s.rules)
	screen._lineup_pressed("L0", s, team)
	screen._lineup_pressed("L3", s, team)
	assert_eq(team.batting_plan.size(), 9)
	assert_eq(str(team.batting_plan[0][0]), str(before[3][0]), "the fourth batter leads off")
	assert_eq(str(team.batting_plan[3][0]), str(before[0][0]))
	# A bench man in for the ninth batter.
	var bench := LineupPlan.bench(team.batting_plan, team)
	screen._lineup_pressed("B" + bench[0].id, s, team)
	screen._lineup_pressed("L8", s, team)
	assert_eq(str(team.batting_plan[8][0]), bench[0].id)
	# Two starters trade turns.
	var first := team.rotation()[0].id
	screen._lineup_pressed("R0", s, team)
	screen._lineup_pressed("R2", s, team)
	assert_eq(team.rotation()[2].id, first)
	# The next game is played with it (a man resting today gives way at his place; the
	# season's seed comes from the clock, so who rests differs from run to run).
	var rest := s.resting(team, s.day)
	var lineup := s.lineup_for(team.id, s.day, AiManager.new(s.env, s.catalog, s.ovr))
	for i: int in 9:
		var planned := str(team.batting_plan[i][0])
		if not rest.has(planned):
			assert_eq(lineup.lineup[i].player_id, planned, "slot %d as planned" % (i + 1))
		assert_eq(Position.code(lineup.lineup[i].position), str(team.batting_plan[i][1]), "at the planned position")


func test_two_men_are_compared_from_the_picked_panel() -> void:
	# docs/08 R5: pin one, pick another, the two side by side; batters with batters only.
	var screen := _screen()
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	screen.begin(clubs[6].id, 36)
	var s := LeagueSession.season
	var team: Team = s.teams[s.my_team]
	var hitters: Array[Player] = []
	var pitcher: Player = null
	for p: Player in team.first_team():
		if p.is_pitcher():
			pitcher = p
		else:
			hitters.append(p)
	screen._tab = "roster"
	screen._compare_id = hitters[0].id
	screen._picked = hitters[1].id
	screen.refresh()
	assert_eq(LeagueScreen.find_player(s, hitters[0].id), hitters[0])
	assert_true(PlayerCompare.comparable(hitters[0], hitters[1]))
	assert_false(PlayerCompare.comparable(hitters[0], pitcher), "a batter is not compared with a pitcher")
	assert_false(PlayerCompare.comparable(hitters[0], hitters[0]))
	var view := PlayerCompare.open_for(screen, hitters[0], hitters[1], s)
	assert_not_null(view)
	var rows := PlayerCompare.ratings(hitters[0], hitters[1], s.catalog)
	assert_eq(rows.size(), 9, "contact and power by hand, eye, speed, running, fielding, arm")
	assert_almost_eq(float(rows[0][1]), hitters[0].batting.contact_r, 1e-6)
	assert_almost_eq(float(rows[0][2]), hitters[1].batting.contact_r, 1e-6)
	view.queue_free()


func test_the_records_room_lists_the_leaders_and_the_clubs() -> void:
	var screen := _screen()
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	screen.begin(clubs[2].id, 36)
	var s := LeagueSession.season
	for i: int in 12:
		screen.quick_result()
		screen.next_day()
	screen._tab = "records"
	for view: String in ["batting", "pitching", "clubs"]:
		screen._records_view = view
		screen.refresh()
	var d := s.division_of(s.my_team)
	var avg := LeagueRecords.leaders(s, d, LeagueRecords.batting_categories()[0], 10)
	assert_gt(avg.size(), 0, "someone qualifies after twelve games")
	var need := LeagueRecords.qualifying_pa(s, s.my_team)
	assert_eq(need, int(floorf(LeagueRecords.games_played(s, s.my_team) * 3.1)))
	assert_gt(LeagueRecords.games_played(s, s.my_team), 8)
	for i: int in avg.size():
		assert_gte(s.book.batting[avg[i].player_id].pa, LeagueRecords.qualifying_pa(s, avg[i].team_id), "only qualified men on a rate board")
		if i > 0:
			assert_lte(avg[i].value, avg[i - 1].value, "best first")
	var era := LeagueRecords.leaders(s, d, LeagueRecords.pitching_categories()[0], 10)
	for i: int in range(1, era.size()):
		assert_gte(era[i].value, era[i - 1].value, "the lowest ERA first")
	var hr := LeagueRecords.leaders(s, d, LeagueRecords.batting_categories()[1], 5)
	assert_gt(hr.size(), 0)
	assert_eq(hr[0].text, str(s.book.batting[hr[0].player_id].home_runs))
	for e: LeagueRecords.Entry in hr:
		assert_gt(e.value, 0.0, "nobody on the home-run board without a home run")
	# The clubs' totals are their men's added up, in the order of the table.
	var rows := LeagueRecords.clubs(s, d)
	assert_eq(rows.size(), s.divisions[d].size())
	assert_eq(str(rows[0][0]), s.standings[d].ranked()[0].team_id)
	var runs := 0
	for p: Player in s.teams[str(rows[0][0])].players:
		if s.book.batting.has(p.id):
			runs += s.book.batting[p.id].runs
	assert_eq((rows[0][1] as BattingLine).runs, runs)


func test_the_second_team_tab_shows_its_men_its_table_and_the_winter() -> void:
	# docs/08 R6.
	var screen := _screen()
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	screen.begin(clubs[5].id, 36)
	var s := LeagueSession.season
	for i: int in 3:
		screen.quick_result()
		screen.next_day()
	screen._tab = "farm"
	screen._picked = (s.teams[s.my_team] as Team).second_team()[0].id
	screen.refresh()
	screen._farm_view = "table"
	screen.refresh()
	assert_eq(s.farm.standings[s.division_of(s.my_team)].row(s.my_team).games(), s.day + 1, "a farm game every day so far, the first day too")
	var p: Player = (s.teams[s.my_team] as Team).second_team()[0]
	var line := LeagueScreen.farm_line(s, p)
	assert_true(line == "-" or line.contains("타석") or line.contains("이닝"))
	for n: int in 6:
		assert_eq(Development.stars_text(n if n <= 5 else 5).length(), 5)
