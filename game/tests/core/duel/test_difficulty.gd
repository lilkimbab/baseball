extends GutTest
## Difficulty (the user, 2026-11-22: judge the difficulty from the player's side; rewards by
## difficulty; in the league, the harder the stronger the other clubs). Measured with
## tools/difficulty_report.gd and tools/balance_report.gd; these pin what the levels do.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func test_each_level_is_harder_than_the_last_and_pays_more() -> void:
	var last := {}
	for level: int in [Difficulty.Level.ROOKIE, Difficulty.Level.PRO, Difficulty.Level.ALL_STAR, Difficulty.Level.LEGEND]:
		var t: Dictionary = Difficulty.TABLE[level]
		if not last.is_empty():
			assert_lt(float(t["timing"]), float(last["timing"]), "a narrower timing window")
			assert_gt(float(t["floor"]), float(last["floor"]), "less of a small aiming error forgiven")
			assert_gt(float(t["scatter"]), float(last["scatter"]), "wilder pitches by hand")
			assert_gt(Difficulty.reward(level, "points"), Difficulty.reward(level - 1, "points"), "and more points")
			assert_gt(Difficulty.league_form(level), Difficulty.league_form(level - 1), "and a stronger league")
		last = t
	assert_eq(Difficulty.reward(Difficulty.Level.LEGEND, "gp", false), 1.0, "a simulated game pays 프로's at most")
	assert_eq(Difficulty.reward(Difficulty.Level.ROOKIE, "gp"), 1.0, "playing never pays less than simulating")


func test_only_the_person_s_own_swing_and_pitch_change() -> void:
	var resolver := PhysicalResolver.new(F.env(), F.catalog(), F.manager(), Rng.new(3))
	var state := F.game()
	resolver.difficulty = Difficulty.Level.LEGEND
	# The computer batting: its own settings.
	var duel := resolver.new_duel(state)
	assert_false(duel.settings.aim_forgiving)
	assert_eq(duel.settings.timing_scale, 1.0)
	# The person batting.
	resolver.person_bats = state.batting()
	duel = resolver.new_duel(state)
	assert_true(duel.settings.aim_forgiving)
	assert_eq(duel.settings.timing_scale, float(Difficulty.TABLE[Difficulty.Level.LEGEND]["timing"]))
	assert_eq(duel.settings.hand_scatter, 1.0, "the computer is pitching")
	resolver.person_bats = -1
	resolver.person_pitches = state.fielding()
	duel = resolver.new_duel(state)
	assert_eq(duel.settings.hand_scatter, float(Difficulty.TABLE[Difficulty.Level.LEGEND]["scatter"]))


func test_the_other_clubs_play_up_at_harder_levels_the_manager_s_does_not() -> void:
	var clubs := F.teams(4)
	var season := Season.create(clubs, 10, 36, 4, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), ClubIO.load_default())
	season.manage(clubs[0].id)
	var other: Team = clubs[1]
	var man: Player = null
	for p: Player in other.first_team():
		if not p.is_pitcher():
			man = p
			break
	var mine_man: Player = null
	for p: Player in (clubs[0] as Team).first_team():
		if not p.is_pitcher():
			mine_man = p
			break
	var contact := func(team: Team, id: String, level: int) -> float:
		season.difficulty = level
		var view := season.squad_for(team, 0, team.rotation()[0].id)
		return view.player(id).batting.contact_r
	var easy: float = contact.call(other, man.id, Difficulty.Level.ROOKIE)
	var hard: float = contact.call(other, man.id, Difficulty.Level.LEGEND)
	assert_gt(hard, easy, "a stronger league at 레전드")
	assert_almost_eq(float(contact.call(clubs[0], mine_man.id, Difficulty.Level.ROOKIE)), float(contact.call(clubs[0], mine_man.id, Difficulty.Level.LEGEND)), 0.001, "his own club as it is")


func test_club_points_buy_better_scouting_and_another_report() -> void:
	var gen := LeagueGenerator.new(RosterIO.load_names(), F.catalog(), 6)
	var clubs: Array[Team] = []
	for i: int in 10:
		clubs.append(gen.team(i, 50.0))
	var season := Season.create(clubs, 10, 36, 6, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), ClubIO.load_default())
	season.manage(clubs[2].id)
	var club := season.club
	club.points = 2000
	var before := club.candidates.duplicate()
	assert_true(club.upgrade_scout(season.club_rules))
	assert_eq(club.scout_level, 2)
	assert_eq(club.points, 2000 - season.club_rules.scout_upgrade[0])
	assert_true(club.upgrade_scout(season.club_rules))
	assert_false(club.upgrade_scout(season.club_rules), "three is the top")
	club.sign(0, clubs[2], season.club_rules)
	assert_true(club.buy_report(season.club_rules))
	season.refresh_candidates(2)
	assert_true(club.signed_today, "a second report is not a second signing")
	assert_false(club.buy_report(season.club_rules), "one more report a day")
	var names := func(list: Array) -> String:
		var out := PackedStringArray()
		for man: Player in list:
			out.append(man.name)
		return ",".join(out)
	assert_ne(names.call(club.candidates), names.call(before), "new names")


func test_a_managed_game_pays_club_points_by_its_difficulty() -> void:
	var club := Club.new()
	var rules := ClubIO.load_default()
	club.earn(1, false, rules, Difficulty.reward(Difficulty.Level.LEGEND, "club"))
	assert_eq(club.points, roundi(int(rules.points["win"]) * Difficulty.reward(Difficulty.Level.LEGEND, "club")))
