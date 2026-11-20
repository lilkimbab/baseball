extends SceneTree
## Plays the duel scene with scripted input and saves screenshots at chosen moments, so the
## stage can be checked without a person at the controls.
##
##   godot --path game --script res://tools/duel_shots.gd -- --out build/duel --mode watch
##
## Options: --out <path prefix>  --mode bat|pitch|watch  --pitches <n, default 2>  --seed <n>
##          --every <seconds>  also save a frame at this interval, to look at how a whole
##          pitch plays out;  --noswing  leave the bat on the shoulder in batting mode

var _scene: DuelScene
var _prefix := "user://duel"
var _pitches := 2
var _seen := 0
var _last_state: DuelScene.State = DuelScene.State.PRE_PITCH
var _shots: Array[String] = []
var _swung := false
var _frames := 0
var _in_play_shot := false
## Shots to save on the next frame. The picture read back is the last one drawn, which is
## from before this frame's game step, so a moment is photographed one frame after it is seen.
var _due: Array[String] = []
var _every := 0.0
var _clock := 0.0
var _strip := 0
var _swing_allowed := true


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_prefix = args.get("out", _prefix)
	_pitches = int(str(args.get("pitches", "2")))
	_every = float(str(args.get("every", "0")))
	_swing_allowed = not args.has("noswing")
	var packed := load("res://match/duel.tscn") as PackedScene
	_scene = packed.instantiate() as DuelScene
	_scene.mode = StringName(str(args.get("mode", "watch")))
	_scene.seed_value = int(str(args.get("seed", "20261120")))
	root.add_child(_scene)


func _process(delta: float) -> bool:
	_frames += 1
	for name: String in _due:
		_save(name)
	_due.clear()
	if _every > 0.0:
		_clock += delta
		if _clock >= _every:
			_clock -= _every
			_due.append("strip_%03d" % _strip)
			_strip += 1
	if _frames > 4000:
		print("duel_shots: gave up after %d frames" % _frames)
		return true
	var state := _scene.state
	var duel := _scene.duel

	# Scripted player input.
	if _scene.human_pitches():
		if state == DuelScene.State.PRE_PITCH and _scene.state_time > 0.6:
			_scene.press_pitch_button()
		elif state == DuelScene.State.CHARGE and _scene.power > 0.9:
			_scene.release_pitch_button()
		elif state == DuelScene.State.ACCURACY and _scene.ring >= DuelScene.ACCURACY_SWEET - 0.03:
			_scene.press_pitch_button()
	if _scene.human_bats() and _swing_allowed and state == DuelScene.State.LIVE and not _swung:
		if duel.time >= duel.ideal_contact_time - SwingModel.swing_time(SwingAttempt.Kind.POWER):
			_scene.swing(SwingAttempt.Kind.POWER)
			_swung = true

	# Captures.
	if state != _last_state:
		if state == DuelScene.State.CHARGE or state == DuelScene.State.ACCURACY:
			pass
		elif state == DuelScene.State.RESULT:
			_shoot("result")
			_seen += 1
			_swung = false
			_in_play_shot = false
		_last_state = state
	if state == DuelScene.State.ACCURACY and _scene.ring > 0.4 and not _has("gauge"):
		_shoot("gauge")
	if state == DuelScene.State.WINDUP and _scene.state_time > _scene.release_time() * 0.62 and not _has("windup"):
		_shoot("windup")
	if state == DuelScene.State.WINDUP and _scene.state_time > _scene.release_time() - 0.05 and not _has("layback"):
		_shoot("layback")
	if state == DuelScene.State.LIVE and duel.phase == PitchDuel.Phase.FLIGHT and duel.time > 0.02 and not _has("release"):
		_shoot("release")
	if state == DuelScene.State.LIVE and duel.phase == PitchDuel.Phase.FLIGHT and duel.time > duel.pitch.flight_time * 0.55 and not _has("flight"):
		_shoot("flight")
	if state == DuelScene.State.LIVE and duel.swing != null and duel.swing.resolved and not _has("swing"):
		_shoot("swing")
	if state == DuelScene.State.LIVE and duel.phase == PitchDuel.Phase.IN_PLAY and _scene.state_time > 1.6 and not _in_play_shot:
		_in_play_shot = true
		_shoot("inplay")
	return _seen >= _pitches and _due.is_empty()


func _has(tag: String) -> bool:
	for name: String in _shots:
		if name.begins_with("%d_%s" % [_seen, tag]):
			return true
	return false


func _shoot(tag: String) -> void:
	var name := "%d_%s" % [_seen, tag]
	_shots.append(name)
	_due.append(name)
	var duel := _scene.duel
	print("duel_shots: %s  state=%d result=%d t=%.2f banner=%s" % [name, _scene.state, duel.result, duel.time, _scene.banner])


func _save(name: String) -> void:
	root.get_texture().get_image().save_png("%s_%s.png" % [_prefix, name])
