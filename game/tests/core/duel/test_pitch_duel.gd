extends PhysicsTest
## A single pitch: flight, swing timing, contact and the result.

var field: AnalyticField
var catalog: Dictionary[StringName, PitchType]


func before_all() -> void:
	super.before_all()
	field = standard_field()
	catalog = PitchCatalogIO.load_default()


func _duel(seed_value: int = 1) -> PitchDuel:
	var settings := DuelSettings.new()
	return PitchDuel.new(cfg, field, settings, Rng.new(seed_value))


func _pitch(type_id: StringName, target: Vector3, quality: float = 1.0) -> PitchDecision:
	var d := PitchDecision.new()
	d.type = catalog[type_id]
	d.target = target
	d.quality = quality
	return d


func _run(duel: PitchDuel) -> void:
	var guard := 0
	while not duel.is_over() and guard < 20000:
		duel.tick(BallFlight.DT)
		guard += 1


func test_strike_zone_scales_with_the_batter() -> void:
	var zone := StrikeZone.for_batter(1.82)
	assert_almost_eq(zone.top, 1.015, 0.002)
	assert_almost_eq(zone.bottom, 0.492, 0.002)
	assert_almost_eq(zone.half_width, 0.2359, 0.0005)
	assert_true(zone.contains(0.0, 0.75))
	assert_false(zone.contains(0.30, 0.75))
	assert_false(zone.contains(0.0, 1.10))
	assert_gt(StrikeZone.for_batter(1.95).top, zone.top)


func test_a_pitch_down_the_middle_taken_is_a_called_strike() -> void:
	var duel := _duel()
	duel.throw_pitch(_pitch(&"four_seam", duel.zone.center()), true)
	_run(duel)
	assert_eq(duel.result, PitchDuel.Result.CALLED_STRIKE)
	assert_between(duel.time, 0.40, 0.55, "the ball reaches the catcher")


func test_a_pitch_well_outside_taken_is_a_ball() -> void:
	var duel := _duel()
	duel.throw_pitch(_pitch(&"four_seam", Vector3(0.6, Field.PLATE_FRONT_Y, 0.75)), true)
	_run(duel)
	assert_eq(duel.result, PitchDuel.Result.BALL)


func test_a_curve_that_drops_below_the_zone_is_a_ball() -> void:
	var duel := _duel()
	duel.throw_pitch(_pitch(&"curve", Vector3(0.0, Field.PLATE_FRONT_Y, 0.25)), true)
	_run(duel)
	assert_eq(duel.result, PitchDuel.Result.BALL)


func test_a_well_timed_swing_puts_the_ball_in_play() -> void:
	var fair := 0
	var total := 0
	for seed_value: int in 40:
		var duel := _duel(seed_value)
		duel.throw_pitch(_pitch(&"four_seam", duel.zone.center()), true)
		duel.swing_at(duel.ideal_contact_time, SwingAttempt.Kind.CONTACT)
		_run(duel)
		total += 1
		assert_eq(duel.swing.judgment, &"perfect")
		if duel.result == PitchDuel.Result.IN_PLAY or duel.result == PitchDuel.Result.HOME_RUN:
			fair += 1
			if duel.contact.exit_speed_kmh() > 130.0:
				assert_lt(absf(duel.contact.spray_deg()), 12.0, "a well-struck, well-timed ball goes up the middle")
	assert_gt(fair, total * 0.6, "perfect timing is usually a fair ball")


func test_swinging_far_too_early_or_late_misses() -> void:
	for offset: float in [-0.20, 0.20] as Array[float]:
		var duel := _duel()
		duel.throw_pitch(_pitch(&"four_seam", duel.zone.center()), true)
		duel.swing_at(duel.ideal_contact_time + offset, SwingAttempt.Kind.CONTACT)
		_run(duel)
		assert_eq(duel.result, PitchDuel.Result.SWINGING_STRIKE)
		assert_eq(duel.swing.judgment, &"miss")


func test_early_swings_are_pulled_and_late_swings_go_the_other_way() -> void:
	var early_sum := 0.0
	var late_sum := 0.0
	var n := 0
	for seed_value: int in 30:
		var early := _duel(seed_value)
		early.throw_pitch(_pitch(&"four_seam", early.zone.center()), true)
		early.swing_at(early.ideal_contact_time - 0.025, SwingAttempt.Kind.CONTACT)
		_run(early)
		var late := _duel(seed_value)
		late.throw_pitch(_pitch(&"four_seam", late.zone.center()), true)
		late.swing_at(late.ideal_contact_time + 0.025, SwingAttempt.Kind.CONTACT)
		_run(late)
		if early.contact != null and early.contact.made_contact and late.contact != null and late.contact.made_contact:
			early_sum += early.contact.spray_deg()
			late_sum += late.contact.spray_deg()
			n += 1
	assert_gt(n, 15)
	assert_lt(early_sum / n, -5.0, "a right-handed batter pulls toward third base")
	assert_gt(late_sum / n, 5.0, "late contact goes to right field")


func test_power_swings_hit_harder_and_higher_than_contact_swings() -> void:
	var speed := [0.0, 0.0]
	var angle := [0.0, 0.0]
	var count := [0, 0]
	for seed_value: int in 60:
		for kind: int in 2:
			var duel := _duel(seed_value)
			duel.throw_pitch(_pitch(&"four_seam", duel.zone.center()), true)
			duel.swing_at(duel.ideal_contact_time, kind as SwingAttempt.Kind)
			_run(duel)
			if duel.contact != null and duel.contact.made_contact:
				speed[kind] += duel.contact.exit_speed_kmh()
				angle[kind] += duel.contact.launch_deg()
				count[kind] += 1
	assert_gt(speed[1] / count[1], speed[0] / count[0] + 8.0, "exit speed")
	assert_gt(angle[1] / count[1], angle[0] / count[0] + 3.0, "launch angle")


func test_aiming_above_the_ball_tops_it_and_aiming_below_lifts_it() -> void:
	var high_aim := 0.0
	var low_aim := 0.0
	var n := 0
	for seed_value: int in 30:
		var over := _duel(seed_value)
		over.throw_pitch(_pitch(&"four_seam", over.zone.center()), true)
		over.swing_at(over.ideal_contact_time, SwingAttempt.Kind.CONTACT, Vector2(0.0, over.ideal_contact_pos.z + 0.08), true)
		_run(over)
		var under := _duel(seed_value)
		under.throw_pitch(_pitch(&"four_seam", under.zone.center()), true)
		under.swing_at(under.ideal_contact_time, SwingAttempt.Kind.CONTACT, Vector2(0.0, under.ideal_contact_pos.z - 0.08), true)
		_run(under)
		if over.contact != null and over.contact.made_contact and under.contact != null and under.contact.made_contact:
			high_aim += over.contact.launch_deg()
			low_aim += under.contact.launch_deg()
			n += 1
	assert_gt(n, 15)
	assert_lt(high_aim / n, low_aim / n - 10.0, "swinging over the ball drives it into the ground")


func test_only_one_swing_per_pitch_and_none_before_release() -> void:
	var duel := _duel()
	assert_false(duel.start_swing(SwingAttempt.Kind.CONTACT), "nothing to swing at yet")
	duel.throw_pitch(_pitch(&"four_seam", duel.zone.center()), true)
	assert_true(duel.start_swing(SwingAttempt.Kind.CONTACT))
	assert_false(duel.start_swing(SwingAttempt.Kind.POWER))


func test_the_live_ball_follows_the_forecast() -> void:
	var duel := _duel(7)
	duel.throw_pitch(_pitch(&"four_seam", duel.zone.center()), true)
	duel.swing_at(duel.ideal_contact_time, SwingAttempt.Kind.POWER)
	_run(duel)
	if duel.path != null and duel.result != PitchDuel.Result.FOUL:
		assert_almost_eq(Trajectory.ground_distance(duel.ball.pos), Trajectory.ground_distance(duel.path.end_point()), 0.05)
	else:
		pass_test("foul or no contact with this seed")


func test_same_seed_replays_the_same_pitch() -> void:
	var outcomes: Array[String] = []
	for attempt: int in 2:
		var duel := _duel(99)
		var rng := Rng.new(5)
		duel.throw_pitch(AiPitcher.choose(catalog, duel.zone, rng))
		AiBatter.react(duel, rng)
		_run(duel)
		outcomes.append("%d %s %s" % [duel.result, duel.ball.pos, duel.time])
	assert_eq(outcomes[0], outcomes[1])


func test_ai_against_ai_produces_a_believable_mix_of_results() -> void:
	var counts := {}
	var rng := Rng.new(2026)
	var pitches := 1500
	var exit_speed := 0.0
	var contacts := 0
	for i: int in pitches:
		var duel := PitchDuel.new(cfg, field, DuelSettings.new(), rng.fork(i))
		duel.throw_pitch(AiPitcher.choose(catalog, duel.zone, rng))
		AiBatter.react(duel, rng)
		_run(duel)
		counts[duel.result] = int(counts.get(duel.result, 0)) + 1
		if duel.contact != null and duel.contact.made_contact:
			exit_speed += duel.contact.exit_speed_kmh()
			contacts += 1
	var balls: int = counts.get(PitchDuel.Result.BALL, 0)
	var called: int = counts.get(PitchDuel.Result.CALLED_STRIKE, 0)
	var whiffs: int = counts.get(PitchDuel.Result.SWINGING_STRIKE, 0)
	var fouls: int = counts.get(PitchDuel.Result.FOUL, 0)
	var in_play: int = counts.get(PitchDuel.Result.IN_PLAY, 0) + int(counts.get(PitchDuel.Result.HOME_RUN, 0))
	gut.p("balls %d, called %d, whiffs %d, fouls %d, in play %d (home runs %d), mean exit speed %.0f km/h" % [
		balls, called, whiffs, fouls, in_play, int(counts.get(PitchDuel.Result.HOME_RUN, 0)), exit_speed / maxi(contacts, 1)])
	# Loose bounds: this minimal AI only has to be plausible. Stage S5 calibrates it properly.
	assert_eq(balls + called + whiffs + fouls + in_play, pitches, "every pitch has a result")
	assert_between(float(balls) / pitches, 0.28, 0.44, "balls")
	assert_between(float(called) / pitches, 0.10, 0.26, "called strikes")
	assert_between(float(whiffs) / pitches, 0.05, 0.16, "swinging strikes")
	assert_between(float(fouls) / pitches, 0.07, 0.25, "fouls")
	assert_between(float(in_play) / pitches, 0.12, 0.30, "balls in play")
	assert_between(exit_speed / contacts, 118.0, 156.0, "mean exit speed (km/h)")
