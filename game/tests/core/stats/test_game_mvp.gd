extends GutTest
## The player of the game.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func test_the_mvp_comes_from_the_winning_side() -> void:
	for seed_value: int in 6:
		var t := F.teams(60 + seed_value)
		var sim := GameSim.create(t[0], t[1], RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), Rng.new(seed_value))
		sim.play()
		var id := GameMvp.pick(sim.state, sim.scorer.book)
		assert_ne(id, "")
		if sim.state.winner >= 0:
			assert_not_null(sim.state.teams[sim.state.winner].player(id), "game %d: the MVP played for the winners" % seed_value)


func test_a_big_day_outscores_a_quiet_one() -> void:
	var big := BattingLine.new()
	big.ab = 4
	big.hits = 3
	big.home_runs = 1
	big.doubles = 1
	big.rbi = 4
	big.runs = 2
	var quiet := BattingLine.new()
	quiet.ab = 4
	quiet.hits = 1
	assert_gt(GameMvp.batter_score(big), GameMvp.batter_score(quiet))
