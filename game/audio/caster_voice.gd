class_name CasterVoice
extends Node
## The play-by-play caster's voice (the user, 2026-11-23: "a man's voice with the tension of a
## real KBO broadcast", the M3 voice): each line is sent to the voice server on this machine
## (tools/audio/voice_server.py: Supertonic 3, numbers read as a broadcast reads them, lifted by
## the moment) and its answer played in turn on the Voice bus. Where the server is and how to
## start it come from the local content pack's voice.json:
##
##   {"url": "http://127.0.0.1:8765", "start": [<a command that starts it, detached>]}
##
## The asking is done on a worker thread with the system's curl (curl.exe on Windows), each
## answer saved to a file and loaded here: the game opens no connection of its own (one held
## open kept the program from closing on Windows). Without the file, or with the server not
## answering, nothing is said: the lines stay on screen as they were. A short queue; a stale
## line is dropped for a newer one.

const CONFIG := "voice.json"
const MAX_WAITING := 2
## Seconds to wait for a server just started.
const START_WAIT := 40.0

var url := ""
## The server answered (lines are sent).
var connected := false
## What was asked (for tests): [text, mood].
var asked: Array = []
var _start: Array = []
var _player: AudioStreamPlayer
var _thread: Thread
var _mutex := Mutex.new()
var _signal := Semaphore.new()
var _waiting: Array = []
var _quit := false
var _to_play: Array[AudioStream] = []
var _dir := ""
var _count := 0


func _ready() -> void:
	var path := MotionLibrary.pack_root().path_join(CONFIG)
	if not FileAccess.file_exists(path) or DisplayServer.get_name() == "headless":
		return
	var cfg := JsonIO.read_object(path)
	url = str(cfg.get("url", "")).trim_suffix("/")
	_start = cfg.get("start", []) as Array
	if url == "":
		return
	_dir = OS.get_user_data_dir().path_join("caster")
	DirAccess.make_dir_recursive_absolute(_dir)
	_player = AudioStreamPlayer.new()
	_player.bus = &"Voice"
	_player.finished.connect(_play_next)
	add_child(_player)
	_thread = Thread.new()
	_thread.start(_work)


## Says a line ("hot" for a home run or a long hit, "warm" for a strikeout or a double play
## out of a jam, "calm" otherwise).
func say(text: String, mood: StringName = &"calm") -> void:
	asked.append([text, mood])
	if url == "" or _thread == null or text.strip_edges() == "":
		return
	_mutex.lock()
	_waiting.append([text, String(mood)])
	while _waiting.size() > MAX_WAITING:
		_waiting.pop_front()
	_mutex.unlock()
	_signal.post()


func _exit_tree() -> void:
	if _thread != null:
		_mutex.lock()
		_quit = true
		_waiting.clear()
		_mutex.unlock()
		_signal.post()
		_thread.wait_to_finish()
		_thread = null


# --- The worker thread ---


func _curl() -> String:
	return "curl.exe" if OS.get_name() == "Windows" else "curl"


func _ping() -> bool:
	var out: Array = []
	return OS.execute(_curl(), ["-s", "-m", "2", url + "/ping"], out) == 0 and not out.is_empty() and str(out[0]).strip_edges() == "ok"


func _work() -> void:
	# Is it there? If not, start it and wait for it.
	var up := _ping()
	if not up and not _start.is_empty():
		OS.create_process(str(_start[0]), PackedStringArray(_start.slice(1)))
		var waited := 0.0
		while not up and waited < START_WAIT and not _quitting():
			OS.delay_msec(1000)
			waited += 1.0
			up = _ping()
	if not up:
		return
	set_deferred("connected", true)
	while true:
		_signal.wait()
		if _quitting():
			return
		_mutex.lock()
		var item: Array = _waiting.pop_front() if not _waiting.is_empty() else []
		_mutex.unlock()
		if item.is_empty():
			continue
		_count += 1
		var file := _dir.path_join("line_%d.ogg" % (_count % 8))
		var code := OS.execute(_curl(), ["-s", "-f", "-m", "15", "-o", file, "%s/say?mood=%s&text=%s" % [url, item[1], str(item[0]).uri_encode()]])
		if code == 0 and not _quitting():
			_loaded.call_deferred(file)


func _quitting() -> bool:
	_mutex.lock()
	var q := _quit
	_mutex.unlock()
	return q


# --- Back on the main thread ---


func _loaded(file: String) -> void:
	var stream := AudioStreamOggVorbis.load_from_file(file)
	if stream == null:
		return
	_to_play.append(stream)
	if not _player.playing:
		_play_next()


func _play_next() -> void:
	if _to_play.is_empty():
		return
	_player.stream = _to_play.pop_front()
	_player.play()
