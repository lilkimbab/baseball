extends GutTest
## The league screen and a season played through it ( completion: a 36-game season
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


func test_a_season_with_one_club_ends_with_its_reward_and_a_new_choice() -> void:
	# (the user: one club, one season, rewards, then a new one): ten clubs in one
	# league, no second teams' league but second teams to call up, the reward paid once.
	var screen := _screen()
	var clubs := LeagueSession.league_clubs()
	assert_eq(clubs.size(), 10)
	screen.begin(clubs[4].id, 36)
	var s := LeagueSession.season
	assert_eq(s.divisions.size(), 1)
	assert_null(s.farm, "no second teams' league in the league")
	assert_false((s.teams[s.my_team] as Team).second_team().is_empty(), "second-team men to call up")
	screen.quick_result()
	screen.to_phase_end()
	var before := Profile.points
	screen.to_phase_end()
	assert_eq(s.phase, Season.Phase.OVER)
	var reward := LeagueScreen.season_reward(s)
	assert_gt(int(reward["total"]), 0)
	assert_almost_eq(float(reward["involvement"]), 0.4, 0.001, "left to the computer: two fifths")
	assert_true(s.rewarded, "paid as the season ended")
	assert_eq(Profile.points, before + int(reward["total"]), "paid once")
	screen.refresh()
	assert_eq(Profile.points, before + int(reward["total"]), "and only once")


func test_an_old_league_of_three_divisions_goes_on_to_the_promotion_verdict() -> void:
	var screen := _screen()
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	var mine := clubs[25].id
	LeagueSession.start(mine, 36, 3, clubs)
	LeagueSession.season.play_day()
	screen._tab = "home"
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
	screen.begin(clubs[2].id, 36)
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
	var s := LeagueSession.start(clubs[7].id, 36, 9)
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
	assert_eq(scene._title_side(), -1, "a regular-season game wins no title")


func test_the_game_that_wins_the_final_is_known_after_its_result_is_in() -> void:
	# The championship scene (FieldScenes.plan_champion) is for the clinching game only, though a
	# league game's result reaches the series the moment it ends.
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	var s := LeagueSession.start(clubs[7].id, 36, 9)
	s.play_regular_season()
	var post: Postseason = s.postseasons[0]
	var guard := 0
	while s.phase == Season.Phase.POSTSEASON and post.current < post.format.size() - 1 and guard < 60:
		s.play_day(true)
		s.advance()
		guard += 1
	assert_eq(post.current, post.format.size() - 1, "on to the final")
	var series := post.series()
	s.my_team = series.high
	series.high_wins = series.wins_needed - 1
	series.low_wins = series.wins_needed - 1
	var g: ScheduledGame = null
	for i: int in 10:
		g = s.my_game_today()
		if g != null and not g.played:
			break
		s.advance()
	assert_not_null(g, "the deciding game")
	LeagueSession.pending = g
	var scene := MATCH.instantiate() as ManagerMatch
	scene.use_motion = false
	add_child_autofree(scene)
	guard = 0
	while not scene.game.over and guard < 300:
		scene.skip(true)
		for i: int in 3:
			scene.step(1.0 / 60.0)
		guard += 1
	assert_true(scene.game.over)
	assert_true(g.played, "the result is in the series already")
	if scene.game.winner >= 0:
		assert_true(series.finished())
		assert_eq(scene._title_side(), scene.game.winner, "the winner of the deciding game is champion")
	else:
		assert_eq(scene._title_side(), -1, "a tie wins nothing")


func test_the_manager_sets_the_order_and_the_rotation_on_the_line_up_tab() -> void:
	# two rows picked one after the other trade places; the plan is the club's.
	var screen := _screen()
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	screen.begin(clubs[4].id, 36)
	var s := LeagueSession.season
	var team: Team = s.teams[s.my_team]
	screen._tab = "lineup"
	screen.refresh()
	assert_true(team.batting_plan.is_empty(), "the computer's until something is changed")
	var before := LineupPlan.current(team, AiManager.new(s.env, s.catalog, s.ovr), s.rules)
	screen._lineup_pressed("O0", s, team)
	screen._lineup_pressed("O3", s, team)
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


func test_cards_dragged_on_the_diamond_and_the_staff() -> void:
	# The user: players dragged onto their positions on the ballpark; the rotation, the set-up
	# men and the closer set by hand, the computer's choices kept as recommendations.
	var screen := _screen()
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	screen.begin(clubs[2].id, 36)
	var s := LeagueSession.season
	var team: Team = s.teams[s.my_team]
	screen._tab = "lineup"
	screen.refresh()
	var before := LineupPlan.current(team, AiManager.new(s.env, s.catalog, s.ovr), s.rules)
	# Two fielders dropped on each other trade positions, not places in the order.
	screen._lineup_drop("L1", "L2", s, team)
	assert_eq(str(team.batting_plan[1][0]), str(before[1][0]))
	assert_eq(str(team.batting_plan[1][1]), str(before[2][1]))
	assert_eq(str(team.batting_plan[2][1]), str(before[1][1]))
	# A bench man dropped on the fifth batter's card takes his place.
	var bench := LineupPlan.bench(team.batting_plan, team)
	screen._lineup_drop("B" + bench[0].id, "L4", s, team)
	assert_eq(str(team.batting_plan[4][0]), bench[0].id)
	# The recommended bullpen: the best reliever closes, the next two set up.
	var rec := screen._recommended_bullpen(s, team)
	assert_ne(str(rec["closer"]), "")
	assert_eq((rec["setup"] as Array).size(), 2)
	# Another reliever dropped on the closer's place closes; the old closer goes back.
	var other := ""
	for man: Player in team.first_team():
		if man.is_pitcher() and man.role() != &"SP" and man.id != str(rec["closer"]) and not (rec["setup"] as Array).has(man.id):
			other = man.id
			break
	screen._lineup_drop("P" + other, "CL", s, team)
	assert_eq(str(team.bullpen_plan["closer"]), other)
	assert_eq(team.bullpen_plan["setup"], rec["setup"], "the set-up men kept")
	# The closer and a set-up man trade places.
	screen._lineup_drop("SU0", "CL", s, team)
	assert_eq(str(team.bullpen_plan["closer"]), str((rec["setup"] as Array)[0]))
	assert_eq(str((team.bullpen_plan["setup"] as Array)[0]), other)
	# A starter does not close; a starter beyond the five takes a place in the rotation.
	var starters := team.rotation()
	screen._lineup_drop("R0", "CL", s, team)
	assert_eq(str((team.bullpen_plan["setup"] as Array)[0]), other, "nothing changed")
	if starters.size() > 5:
		screen._lineup_drop("P" + starters[5].id, "R1", s, team)
		assert_eq(team.rotation()[1].id, starters[5].id)
		assert_eq(team.rotation()[5].id, starters[1].id, "the man he replaced waits")
	screen.refresh()
	# The computer's manager uses the closer that was chosen.
	var manager := AiManager.new(s.env, s.catalog, s.ovr)
	manager.use_bullpen_plan(team)
	assert_eq(manager.role_overall[str(team.bullpen_plan["closer"])], 10000.0)
	# 추천대로 brings the computer's choices back.
	team.bullpen_plan = screen._recommended_bullpen(s, team)
	assert_eq(str(team.bullpen_plan["closer"]), str(rec["closer"]))


func test_two_men_are_compared_from_the_picked_panel() -> void:
	# pin one, pick another, the two side by side; batters with batters only.
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
	assert_eq(rows.size(), 8, "contact and power by hand, eye, running (speed and base-running as one), fielding, arm")
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
	# in an old league of three divisions (a new league has no second teams' league).
	var screen := _screen()
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	LeagueSession.start(clubs[5].id, 36, 3, clubs)
	LeagueSession.season.play_day()
	screen._tab = "home"
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


func test_a_trade_the_other_club_finds_fair_goes_through_before_the_deadline() -> void:
	# The user: trades in the regular season. A star for a bench man is refused; the bench man
	# and a better player for their regular is taken; the men change clubs and places.
	var clubs := LeagueSession.league_clubs()
	var s := LeagueSession.start(clubs[1].id, 36, 4)
	var mine: Team = s.teams[s.my_team]
	var theirs: Team = s.teams[s.divisions[0][3] if s.divisions[0][3] != s.my_team else s.divisions[0][4]]
	var by_ovr := func(team: Team) -> Array[Player]:
		var men: Array[Player] = team.players.duplicate()
		men.sort_custom(func(x: Player, y: Player) -> bool: return ClubRules.player_ovr(x, s.ovr, s.catalog) > ClubRules.player_ovr(y, s.ovr, s.catalog))
		return men
	var my_men: Array[Player] = by_ovr.call(mine)
	var their_men: Array[Player] = by_ovr.call(theirs)
	var star := their_men[0]
	var bench := my_men[my_men.size() - 1]
	var no := Trade.weigh(s, mine, theirs, PackedStringArray([bench.id]), PackedStringArray([star.id]))
	assert_false(bool(no["accepted"]), "a star for a bench man")
	var fair := their_men[their_men.size() - 1]
	var yes := Trade.weigh(s, mine, theirs, PackedStringArray([my_men[0].id]), PackedStringArray([fair.id]))
	assert_true(bool(yes["accepted"]), "his best man for their worst")
	var was_first := theirs.is_registered(fair.id)
	Trade.apply(s, mine, theirs, PackedStringArray([my_men[0].id]), PackedStringArray([fair.id]))
	assert_not_null(theirs.player(my_men[0].id))
	assert_null(mine.player(my_men[0].id))
	assert_not_null(mine.player(fair.id))
	if was_first:
		assert_true(theirs.is_registered(my_men[0].id), "he takes the first-team place of the man who left")
	s.day = Trade.deadline(s) + 1
	assert_false(bool(Trade.weigh(s, mine, theirs, PackedStringArray([my_men[1].id]), PackedStringArray([their_men[2].id]))["accepted"]), "not after the deadline")
