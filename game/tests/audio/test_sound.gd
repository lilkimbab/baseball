extends GutTest
## The game's sound: every sound the game asks for exists, the buses
## are there with their effects, the fans' excitement follows the game, the cheering keeps
## to the beat and warms up with the fans, and a game's events make the right sounds.

const MATCH := preload("res://match/match.tscn")
const DT := 1.0 / 120.0


func test_every_sound_asked_for_exists() -> void:
	var names: Array[String] = []
	for tier: int in range(1, 5):
		names.append("sfx/bat_solid_%d" % tier)
	for tier: int in range(1, 4):
		names.append("sfx/bat_jam_%d" % tier)
		names.append("sfx/bat_end_%d" % tier)
		names.append("sfx/mitt_%d" % tier)
	for prefix: String in ["sfx/glove", "sfx/bounce_grass", "sfx/bounce_dirt", "sfx/swing", "sfx/swing_power", "sfx/slide", "sfx/base_tag"]:
		names.append(prefix)
	for prefix: String in names:
		assert_gt(GameAudio.variants(prefix).size(), 0, prefix)
		assert_not_null(GameAudio.pick(prefix, 0.5), prefix)
	for name: String in ["crowd/bed_quiet", "crowd/bed_normal", "crowd/bed_loud", "crowd/cheer", "crowd/cheer_long", "crowd/roar", "crowd/groan", "crowd/groan_big",
			"crowd/clap", "crowd/clap_light", "crowd/rise_2", "crowd/rise_4", "crowd/rise_6", "music/menu", "music/homerun", "music/win", "music/lose", "music/jingle_1", "music/organ_1", "ui/move", "ui/select", "ui/confirm"]:
		assert_not_null(GameAudio.stream(name), name)
	for hit: Array in CheerSequencer.PATTERNS.reduce(func(all: Array, p: Array) -> Array: return all + p, []):
		assert_not_null(GameAudio.stream("cheer/" + str(hit[1])), str(hit[1]))
	var bed := GameAudio.stream("crowd/bed_normal", true) as AudioStreamOggVorbis
	assert_true(bed.loop, "a bed loops")
	assert_false((GameAudio.stream("crowd/cheer") as AudioStreamOggVorbis).loop, "a cheer does not")


func test_the_buses_and_their_effects() -> void:
	GameAudio.ensure_buses()
	for name: String in GameAudio.BUSES:
		assert_gte(AudioServer.get_bus_index(name), 0, name)
	var crowd := AudioServer.get_bus_index("Crowd")
	assert_true(AudioServer.get_bus_effect(crowd, GameAudio.CROWD_REVERB) is AudioEffectReverb)
	GameAudio.muffle_crowd(true)
	assert_true(AudioServer.is_bus_effect_enabled(crowd, GameAudio.CROWD_MUFFLE), "muffled behind a board")
	GameAudio.muffle_crowd(false)
	assert_false(AudioServer.is_bus_effect_enabled(crowd, GameAudio.CROWD_MUFFLE))


func test_the_fans_rise_with_the_moment_and_with_what_happens() -> void:
	var e := Excitement.new()
	var g := GameState.new()
	g.rules = RuleSet.kbo_2026()
	g.teams = [TeamInGame.new(), TeamInGame.new()]
	g.inning = 1
	var calm := e.value(1, g, 0.5)
	g.inning = 8
	g.balls = 3
	g.strikes = 2
	var tense := e.value(1, g, 2.5)
	assert_gt(tense, calm + 0.3, "late, a full count, a big moment")
	e.jolt(&"home_run", GameState.HOME)
	assert_gt(e.value(1, g, 2.5), tense, "the home fans after a home-team home run")
	assert_lt(e.jolt_of(0), 0.0, "the visitors quiet")
	for i: int in 600:
		e.step(1.0 / 60.0)
	assert_lt(e.jolt_of(1), 0.05, "it fades in seconds")
	var w := MatchSound.bed_weights(0.1)
	assert_gt(w[0], 0.9, "a calm crowd: the quiet bed")
	w = MatchSound.bed_weights(0.95)
	assert_gt(w[2], 0.9, "a roaring one: the loud bed")


func test_the_cheering_keeps_to_the_beat_and_warms_up() -> void:
	assert_true(CheerSequencer.choose(0.2, false, false, 0.5) <= 3, "calm patterns for calm fans")
	assert_true(CheerSequencer.choose(0.6, false, false, 0.5) in [4, 5, 6, 7])
	assert_true(CheerSequencer.choose(0.9, false, false, 0.5) in [8, 9])
	assert_eq(CheerSequencer.choose(0.9, true, false, 0.5), 10, "a full count has its own")
	assert_eq(CheerSequencer.choose(0.6, false, true, 0.5), 11, "so do runners in scoring position")
	var seq := CheerSequencer.new()
	seq.pattern = 0
	assert_eq(seq.due(0.0, func() -> int: return 0).size(), 0, "starts listening")
	var hits := PackedStringArray()
	for i: int in 256:
		hits.append_array(seq.due((i + 1) * 0.0625, func() -> int: return 0))
	assert_eq(hits.size(), 8, "pattern 0: four drums a bar, two bars")
	for h: String in hits:
		assert_eq(h, "drum_low")


func test_a_game_makes_the_sounds_of_what_happens() -> void:
	var scene := MATCH.instantiate() as MatchScene
	scene.human_team = -1
	scene.innings = 2
	scene.seed_value = 21
	scene.use_motion = false
	add_child_autofree(scene)
	var sound := scene.sound
	assert_not_null(sound, "every game has its sound")
	for i: int in roundi(240.0 / DT):
		scene.step(DT)
		sound.step(DT)
		if scene.game.over:
			break
	var heard := func(prefix: String) -> int:
		var n := 0
		for k: String in sound.played:
			if k.begins_with(prefix):
				n += sound.played[k]
		return n
	assert_gt(heard.call("sfx/mitt"), 5, "pitches caught")
	assert_gt(heard.call("sfx/bat"), 2, "balls hit")
	assert_gt(heard.call("sfx/glove") + heard.call("sfx/bounce"), 1, "plays in the field")
	assert_gt(heard.call("cheer/"), 10, "the cheering between pitches")
	assert_gt(heard.call("cheer/song_"), 0, "the batters' songs")
	var songs := GameAudio.variants("cheer/song").size()
	assert_eq(songs, 6, "the game's six songs")
	for id: String in ["a", "kbo-123", "career-7"]:
		var n := MatchSound.song_number(id, songs)
		assert_between(n, 1, songs)
		assert_eq(MatchSound.song_number(id, songs), n, "a man's song is always his")
	assert_gt(heard.call("crowd/"), 1, "the crowd's reactions")
	assert_eq(MatchSound.bat_sound(160.0, &"good"), "sfx/bat_solid_4", "crushed on time")
	assert_eq(MatchSound.bat_sound(80.0, &"late"), "sfx/bat_jam_1", "late and weak: jammed")
	assert_eq(MatchSound.bat_sound(140.0, &"early"), "sfx/bat_end_3", "early: off the end")
	assert_eq(MatchSound.mitt_sound(150.0, 0.0), "sfx/mitt_3")
	assert_eq(MatchSound.mitt_sound(120.0, 0.0), "sfx/mitt_1")
