extends SceneTree
## Plays the match scene (computer against computer) and saves screenshots: before a pitch
## and at moments during the first balls in play, to check the stage without a person.
##
##   ./dev tool-win match_shots build/match/shot --plays 3
##
## Options: --out <path prefix>  --plays <n, default 2>  --seed <n>  --speed <time scale,
##          default 2: waits between pitches pass faster>  --to-end: play the game out and
##          photograph the screen after it  --menus: the player's side, with the pause menu
##          and the pitch clock  --manager: the manager mode (situation board, orders menu,
##          a ball in play shown from the summary)

var _scene: MatchScene
var _prefix := "user://match"
var _plays := 2
var _seen := 0
var _frames := 0
var _due: Array[String] = []
var _taken := {}
var _was_playing := false
var _to_end := false
var _menus := false
var _manager := false


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_prefix = args.get("out", _prefix)
	_plays = int(str(args.get("plays", "2")))
	Engine.time_scale = float(str(args.get("speed", "2")))
	_manager = args.has("manager")
	var packed := load("res://match/manager_match.tscn" if _manager else "res://match/match.tscn") as PackedScene
	_scene = packed.instantiate() as MatchScene
	_to_end = args.has("to-end")
	_menus = args.has("menus")
	_scene.human_team = 1 if _menus else -1
	_scene.innings = 3
	_scene.seed_value = int(str(args.get("seed", "20261121")))
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	for name: String in _due:
		root.get_texture().get_image().save_png("%s_%s.png" % [_prefix, name])
	_due.clear()
	if _frames > (200000 if _to_end else 20000):
		print("match_shots: gave up after %d frames" % _frames)
		return true
	if _menus:
		return _menu_shots()
	if _manager:
		return _manager_shots()
	if _to_end:
		if _scene.game.over and not _taken.has("postgame"):
			_shoot("postgame")
		return _taken.has("postgame") and _due.is_empty()
	if _scene.state == DuelScene.State.LIVE and _scene.duel.phase == PitchDuel.Phase.FLIGHT and not _taken.has("pitch"):
		_shoot("pitch")
	# The Tab detail cards, once, a moment before the second pitch.
	if _taken.has("pitch") and _scene.state == DuelScene.State.PRE_PITCH and _scene.state_time > 0.5 and not _taken.has("detail"):
		_scene.bottom_bar.detail = true
		_shoot("detail")
	elif _taken.has("detail") and _due.is_empty():
		_scene.bottom_bar.detail = false
	# A left-handed batter (mirrored model) and a left-handed pitcher, once each.
	if _scene.state == DuelScene.State.WINDUP and _scene.settings.bats_left and not _taken.has("lefty_batter"):
		_shoot("lefty_batter")
	if _scene.state == DuelScene.State.WINDUP and _scene.settings.throws_left and not _taken.has("lefty_pitcher"):
		_shoot("lefty_pitcher")
	if _frames % 600 == 0:
		print("match_shots: fps %.0f" % Engine.get_frames_per_second())
	var playing := _scene._play_time >= 0.0 and _scene._play != null and not _scene._play.foul
	if playing:
		for at: float in [0.5, 1.5, 3.0, 5.0]:
			var tag := "%d_play_%.1f" % [_seen, at]
			if _scene._play_time >= at and not _taken.has(tag) and _scene._play_time < _scene._play.timeline.duration + 0.5:
				_shoot(tag)
	if _was_playing and not playing:
		_seen += 1
		_shoot("%d_after" % (_seen - 1))
	_was_playing = playing
	return _seen >= _plays and _due.is_empty()


## The pitch clock running, then the pause menu, then the manager's menu.
func _menu_shots() -> bool:
	if _scene.pitch_clock >= 0.0 and _scene.pitch_clock < 12.0 and not _taken.has("clock"):
		_shoot("clock")
	elif _taken.has("clock") and not _taken.has("pause") and _due.is_empty():
		_scene._menu_key(KEY_ESCAPE)
		_shoot("pause")
	elif _taken.has("pause") and not _taken.has("subs") and _due.is_empty():
		_scene.pause_menu.close()
		_scene.toggle_menu()
		_shoot("subs")
	return _taken.has("subs") and _due.is_empty()


## The board between pitches, the orders menu, then a ball in play from the summary.
func _manager_shots() -> bool:
	var m := _scene as ManagerMatch
	if m.board_visible() and m.log.size() >= 4 and not _taken.has("board"):
		_shoot("board")
	elif _taken.has("board") and not _taken.has("orders") and _due.is_empty() and m.state == DuelScene.State.PRE_PITCH and m._play_time < 0.0:
		m.open_orders()
		_shoot("orders")
	elif _taken.has("orders") and _due.is_empty() and m.orders.visible:
		m.orders.close()
	var playing := m._play_time >= 1.5 and m._play != null and not m._play.foul
	if _taken.has("orders") and playing and not _taken.has("play"):
		_shoot("play")
	return _taken.has("play") and _due.is_empty()


func _shoot(tag: String) -> void:
	_taken[tag] = true
	_due.append(tag)
	print("match_shots: %s  %s  %s" % [tag, _scene.banner, _scene.last_text])
