extends GutTest
## A career game on screen (docs/13 S8-3): only his scenes, a card before each, the result and
## growth points back to the career.

const MATCH := preload("res://career/career_match.tscn")
const DT := 1.0 / 60.0


func after_all() -> void:
	CareerSession.career_season = null
	CareerSession.last_report = null


func _start(position: String, type_id: String) -> void:
	var r := CareerIO.load_default()
	var spec := PlayerCreator.Spec.new()
	spec.name = "화면신인"
	spec.position = position
	spec.type_id = type_id
	var c := PlayerCreator.create(spec, r, PitchCatalogIO.load_default())
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	CareerSession.start(c, clubs[24].id, 36, 7)
	# Wait for a game day.
	var guard := 0
	while not CareerSession.career_season.has_game() and guard < 10:
		CareerSession.career_season.next_day()
		guard += 1


func test_a_hitter_s_game_stops_for_his_scenes_and_reports_back() -> void:
	_start("CF", "speed")
	var scene := MATCH.instantiate() as CareerMatch
	scene.use_motion = false
	add_child_autofree(scene)
	assert_eq(scene.me, CareerSession.career.player.id)
	assert_eq(scene.game.teams[scene.my_team].team_id, CareerSession.career.team_id)
	var scenes := 0
	var t := 0.0
	while not scene.game.over and t < 1800.0:
		scene.step(DT)
		t += DT
		if scene.paused and scene.my_scene_now():
			assert_not_null(scene.goal)
			assert_string_contains(scene.alert, scene.goal.label())
			scenes += 1
			scene.intervene()
			assert_true(scene.human_bats())
	assert_true(scene.game.over, "the game ended")
	assert_between(scenes, 3, 6, "four or five turns at bat")
	gut.p("a fielder's career game: %.1f min, %d scenes" % [t / 60.0, scenes])
	assert_lt(t, 8.5 * 60.0, "docs/02: six to eight minutes")
	assert_not_null(scene.report, "the result went to the career")
	assert_eq(CareerSession.last_report, scene.report)
	assert_eq(CareerSession.career_season.futures_games, 1, "a second-team game")
