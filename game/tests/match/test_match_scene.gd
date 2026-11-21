extends GutTest
## The match scene headless (docs/13 S5-10): a three-inning game between two computer teams
## plays to the end, and its books add up.

const MATCH := preload("res://match/match.tscn")
const DT := 1.0 / 120.0


func _start(seed_value: int) -> MatchScene:
	var scene := MATCH.instantiate() as MatchScene
	scene.human_team = -1
	scene.innings = 3
	scene.seed_value = seed_value
	scene.use_motion = false
	add_child_autofree(scene)
	return scene


func test_a_three_inning_game_plays_to_the_end() -> void:
	var scene := _start(11)
	var ticks := 0
	while not scene.game.over and ticks < 200000:
		for i: int in 500:
			scene.step(DT)
		ticks += 500
	assert_true(scene.game.over, "the game finished in %d ticks" % ticks)
	var g := scene.game
	for t: int in 2:
		var runs := 0
		for r: int in g.line[t]:
			runs += r
		assert_eq(runs, g.score[t], "line score adds up")
		assert_eq(scene.scorer.book.team_batting(t).runs, g.score[t])
	assert_gte(g.line[0].size(), 3, "at least three innings")
	assert_gt(scene.log.size(), 10, "a play-by-play was kept")


func test_a_ball_in_play_is_shown_before_it_counts() -> void:
	var scene := _start(12)
	var saw_play := false
	var ticks := 0
	while not saw_play and ticks < 60000:
		scene.step(DT)
		ticks += 1
		if scene._play_time > 0.0 and scene._play != null and not scene._play.foul:
			saw_play = true
			var outs_before := scene.game.outs
			var pa_before := scene.scorer.book.team_batting(scene.game.batting()).pa
			# Nothing is applied until the play has been shown.
			scene.step(DT)
			assert_eq(scene.scorer.book.team_batting(scene.game.batting()).pa, pa_before)
			assert_eq(scene.game.outs, outs_before)
			scene.refresh(DT)
	assert_true(saw_play, "a ball was put in play")


func test_the_manager_s_menu_stops_the_game_and_changes_the_pitcher() -> void:
	var scene := MATCH.instantiate() as MatchScene
	scene.human_team = 1
	scene.innings = 3
	scene.seed_value = 13
	scene.use_motion = false
	add_child_autofree(scene)
	# The home team takes the field in the top of the first: the player is pitching.
	assert_true(scene.human_pitches())
	scene.toggle_menu()
	assert_true(scene.menu.visible)
	var before := scene.state_time
	scene.step(0.5)
	assert_eq(scene.state_time, before, "nothing moves while the menu is open")
	var team := scene.game.teams[1]
	var starter := team.pitcher_id
	var reliever := SubstitutionOptions.relievers(team)[0]
	scene.menu._apply(SubstitutionOptions.pitcher_change(scene.game, 1, reliever))
	assert_eq(team.pitcher_id, reliever)
	assert_false(SubstitutionOptions.relievers(team).has(reliever), "no longer offered")
	assert_eq(scene.duel.settings.command, team.player(reliever).pitching.control, "the next pitch is his")
	assert_ne(starter, reliever)
	scene.toggle_menu()
	assert_false(scene.menu.visible)


## Plays the player's side with scripted input: pitches with a full gauge on varied targets,
## swings on time at what is in the zone.
func _script_player(scene: MatchScene, rng: Rng, swung: Array[bool]) -> void:
	var duel := scene.duel
	if scene.human_pitches():
		match scene.state:
			DuelScene.State.PRE_PITCH:
				if scene.state_time > 0.3:
					scene.target = duel.zone.point(rng.next_range(-0.1, 1.1), rng.next_range(-0.1, 1.1))
					scene.press_pitch_button()
			DuelScene.State.CHARGE:
				if scene.power > 0.8:
					scene.release_pitch_button()
			DuelScene.State.ACCURACY:
				if scene.ring >= DuelScene.ACCURACY_SWEET - 0.03:
					scene.press_pitch_button()
	if scene.human_bats() and scene.state == DuelScene.State.LIVE and duel.phase == PitchDuel.Phase.FLIGHT and not swung[0]:
		var at := duel.pitch.plate_pos
		if duel.zone.contains(at.x, at.z) and duel.time >= duel.ideal_contact_time - SwingModel.swing_time(SwingAttempt.Kind.CONTACT):
			scene.swing(SwingAttempt.Kind.CONTACT)
			swung[0] = true
	if scene.state != DuelScene.State.LIVE:
		swung[0] = false


func test_a_player_can_play_a_three_inning_game_to_the_end() -> void:
	var scene := MATCH.instantiate() as MatchScene
	scene.human_team = 1
	scene.innings = 3
	scene.seed_value = 21
	scene.use_motion = false
	add_child_autofree(scene)
	var rng := Rng.new(3)
	var swung: Array[bool] = [false]
	var ticks := 0
	var batted := 0
	var pitched := 0
	while not scene.game.over and ticks < 400000:
		_script_player(scene, rng, swung)
		if scene.human_bats():
			batted += 1
		elif scene.human_pitches():
			pitched += 1
		scene.step(DT)
		ticks += 1
	assert_true(scene.game.over, "the game finished in %d ticks" % ticks)
	assert_gt(batted, 0, "the player batted")
	assert_gt(pitched, 0, "the player pitched")
	var book := scene.scorer.book
	for t: int in 2:
		var b := book.team_batting(t)
		assert_eq(b.runs, scene.game.score[t])
		assert_eq(b.pa, b.ab + b.walks + b.intentional_walks + b.hit_by_pitch + b.sac_bunts + b.sac_flies)
	assert_eq(book.team_pitching(1).outs, scene.game.line[0].size() * 3, "three outs in every top half")


func test_the_pitch_clock_calls_a_ball_when_the_player_takes_too_long() -> void:
	var scene := MATCH.instantiate() as MatchScene
	scene.human_team = 1
	scene.innings = 3
	scene.seed_value = 31
	scene.use_motion = false
	add_child_autofree(scene)
	assert_true(scene.human_pitches())
	var limit := float(scene.game.rules.pitch_clock_empty)
	for i: int in roundi((limit - 1.0) / DT):
		scene.step(DT)
	assert_eq(scene.game.balls, 0, "still within the clock")
	assert_gt(scene.pitch_clock, 0.0)
	for i: int in roundi(2.0 / DT):
		scene.step(DT)
	assert_eq(scene.game.balls, 1, "the clock ran out: ball one")


func test_the_pause_menu_stops_the_game_and_the_clock_can_be_turned_off() -> void:
	var scene := MATCH.instantiate() as MatchScene
	scene.human_team = 1
	scene.innings = 3
	scene.seed_value = 32
	scene.use_motion = false
	add_child_autofree(scene)
	scene._menu_key(KEY_ESCAPE)
	assert_true(scene.pause_menu.visible)
	var before := scene.state_time
	scene.step(1.0)
	assert_eq(scene.state_time, before, "paused")
	scene.pitch_clock_on = false
	scene._menu_key(KEY_ESCAPE)
	assert_false(scene.pause_menu.visible)
	for i: int in roundi(30.0 / DT):
		scene.step(DT)
	assert_eq(scene.game.balls, 0, "no clock: the player may take his time")


func test_with_manual_changes_the_computer_leaves_the_player_s_pitcher_in() -> void:
	var scene := MATCH.instantiate() as MatchScene
	scene.human_team = 1
	scene.innings = 3
	scene.seed_value = 33
	scene.use_motion = false
	add_child_autofree(scene)
	scene.set_auto_changes(false)
	assert_eq(scene.manager.manual_team, 1)
	var g := scene.game
	# A starter far past his limit would be taken out by the computer manager.
	g.pitch_counts[g.teams[1].pitcher_id] = 160
	assert_null(scene.manager.next_change(g), "the player's own pitcher stays until he changes him")
	scene.set_auto_changes(true)
	assert_not_null(scene.manager.next_change(g), "with the computer's help he is relieved")


func test_the_catcher_s_mitt_takes_the_pitch_where_it_arrives() -> void:
	# docs/13 S12-4, S12-8: the pocket of the mitt is on the ball as it is caught.
	var scene := _start(13)
	var checked := 0
	var ticks := 0
	while checked < 3 and ticks < 60000:
		scene.step(DT)
		scene.refresh(DT)
		ticks += 1
		if scene.state != DuelScene.State.RESULT or scene.state_time > 0.02 or scene._play_time >= 0.0:
			continue
		if scene.duel.bounced or scene.duel.result not in [PitchDuel.Result.BALL, PitchDuel.Result.CALLED_STRIKE, PitchDuel.Result.SWINGING_STRIKE]:
			continue
		var pocket := scene.catcher.global_transform * scene.catcher.glove_pocket()
		assert_lt(pocket.distance_to(Field.to_world(scene.duel.ball.pos)), 0.05, "pitch %d" % checked)
		checked += 1
		while scene.state == DuelScene.State.RESULT:
			scene.step(DT)
	assert_eq(checked, 3, "three caught pitches looked at")


func test_the_player_s_throw_or_running_call_is_taken_when_the_fielder_has_the_ball() -> void:
	# docs/05 2.3, 2.4: keys pressed while the ball is on its way count once it is fielded.
	var scene := MATCH.instantiate() as MatchScene
	scene.human_team = 1
	scene.innings = 3
	scene.seed_value = 14
	scene.use_motion = false
	add_child_autofree(scene)
	var rng := Rng.new(3)
	var swung: Array[bool] = [false]
	var taken := 0
	var ticks := 0
	while taken < 2 and ticks < 120000 and not scene.game.over:
		_script_player(scene, rng, swung)
		scene.step(DT)
		ticks += 1
		if not scene.choice_open() or scene._play_time > 0.05:
			continue
		var fielding := scene._controls_fielding()
		assert_true(scene.choice_key(KEY_RIGHT if fielding else KEY_E, true))
		if fielding:
			for i: int in 30:
				scene.step(DT)
			assert_true(scene.choice_key(KEY_RIGHT, false))
		while scene.choice_open():
			scene.step(DT)
		if fielding:
			assert_eq(scene.choice().throw_to, 1)
			assert_between(scene.choice().gauge, 0.3, 0.7, "a quarter second of gauge")
		else:
			assert_eq(scene.choice().running, 1)
		assert_eq(scene._play, scene.resolver.last_play, "the play shown is the one played again")
		taken += 1
		while scene._play_time >= 0.0:
			scene.step(DT)
	assert_eq(taken, 2, "two plays with a choice")
	# The game goes on to the end with its books straight.
	while not scene.game.over and ticks < 400000:
		_script_player(scene, rng, swung)
		scene.step(DT)
		ticks += 1
	assert_true(scene.game.over)
	for t: int in 2:
		assert_eq(scene.scorer.book.team_batting(t).runs, scene.game.score[t])


func test_the_player_steals_second_by_letting_go_as_the_pitcher_moves() -> void:
	# docs/05 2.4: hold Shift, let go with the pitcher's first move.
	var scene := MATCH.instantiate() as MatchScene
	scene.human_team = 0
	scene.innings = 3
	scene.seed_value = 16
	scene.use_motion = false
	add_child_autofree(scene)
	while scene.state != DuelScene.State.PRE_PITCH:
		scene.step(DT)
	var team := scene.game.batting_team()
	var runner_id := team.lineup[8].player_id
	scene.game.bases[0] = BaseRunner.make(runner_id, scene.game.pitcher_id())
	assert_eq(scene.steal_base(), 1)
	assert_true(scene.steal_key(true))
	while scene._pitch_clock < 0.05:
		scene.step(DT)
	assert_true(scene.steal_key(false))
	assert_almost_eq(scene.steal_jump(), MatchScene.BEST_JUMP, 0.01, "a good jump")
	assert_eq(scene.resolver.human_steal, 1)
	var outs := scene.game.outs
	var ticks := 0
	while scene.state != DuelScene.State.RESULT and ticks < 6000:
		scene.step(DT)
		ticks += 1
	if scene._play != null and not scene._running:
		pass_test("the pitch was put in play; the runner's start went into it")
		return
	if not scene._running:
		# The throw got away: he is on third, and it is only reported.
		assert_not_null(scene.game.runner_on(3), "a wild throw takes him to third")
		return
	assert_true(scene._running, "the catcher's throw is shown")
	gut.p("steal play shown")
	while scene._play_time >= 0.0:
		scene.step(DT)
	var on_second: bool = scene.game.runner_on(2) != null and scene.game.runner_on(2).player_id == runner_id
	assert_true(on_second or scene.game.outs == outs + 1 or scene.game.top == false, "safe at second or out")


func test_a_one_inning_practice_game_is_one_half_batting_and_one_pitching() -> void:
	# The player as the visitors: he bats in the top of the first and pitches in the bottom,
	# and the game ends there, tied or not.
	var scene := MATCH.instantiate() as MatchScene
	scene.human_team = 0
	scene.innings = 1
	scene.seed_value = 18
	scene.use_motion = false
	add_child_autofree(scene)
	var rng := Rng.new(9)
	var swung: Array[bool] = [false]
	var batted := false
	var pitched := false
	var ticks := 0
	while not scene.game.over and ticks < 200000:
		_script_player(scene, rng, swung)
		scene.step(DT)
		ticks += 1
		if scene.state == DuelScene.State.PRE_PITCH and not scene.game.over:
			batted = batted or scene.human_bats()
			pitched = pitched or scene.human_pitches()
	assert_true(scene.game.over, "finished")
	assert_true(batted, "the player batted")
	assert_eq(scene.game.inning, 1, "no extra innings")
	assert_eq(scene.game.line[0].size(), 1)
	# The bottom half is always played: the home side cannot lead before it.
	assert_true(pitched, "the player pitched the bottom half")


func test_the_ball_leaves_from_the_pitcher_s_hand() -> void:
	# The release point was measured through the pitcher as he happened to stand when his
	# delivery was picked: after fielding a ball he was still turned away and the pitch came
	# from behind him. Now it is his hand at the moment of release, for every pitch.
	if MotionLibrary.find(&"pitch") == null:
		pass_test("no recorded deliveries here")
		return
	var scene := MATCH.instantiate() as MatchScene
	scene.human_team = -1
	scene.innings = 3
	scene.seed_value = 5
	add_child_autofree(scene)
	var checked := 0
	var ticks := 0
	while checked < 14 and ticks < 120000 and not scene.game.over:
		var before := scene.state
		scene.step(1.0 / 240.0)
		ticks += 1
		if not (before == DuelScene.State.WINDUP and scene.state == DuelScene.State.LIVE):
			continue
		var start := scene.duel.ball.pos
		assert_lt(start.y, Field.RUBBER_Y, "pitch %d leaves in front of the rubber" % checked)
		scene.pitcher.apply_joints(scene.pitch_motion.frame(scene.release_time()), scene.pitch_motion.clip)
		var hand := Field.to_field(scene.pitcher.global_transform * scene.pitcher.ball_spot(scene._throwing_hand))
		assert_lt(hand.distance_to(start), 0.2, "pitch %d leaves from his hand" % checked)
		checked += 1
	assert_eq(checked, 14)


func test_the_catcher_stays_put_while_the_pitcher_aims() -> void:
	var scene := MATCH.instantiate() as MatchScene
	scene.human_team = 1
	scene.innings = 3
	scene.seed_value = 19
	scene.use_motion = false
	add_child_autofree(scene)
	while not scene.human_pitches() or scene.state != DuelScene.State.PRE_PITCH:
		scene.step(DT)
	var middle := scene.catcher.position
	for corner: Vector3 in [Vector3(0.3, Field.PLATE_FRONT_Y, 0.5), Vector3(-0.3, Field.PLATE_FRONT_Y, 1.1)]:
		scene.pointer_override = scene.camera.unproject_position(Field.to_world(corner))
		scene.refresh(DT)
		assert_lt(scene.catcher.position.distance_to(middle), 0.001, "he does not move to the target")
