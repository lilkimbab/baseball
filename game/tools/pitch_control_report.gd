extends SceneTree
## How near the player's pitches come to where he aims (docs/04 5.2): plays the match scene
## with the player pitching, aims every pitch at a spot, lets go of the accuracy ring a set
## time off its best moment, and prints how far from the spot the ball crossed the plate.
##
##   godot --headless --path game --script res://tools/pitch_control_report.gd -- --pitches 60 --late 0.05

var _scene: MatchScene
var _late := 0.0
var _want := 60
var _spots: Array[Vector2] = [Vector2(0.15, 0.15), Vector2(0.85, 0.85), Vector2(0.5, 0.5), Vector2(0.1, 0.9), Vector2(0.9, 0.1)]
var _n := 0
var _aimed := Vector3.ZERO
var _misses := PackedFloat32Array()
var _quality := PackedFloat32Array()
var _by_type := {}
var _was_live := false
var _held := 0.0


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_late = float(str(args.get("late", "0")))
	_want = int(str(args.get("pitches", "60")))
	_scene = (load("res://match/match.tscn") as PackedScene).instantiate() as MatchScene
	_scene.human_team = 1
	_scene.innings = 9
	_scene.use_motion = false
	_scene.seed_value = int(str(args.get("seed", "7")))
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	for i: int in 40:
		_tick()
		if _misses.size() >= _want or _scene.game.over:
			_report()
			return true
	return false


func _tick() -> void:
	var dt := 1.0 / 120.0
	if _scene.human_pitches():
		match _scene.state:
			DuelScene.State.PRE_PITCH:
				if _scene.state_time > 0.3:
					var spot := _spots[_n % _spots.size()]
					_scene.selected_pitch = _n % maxi(_scene.pitch_ids.size(), 1)
					_scene.target = _scene.duel.zone.point(spot.x, spot.y)
					_aimed = _scene.target
					_scene.press_pitch_button()
			DuelScene.State.CHARGE:
				if _scene.ring >= DuelScene.ACCURACY_SWEET + _late / DuelScene.GAUGE_TIME:
					_scene.release_pitch_button()
	var live := _scene.state == DuelScene.State.LIVE and _scene.duel.phase == PitchDuel.Phase.FLIGHT
	if live and not _was_live and _scene.human_pitches():
		var at := _scene.duel.pitch.plate_pos
		var miss := Vector2(at.x - _aimed.x, at.z - _aimed.z).length()
		_misses.append(miss)
		_quality.append(_scene.decision.quality)
		var id := str(_scene.decision.type.id)
		var so_far: PackedFloat32Array = _by_type.get(id, PackedFloat32Array())
		so_far.append(miss)
		_by_type[id] = so_far
		_n += 1
	_was_live = live
	_scene.step(dt)


func _report() -> void:
	var total := 0.0
	var worst := 0.0
	var q := 0.0
	var in_10 := 0
	for i: int in _misses.size():
		total += _misses[i]
		worst = maxf(worst, _misses[i])
		q += _quality[i]
		in_10 += 1 if _misses[i] < 0.10 else 0
	var n := maxi(_misses.size(), 1)
	print("control: late %.3f s  pitches %d  ring quality %.2f  mean miss %.1f cm  worst %.1f cm  within 10 cm %d%%  command %.0f" % [_late, _misses.size(), q / n, total / n * 100.0, worst * 100.0, in_10 * 100 / n, _scene.settings.command])
	for id: String in _by_type:
		var a: PackedFloat32Array = _by_type[id]
		var s := 0.0
		for v: float in a:
			s += v
		print("control:   %s  %d pitches  mean miss %.1f cm" % [id, a.size(), s / a.size() * 100.0])
	quit(0)
