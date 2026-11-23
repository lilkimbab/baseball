class_name GameAudio
extends RefCounted
## The game's sound (docs/11, docs/13 S15): the buses — Music, Crowd, SFX, Voice and UI under
## the Master — their volumes from the settings, and the sounds by name. The sounds are the
## game's own (tools/audio/make_sounds.py, in audio/); one with the same name in the local
## content pack (content-local/audio/<name>.ogg: real chants, walk-up songs, menu music) is
## played instead.
##
## Crowd has a stadium's reverb, and a low-pass that muffles it while the game waits on a
## board or a menu. Voice has a short slap echo, as a public-address system has.

const BUSES: Array[String] = ["Music", "Crowd", "SFX", "Voice", "UI"]
## The Crowd bus's effects, by index.
const CROWD_REVERB := 0
const CROWD_MUFFLE := 1

static var _streams: Dictionary[String, AudioStream] = {}
static var _variants: Dictionary[String, PackedStringArray] = {}


## Makes the buses once (a layout from code: nothing to keep in step with a .tres).
static func ensure_buses() -> void:
	if AudioServer.get_bus_index("Crowd") >= 0:
		return
	for name: String in BUSES:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, &"Master")
	var crowd := AudioServer.get_bus_index("Crowd")
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.75
	reverb.damping = 0.55
	reverb.spread = 1.0
	reverb.wet = 0.14
	reverb.dry = 1.0
	AudioServer.add_bus_effect(crowd, reverb, CROWD_REVERB)
	var muffle := AudioEffectLowPassFilter.new()
	muffle.cutoff_hz = 900.0
	AudioServer.add_bus_effect(crowd, muffle, CROWD_MUFFLE)
	AudioServer.set_bus_effect_enabled(crowd, CROWD_MUFFLE, false)
	var voice := AudioServer.get_bus_index("Voice")
	var echo := AudioEffectDelay.new()
	echo.dry = 1.0
	echo.tap1_active = true
	echo.tap1_delay_ms = 160.0
	echo.tap1_level_db = -10.0
	echo.tap2_active = true
	echo.tap2_delay_ms = 330.0
	echo.tap2_level_db = -16.0
	echo.feedback_active = false
	AudioServer.add_bus_effect(voice, echo, 0)
	apply_volumes()


## The settings' volumes on the buses (0 silences one).
static func apply_volumes() -> void:
	_set_volume("Master", Settings.volume)
	_set_volume("Music", Settings.music_volume)
	_set_volume("Crowd", Settings.crowd_volume)
	_set_volume("SFX", Settings.sfx_volume)
	_set_volume("Voice", Settings.voice_volume)
	_set_volume("UI", Settings.sfx_volume)


static func _set_volume(bus: String, level: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, level <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(level, 0.001)))


## The crowd heard through a wall (a board, a menu over the game) or as it is.
static func muffle_crowd(on: bool) -> void:
	var i := AudioServer.get_bus_index("Crowd")
	if i >= 0:
		AudioServer.set_bus_effect_enabled(i, CROWD_MUFFLE, on)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(Settings.crowd_volume, 0.001)) - (8.0 if on else 0.0))


## A sound by name ("sfx/mitt_2_1"): the local pack's if there is one, else the game's; null
## if neither. `loop` for a bed or a pattern that repeats.
static func stream(name: String, loop: bool = false) -> AudioStream:
	var key := name + (":loop" if loop else "")
	if _streams.has(key):
		return _streams[key]
	var s: AudioStreamOggVorbis = null
	var local := MotionLibrary.pack_root().path_join("audio").path_join(name + ".ogg")
	if FileAccess.file_exists(local):
		s = AudioStreamOggVorbis.load_from_file(local)
	if s == null:
		var path := "res://audio/%s.ogg" % name
		if ResourceLoader.exists(path):
			s = (load(path) as AudioStreamOggVorbis)
			if s != null and loop:
				s = s.duplicate() as AudioStreamOggVorbis
	if s != null:
		s.loop = loop
	_streams[key] = s
	return s


## A sound only the local content pack has (a club's chant, a player's walk-up song), or null.
static func local(name: String, loop: bool = false) -> AudioStream:
	var key := "local:" + name + (":loop" if loop else "")
	if _streams.has(key):
		return _streams[key]
	var path := MotionLibrary.pack_root().path_join("audio").path_join(name + ".ogg")
	var s: AudioStreamOggVorbis = AudioStreamOggVorbis.load_from_file(path) if FileAccess.file_exists(path) else null
	if s != null:
		s.loop = loop
	_streams[key] = s
	return s


## The names of a sound's variants ("sfx/glove" → sfx/glove_1, _2, _3), found once.
static func variants(prefix: String) -> PackedStringArray:
	if _variants.has(prefix):
		return _variants[prefix]
	var out := PackedStringArray()
	# The game's own takes and those the local pack adds (real recordings may have more).
	var local := MotionLibrary.pack_root().path_join("audio")
	for i: int in range(1, 10):
		var name := "%s_%d" % [prefix, i]
		if ResourceLoader.exists("res://audio/%s.ogg" % name) or FileAccess.file_exists(local.path_join(name + ".ogg")):
			out.append(name)
		else:
			break
	if out.is_empty() and ResourceLoader.exists("res://audio/%s.ogg" % prefix):
		out.append(prefix)
	_variants[prefix] = out
	return out


## One of a sound's variants, picked with `roll` (0..1).
static func pick(prefix: String, roll: float) -> AudioStream:
	var names := variants(prefix)
	if names.is_empty():
		return null
	return stream(names[clampi(int(roll * names.size()), 0, names.size() - 1)])


static var _ui: Array[AudioStreamPlayer] = []
static var _ui_next := 0


## A menu sound ("ui/move", "ui/select"): from a small pool kept in the root, so it is not
## cut off when the screen it came from goes away.
static func ui(tree: SceneTree, name: String) -> void:
	if tree == null or DisplayServer.get_name() == "headless":
		return
	ensure_buses()
	if _ui.is_empty() or not is_instance_valid(_ui[0]):
		_ui.clear()
		for i: int in 3:
			var p := AudioStreamPlayer.new()
			p.bus = &"UI"
			tree.root.add_child.call_deferred(p)
			_ui.append(p)
		return
	var p := _ui[_ui_next % _ui.size()]
	_ui_next += 1
	if not p.is_inside_tree():
		return
	p.stream = stream(name)
	p.play()
