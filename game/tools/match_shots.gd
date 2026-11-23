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
##          a ball in play shown from the summary)  --moves: a close camera on each catch,
##          throw and slide in the plays (docs/13 S12)  --running: the same for steals and
##          pickoffs only, fast-forwarding to them  --fielding: the player's team in the
##          field (pitches scripted), the throw gauge held during a ball in play
##          --manual: the player's own fielder run at the ball (docs/05 2.3)  --highlight:
##          the player at bat (swings scripted), the slow-motion moments photographed; with
##          --force every fly and every first catch is made one, to see the cameras

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
var _moves := false
var _running_only := false
var _fielding := false
var _manual := false
var _highlight := false
var _bullpen := false
var _force := false
var _swung := false
var _play_seen: PlayResult
var _rng := Rng.new(5)
var _close: Camera3D
var _shot_moves := {}
var _broadcast := false
var _segment_seen: Broadcast.Segment


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
	_moves = args.has("moves") or args.has("running")
	_running_only = args.has("running")
	if _moves:
		Engine.time_scale = 1.0
		_close = Camera3D.new()
		_close.fov = 38.0
		root.add_child.call_deferred(_close)
	_fielding = args.has("fielding")
	_manual = args.has("manual")
	_highlight = args.has("highlight")
	_bullpen = args.has("bullpen")
	if _bullpen:
		Engine.time_scale = 1.0
		_close = Camera3D.new()
		_close.fov = 40.0
		root.add_child.call_deferred(_close)
	_force = args.has("force")
	if _manual or _highlight:
		Engine.time_scale = 1.0
	Settings.manual_fielding = _manual
	# --broadcast: the broadcast's moments (introduction, inning cards, batter cards, a pitching
	# change, a replay); the other shots are taken without them.
	_broadcast = args.has("broadcast")
	Settings.ensure_loaded()
	Settings.broadcast = _broadcast
	if _broadcast:
		Engine.time_scale = 1.0
	_scene.human_team = 0 if _highlight else (1 if _menus or _fielding or _manual else -1)
	_scene.manual_always = _manual
	_scene.innings = 3
	_scene.seed_value = int(str(args.get("seed", "20261121")))
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	for name: String in _due:
		root.get_texture().get_image().save_png("%s_%s.png" % [_prefix, name])
	_due.clear()
	if _frames > (200000 if _to_end or _running_only or _highlight else 20000):
		print("match_shots: gave up after %d frames" % _frames)
		return true
	if _broadcast:
		return _broadcast_shots()
	if _menus:
		return _menu_shots()
	if _fielding:
		return _fielding_shots()
	if _manual:
		return _manual_shots()
	if _bullpen:
		return _bullpen_shots()
	if _highlight:
		return _highlight_shots()
	if _manager:
		return _manager_shots()
	if _to_end:
		if _scene.game.over and not _taken.has("postgame"):
			if _scene.profile_lines.is_empty():
				_scene.profile_lines = PackedStringArray(["승리 +195P  (올스타 ×1.3)", "목표 달성: 안타 3개 +40P", "업적: 첫 홈런 +100P", "레벨 업! Lv.4  +120P"])
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
	if _running_only:
		playing = playing and _scene._running
		Engine.time_scale = 1.0 if playing else 8.0
	if _moves:
		_close_up(playing)
	elif playing:
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


## Cuts to a close camera on whoever is catching, throwing or sliding, a moment into it.
func _close_up(playing: bool) -> void:
	if not playing or _scene._moves == null:
		if _close.current:
			_scene.camera.make_current()
		return
	var tl := _scene._play.timeline
	var t := _scene._play_time
	for key: String in _scene._moves.by_key:
		for m: PlayMoves.Moment in _scene._moves.by_key[key]:
			var at := m.time + (0.0 if m.kind == PlayMoves.Kind.CATCH else 0.12)
			var tag := "%d_%s_%s_%.1f" % [_seen, key.replace(":", ""), PlayMoves.Kind.keys()[m.kind], m.time]
			if m.kind == PlayMoves.Kind.SLIDE:
				at = m.time + 0.25
			if t >= at and t < at + 0.2 and not _shot_moves.has(tag):
				_shot_moves[tag] = true
				var who := tl.position(key, t)
				var spot := Field.to_world(Vector3(who.x, who.y, 0.0))
				var side := Field.to_world(Vector3(who.x, who.y, 0.0) + Vector3(who.y, -who.x, 0.0).normalized() * 4.0)
				_close.look_at_from_position(side + Vector3.UP * 1.4, spot + Vector3.UP * 0.8)
				_close.make_current()
				_shoot(tag)
				return


## Pitches for the player; in the first ball in play holds → (first base), photographs the
## gauge, lets go in the green, and photographs the throw.
func _fielding_shots() -> bool:
	if _scene.human_pitches():
		match _scene.state:
			DuelScene.State.PRE_PITCH:
				if _scene.state_time > 0.3:
					_scene.target = _scene.duel.zone.point(_rng.next_range(-0.1, 1.1), _rng.next_range(-0.1, 1.1))
					_scene.press_pitch_button()
			DuelScene.State.CHARGE:
				if _scene.ring >= _scene.sweet - 0.02:
					_scene.release_pitch_button()
	if _scene.choice_open() and _scene._controls_fielding():
		if _scene.charge() < 0.0 and not _taken.has("gauge"):
			_scene.choice_key(KEY_RIGHT, true)
		elif _scene.charge() > 0.55 and not _taken.has("gauge"):
			_shoot("gauge")
		elif _scene.charge() > 0.85 and _taken.has("gauge"):
			_scene.choice_key(KEY_RIGHT, false)
	if _taken.has("gauge") and not _taken.has("throw") and not _scene.choice_open() and _scene._play_time > 0.0:
		for m: PlayMoves.Moment in _scene._moves.by_key.values().reduce(func(acc: Array, a: Array) -> Array: return acc + a, []):
			if m.kind == PlayMoves.Kind.THROW and _scene._play_time > m.time + 0.3:
				_shoot("throw")
				break
	if _taken.has("throw") and _scene._play_time < 0.0 and not _taken.has("after"):
		_shoot("after")
	return _taken.has("after") and _due.is_empty()


## --bullpen: two men warming on each side, photographed from beside each bullpen's mound.
func _bullpen_shots() -> bool:
	var g := _scene.game
	if _frames == 30:
		for t: int in 2:
			var team := g.teams[t]
			g.set_warming(t, PackedStringArray(team.bullpen.slice(0, 2)))
	for side: int in [1, -1]:
		var tag := "bullpen_%s" % ("right" if side == 1 else "left")
		var at := 90 if side == 1 else 150
		if _frames == at - 20:
			for spot: Array in _scene.park.bullpen_spots:
				if float(spot[0]) == float(side) and int(spot[1]) == 0:
					var centre: Vector2 = spot[2]
					var facing: float = spot[3]
					var forward := Vector2(sin(facing), cos(facing))
					var beside := Vector2(forward.y, -forward.x) * 7.0 * side
					var eye := Field.to_world(Vector3(centre.x + beside.x + forward.x * 4.0, centre.y + beside.y + forward.y * 4.0, 2.4))
					_close.look_at_from_position(eye, Field.to_world(Vector3(centre.x + forward.x * 1.5, centre.y + forward.y * 1.5, 1.2)))
					_close.make_current()
		if _frames == at:
			_shoot(tag)
	return _frames > 160 and _due.is_empty()


func _pitch_for_the_player() -> void:
	if not _scene.human_pitches():
		return
	match _scene.state:
		DuelScene.State.PRE_PITCH:
			if _scene.state_time > 0.3:
				_scene.target = _scene.duel.zone.point(_rng.next_range(0.1, 0.9), _rng.next_range(0.1, 0.9))
				_scene.press_pitch_button()
		DuelScene.State.CHARGE:
			if _scene.ring >= _scene.sweet - 0.02:
				_scene.release_pitch_button()


## The player's own fielder run at where the ball is going: photographed on the way, with the
## ball in his glove, and when the throw is on its way.
func _manual_shots() -> bool:
	_pitch_for_the_player()
	var playing := _scene._play_time >= 0.0 and _scene._play != null
	Engine.time_scale = 1.0 if playing else 6.0
	_scene.manual_push = Vector2.ZERO
	var own := _scene.manual_fielder()
	if own != null:
		var t := _scene._play_time
		if _scene.manual_chasing():
			# The catch key when the prompt shows, as a player would.
			if own.catch_soon(t, _scene.duel.path) and not own.glove_up(t):
				if not _taken.has("%d_prompt" % _seen):
					_shoot("%d_prompt" % _seen)
				own.press_catch(t + 0.1)
			var going := _scene.duel.path.position_at(t + 0.35)
			if _scene.landing_known and t < _scene.landing_time:
				going = _scene.landing_point
			var to := Vector2(going.x, going.y) - own.pos
			if to.length() > 0.3:
				_scene.manual_push = to.normalized()
		for at: float in [0.5, 1.2, 2.2]:
			var tag := "%d_chase_%.1f" % [_seen, at]
			if t >= at and not own.got and not _taken.has(tag):
				_shoot(tag)
		if own.got and not _taken.has("%d_got" % _seen):
			_shoot("%d_got" % _seen)
	elif playing and _taken.has("%d_got" % _seen) and not _taken.has("%d_thrown" % _seen):
		for m: PlayMoves.Moment in _scene._moves.by_key.values().reduce(func(acc: Array, a: Array) -> Array: return acc + a, []):
			if m.kind == PlayMoves.Kind.THROW and _scene._play_time > m.time + 0.25:
				_shoot("%d_thrown" % _seen)
				break
	if _was_playing and not playing:
		_seen += 1
	_was_playing = playing
	return _seen >= _plays and _due.is_empty()


## The player at bat: every slow-motion moment photographed as it starts, in its middle and
## as it ends.
func _highlight_shots() -> bool:
	_pitch_for_the_player()
	# The bat aimed where the pitch arrives (the real pointer is wherever the mouse is).
	if _scene.human_bats() and _scene.state == DuelScene.State.LIVE and _scene.duel.pitch != null:
		_scene.pointer_override = _scene.camera.unproject_position(Field.to_world(_scene.duel.pitch.plate_pos))
	if _scene.human_bats() and _scene.state == DuelScene.State.LIVE and _scene.duel.phase == PitchDuel.Phase.FLIGHT and not _swung:
		var at := _scene.duel.pitch.plate_pos
		if _scene.duel.zone.contains(at.x, at.z) and _scene.duel.time >= _scene.duel.ideal_contact_time - SwingModel.swing_time(SwingAttempt.Kind.POWER):
			_scene.swing(SwingAttempt.Kind.POWER)
			_swung = true
	if _scene.state != DuelScene.State.LIVE:
		_swung = false
	var playing := _scene._play_time >= 0.0 and _scene._play != null and not _scene._play.foul
	if playing and _scene._play != _play_seen:
		_play_seen = _scene._play
		if _force and _scene._highlights.is_empty() and _scene._controls_running():
			_force_highlights()
	var h := _scene.highlight()
	# (At its own speed while a pitch is on its way, so that a play is seen from its first
	# tick: the highlights are forced before anything of it is shown.)
	Engine.time_scale = 1.0 if h != null or _scene.state == DuelScene.State.LIVE else 6.0
	if h != null:
		var kind: String = PlayHighlight.Kind.keys()[h.kind]
		var t := _scene._play_time
		var marks := {"a": h.from - 0.02, "b": lerpf(h.from, h.until, 0.45), "c": h.until - 0.02, "d": h.until + 0.12}
		if h.kind == PlayHighlight.Kind.CONTACT:
			marks = {"a": 0.0, "b": 0.03, "c": 0.09, "d": h.until}
		for mark: String in marks:
			var tag := "%d_%s_%s" % [_seen, kind, mark]
			if t >= float(marks[mark]) and not _taken.has(tag):
				_shoot(tag)
				print("match_shots: %s at %.2f pace %.2f  eye %s target %s batter %s ball %s" % [tag, t, _scene._pace, Field.to_field(_scene.camera.global_position), _scene._follow_target, Field.to_field(_scene.batter.global_position), _scene.shown_ball(t)])
				break
	if _was_playing and not playing:
		if not _taken.keys().filter(func(k: String) -> bool: return k.begins_with("%d_" % _seen)).is_empty():
			_seen += 1
	_was_playing = playing
	return _seen >= _plays and _due.is_empty()


func _force_highlights() -> void:
	var play := _scene._play
	var found: Array[PlayHighlight] = []
	if _scene.duel.contact != null and _scene.duel.contact.launch_deg() > 15.0:
		var c := PlayHighlight.new()
		c.kind = PlayHighlight.Kind.CONTACT
		c.until = PlayHighlight.CONTACT_SPAN
		c.pace = PlayHighlight.CONTACT_PACE
		c.freeze = PlayHighlight.CONTACT_FREEZE
		found.append(c)
		_scene._freeze = c.freeze
	var kind := _scene.chasing_fielder()
	var key := "F:%s" % Position.code(kind)
	var when := play.hard_time if play.has_hard_chance() else -1.0
	var where := play.hard_at
	if play.has_hard_chance():
		key = "F:%s" % Position.code(play.hard_fielder)
	else:
		for m: PlayMoves.Moment in _scene._moves.by_key.get(key, []):
			if m.kind == PlayMoves.Kind.CATCH and when < 0.0:
				when = m.time
				where = m.at
	if when > 1.0:
		var h := PlayHighlight.new()
		h.kind = PlayHighlight.Kind.CHANCE
		h.from = when - PlayHighlight.CHANCE_BEFORE
		h.until = when + PlayHighlight.CHANCE_AFTER
		h.pace = PlayHighlight.CHANCE_PACE
		h.at = where
		h.key = key
		found.append(h)
	_scene._highlights = found


func _shoot(tag: String) -> void:
	_taken[tag] = true
	_due.append(tag)
	print("match_shots: %s  %s  %s" % [tag, _scene.banner, _scene.last_text])


## Each kind of broadcast moment once, a moment into it; the game hurried between them.
func _broadcast_shots() -> bool:
	var b := _scene.broadcast
	var c := b.current
	if c != null:
		Engine.time_scale = 1.0
		var names := {Broadcast.Kind.PREGAME: "pregame", Broadcast.Kind.HALF: "half", Broadcast.Kind.BATTER: "batter", Broadcast.Kind.PITCHER_CHANGE: "pitcher", Broadcast.Kind.REPLAY: "replay", Broadcast.Kind.GAME_END: "end"}
		var name: String = names[c.kind]
		if c.kind == Broadcast.Kind.PREGAME:
			# The match-up, the starter, each club's line-up building on the field (and done).
			for at: float in [2.5, 6.2, 9.4, 13.8, 19.5]:
				var tag := "pregame_%.0f" % at
				if b.time >= at and not _taken.has(tag):
					_shoot(tag)
		elif c.kind == Broadcast.Kind.REPLAY:
			var tag := "replay_%s" % str(c.data.get("kind", "home_run"))
			if b.time >= 1.6 and not _taken.has(tag):
				_shoot(tag)
		elif b.time >= minf(1.2, c.duration * 0.5) and not _taken.has(name):
			_shoot(name)
	else:
		Engine.time_scale = 6.0
	var done := 0
	for n: String in ["pregame_9", "half", "batter", "replay_home_run", "end"]:
		if _taken.has(n):
			done += 1
	if _scene.game.over and _scene.broadcast.current == null and _taken.has("end"):
		if not _taken.has("postgame"):
			# (A tool's game pays nothing: sample lines, to see the earnings laid out.)
			if _scene.profile_lines.is_empty():
				_scene.profile_lines = PackedStringArray(["승리 +195P  (올스타 ×1.3)", "목표 달성: 안타 3개 +40P", "업적: 첫 홈런 +100P", "레벨 업! Lv.4  +120P"])
			_shoot("postgame")
		return _due.is_empty()
	return false
