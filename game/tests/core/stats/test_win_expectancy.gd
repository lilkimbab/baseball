extends GutTest
## Win probability and leverage from the base-out chain.

const F := preload("res://tests/core/rules/rules_fixture.gd")

static var _we: WinExpectancy


func _w() -> WinExpectancy:
	if _we == null:
		_we = WinExpectancy.for_league(F.env(), RuleSet.kbo_2026())
	return _we


func test_every_plate_appearance_s_outcomes_add_up_to_one() -> void:
	for outs: int in 3:
		for bases: int in 8:
			var total := 0.0
			for t: PackedFloat64Array in _w().transitions(outs, bases):
				total += t[0]
				assert_true(int(t[1]) >= outs, "outs never go back")
			assert_almost_eq(total, 1.0, 1e-9, "%d out, bases %d" % [outs, bases])


func test_the_run_expectancy_table_looks_like_a_real_one() -> void:
	var w := _w()
	# KBO 2025: 4.73 runs a game, about 0.53 a half-inning.
	assert_between(w.run_expectancy(0, 0), 0.45, 0.62, "nobody on, nobody out")
	assert_between(w.run_expectancy(0, 7), 1.9, 2.6, "bases loaded, nobody out")
	assert_between(w.run_expectancy(2, 0), 0.08, 0.16, "nobody on, two out")
	assert_gt(w.run_expectancy(0, 1), w.run_expectancy(0, 0))
	assert_gt(w.run_expectancy(1, 4), w.run_expectancy(1, 2), "third is worth more than second")
	var d := w.runs_to_come(1, 3)
	var total := 0.0
	for p: float in d:
		total += p
	assert_almost_eq(total, 1.0, 1e-6)


func test_win_chances_follow_the_score_and_the_inning() -> void:
	var w := _w()
	assert_almost_eq(w.home_win(1, true, 0, 0, 0), 0.5, 0.03, "a level start")
	assert_gt(w.home_win(9, true, 1, 2, 0), 0.9, "home up one, two out in the ninth")
	assert_lt(w.home_win(9, false, -3, 2, 0), 0.03, "home down three, two out in the bottom of the ninth")
	assert_gt(w.home_win(5, true, 2, 0, 0), w.home_win(5, true, 1, 0, 0))
	assert_gt(w.home_win(9, false, 0, 0, 4), 0.75, "winning run on third, nobody out")
	assert_almost_eq(w.home_win(9, false, 0, 3, 0), w.at_half(10, true, 0), 1e-9, "level after nine: extra innings")
	assert_almost_eq(w.home_win(11, false, 0, 3, 0), 0.5, 1e-9, "level after eleven: a tie")


func test_leverage_is_high_late_and_close_and_low_in_a_blowout() -> void:
	var w := _w()
	var tight := w.leverage(9, false, 0, 2, 7)
	var start := w.leverage(1, true, 0, 0, 0)
	var blowout := w.leverage(8, true, 9, 1, 0)
	assert_gt(tight, 4.0, "bottom of the ninth, level, bases loaded, two out")
	assert_between(start, 0.6, 1.2, "the first batter of the game")
	assert_lt(blowout, 0.1)
	assert_gt(w.leverage(8, false, -1, 1, 2), WinExpectancy.HIGH, "down one in the eighth, tying run on second")


func test_the_chain_is_quick_enough_for_the_match_screen() -> void:
	var start := Time.get_ticks_msec()
	var w := WinExpectancy.for_league(F.env(), RuleSet.kbo_2026())
	w.leverage(1, true, 0, 0, 0)
	assert_lt(Time.get_ticks_msec() - start, 3000)
