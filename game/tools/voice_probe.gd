extends SceneTree
## Checks the caster's voice end to end from the game (CasterVoice → the voice server): starts it
## if it is not running (content-local/voice.json), says a few lines, and reports what came back.
##
##   ./dev tool-win voice_probe build/voice/v

var _caster: CasterVoice
var _log: FileAccess


func _note(line: String) -> void:
	print(line)
	if _log != null:
		_log.store_line(line)
		_log.flush()
var _t := 0.0
var _asked := false
var _done := false
var _after := 0.0


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--bare"):
		_done = true
		return
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_log = FileAccess.open(str(args.get("out", "user://voice_probe")) + ".txt", FileAccess.WRITE)
	_note("voice_probe: start")
	_caster = CasterVoice.new()
	root.add_child(_caster)
	_note("voice_probe: url=%s" % _caster.url)


func _process(delta: float) -> bool:
	_t += delta
	if _done:
		_after += delta
		if _after > 0.3:
			_note("voice_probe: quitting")
			_log.close()
			_log = null
			return true
		return false
	if _caster.connected and not _asked and OS.get_cmdline_user_args().has("--ping-only"):
		_note("voice_probe: ping only, quitting")
		_done = true
		return false
	if _caster.connected and not _asked:
		_asked = true
		_note("voice_probe: connected after %.1f s" % _t)
		_caster.say("큽니다, 큽니다, 넘어갑니다!", &"hot")
		_caster.say("김윤민, 좌중간을 가르는 2루타! 4번 타자의 한 방입니다.", &"hot")
	if _asked and _caster._to_play.size() + (1 if _caster._player.playing else 0) >= 1:
		_note("voice_probe: answered, playing=%s queued=%d after %.1f s" % [_caster._player.playing, _caster._to_play.size(), _t])
		_caster._player.stop()
		_caster.queue_free()
		_done = true
		return false
	if _t > 25.0:
		_note("voice_probe: gave up (connected=%s)" % _caster.connected)
		return true
	return false
