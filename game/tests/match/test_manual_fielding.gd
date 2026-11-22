extends PlayTest
## The player's own fielder (docs/05 2.3): he runs at his own speed where he is pushed, takes
## the ball when it comes within his reach, dives for one just beyond it, and stays in the
## park. And the slow-motion moments (docs/05 3.4): only real ones, and not one after another.

const DT := 1.0 / 60.0


func _fielder(kind: Position.Kind, at: Vector2, speed: float = 50.0, range_rating: float = 50.0) -> ManualFielding:
	return ManualFielding.make(PlayFielder.make(kind, at, speed, range_rating), motion, field)


## Runs him toward `to` until `until` s, then lets him stand; true if he got the ball. The
## catch key is pressed from `catch_from` s on, every frame (−1: never).
func _chase(mf: ManualFielding, path: Trajectory, to: Vector2, until: float, dive_at: float = -1.0, catch_from: float = 0.0) -> bool:
	var t := 0.0
	while t < until:
		t += DT
		if catch_from >= 0.0 and t >= catch_from:
			mf.press_catch(t)
		if dive_at >= 0.0 and t >= dive_at and mf.dive_time < 0.0 and not mf.got:
			mf.dive(t, path)
		var push := (to - mf.pos).normalized() if mf.pos.distance_to(to) > 0.4 else Vector2.ZERO
		if mf.step(t, DT, push, path):
			return true
	return false


func test_he_runs_at_his_own_speed_and_a_rangy_fielder_gets_going_sooner() -> void:
	var path := _fly_to(95.0, 0.0, 34.0)
	var slow := _fielder(Position.Kind.SS, Vector2(0.0, 40.0), 30.0, 30.0)
	var quick := _fielder(Position.Kind.SS, Vector2(0.0, 40.0), 30.0, 90.0)
	for i: int in 30:
		slow.step((i + 1) * DT, DT, Vector2(1.0, 0.0), path)
		quick.step((i + 1) * DT, DT, Vector2(1.0, 0.0), path)
	assert_gt(quick.pos.x, slow.pos.x + 0.3, "half a second in, the rangy one is ahead")
	var charging := _fielder(Position.Kind.CF, Vector2(0.0, 95.0), 30.0, 30.0)
	for i: int in 240:
		charging.step((i + 1) * DT, DT, Vector2(0.0, -1.0), path)
	assert_almost_eq(charging.velocity.length(), motion.top_speed_for(30.0), 0.01, "never faster than he runs")
	# Going back on the ball is slower.
	var back := _fielder(Position.Kind.CF, Vector2(0.0, 80.0), 30.0, 30.0)
	for i: int in 240:
		back.step((i + 1) * DT, DT, Vector2(0.0, 1.0), path)
	assert_almost_eq(back.velocity.length(), motion.top_speed_for(30.0) * motion.backward, 0.01)


func test_he_catches_the_fly_he_gets_under_and_not_the_one_he_does_not() -> void:
	var path := _fly_to(95.0, 3.0, 34.0)
	var land := path.events[0]
	var spot := Vector2(land.pos.x, land.pos.y)
	var under := _fielder(Position.Kind.CF, spot + Vector2(6.0, -4.0))
	assert_true(_chase(under, path, spot, land.time + 0.5), "under it in time")
	assert_lt(under.got_time, land.time, "in the air")
	assert_lte(under.got_at.z, motion.reach_high)
	assert_false(under.got_dive)
	var choice := PlayChoice.new()
	under.write(choice, under.got_time + 0.3)
	assert_eq(choice.manual_fielder, Position.Kind.CF)
	assert_almost_eq(choice.manual_time, under.got_time, 1e-6)
	assert_gt(choice.manual_track.size(), 5, "where he went is kept")
	assert_true(choice.has_any())
	# Three metres off, standing still: it falls.
	var off := _fielder(Position.Kind.CF, spot + Vector2(3.0, 0.0))
	assert_false(_chase(off, path, off.pos, land.time), "out of reach")
	off.write(choice)
	assert_lt(choice.manual_time, 0.0)


func test_he_catches_only_with_the_glove_up() -> void:
	# docs/05 2.3 (the user: "C를 눌러서 잡게 해"): under the ball without the catch key, it falls
	# by him; the key a moment before it comes is a catch; pressed too soon, the glove is down
	# again by then.
	var path := _fly_to(95.0, 3.0, 34.0)
	var land := path.events[0]
	var spot := Vector2(land.pos.x, land.pos.y)
	var idle := _fielder(Position.Kind.CF, spot + Vector2(6.0, -4.0))
	assert_false(_chase(idle, path, spot, land.time + 0.5, -1.0, -1.0), "no key: it drops")
	var ready := _fielder(Position.Kind.CF, spot + Vector2(6.0, -4.0))
	var t := 0.0
	var pressed := false
	var got := false
	while t < land.time + 0.5 and not got:
		t += DT
		if not pressed and ready.catch_soon(t, path):
			ready.press_catch(t)
			pressed = true
		var push := (spot - ready.pos).normalized() if ready.pos.distance_to(spot) > 0.4 else Vector2.ZERO
		got = ready.step(t, DT, push, path)
	assert_true(pressed, "the prompt came")
	assert_true(got, "one press when the prompt shows is enough")
	var early := _fielder(Position.Kind.CF, spot + Vector2(6.0, -4.0))
	early.press_catch(0.5)
	assert_false(_chase(early, path, spot, land.time + 0.5, -1.0, -1.0), "pressed seconds before: the glove is down again")
	var auto := _fielder(Position.Kind.CF, spot + Vector2(6.0, -4.0))
	auto.auto_catch = true
	assert_true(_chase(auto, path, spot, land.time + 0.5, -1.0, -1.0), "tools may let him take it himself")


func test_a_dive_reaches_what_a_run_does_not_and_leaves_him_down() -> void:
	var path := _fly_to(95.0, 3.0, 34.0)
	var land := path.events[0]
	var spot := Vector2(land.pos.x, land.pos.y)
	# Standing beside its line, further off than he can reach: a dive as it comes down gets
	# it, standing does not.
	var before := path.position_at(land.time - 0.2)
	var along := (spot - Vector2(before.x, before.y)).normalized()
	var beside := spot - along * 0.5 + Vector2(-along.y, along.x) * (motion.reach_running + 0.5)
	var stands := _fielder(Position.Kind.CF, beside)
	assert_false(_chase(stands, path, stands.pos, land.time))
	var dives := _fielder(Position.Kind.CF, beside)
	assert_true(_chase(dives, path, dives.pos, land.time, land.time - 0.3), "laid out for it")
	assert_true(dives.got_dive)
	# One who dives too soon is on the ground when it comes, and the keys do not move him.
	var early := _fielder(Position.Kind.CF, beside)
	assert_false(_chase(early, path, early.pos, land.time, land.time - 0.8))
	var down := _fielder(Position.Kind.CF, Vector2(0.0, 80.0))
	down.step(1.0, DT, Vector2.ZERO, path)
	assert_true(down.dive(1.0, path))
	assert_false(down.dive(1.2, path), "not twice at once")
	for i: int in 30:
		down.step(1.0 + (i + 1) * DT, DT, Vector2(1.0, 0.0), path)
	var lay := down.pos
	down.step(1.0 + 31 * DT, DT, Vector2(1.0, 0.0), path)
	assert_lt(down.pos.distance_to(lay), 0.02, "half a second on he is still getting up")
	for i: int in range(31, 120):
		down.step(1.0 + (i + 1) * DT, DT, Vector2(1.0, 0.0), path)
	assert_gt(down.pos.x, lay.x + 3.0, "then he runs again")


func test_he_fields_a_grounder_that_comes_to_him() -> void:
	var path := _hit(125.0, -6.0, -15.0)
	var ss := _fielder(Position.Kind.SS, Vector2(-9.0, 38.0))
	var meet := Vector2.ZERO
	var t := 0.0
	while t < path.duration():
		var p := path.position_at(t)
		if Trajectory.ground_distance(p) >= 37.0:
			meet = Vector2(p.x, p.y)
			break
		t += 0.01
	assert_true(_chase(ss, path, meet, 3.0), "he cuts it off")
	assert_gt(ss.got_time, path.events[0].time, "on the ground")


func test_he_stays_inside_the_fence() -> void:
	var path := _fly_to(95.0, 0.0, 34.0)
	var cf := _fielder(Position.Kind.CF, Vector2(0.0, 100.0), 90.0, 90.0)
	for i: int in 600:
		cf.step((i + 1) * DT, DT, Vector2(0.0, 1.0), path)
	assert_almost_eq(cf.pos.length(), field.boundary_distance(0.0) - ManualFielding.WALL_ROOM, 0.05)


# --- Highlights ---


func _play_of(result: PaResult.Kind) -> PlayResult:
	var p := PlayResult.new()
	p.result = result
	return p


func test_only_a_ball_really_crushed_is_one() -> void:
	assert_true(PlayHighlight.crushed(_play_of(PaResult.Kind.HOME_RUN), 150.0))
	var deep := _play_of(PaResult.Kind.FLY_OUT)
	deep.short_of_fence = 2.0
	assert_true(PlayHighlight.crushed(deep, 165.0), "a drive to the foot of the fence")
	assert_false(PlayHighlight.crushed(deep, 140.0), "a lazy fly that carried is not")
	deep.short_of_fence = 12.0
	assert_false(PlayHighlight.crushed(deep, 165.0), "nor one caught well short")
	assert_false(PlayHighlight.crushed(_play_of(PaResult.Kind.SINGLE), 175.0), "nor a hard grounder")
	var foul := _play_of(PaResult.Kind.NONE)
	foul.foul = true
	assert_false(PlayHighlight.crushed(foul, 175.0))


func test_only_a_chance_really_in_doubt_is_one() -> void:
	var p := _play_of(PaResult.Kind.FLY_OUT)
	assert_false(PlayHighlight.in_doubt(p), "no hard chance at all")
	p.hard_fielder = Position.Kind.CF
	p.hard_made = true
	p.hard_odds = 0.9
	assert_false(PlayHighlight.in_doubt(p), "a catch he makes nine times in ten")
	p.hard_odds = 0.4
	assert_true(PlayHighlight.in_doubt(p), "a catch he makes less than half the time")
	p.hard_made = false
	assert_true(PlayHighlight.in_doubt(p), "missed, when it could well have been caught")
	p.hard_odds = 0.05
	assert_false(PlayHighlight.in_doubt(p), "missed, when he never had a chance")


func test_highlights_do_not_come_one_after_another() -> void:
	var p := _play_of(PaResult.Kind.FLY_OUT)
	p.hard_fielder = Position.Kind.CF
	p.hard_made = true
	p.hard_odds = 0.4
	p.hard_time = 3.2
	p.hard_at = Vector3(10.0, 80.0, 1.0)
	assert_eq(PlayHighlight.of(p, 140.0, PlayHighlight.REST).size(), 1)
	assert_eq(PlayHighlight.of(p, 140.0, PlayHighlight.REST - 1).size(), 0, "too soon after the last")
	var h := PlayHighlight.of(p, 140.0, PlayHighlight.REST)[0]
	assert_eq(h.kind, PlayHighlight.Kind.CHANCE)
	assert_eq(h.key, "F:CF")
	assert_almost_eq(h.pace_at(3.2), PlayHighlight.CHANCE_PACE, 1e-6, "slow as the ball gets to him")
	assert_eq(h.pace_at(1.0), 1.0, "and at its own speed before")
	assert_eq(h.pace_at(4.2), 1.0, "and after")
	assert_true(h.showing(3.0))
	assert_false(h.showing(1.0))
	# A home run is always shown; with the catch at the wall both are.
	var gone := _play_of(PaResult.Kind.HOME_RUN)
	assert_eq(PlayHighlight.of(gone, 170.0, 0).size(), 1)
	p.short_of_fence = 1.0
	var both := PlayHighlight.of(p, 168.0, PlayHighlight.REST)
	assert_eq(both.size(), 2, "crushed, and caught against the fence")
	assert_eq(both[0].kind, PlayHighlight.Kind.CONTACT)
	assert_gt(both[0].freeze, 0.0, "the picture stands still on the contact")
	assert_almost_eq(both[0].pace_at(0.05), PlayHighlight.CONTACT_PACE, 1e-6)
