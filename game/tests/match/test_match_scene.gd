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
