extends GutTest
## The substitution choices offered to a manager.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func test_a_player_who_left_the_game_is_not_offered_again() -> void:
	var s := F.game()
	var team := s.batting_team()
	var sub := SubstitutionOptions.bench(team)[0]
	var leaving := s.batter_id()
	var e := SubstitutionOptions.pinch_hitter(s, sub)
	assert_eq(SubstitutionOptions.check(s, e), PackedStringArray())
	GameFlow.apply(s, e)
	assert_false(SubstitutionOptions.bench(team).has(sub), "the pinch hitter is in the game now")
	assert_false(SubstitutionOptions.bench(team).has(leaving), "the man he batted for is out for good")
	var back := SubstitutionOptions.pinch_hitter(s, leaving)
	assert_ne(SubstitutionOptions.check(s, back), PackedStringArray(), "he cannot come back")


func test_a_pitcher_who_has_pitched_is_not_offered_again() -> void:
	var s := F.game()
	var t := s.fielding()
	var team := s.teams[t]
	var starter := team.pitcher_id
	var reliever := SubstitutionOptions.relievers(team)[0]
	var e := SubstitutionOptions.pitcher_change(s, t, reliever)
	assert_eq(SubstitutionOptions.check(s, e), PackedStringArray())
	GameFlow.apply(s, e)
	assert_false(SubstitutionOptions.relievers(team).has(reliever))
	assert_false(SubstitutionOptions.relievers(team).has(starter))


func test_a_pinch_runner_replaces_the_runner_on_base() -> void:
	var s := F.game()
	F.put_runners(s, [2])
	var runner := s.runner_on(2).player_id
	var fast := SubstitutionOptions.bench(s.batting_team())[0]
	var e := SubstitutionOptions.pinch_runner(s, 2, fast)
	assert_eq(SubstitutionOptions.check(s, e), PackedStringArray())
	GameFlow.apply(s, e)
	assert_eq(s.runner_on(2).player_id, fast)
	assert_false(SubstitutionOptions.bench(s.batting_team()).has(runner))
