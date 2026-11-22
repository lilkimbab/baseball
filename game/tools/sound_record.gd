extends SceneTree
## Records a game's sound without playing it aloud (docs/11 section 9: the bed, the periodic
## cheering, the bursts at events should show in a spectrogram): the computer plays both
## sides, everything the game would play is mixed (the dummy audio driver) and recorded off
## the Master bus to a WAV, with each second's loudness printed.
##
##   godot --headless --audio-driver Dummy --path game --script res://tools/sound_record.gd -- --out build/sound/game.wav --seconds 60

const MATCH := preload("res://match/match.tscn")

var _scene: MatchScene
var _record: AudioEffectRecord
var _seconds := 60.0
var _out := "res://../build/sound/game.wav"
var _t := 0.0


func _init() -> void:
	var raw := OS.get_cmdline_user_args()
	for i: int in raw.size():
		if raw[i] == "--seconds" and i + 1 < raw.size():
			_seconds = float(raw[i + 1])
		if raw[i] == "--out" and i + 1 < raw.size():
			_out = raw[i + 1]
	GameAudio.ensure_buses()
	_record = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, _record)
	_record.set_recording_active(true)
	_scene = MATCH.instantiate() as MatchScene
	_scene.human_team = -1
	_scene.innings = 9
	_scene.seed_value = 5
	_scene.use_motion = false
	root.add_child(_scene)
	current_scene = _scene


func _process(delta: float) -> bool:
	if _t == 0.0 and _scene.sound != null:
		# Headless, the game keeps quiet; here it is to be heard.
		_scene.sound.audible = true
		for p: AudioStreamPlayer in _scene.sound._beds:
			p.play()
	_t += delta
	if _t < _seconds:
		return false
	_record.set_recording_active(false)
	var rec := _record.get_recording()
	if rec == null:
		print("sound_record: nothing recorded (no audio mixing?)")
		quit(1)
		return true
	var path := _out if _out.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(_out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	rec.save_to_wav(path)
	print("sound_record: %s (%.1f s), heard: %s" % [path, _t, str(_scene.sound.played)])
	quit()
	return true
