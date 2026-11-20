extends SceneTree
## Plays a short scripted demonstration for recording: the player bats at a few pitches, then
## throws a few. Run it in Godot's movie mode to get a video ("./dev video" does this):
##
##   godot --path game --write-movie demo.avi --script res://tools/demo_reel.gd -- --bat 2 --pitch 2
##
## Options: --bat <pitches to bat at, default 2>  --pitch <pitches to throw, default 2>  --seed <n>

## What to throw in pitching mode: index into the pitch list, and where to aim as a fraction
## of the strike zone's half width (toward first base) and half height (up).
const PLAN: Array[Array] = [[0, Vector2(-0.45, 0.4)], [2, Vector2(0.6, -0.55)], [3, Vector2(0.1, -0.7)], [4, Vector2(-0.5, -0.4)]]

var _scene: DuelScene
var _bat := 2
var _pitch := 2
var _done := 0
var _swung := false
var _last_state: DuelScene.State = DuelScene.State.PRE_PITCH
var _tail := 0.0


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_bat = int(str(args.get("bat", "2")))
	_pitch = int(str(args.get("pitch", "2")))
	_scene = (load("res://match/duel.tscn") as PackedScene).instantiate() as DuelScene
	_scene.mode = &"bat" if _bat > 0 else &"pitch"
	_scene.seed_value = int(str(args.get("seed", "20261120")))
	root.add_child(_scene)


func _process(delta: float) -> bool:
	var state := _scene.state
	var duel := _scene.duel
	if state != _last_state:
		if state == DuelScene.State.RESULT:
			print("demo_reel: %s  %s" % [_scene.mode, _scene.banner])
		elif state == DuelScene.State.PRE_PITCH and _last_state == DuelScene.State.RESULT:
			_done += 1
			_swung = false
			if _done == _bat and _pitch > 0:
				_scene.set_mode(&"pitch")
		_last_state = state
	if _done >= _bat + _pitch:
		_tail += delta
		return _tail > 0.4

	if _scene.human_bats():
		# Swing for power, timed to meet the ball.
		if state == DuelScene.State.LIVE and not _swung and duel.time >= duel.ideal_contact_time - SwingModel.swing_time(SwingAttempt.Kind.POWER):
			_scene.swing(SwingAttempt.Kind.POWER)
			_swung = true
	elif _scene.human_pitches():
		var choice: Array = PLAN[(_done - _bat) % PLAN.size()]
		if state == DuelScene.State.PRE_PITCH:
			# Pick the pitch, move the pointer to the spot, then run the gauge.
			_scene.selected_pitch = choice[0]
			_point_at(choice[1])
			if _scene.state_time > 1.0:
				_scene.press_pitch_button()
		elif state == DuelScene.State.CHARGE and _scene.power > 0.92:
			_scene.release_pitch_button()
		elif state == DuelScene.State.ACCURACY and _scene.ring >= DuelScene.ACCURACY_SWEET - 0.02:
			_scene.press_pitch_button()
	return false


## Moves the mouse pointer to a spot in the strike zone, as a player would to aim a pitch.
func _point_at(spot: Vector2) -> void:
	var zone := _scene.duel.zone
	var middle := (zone.top + zone.bottom) * 0.5
	var at := Vector3(zone.half_width * spot.x, Field.PLATE_FRONT_Y, middle + (zone.top - middle) * spot.y)
	_scene.pointer_override = _scene.camera.unproject_position(Field.to_world(at))
