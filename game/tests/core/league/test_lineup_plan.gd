extends GutTest
## The manager's own line-up and rotation (docs/08 R5): a batting order and positions he set
## are the ones played, a man who cannot play today gives way at his position to the best one
## free, a plan that does not cover the field is not used, the starters take their turns in
## his order, and all of it is saved with the league.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func _team() -> Team:
	return F.teams(5)[0]


## The computer's line-up turned into a plan, reversed (to tell it apart from the computer's).
func _reversed_plan(team: Team, ai: AiManager) -> Array:
	var auto := ai.make_lineup(team, RuleSet.kbo_2026(), team.rotation()[0].id)
	var plan: Array = []
	for slot: LineupSlot in auto.lineup:
		plan.push_front([slot.player_id, Position.code(slot.position)])
	return plan


func test_the_manager_s_order_and_positions_are_played() -> void:
	var team := _team()
	var ai := F.manager()
	team.batting_plan = _reversed_plan(team, ai)
	var game := ai.make_lineup(team, RuleSet.kbo_2026(), team.rotation()[0].id)
	assert_eq(game.lineup.size(), 9)
	for i: int in 9:
		assert_eq(game.lineup[i].player_id, str(team.batting_plan[i][0]))
		assert_eq(Position.code(game.lineup[i].position), str(team.batting_plan[i][1]))
	for slot: LineupSlot in game.lineup:
		assert_false(game.bench.has(slot.player_id), "nobody both in the line-up and on the bench")


func test_a_man_resting_gives_way_at_his_position() -> void:
	var team := _team()
	var ai := F.manager()
	team.batting_plan = _reversed_plan(team, ai)
	var out_id := str(team.batting_plan[4][0])
	var kind := Position.from_code(str(team.batting_plan[4][1]))
	var rest: Dictionary[String, bool] = {out_id: true}
	var game := ai.make_lineup(team, RuleSet.kbo_2026(), team.rotation()[0].id, rest)
	assert_ne(game.lineup[4].player_id, out_id, "someone else bats fifth")
	assert_eq(game.lineup[4].position, kind, "at the same position")
	var p := team.player(game.lineup[4].player_id)
	assert_true(kind == Position.Kind.DH or p.aptitude(kind) > 0.0, "a man who can play it")
	for i: int in 9:
		if i != 4:
			assert_eq(game.lineup[i].player_id, str(team.batting_plan[i][0]), "the rest as planned")


func test_a_plan_that_does_not_cover_the_field_is_not_used() -> void:
	var team := _team()
	var ai := F.manager()
	var plan := _reversed_plan(team, ai)
	# Two first basemen and no catcher.
	for i: int in 9:
		if str(plan[i][1]) == "C":
			plan[i][1] = "1B"
	team.batting_plan = plan
	var game := ai.make_lineup(team, RuleSet.kbo_2026(), team.rotation()[0].id)
	var catchers := game.lineup.filter(func(s: LineupSlot) -> bool: return s.position == Position.Kind.C)
	assert_eq(catchers.size(), 1, "the computer's line-up instead, with its catcher")


func test_the_starters_take_their_turns_in_the_manager_s_order() -> void:
	var team := _team()
	var usual := team.rotation()
	assert_gt(usual.size(), 2)
	team.rotation_plan = PackedStringArray([usual[2].id, usual[0].id])
	var planned := team.rotation()
	assert_eq(planned[0].id, usual[2].id)
	assert_eq(planned[1].id, usual[0].id)
	assert_eq(planned.size(), usual.size(), "those left out follow")


func test_the_plans_are_saved_with_the_league() -> void:
	var gen := LeagueGenerator.new(RosterIO.load_names(), F.catalog(), 7)
	var clubs: Array[Team] = []
	for i: int in 20:
		clubs.append(gen.team(i, 50.0))
	var s := Season.create(clubs, 10, 36, 7, RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), ClubIO.load_default())
	var mine: Team = s.teams[clubs[3].id]
	mine.batting_plan = _reversed_plan(mine, F.manager())
	mine.rotation_plan = PackedStringArray([mine.rotation()[1].id])
	var back := SaveIO.season_from(SaveIO.season_to(s))
	var again: Team = back.teams[clubs[3].id]
	assert_eq(again.batting_plan.size(), 9)
	assert_eq(str(again.batting_plan[0][0]), str(mine.batting_plan[0][0]))
	assert_eq(again.rotation_plan, mine.rotation_plan)


# --- Editing (LineupPlan) ---


func test_editing_an_order_keeps_it_playable_or_says_why_not() -> void:
	var team := _team()
	var ai := F.manager()
	var plan := LineupPlan.current(team, ai, RuleSet.kbo_2026())
	assert_eq(plan.size(), 9, "the computer's order to start from")
	assert_true(LineupPlan.problems(plan, team).is_empty())
	var first := str(plan[0][0])
	LineupPlan.swap_order(plan, 0, 3)
	assert_eq(str(plan[3][0]), first, "traded places in the order")
	assert_true(LineupPlan.problems(plan, team).is_empty(), "still playable: each kept his position")
	# A catcher and the designated hitter trade positions: the hitter cannot catch.
	var c := -1
	var dh := -1
	for i: int in 9:
		if str(plan[i][1]) == "C":
			c = i
		if str(plan[i][1]) == "DH":
			dh = i
	var hitter := team.player(str(plan[dh][0]))
	LineupPlan.swap_positions(plan, c, dh)
	if hitter.aptitude(Position.Kind.C) <= 0.0:
		assert_false(LineupPlan.problems(plan, team).is_empty(), "says who cannot catch")
	LineupPlan.swap_positions(plan, c, dh)
	var bench := LineupPlan.bench(plan, team)
	assert_gt(bench.size(), 0)
	LineupPlan.bring_in(plan, dh, bench[0].id)
	assert_eq(str(plan[dh][0]), bench[0].id)
	assert_eq(str(plan[dh][1]), "DH", "at the place's position")
	assert_false(LineupPlan.bench(plan, team).has(bench[0]))


func test_two_starters_trade_turns() -> void:
	var team := _team()
	var before := team.rotation()
	LineupPlan.swap_rotation(team, 0, 1)
	var after := team.rotation()
	assert_eq(after[0].id, before[1].id)
	assert_eq(after[1].id, before[0].id)


func test_a_resting_catcher_with_nobody_to_take_over_still_catches() -> void:
	# The plan is kept: a day of rest gives way when nobody free can play the position (it
	# used to throw the whole plan away for the computer's line-up).
	var team := _team()
	var ai := F.manager()
	team.batting_plan = _reversed_plan(team, ai)
	var catcher := ""
	for entry: Variant in team.batting_plan:
		if str((entry as Array)[1]) == "C":
			catcher = str((entry as Array)[0])
	# Every other catcher off the first team.
	for p: Player in team.first_team():
		if p.id != catcher and p.aptitude(Position.Kind.C) > 0.0 and not team.batting_plan.any(func(e: Variant) -> bool: return str((e as Array)[0]) == p.id):
			team.unregister(p.id, 0)
	var rest: Dictionary[String, bool] = {catcher: true}
	var game := ai.make_lineup(team, RuleSet.kbo_2026(), team.rotation()[0].id, rest)
	for i: int in 9:
		assert_eq(game.lineup[i].player_id, str(team.batting_plan[i][0]), "the plan as it is")
		assert_eq(Position.code(game.lineup[i].position), str(team.batting_plan[i][1]))
