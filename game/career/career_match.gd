class_name CareerMatch
extends ManagerMatch
## A career game (docs/02 section 6.2, docs/13 S8-3): only the player's scenes are played —
## his turns at bat, and on the mound the batters that matter (runners in scoring position,
## the heart of the order, the first batter of an inning; "전부 직접" plays them all). The rest
## goes by on the situation board. Before each scene a card shows the score, the situation and
## the scene's goal; Enter goes in. Balls in play are shown on the field as in the manager mode.
##
## The game (first team or second team) comes from CareerSession; the result goes back to it.

## Pitch to every batter, not just the ones that matter.
var pitch_all := false
## The position camera: metres behind and above him.
const POSITION_BACK := 3.5
const POSITION_HEIGHT := 2.1
var me := ""
var goal: SceneGoal
var game_goal: GameGoal
## Growth points from scene goals in this game, per field; clutch scenes won.
var scene_gp: Dictionary[String, float] = {"batting": 0.0, "fielding": 0.0, "running": 0.0, "pitching": 0.0}
var clutch_wins := 0
var chances := 0
var errors := 0
var report: CareerSeason.Report
var _scene_key := ""
var _best_count := Vector2i.ZERO
var _runners_before: Array[bool] = [false, false, false]
var _scene_leverage := 0.0
var _card := PackedStringArray()


func card_lines() -> PackedStringArray:
	if not paused or _card.is_empty():
		return PackedStringArray()
	return _card


func _start_game() -> void:
	var cs := CareerSession.career_season
	if cs == null:
		super._start_game()
		return
	var sim := cs.prepare(true)
	game = sim.state
	resolver = sim.resolver as PhysicalResolver
	scorer = sim.scorer
	manager = sim.manager
	innings = game.rules.innings
	var g := cs.club_game()
	my_team = 0 if g.away == cs.career.team_id else 1
	me = cs.career.player.id
	game_goal = GameGoal.for_player(cs.career, cs.rules)
	interventions_left = 0
	_chosen_team = my_team
	balls = 0
	strikes = 0


func _ready() -> void:
	# The board goes faster than in the manager mode: a plate appearance in a second or so
	# (docs/05 section 3.5).
	summary_gap = 0.05
	summary_pitch_time = 0.12
	summary_result_time = 1.1
	super._ready()
	if CareerSession.career_season != null:
		for c: Dictionary in pause_menu.quit_requested.get_connections():
			pause_menu.quit_requested.disconnect(c["callable"])
		pause_menu.quit_requested.connect(func() -> void: get_tree().change_scene_to_file(CareerSession.HUB))


func help_keys() -> String:
	if intervening:
		return super.help_keys()
	return "Enter 장면 시작  1·2·4 속도  Space 멈춤  → 타석 넘기기  Shift+→ 이닝 넘기기"


## The player is not the manager here.
func open_orders() -> void:
	pass


func board_note() -> String:
	if game_goal == null:
		return ""
	return "경기 목표: %s" % game_goal.label()


func post_game_hint() -> String:
	return "Enter · Esc 커리어로 돌아가기"


## His scene: he is at bat, or on the mound against a batter that matters.
func my_scene_now() -> bool:
	if game == null or game.over or me == "":
		return false
	if game.batting() == my_team and game.batter_id() == me:
		return true
	if game.fielding() == my_team and game.pitcher_id() == me:
		return pitch_all or _key_batter()
	return false


func _key_batter() -> bool:
	if not game.base_empty(2) or not game.base_empty(3):
		return true
	var slot := game.batting_team().slot_of(game.batter_id())
	if slot >= 2 and slot <= 4:
		return true
	return game.outs == 0 and game.runners_on() == 0


## No interventions here; Enter starts the scene on the card.
func intervene() -> void:
	if intervening or not my_scene_now():
		return
	intervening = true
	_intervened_key = _key_now()
	paused = false
	alert = ""
	_skip = 0
	human_team = my_team
	set_auto_changes(true)
	_sync_mode()
	_snap_camera()


func _note_plate_appearance() -> void:
	if state != State.PRE_PITCH or _play_time >= 0.0 or game.over:
		return
	var key := _key_now()
	if key == _pa_key:
		return
	super._note_plate_appearance()
	if my_scene_now() and key != _scene_key:
		_scene_key = key
		goal = SceneGoal.for_batting(game) if game.batting() == my_team else SceneGoal.for_pitching(game)
		_best_count = Vector2i.ZERO
		_runners_before = [not game.base_empty(1), not game.base_empty(2), not game.base_empty(3)]
		_scene_leverage = leverage
		var who := "타석" if game.batting() == my_team else "마운드"
		alert = "내 장면 · %s   %s   목표: %s   Enter 시작" % [who, _situation(), goal.label()]
		_card = PackedStringArray(["내 장면 · %s" % who, _situation(), "목표: " + goal.label(), "Enter 시작"])
		banner = ""
		banner_time = 0.0
		paused = true
		_skip = 0


func _situation() -> String:
	var bases := PackedStringArray()
	for b: int in [1, 2, 3]:
		if not game.base_empty(b):
			bases.append(str(b))
	var on := "주자 없음" if bases.is_empty() else "%s루" % "·".join(bases)
	return "%d회%s %d사 %s · %d-%d" % [game.inning, "초" if game.top else "말", game.outs, on, game.score[0], game.score[1]]


## Only balls hit his way are shown (docs/02 section 6.2): his fielding chances.
func show_in_summary(play: PlayResult) -> bool:
	if game.fielding() != my_team or CareerSession.career_season == null:
		return false
	var number := str(CareerSession.career_season.career.player.primary_position() + 1)
	if CareerSession.career_season.career.is_pitcher():
		number = "1"
	for part: String in play.fielders.split("-"):
		if part == number or part == "E" + number:
			return true
	return play.direction == int(number)


## A ball hit his way is watched from where he plays (docs/02 section 6.2, docs/13 S8-4): just
## behind and above him, turning with the ball. He fields it automatically until the fielding
## controls come (S12).
func _move_camera_play(delta: float) -> void:
	if _play == null or game.fielding() != my_team or not show_in_summary(_play):
		super._move_camera_play(delta)
		return
	var kind := CareerSession.career_season.career.player.primary_position()
	if CareerSession.career_season.career.is_pitcher():
		kind = Position.Kind.P
	var key := "F:%s" % Position.code(kind)
	if not _play.timeline.tracks.has(key):
		super._move_camera_play(delta)
		return
	var me_at := _play.timeline.position(key, _play_time)
	var out := Vector2(me_at.x, me_at.y)
	out = out.normalized() if out.length() > 0.5 else Vector2(0.0, 1.0)
	var from := Vector3(me_at.x + out.x * POSITION_BACK, me_at.y + out.y * POSITION_BACK, POSITION_HEIGHT)
	var ball := _ball_at(_play.timeline, _play_time)
	_follow_target = _follow_target.lerp(ball, clampf(delta * 5.0, 0.0, 1.0))
	camera.position = camera.position.lerp(Field.to_world(from), clampf(delta * 6.0, 0.0, 1.0))
	camera.fov = lerpf(camera.fov, 62.0, clampf(delta * 3.0, 0.0, 1.0))
	camera.look_at(Field.to_world(_follow_target))


func live() -> bool:
	if intervening:
		return true
	if _skip > 0:
		return false
	return show_every_pitch


func step(delta: float) -> void:
	if intervening:
		var c := Vector2i(game.balls, game.strikes)
		if c.x - c.y > _best_count.x - _best_count.y:
			_best_count = c
	super.step(delta)


func _apply(e: GameEvent) -> void:
	var fielding := game.fielding()
	var was_mine := intervening
	super._apply(e)
	if fielding == my_team and CareerSession.career_season != null:
		var credit := CareerSession.career_season.fielding_credit(e)
		chances += credit.x
		errors += credit.y
	if e.kind == GameEvent.Kind.PLATE_APPEARANCE and was_mine and goal != null:
		var met := goal.achieved(e, last_outcome, _best_count, _runners_before)
		if met:
			var gp := CareerSession.career_season.rules.scene_goal_gp
			if _scene_leverage >= WinExpectancy.HIGH:
				gp *= CareerSession.career_season.rules.clutch
				clutch_wins += 1
			scene_gp[goal.field] = float(scene_gp.get(goal.field, 0.0)) + gp
		banner = "목표 %s: %s" % ["달성" if met else "실패", goal.label()]
		banner_time = 2.4
		goal = null


## The result goes to the career once the game is over.
func _record_result() -> void:
	if _recorded or game == null or not game.over or CareerSession.career_season == null:
		return
	_recorded = true
	report = CareerSession.career_season.finish(game, scorer.book, chances, errors, scene_gp, clutch_wins)
	CareerSession.last_report = report


func _menu_key(code: Key) -> void:
	if game.over and CareerSession.career_season != null:
		_record_result()
		get_tree().change_scene_to_file(CareerSession.HUB)
		return
	super._menu_key(code)
