extends GutTest
## The all-star break: picks, the two teams, the derby, and the career
## player's part.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func _career_season(position: String, type_id: String, seed_value: int) -> CareerSeason:
	var r := CareerIO.load_default()
	var spec := PlayerCreator.Spec.new()
	spec.name = "별%d" % seed_value
	spec.position = position
	spec.type_id = type_id
	var c := PlayerCreator.create(spec, r, F.catalog())
	var gen := LeagueGenerator.new(RosterIO.load_names(), F.catalog(), seed_value)
	var clubs: Array[Team] = []
	for i: int in 10:
		clubs.append(gen.team(i, 50.0))
	var season := Season.create(clubs, 10, 36, seed_value, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), ClubIO.load_default())
	c.join(clubs[2])
	return CareerSeason.start(season, c, r)


func test_the_break_comes_at_mid_season_with_picks_teams_and_a_derby() -> void:
	var cs := _career_season("1B", "power", 41)
	var guard := 0
	while not cs.all_star_done and guard < 200:
		if cs.has_game():
			cs.quick()
		cs.next_day()
		guard += 1
	assert_true(cs.all_star_done)
	assert_between(cs.season.day, int(cs.season.total_days() * 0.5), int(cs.season.total_days() * 0.5) + 2)
	assert_eq(cs.all_star_selected.size(), 22)
	var d := cs.season.division_of(cs.career.team_id)
	var sides := AllStar.teams(cs.season, d, cs.all_star_selected, cs.career)
	for t: Team in sides:
		var hitters := 0
		var catcher := false
		for p: Player in t.players:
			if not p.is_pitcher():
				hitters += 1
				catcher = catcher or p.primary_position() == Position.Kind.C
		assert_true(catcher, "%s has a catcher" % t.name)
		assert_gte(hitters, 9)
		assert_false(t.rotation().is_empty(), "and a starter")
	# Everyone in the derby has a count unless the career player still has his turn.
	if cs.derby_waiting:
		var winner := cs.quick_derby()
		assert_ne(winner, "")
	assert_gte(cs.derby.size(), 7)


func test_the_all_star_game_counts_for_nothing_in_the_season() -> void:
	var cs := _career_season("SS", "contact", 42)
	cs.career.popularity = 500.0
	# Up from the start (a 36-game season reaches the break before a rookie's twenty games
	# in the second team).
	cs.call_up()
	var guard := 0
	while not cs.all_star_done and guard < 200:
		# (Kept up to the break: a rookie may be sent down for his form, which is not what this
		# is about; his recent games are forgotten before each one.)
		cs.recent_first.clear()
		if cs.has_game():
			cs.quick()
		cs.next_day()
		guard += 1
	assert_true(cs.all_star_today, "a popular player is picked")
	var games_before := 0
	for row: StandingsRow in cs.season.standings[0].rows.values():
		games_before += row.games()
	var report := cs.quick_all_star()
	assert_eq(report.goal, "올스타전")
	assert_false(cs.all_star_today)
	var games_after := 0
	for row: StandingsRow in cs.season.standings[0].rows.values():
		games_after += row.games()
	assert_eq(games_after, games_before, "not in the standings")
	assert_string_contains(cs.log[-1], "올스타전")


func test_more_power_hits_more_derby_home_runs() -> void:
	var rng := Rng.new(5)
	var weak := 0
	var strong := 0
	for i: int in 200:
		weak += AllStar.derby_swings(40.0, 10, rng)
		strong += AllStar.derby_swings(85.0, 10, rng)
	assert_gt(strong, weak * 2)


func test_the_fans_vote_is_announced_as_two_best_twelves() -> void:
	# 청팀 and 백팀, each with its best twelve by place; his own line lit; a show to announce it.
	var cs := _career_season("SS", "contact", 43)
	cs.career.popularity = 500.0
	var guard := 0
	while not cs.all_star_done and guard < 200:
		cs.recent_first.clear()
		if cs.has_game():
			cs.quick()
		cs.next_day()
		guard += 1
	var d := cs.season.division_of(cs.career.team_id)
	var sides := AllStar.teams(cs.season, d, cs.all_star_selected, cs.career)
	assert_eq(sides[0].name, "청팀 올스타")
	assert_eq(sides[1].short_name, "백팀")
	assert_eq(sides[0].primary, AllStar.TEAM_COLOURS[0][0])
	var board := AllStar.board(cs.season, d, cs.all_star_selected, cs.career)
	var per_side := [0, 0]
	var slots: Array = []
	for line: String in board:
		var f := line.split("|")
		assert_eq(f.size(), 6, line)
		per_side[int(f[0])] += 1
		if int(f[0]) == 0:
			slots.append(f[1])
		assert_gt(int(f[4]), 100000, "a ballot's count")
	assert_eq(per_side, [12, 12], "twelve a side")
	assert_eq(slots[0], "선발투수")
	assert_eq(slots[3], "포수")
	assert_eq(slots[11], "지명타자")
	var kinds: Array = cs.cues.map(func(c: Array) -> StringName: return c[0])
	assert_true(kinds.has(&"all_star_vote"), "announced as a show")
	var vote: Array = cs.cues[kinds.find(&"all_star_vote")]
	assert_eq((vote[3] as PackedStringArray).size(), 24)
	if cs.all_star_selected.has(cs.career.player.id):
		assert_string_contains(str(vote[2]), "올스타 선정")
	assert_eq(AllStarVote._thousands(1234567), "1,234,567")
