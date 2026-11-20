extends GutTest
## The physical resolver: pitch-by-pitch games, the extra pitch results and the pitcher and
## batter AI (docs/13 S5-1, S5-8, S5-9).

const F := preload("res://tests/core/rules/rules_fixture.gd")


func _resolver(seed_value: int = 1) -> PhysicalResolver:
	return PhysicalResolver.new(F.env(), F.catalog(), F.manager(), Rng.new(seed_value))


func _pitch(type: StringName, target: Vector3) -> PitchDecision:
	var d := PitchDecision.new()
	d.type = F.catalog()[type]
	d.target = target
	d.quality = 1.0
	return d


func _fly(duel: PitchDuel) -> void:
	while duel.phase == PitchDuel.Phase.FLIGHT:
		duel.tick(PhysicalResolver.DT)


func _game(seed_value: int, physical: bool = true) -> GameSim:
	var t := F.teams(seed_value)
	return GameSim.create(t[0], t[1], RuleSet.kbo_2026(), F.env(), F.catalog(), F.overall(), Rng.new(seed_value), null, null, physical)


# --- S5-9 ---


func test_the_same_seed_plays_the_same_game() -> void:
	var results: Array[String] = []
	for attempt: int in 2:
		var sim := _game(5)
		sim.play()
		results.append("%d-%d %s %d" % [sim.state.score[0], sim.state.score[1], sim.scorer.book.winner_id, sim.scorer.book.team_pitching(0).pitches])
	assert_eq(results[0], results[1])


func test_a_game_plays_headless_in_under_ten_seconds() -> void:
	var start := Time.get_ticks_msec()
	var sim := _game(8)
	sim.play()
	assert_true(sim.state.over)
	assert_lt(Time.get_ticks_msec() - start, 10000)


func test_physical_games_keep_their_books_straight() -> void:
	var bad := PackedStringArray()
	for g: int in 6:
		var sim := _game(100 + g)
		var pitches := PackedInt32Array([0, 0])
		var guard := 0
		while not sim.state.over and guard < GameSim.MAX_EVENTS:
			var event := sim.resolver.next_event(sim.state)
			var fielding := sim.state.fielding()
			var out := GameFlow.apply(sim.state, event)
			sim.scorer.record(sim.state, event, out)
			sim.manager.note_change(sim.state, event)
			if event.kind == GameEvent.Kind.PITCH:
				pitches[fielding] += 1
			elif event.kind == GameEvent.Kind.PLATE_APPEARANCE:
				pitches[fielding] += event.pitches
			guard += 1
		sim.scorer.finish(sim.state)
		var s := sim.state
		var book := sim.scorer.book
		if not s.over:
			bad.append("game %d did not finish" % g)
		for t: int in 2:
			var runs := 0
			for r: int in s.line[t]:
				runs += r
			if runs != s.score[t] or book.team_batting(t).runs != s.score[t]:
				bad.append("game %d team %d: runs" % [g, t])
			var b := book.team_batting(t)
			if b.pa != b.ab + b.walks + b.intentional_walks + b.hit_by_pitch + b.sac_bunts + b.sac_flies:
				bad.append("game %d team %d: plate appearances" % [g, t])
			if book.team_pitching(t).pitches != pitches[t]:
				bad.append("game %d team %d: %d pitches thrown, %d in the box" % [g, t, pitches[t], book.team_pitching(t).pitches])
		if book.team_pitching(1).outs != s.line[0].size() * 3:
			bad.append("game %d: outs" % g)
		if s.winner >= 0 and (book.winner_id == "" or book.loser_id == ""):
			bad.append("game %d: no decision" % g)
	assert_eq(bad, PackedStringArray())


# --- S5-1 ---


func test_a_pitch_into_the_batter_s_body_hits_him() -> void:
	var state := F.game()
	var r := _resolver()
	var duel := r.new_duel(state)
	duel.settings.dodge = 0.0
	var side := 1.0 if duel.settings.bats_left else -1.0
	duel.throw_pitch(_pitch(&"four_seam", Vector3(side * 0.70, Field.PLATE_FRONT_Y, 1.0)), true)
	_fly(duel)
	assert_eq(duel.result, PitchDuel.Result.HIT_BY_PITCH)
	var events := r.after_pitch(state, duel)
	assert_eq(events[0].result, PaResult.Kind.HIT_BY_PITCH)


func test_a_swing_at_a_pitch_that_hits_him_is_a_strike() -> void:
	var state := F.game()
	var duel := _resolver().new_duel(state)
	var side := 1.0 if duel.settings.bats_left else -1.0
	duel.throw_pitch(_pitch(&"four_seam", Vector3(side * 0.70, Field.PLATE_FRONT_Y, 1.0)), true)
	duel.swing_at(duel.ideal_contact_time, SwingAttempt.Kind.CONTACT, Vector2(0.0, 0.8), true)
	_fly(duel)
	assert_eq(duel.result, PitchDuel.Result.SWINGING_STRIKE)


func test_a_pitch_two_metres_over_the_catcher_is_a_wild_pitch_with_runners_on() -> void:
	var wild := 0
	for seed_value: int in 20:
		var state := F.game()
		F.put_runners(state, [1])
		var r := _resolver(seed_value)
		var duel := r.new_duel(state)
		duel.throw_pitch(_pitch(&"four_seam", Vector3(0.0, Field.PLATE_FRONT_Y, 3.6)), true)
		_fly(duel)
		for e: GameEvent in r.after_pitch(state, duel):
			if e.kind == GameEvent.Kind.WILD_PITCH:
				wild += 1
				assert_eq(e.moves[0].from, 1)
				assert_eq(e.moves[0].to, 2)
	assert_gt(wild, 17)


func test_no_wild_pitch_event_with_the_bases_empty() -> void:
	var state := F.game()
	var r := _resolver(3)
	var duel := r.new_duel(state)
	duel.throw_pitch(_pitch(&"four_seam", Vector3(0.0, Field.PLATE_FRONT_Y, 3.6)), true)
	_fly(duel)
	for e: GameEvent in r.after_pitch(state, duel):
		assert_ne(e.kind, GameEvent.Kind.WILD_PITCH)


func test_strike_three_in_the_dirt_lets_the_batter_run_with_first_open() -> void:
	var outcomes := {}
	for seed_value: int in 30:
		var state := F.game()
		state.strikes = 2
		var r := _resolver(seed_value)
		var duel := r.new_duel(state)
		duel.throw_pitch(_pitch(&"curve", Vector3(0.0, Field.PLATE_FRONT_Y, -0.1)), true)
		duel.swing_at(duel.ideal_contact_time + 0.5, SwingAttempt.Kind.CONTACT)
		_fly(duel)
		var events := r.after_pitch(state, duel)
		for e: GameEvent in events:
			GameFlow.apply(state, e)
		var pa := r.before_pitch(state)
		assert_eq(pa.kind, GameEvent.Kind.PLATE_APPEARANCE)
		assert_true(PaResult.is_strikeout(pa.result))
		outcomes[pa.result] = int(outcomes.get(pa.result, 0)) + 1
		if pa.result == PaResult.Kind.STRIKEOUT:
			assert_eq(pa.fielders, "2-3", "blocked: thrown out at first")
	assert_true(outcomes.has(PaResult.Kind.STRIKEOUT), "usually blocked and thrown out")


# --- S5-8 ---


func test_the_computer_batter_never_swings_a_metre_off_the_zone() -> void:
	var state := F.game()
	var r := _resolver()
	var swings := 0
	var rng := Rng.new(9)
	for i: int in 200:
		var duel := r.new_duel(state)
		duel.throw_pitch(_pitch(&"slider", duel.zone.center() + Vector3(1.0 if i % 2 == 0 else -1.0, 0.0, 0.0)), true)
		AiBatter.decide(duel, 1, 2, PackedInt32Array(), 145.0, rng)
		if duel.swing != null:
			swings += 1
	assert_eq(swings, 0)


func test_the_computer_batter_takes_three_and_oh() -> void:
	var state := F.game()
	var r := _resolver()
	var swings := 0
	var rng := Rng.new(10)
	for i: int in 400:
		var duel := r.new_duel(state)
		duel.throw_pitch(_pitch(&"four_seam", duel.zone.center()), true)
		AiBatter.decide(duel, 3, 0, PackedInt32Array(), 145.0, rng)
		if duel.swing != null:
			swings += 1
	assert_lt(float(swings) / 400.0, 0.10)


func test_the_computer_pitcher_does_not_throw_the_same_pitch_to_the_same_spot_three_times() -> void:
	var state := F.game()
	var r := _resolver()
	var duel := r.new_duel(state)
	var options := AiPitcher.options_for(state.fielding_team().player(state.pitcher_id()), F.catalog())
	var memory := AiPitcher.Memory.new()
	var rng := Rng.new(4)
	var run := 0
	var last := ""
	for i: int in 500:
		var d := AiPitcher.decide(options, duel.zone, 1, 1, false, PackedInt32Array(), memory, rng)
		var key := "%s %d" % [d.type.id, AiPitcher.cell_of(duel.zone, d.target)]
		run = run + 1 if key == last else 1
		last = key
		assert_lt(run, 3, key)


func test_the_computer_pitcher_comes_in_with_three_balls_and_expands_at_oh_two() -> void:
	var state := F.game()
	var r := _resolver()
	var duel := r.new_duel(state)
	var options := AiPitcher.options_for(state.fielding_team().player(state.pitcher_id()), F.catalog())
	var rng := Rng.new(6)
	var full := 0
	var ahead := 0
	for i: int in 1000:
		if duel.zone.contains(AiPitcher.decide(options, duel.zone, 3, 1, false, PackedInt32Array(), null, rng).target.x, AiPitcher.decide(options, duel.zone, 3, 1, false, PackedInt32Array(), null, rng).target.z):
			full += 1
		var d := AiPitcher.decide(options, duel.zone, 0, 2, false, PackedInt32Array(), null, rng)
		if duel.zone.contains(d.target.x, d.target.z):
			ahead += 1
	assert_gt(full, ahead * 2, "aims at the zone far more often with three balls than with two strikes")


func test_a_batter_has_two_or_three_weak_spots_and_they_stay_put() -> void:
	var cells := AiBatter.weak_cells("kbo-1234")
	assert_between(cells.size(), 2, 3)
	assert_eq(cells, AiBatter.weak_cells("kbo-1234"))
	for c: int in cells:
		assert_between(c, 0, 8)


func test_every_runner_scores_is_put_out_or_is_left_on_base() -> void:
	var bad := PackedStringArray()
	for g: int in 24:
		var sim := _game(300 + g)
		var reached := PackedInt32Array([0, 0])
		var runner_outs := PackedInt32Array([0, 0])
		var uncounted := PackedInt32Array([0, 0])
		var guard := 0
		while not sim.state.over and guard < GameSim.MAX_EVENTS:
			var event := sim.resolver.next_event(sim.state)
			var batting := sim.state.batting()
			var out := GameFlow.apply(sim.state, event)
			sim.scorer.record(sim.state, event, out)
			sim.manager.note_change(sim.state, event)
			var crossed := 0
			for i: int in event.moves.size():
				var m := event.moves[i]
				if out.applied.size() > i and out.applied[i] == 0:
					continue
				if m.from == 0 and m.to >= 1:
					reached[batting] += 1
				elif m.from > 0 and m.is_out():
					runner_outs[batting] += 1
				if m.scores():
					crossed += 1
			uncounted[batting] += crossed - out.scored.size()
			guard += 1
		sim.scorer.finish(sim.state)
		var s := sim.state
		for t: int in 2:
			var walk_off_half := t == 1 and s.winner == GameState.HOME and s.inning >= s.rules.innings and s.line[1].size() == s.inning
			if walk_off_half:
				continue
			var left := reached[t] - s.score[t] - runner_outs[t] - uncounted[t]
			if left != sim.scorer.book.left_on_base[t]:
				bad.append("game %d team %d: %d left by count, %d in the box" % [g, t, left, sim.scorer.book.left_on_base[t]])
	assert_eq(bad, PackedStringArray())
