extends PlayTest
## The player's choices in a ball in play (docs/05 2.3, 2.4; docs/13 S12): the base the
## fielder throws to and how hard, and the runners going or holding.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func _choose(path: Trajectory, bases: Array[int], outs: int, seed_value: int, choice: PlayChoice) -> PlayResult:
	var c := _context(path, bases, outs)
	choice.apply(c)
	return PlaySim.run(c, Rng.new(seed_value))


func _throw(base: int, gauge: float = 0.85) -> PlayChoice:
	var p := PlayChoice.new()
	p.throw_to = base
	p.gauge = gauge
	return p


func test_the_gauge_rewards_letting_go_in_the_green() -> void:
	assert_almost_eq(_throw(1, 0.85).throw_power(), 1.0, 1e-6)
	assert_lt(_throw(1, 0.85).throw_wild(), 1.0, "accurate in the green")
	assert_lt(_throw(1, 0.3).throw_power(), 0.95, "weak short of it")
	assert_gt(_throw(1, 1.2).throw_power(), 1.0, "harder past it")
	assert_gt(_throw(1, 1.2).throw_wild(), 2.0, "and wilder")
	assert_false(PlayChoice.new().has_any())


func test_a_grounder_to_short_with_a_man_on_first_goes_where_the_player_throws() -> void:
	var path := _hit(125.0, -6.0, -15.0)
	var to_second := 0
	var to_first := 0
	for seed_value: int in 10:
		var second := _choose(path, [1], 0, seed_value, _throw(2))
		var first := _choose(path, [1], 0, seed_value, _throw(1))
		if second.errors == 0 and second.fielders.begins_with("6-4"):
			to_second += 1
		if first.errors == 0 and first.fielders == "6-3":
			to_first += 1
			# Thrown to first: the runner from first is safe at second.
			var m := _move_of(first, 1)
			assert_eq(m.to, 2, "seed %d" % seed_value)
	assert_gt(to_second, 7, "thrown to second when the player says so")
	assert_gt(to_first, 7, "and to first when he says that")


func test_a_throw_to_a_base_nobody_is_running_to_makes_no_play() -> void:
	var r := _choose(_hit(125.0, -6.0, -15.0), [], 0, 3, _throw(3))
	assert_eq(r.calls.size(), 0, "no play at third")
	assert_eq(r.result, PaResult.Kind.SINGLE, "and the batter is safe at first")


func test_runners_hold_or_go_as_told_on_a_single() -> void:
	# A single to centre with a man on second: does he try to score?
	var path := _hit(150.0, 8.0, 5.0)
	var scored := [0, 0, 0]
	for seed_value: int in 30:
		for i: int in 3:
			var choice := PlayChoice.new()
			choice.running = i - 1
			var r := _choose(path, [2], 0, seed_value, choice)
			var m := _move_of(r, 2)
			if m != null and m.to == 4:
				scored[i] += 1
	assert_lt(scored[0], scored[1] + 1, "holding never sends more home")
	assert_gt(scored[2], scored[1] - 1, "going never sends fewer")
	assert_lt(scored[0], scored[2], "and the two differ")


# --- Played again from the same moment ---


func _ball_in_play(seed_value: int) -> Array:
	var t := F.teams(seed_value)
	var sim := GameSim.create(t[0], t[1], RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), Rng.new(seed_value), null, null, true)
	var res := sim.resolver as PhysicalResolver
	for guard: int in 3000:
		var before := res.before_pitch(sim.state)
		if before != null:
			var out := GameFlow.apply(sim.state, before)
			sim.scorer.record(sim.state, before, out)
			continue
		var duel := res.new_duel(sim.state)
		duel.throw_pitch(res.tire(sim.state, res.controllers[sim.state.fielding()].choose_pitch(sim.state, duel)))
		res.controllers[sim.state.batting()].react(sim.state, duel)
		while duel.phase == PitchDuel.Phase.FLIGHT:
			duel.tick(PhysicalResolver.DT)
		res.last_play = null
		var events := res.after_pitch(sim.state, duel)
		if res.last_play != null and not res.last_play.foul:
			return [sim, duel, events]
		for e: GameEvent in events:
			var out := GameFlow.apply(sim.state, e)
			sim.scorer.record(sim.state, e, out)
	return []


func test_a_ball_played_again_without_choices_comes_out_the_same() -> void:
	var found := _ball_in_play(31)
	assert_false(found.is_empty())
	if found.is_empty():
		return
	var sim: GameSim = found[0]
	var res := sim.resolver as PhysicalResolver
	var first := res.last_play
	var events := res.replay_ball(sim.state, found[1], PlayChoice.new())
	var again := res.last_play
	assert_eq(again.result, first.result)
	assert_eq(again.fielders, first.fielders)
	assert_almost_eq(again.timeline.duration, first.timeline.duration, 1e-9)
	assert_eq(events.size(), 1)
	assert_eq(events[0].result, (found[2][0] as GameEvent).result)
	# The same choice twice: the same play.
	var choice := _throw(1)
	res.replay_ball(sim.state, found[1], choice)
	var a := res.last_play
	res.replay_ball(sim.state, found[1], choice)
	assert_eq(res.last_play.fielders, a.fielders)
	assert_eq(res.last_play.result, a.result)
