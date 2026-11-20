extends GutTest
## The manager's orders (docs/13 S7-6): what each one does to the next pitch or play.

const F := preload("res://tests/core/rules/rules_fixture.gd")


func _resolver(seed_value: int = 1) -> PhysicalResolver:
	return PhysicalResolver.new(F.env(), F.catalog(), F.manager(), Rng.new(seed_value))


func test_an_intentional_walk_order_walks_him_at_once() -> void:
	var s := F.game()
	var r := _resolver()
	r.tactics[s.fielding()].order = Tactics.Order.INTENTIONAL_WALK
	var e := r.next_event(s)
	assert_eq(e.kind, GameEvent.Kind.PLATE_APPEARANCE)
	assert_eq(e.result, PaResult.Kind.INTENTIONAL_WALK)
	assert_eq(r.tactics[s.fielding()].order, Tactics.Order.NONE, "used up")


func test_a_bunt_order_squares_him_around_until_two_strikes() -> void:
	var s := F.game()
	F.put_runners(s, [1])
	var r := _resolver()
	r.tactics[s.batting()].order = Tactics.Order.BUNT
	assert_null(r.before_pitch(s))
	assert_true(r.is_bunting())
	s.strikes = 2
	assert_null(r.before_pitch(s))
	assert_false(r.is_bunting(), "with two strikes he swings away")


func test_a_steal_order_sends_the_lead_runner_on_this_pitch() -> void:
	var s := F.game()
	F.put_runners(s, [1])
	var r := _resolver()
	r.tactics[s.batting()].order = Tactics.Order.STEAL
	var e := r.before_pitch(s)
	assert_not_null(e)
	assert_eq(e.kind, GameEvent.Kind.STEAL)
	assert_eq(e.moves[0].from, 1)
	assert_eq(r.tactics[s.batting()].order, Tactics.Order.NONE, "a steal is one go")


func test_no_steal_order_without_an_open_base() -> void:
	var s := F.game()
	F.put_runners(s, [1, 2, 3])
	assert_false(Tactics.can_give(Tactics.Order.STEAL, s))
	assert_false(Tactics.can_give(Tactics.Order.DOUBLE_STEAL, s))
	assert_false(Tactics.can_give(Tactics.Order.SQUEEZE, F.game()), "nobody on third")


func test_a_double_steal_credits_both_runners_unless_one_is_thrown_out() -> void:
	for safe: bool in [true, false]:
		var s := F.game()
		F.put_runners(s, [1, 2])
		var first := s.runner_on(1).player_id
		var second := s.runner_on(2).player_id
		var scorer := Scorer.new()
		scorer.start(s)
		var e := PhysicalResolver.double_steal(s, 0.2 if safe else -0.2, false)
		var out := GameFlow.apply(s, e)
		scorer.record(s, e, out)
		assert_eq(s.runner_on(2).player_id, first, "the trailing runner takes second")
		if safe:
			assert_eq(s.runner_on(3).player_id, second)
			assert_eq(scorer.book.bat(second).stolen_bases, 1)
			assert_eq(scorer.book.bat(first).stolen_bases, 1)
		else:
			assert_true(s.base_empty(3))
			assert_eq(s.outs, 1)
			assert_eq(scorer.book.bat(second).caught_stealing, 1)
			assert_eq(scorer.book.bat(first).stolen_bases, 0, "no steal for him when the lead runner is out")


func test_a_take_order_lets_pitches_go_until_a_strike() -> void:
	var s := F.game()
	var r := _resolver(3)
	r.tactics[s.batting()].order = Tactics.Order.TAKE
	assert_true(r.batter_takes(s))
	var swings := 0
	for i: int in 30:
		var t := F.game(null, 10 + i)
		var rr := _resolver(10 + i)
		rr.tactics[t.batting()].order = Tactics.Order.TAKE
		rr.next_event(t)
		if rr.last_duel != null and rr.last_duel.swing != null:
			swings += 1
	assert_eq(swings, 0, "no swing at 0 strikes")
	s.strikes = 1
	assert_false(r.batter_takes(s))


func test_pitching_around_throws_fewer_strikes_and_attacking_more() -> void:
	var s := F.game()
	var p := s.fielding_team().player(s.pitcher_id())
	var options := AiPitcher.options_for(p, F.catalog())
	var zone := StrikeZone.for_batter(1.83, s.rules)
	var rng := Rng.new(4)
	var counts := PackedInt32Array([0, 0, 0])
	var factors: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(Tactics.AROUND_ZONE, 0.0), Vector2(1.0, Tactics.ATTACK_ZONE)]
	for k: int in 3:
		for i: int in 1500:
			var d := AiPitcher.decide(options, zone, 1, 1, false, PackedInt32Array(), null, rng, factors[k].x, factors[k].y)
			if zone.contains(d.target.x, d.target.z):
				counts[k] += 1
	assert_lt(counts[1], counts[0] * 0.8)
	assert_gt(counts[2], counts[0] * 1.1)


func test_a_defence_order_replaces_the_usual_positioning() -> void:
	var s := F.game()
	F.put_runners(s, [3])
	var t := Tactics.new()
	assert_eq(t.variants(s, false), FieldingAlignment.variants_for(s, false), "automatic by default")
	t.defence = Tactics.Defence.INFIELD_IN
	assert_eq(t.variants(s, false), ["infield_in"] as Array[String])
	t.defence = Tactics.Defence.NORMAL
	assert_eq(t.variants(s, true), ["bunt"] as Array[String])
	var alignment := MotionIO.alignment()
	t.defence = Tactics.Defence.INFIELD_IN
	var drawn_in := alignment.positions(s, null, false, false, t)
	var normal := alignment.positions(s, null, false)
	assert_lt(drawn_in[Position.Kind.SS].length(), normal[Position.Kind.SS].length() - 3.0)


func test_orders_last_one_plate_appearance_and_the_rest_stay() -> void:
	var s := F.game()
	var r := _resolver()
	var t := r.tactics[s.batting()]
	t.order = Tactics.Order.TAKE
	t.running = Tactics.Running.AGGRESSIVE
	var defending := s.fielding()
	r.tactics[defending].defence = Tactics.Defence.DOUBLE_PLAY
	var guard := 0
	var batter := s.batter_id()
	while s.batter_id() == batter and guard < 20:
		var e := r.next_event(s)
		GameFlow.apply(s, e)
		guard += 1
	assert_eq(t.order, Tactics.Order.NONE)
	assert_eq(t.running, Tactics.Running.AGGRESSIVE)
	assert_eq(r.tactics[defending].defence, Tactics.Defence.DOUBLE_PLAY)
	assert_eq(t.summary(), "주루 적극")
