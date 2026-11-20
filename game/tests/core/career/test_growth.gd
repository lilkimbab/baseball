extends GutTest
## Scene goals, game goals and growth points (docs/13 S8-2, S8-5).

const F := preload("res://tests/core/rules/rules_fixture.gd")

static var _rules: CareerRules


func _r() -> CareerRules:
	if _rules == null:
		_rules = CareerIO.load_default()
	return _rules


func _career(position: String, type_id: String) -> CareerPlayer:
	var s := PlayerCreator.Spec.new()
	s.position = position
	s.type_id = type_id
	return PlayerCreator.create(s, _r(), F.catalog())


func test_the_scene_goal_fits_the_situation() -> void:
	var s := F.game()
	assert_eq(SceneGoal.for_batting(s).kind, SceneGoal.Kind.REACH_BASE, "leading off an inning")
	F.put_runners(s, [3])
	assert_eq(SceneGoal.for_batting(s).kind, SceneGoal.Kind.DRIVE_IN)
	assert_eq(SceneGoal.for_pitching(s).kind, SceneGoal.Kind.NO_RUNS)
	var t := F.game()
	F.put_runners(t, [2])
	assert_eq(SceneGoal.for_batting(t).kind, SceneGoal.Kind.ADVANCE_RUNNER)
	assert_eq(SceneGoal.for_batting(t).label(), "주자를 진루시키기")
	assert_eq(SceneGoal.for_batting(t).field, "batting")
	assert_eq(SceneGoal.make(SceneGoal.Kind.STRIKEOUT).field, "pitching")


func test_scene_goals_are_checked_on_the_result() -> void:
	var s := F.game()
	F.put_runners(s, [2])
	var before: Array[bool] = [false, true, false]
	var goal := SceneGoal.for_batting(s)
	var grounder := F.pa(PaResult.Kind.GROUND_OUT, [F.move(0, 1, RunnerMove.OutKind.FORCE), F.move(2, 3)] as Array[RunnerMove])
	var out := GameFlow.apply(s, grounder)
	assert_true(goal.achieved(grounder, out, Vector2i(0, 1), before), "the runner moved up on the out")
	var count := SceneGoal.make(SceneGoal.Kind.FAVOURABLE_COUNT)
	var k := F.pa(PaResult.Kind.STRIKEOUT, [F.move(0, 1, RunnerMove.OutKind.STRIKEOUT)] as Array[RunnerMove])
	var t := F.game()
	var out2 := GameFlow.apply(t, k)
	assert_true(count.achieved(k, out2, Vector2i(3, 1), [false, false, false] as Array[bool]), "he had 3-1 before striking out")
	assert_false(count.achieved(k, out2, Vector2i(1, 2), [false, false, false] as Array[bool]))
	assert_true(SceneGoal.make(SceneGoal.Kind.STRIKEOUT).achieved(k, out2, Vector2i.ZERO, [false, false, false] as Array[bool]))


func test_points_come_from_the_game_in_their_own_fields() -> void:
	var bat := BattingLine.new()
	bat.pa = 4
	bat.ab = 4
	bat.hits = 2
	bat.home_runs = 1
	bat.rbi = 2
	bat.runs = 1
	var gp := Growth.from_game(bat, null, 3, 0, _r())
	assert_eq(gp["batting"], 6.0 + 15.0 + 2 * 4.0 + 4 * 1.0, "a single, a homer, two RBI, four trips")
	assert_eq(gp["fielding"], 3 * 4.0)
	assert_eq(gp["pitching"], 0.0, "a hitter earns nothing on the mound")
	var pitch := PitchingLine.new()
	pitch.outs = 18
	pitch.runs = 2
	pitch.strikeouts = 7
	pitch.wins = 1
	var pgp := Growth.from_game(null, pitch, 0, 0, _r())
	assert_eq(pgp["pitching"], 18 * 2.0 + 7 * 3.0 + 4 * 5.0 + 10.0)


func test_raising_a_rating_costs_more_the_higher_it_is_and_less_for_a_strength() -> void:
	var c := _career("2B", "contact")
	var cheap := Growth.cost(c, "contact", _r())
	var dear := Growth.cost(c, "power", _r())
	# Contact is his strength (higher, so dearer by the curve, but a fifth off).
	var curve := _r().cost_base * pow(1.0 + (Growth.value(c.player, "contact") - 40.0) / 20.0, 2.0)
	assert_almost_eq(cheap, curve * 0.8, 1e-6)
	assert_gt(dear, 0.0)
	c.gp["batting"] = cheap - 0.5
	assert_false(Growth.raise(c, "contact", _r()), "not enough points")
	c.gp["batting"] = 1000.0
	var before := c.player.batting.contact_r
	assert_true(Growth.raise(c, "contact", _r()))
	assert_almost_eq(c.player.batting.contact_r, before + 1.0, 1e-6)
	assert_lt(c.gp["batting"], 1000.0)
	assert_false(Growth.raise(c, "control", _r()), "a hitter cannot buy pitching")
	assert_false(Growth.raise(c, "speed", _r()), "running points are separate")


func test_a_pitcher_buys_speed_in_half_km_steps() -> void:
	var c := _career("SP", "power_arm")
	c.gp["pitching"] = 1000.0
	var before := c.player.pitching.fastball_speed()
	assert_true(Growth.raise(c, "velocity", _r()))
	assert_almost_eq(c.player.pitching.fastball_speed(), before + 0.5, 0.01)


func test_game_goals_by_type_and_role() -> void:
	var hitter := GameGoal.for_player(_career("1B", "power"), _r())
	assert_eq(hitter.label(), "장타 1개")
	var starter := GameGoal.for_player(_career("SP", "control"), _r())
	assert_eq(starter.label(), "6이닝 2실점 이하")
	var line := PitchingLine.new()
	line.outs = 18
	line.runs = 2
	assert_true(starter.achieved(null, line))
	line.runs = 3
	assert_false(starter.achieved(null, line))
	assert_eq(GameGoal.for_player(_career("CL", "control"), _r()).label(), "실점 없이 마치기")
