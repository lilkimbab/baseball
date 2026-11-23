extends SceneTree
## Plays a game with the person at bat and photographs one thing closely, for checking it:
##
##   ./dev tool-win scene_probe build/probe/trot --what trot [--hbp] [--mine]
##       the walk to first after four balls (the bat is left on the shoulder until one comes):
##       a frame every quarter second of the scene and of the dissolve after it; with --hbp
##       the first one is shown as a pitch that hit him.
##   ./dev tool-win scene_probe build/probe/hr --what hr
##       the person bats, swinging hard at strikes, until a home run: frames every 0.4 s of its
##       trot (the close camera beside him, the fist at home).
##   ./dev tool-win scene_probe build/probe/stage --what stage
##       the broadcast's look at the cheering stages (home, then away: the cheerleaders and
##       the fans behind them) and at the scoreboard introducing the batter: a frame every
##       0.7 s of each.
##   ./dev tool-win scene_probe build/probe/catch --what catch [--pitches 3]
##       the person pitching (the pitching camera): frames around each pitch's arrival in
##       the catcher's mitt, every 1/30 s from 0.15 s before to 0.4 s after.
##   ./dev tool-win scene_probe build/probe/swing --what swing [--high | --low] [--pitches 3]
##       swings aimed away from the pitch (high and inside, or low and away): frames through
##       each swing, to see that the bat goes where the pointer is.

var _scene: MatchScene
var _prefix := "user://probe"
var _what := "trot"
var _args: Dictionary = {}
var _frames := 0
var _due: Array[String] = []
var _clock := 0.0
var _shots := 0
var _after := -1.0
var _pitches := 0
var _want := 3
var _swung := false
var _last_state := -1


func _initialize() -> void:
	_args = CmdArgs.parse(OS.get_cmdline_user_args())
	_prefix = _args.get("out", _prefix)
	_what = str(_args.get("what", "trot"))
	_want = int(str(_args.get("pitches", "3")))
	Profile.tool_run()
	_scene = (load("res://match/match.tscn") as PackedScene).instantiate() as MatchScene
	# Catching: the person's side is in the field first (the top of the first).
	_scene.human_team = 1 if _what == "catch" else 0
	_scene.innings = 9
	_scene.seed_value = int(str(_args.get("seed", "31")))
	root.add_child(_scene)


func _process(delta: float) -> bool:
	_frames += 1
	for name: String in _due:
		root.get_texture().get_image().save_png("%s_%s.png" % [_prefix, name])
	_due.clear()
	if _frames > (160000 if _what == "hr" else 40000):
		print("scene_probe: gave up")
		return true
	if _what == "stage":
		return _stage_frames(delta)
	if _scene.broadcast.current != null and _scene.broadcast.holding():
		_scene.broadcast.skip()
	var duel := _scene.duel
	if _what == "trot":
		# --mine: the computer pitches wide to the person's batter, who takes four balls.
		if _args.has("mine") and _scene.human_bats() and _scene.state == DuelScene.State.WINDUP and _scene.decision != null:
			_scene.decision.target = Vector3(0.75, Field.PLATE_FRONT_Y, 0.4)
		var on: bool = _scene.state == DuelScene.State.RESULT and _scene._trot != ""
		# --mine: only the person's own batter's walk (the view from behind the plate).
		if on and _args.has("mine") and _scene.game.batting() != _scene.human_team and _shots == 0:
			on = false
		Engine.time_scale = 1.0 if (on or _after >= 0.0) else 4.0
		if on and _after < 0.0 and _shots == 0 and _args.has("hbp"):
			_scene._trot = "hbp"
		if on:
			_clock += delta
			if _clock >= 0.25 or _shots == 0:
				_clock = 0.0
				_due.append("%02d" % _shots)
				_shots += 1
		elif _shots > 0:
			# The dissolve into the next plate appearance.
			if _after < 0.0:
				_after = 0.0
				_due.append("%02d_after" % _shots)
			_after += delta
			if _after > 0.2 and _after - delta <= 0.2:
				_due.append("%02d_after2" % _shots)
			if _after > 0.8:
				_due.append("%02d_after3" % _shots)
				print("scene_probe: trot, %d frames" % _shots)
				_what = "done"
		return false
	if _what == "done":
		return _due.is_empty()
	if _what == "catch":
		return _catch_frames(delta)
	if _what == "hr":
		return _hr_frames(delta)
	# Swings aimed away from the pitch.
	if not _scene.human_bats():
		Engine.time_scale = 4.0
		return false
	Engine.time_scale = 1.0
	var zone := duel.zone
	var spot := Vector3(-zone.half_width * 0.8, Field.PLATE_FRONT_Y, zone.top - 0.05)
	if _args.has("low"):
		spot = Vector3(zone.half_width * 0.8, Field.PLATE_FRONT_Y, zone.bottom + 0.05)
	_scene.pointer_override = _scene.camera.unproject_position(Field.to_world(spot))
	if _scene.state == DuelScene.State.LIVE and duel.pitch != null and duel.phase == PitchDuel.Phase.FLIGHT:
		var lead := SwingModel.swing_time(SwingAttempt.Kind.CONTACT)
		if not _swung and duel.time >= duel.ideal_contact_time - lead:
			_scene.swing(SwingAttempt.Kind.CONTACT)
			_swung = true
			print("scene_probe: swing %d aim=(%.2f, %.2f) pitch=(%.2f, %.2f)" % [_pitches, spot.x, spot.z, duel.pitch.plate_pos.x, duel.pitch.plate_pos.z])
		if _swung and duel.time >= duel.ideal_contact_time - 0.02 and _shots == _pitches:
			_due.append("swing%d_contact" % _pitches)
			_shots += 1
	var s := int(_scene.state)
	if s != _last_state:
		if _scene.state == DuelScene.State.RESULT:
			_pitches += 1
			_swung = false
		_last_state = s
	return _pitches >= _want and _due.is_empty()


var _arrived := -1.0


func _catch_frames(delta: float) -> bool:
	if not _scene.human_pitches():
		Engine.time_scale = 4.0
		return false
	Engine.time_scale = 0.25
	var duel := _scene.duel
	match _scene.state:
		DuelScene.State.PRE_PITCH:
			if _scene.state_time > 0.4:
				# Just off the plate (the batter takes it and the catcher has it), now high, now low.
				var zone := duel.zone
				_scene.target = Vector3(zone.half_width + 0.12, Field.PLATE_FRONT_Y, zone.bottom + 0.15 if _pitches % 2 == 0 else zone.top - 0.1)
				_scene.press_pitch_button()
		DuelScene.State.CHARGE:
			if _scene.ring >= _scene.sweet - 0.02:
				_scene.release_pitch_button()
	var live := _scene.state == DuelScene.State.LIVE and duel.phase == PitchDuel.Phase.FLIGHT
	if live:
		var left := (duel.ball.pos.y - PitchDuel.CATCH_Y) / maxf(-duel.ball.vel.y, 1.0)
		if left < 0.15 and _arrived < 0.0:
			_arrived = 0.0
			_clock = 1.0
	if _arrived >= 0.0:
		_arrived += delta * Engine.time_scale
		_clock += delta * Engine.time_scale
		if _clock >= 1.0 / 30.0:
			_clock = 0.0
			_due.append("p%d_%02d" % [_pitches, _shots])
			_shots += 1
		if _arrived > 0.55:
			_arrived = -1.0
			_shots = 0
			var hit := duel.contact != null and duel.contact.made_contact
			print("scene_probe: catch %d%s" % [_pitches, " (hit: taken again)" if hit else ""])
			if not hit:
				_pitches += 1
	return _pitches >= _want and _due.is_empty()


func _hr_frames(delta: float) -> bool:
	if not _scene.human_bats() and _scene._play_time < 0.0:
		Engine.time_scale = 6.0
		return false
	var duel := _scene.duel
	if _scene.hr_trot_on():
		Engine.time_scale = 1.0
		_clock += delta
		if _clock >= 0.4 or _shots == 0:
			_clock = 0.0
			_due.append("%02d" % _shots)
			_shots += 1
		return false
	if _shots > 0:
		print("scene_probe: home run trot, %d frames" % _shots)
		_what = "done"
		return false
	Engine.time_scale = 4.0
	# (A slugger for the picture: a home run comes sooner.)
	_scene.settings.power = 99.0
	_scene.settings.contact = 99.0
	duel.probe_launch = Vector3(47.0, 29.0, 6.0)
	if _scene.state == DuelScene.State.LIVE and duel.pitch != null and duel.phase == PitchDuel.Phase.FLIGHT and not _swung:
		var at := duel.pitch.plate_pos
		_scene.pointer_override = _scene.camera.unproject_position(Field.to_world(Vector3(at.x, Field.PLATE_FRONT_Y, at.z)))
		if duel.zone.contains(at.x, at.z) and duel.time >= duel.ideal_contact_time - SwingModel.swing_time(SwingAttempt.Kind.POWER):
			_scene.swing(SwingAttempt.Kind.POWER)
			_swung = true
	if _scene.state != DuelScene.State.LIVE:
		_swung = false
	return false


var _stage_step := 0


func _stage_frames(delta: float) -> bool:
	Engine.time_scale = 1.0
	var b := _scene.broadcast
	if _stage_step == 0:
		# Past the introduction, to the first pitch; then the shots, one after another.
		if b.current != null:
			b.skip_all()
			return false
		if _scene.state != DuelScene.State.PRE_PITCH:
			return false
		_stage_step = 1
		for side: int in [GameState.HOME, GameState.AWAY]:
			var fans := Broadcast.segment(Broadcast.Kind.FANS)
			fans.shots = [_scene.stage_shot(side)]
			b.push(fans)
		var board := Broadcast.segment(Broadcast.Kind.BOARD)
		board.shots = [_scene.board_shot()]
		b.push(board)
		if _args.has("rush"):
			# --rush: a walk-off's mob and the benches clearing (planned when each starts).
			b.queue.clear()
			var mob := Broadcast.segment(Broadcast.Kind.WALK_OFF)
			mob.shots = [Broadcast.Shot.make(0.0, Vector3(9.0, -5.0, 2.6), Vector3(0.0, 0.8, 1.1), 36.0, Vector3(7.0, -4.0, 2.2), Vector3(0.0, 0.8, 1.2), 30.0)]
			_scene._plan_walk_off(_scene.game.teams[GameState.HOME].batter_at(0))
			b.current = null
			b.push(mob)
		_clock = 0.0
		return false
	if b.current == null:
		if _args.has("rush") and _stage_step == 1:
			_stage_step = 2
			_scene._plan_bench_clear()
			var clear := Broadcast.segment(Broadcast.Kind.BENCH_CLEAR)
			clear.shots = _scene.bench_clear_shots()
			b.push(clear)
			return false
		if _args.has("rush") and _stage_step == 2:
			_stage_step = 3
			var hurt := _scene.game.batter_id()
			_scene._plan_injury(hurt, _scene.game.batting())
			var help := Broadcast.segment(Broadcast.Kind.INJURY)
			help.shots = _scene.injury_shots()
			b.push(help)
			return false
		print("scene_probe: stage, %d frames" % _shots)
		_what = "done"
		return false
	_clock += delta
	if _clock >= 0.7 or _shots == 0:
		_clock = 0.0
		_due.append("%02d_%s" % [_shots, str(Broadcast.Kind.keys()[b.current.kind]).to_lower()])
		_shots += 1
	return false
