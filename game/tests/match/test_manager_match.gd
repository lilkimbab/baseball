extends GutTest
## The manager mode headless (docs/13 S7-6): summary plate appearances, key moments played out,
## orders, reservations, interventions and skipping.

const SCENE := preload("res://match/manager_match.tscn")
const DT := 1.0 / 60.0


func _start(seed_value: int, innings: int = 3) -> ManagerMatch:
	var scene := SCENE.instantiate() as ManagerMatch
	scene.human_team = -1
	scene.my_team = 1
	scene.innings = innings
	scene.seed_value = seed_value
	scene.use_motion = false
	# The park the pace was measured in (a small park's extra hits make longer innings).
	scene.stadium_id = "standard"
	add_child_autofree(scene)
	return scene


## Steps until `done` or the time runs out; returns the seconds of game time used.
func _run(scene: ManagerMatch, done: Callable, limit: float = 3600.0) -> float:
	var t := 0.0
	while not done.call() and t < limit:
		scene.step(DT)
		t += DT
	return t


func test_a_managed_game_goes_by_in_summary_and_ends() -> void:
	var scene := _start(21)
	assert_eq(scene.human_team, -1, "the computer plays both sides")
	var board_seen := false
	var live_seen := false
	var t := 0.0
	while not scene.game.over and t < 3600.0:
		scene.step(DT)
		t += DT
		if scene.board_visible():
			board_seen = true
		if scene.live():
			live_seen = true
		# An alert would wait for the player; none is set here.
		assert_false(scene.paused)
	assert_true(scene.game.over, "finished in %.0f s of game time" % t)
	assert_true(board_seen)
	gut.p("three innings managed in %.0f s (%d plate appearances, key moments live: %s)" % [t, scene.scorer.book.team_batting(0).pa + scene.scorer.book.team_batting(1).pa, live_seen])
	# Docs/02: a nine-inning managed game takes 10 to 15 minutes; three innings a third of it.
	assert_lt(t, 330.0)
	assert_eq(scene.interventions_left, ManagerMatch.INTERVENTIONS)


func test_a_reservation_stops_the_game_and_enter_takes_the_plate_appearance() -> void:
	var scene := _start(22)
	var preset := scene.reservation_presets[0]
	assert_eq(preset.label, "득점권 기회에 알림")
	scene.reservations.append(preset)
	_run(scene, func() -> bool: return scene.paused or scene.game.over)
	assert_true(scene.paused, "our runner reached scoring position")
	assert_eq(scene.game.batting(), scene.my_team)
	assert_false(scene.game.base_empty(2) and scene.game.base_empty(3))
	var batter := scene.game.batter_id()
	scene.intervene()
	assert_false(scene.paused)
	assert_true(scene.intervening)
	assert_eq(scene.human_team, scene.my_team)
	assert_true(scene.human_bats())
	assert_eq(scene.interventions_left, ManagerMatch.INTERVENTIONS - 1)
	# The player does not swing: the plate appearance still ends, and the computer takes over.
	_run(scene, func() -> bool: return scene.game.batter_id() != batter or scene.game.over, 600.0)
	assert_true(scene.intervening, "until the result has been shown")
	_run(scene, func() -> bool: return not scene.intervening, 10.0)
	assert_false(scene.intervening)
	assert_eq(scene.human_team, -1)


func test_no_interventions_left_means_none() -> void:
	var scene := _start(23)
	scene.interventions_left = 0
	scene.intervene()
	assert_false(scene.intervening)


func test_an_order_given_between_pitches_counts_for_this_pitch() -> void:
	var scene := _start(24)
	# Wait for our turn at bat.
	_run(scene, func() -> bool: return scene.game.batting() == scene.my_team and scene.state == DuelScene.State.PRE_PITCH and scene._play_time < 0.0 and scene.game.strikes < 2)
	scene.resolver.tactics[scene.my_team].order = Tactics.Order.BUNT
	scene.apply_orders_now()
	assert_true(scene.resolver.is_bunting())
	scene.open_orders()
	assert_true(scene.orders.visible)
	var before := scene.state_time
	scene.step(0.5)
	assert_eq(scene.state_time, before, "the game waits while the orders menu is open")
	scene.orders.close()


func test_skipping_runs_to_the_end_of_the_half_inning() -> void:
	var scene := _start(25)
	var half := "%d%s" % [scene.game.inning, scene.game.top]
	scene.skip(true)
	scene.step(DT)
	var guard := 0
	while scene._skip > 0 and guard < 50:
		scene.step(DT)
		guard += 1
	assert_ne("%d%s" % [scene.game.inning, scene.game.top], half)
	assert_eq(scene._skip, 0)


func test_a_key_moment_is_played_out_live() -> void:
	var scene := _start(26)
	scene.leverage = WinExpectancy.HIGH + 0.5
	assert_true(scene.live())
	assert_false(scene.board_visible())
	scene.leverage = 0.5
	assert_false(scene.live())
	scene.show_every_pitch = true
	assert_true(scene.live())
