class_name MatchSound
extends Node3D
## The sound of a game (docs/11, docs/13 S15), from what the scene shows — it hooks nothing,
## it watches: the bat when the ball is hit (its tier from the exit speed, solid, jammed or
## off the end from the swing's timing), the mitt when a pitch is caught (sharper the faster
## it came), a glove on each catch of a play, a tag, a slide, a bounce; the crowd's bed
## swelling and falling with the fans' excitement (Excitement), its cheers and groans as
## things go one way or the other, the rise as a big fly hangs; the batting side's cheering
## on the beat the visible crowd moves to (CheerSequencer); an organ between batters,
## a jingle between halves, a fanfare for a home-team home run; the umpire's calls and the
## announcer by the system's Korean voice when there is one. Nothing plays while the game is
## being simulated without a screen.

## Pitch speeds (km/h) where the mitt's pop gets sharper.
const MITT_TIERS := Vector2(130.0, 145.0)
## Exit speeds (km/h) of the bat's four tiers.
const BAT_TIERS: Array[float] = [95.0, 130.0, 155.0]
## A fly the crowd rises with: this launch angle and exit speed and up.
const RISE_LAUNCH := 18.0
const RISE_SPEED := 140.0
## Chances of an organ riff between batters.
const ORGAN_CHANCE := 0.25
const SFX_PLAYERS := 10
const CROWD_PLAYERS := 4
const CHEER_PLAYERS := 6

var scene: DuelScene
var excitement := Excitement.new()
var cheers := CheerSequencer.new()
## Off in tests and in simulations: nothing is played (the logic still runs).
var audible := true

var _beds: Array[AudioStreamPlayer] = []
var _crowd: Array[AudioStreamPlayer] = []
var _cheer: Array[AudioStreamPlayer3D] = []
var _sfx: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _chant: AudioStreamPlayer3D
var _rng := Rng.new(77)
var _duel: PitchDuel
var _contact_heard := false
var _arrival_heard := false
var _swing_heard := false
var _rise_heard := false
var _play_t := -1.0
var _ball_z := 0.0
var _ball_vz := 0.0
var _snapshot := {}
var _voice := ""
## Its own beat clock, for when the visible crowd's is not running (no screen).
var _beat := 0.0
var _muffled := false
## What was played (name → times), for tests.
var played: Dictionary[String, int] = {}


func _ready() -> void:
	GameAudio.ensure_buses()
	audible = DisplayServer.get_name() != "headless"
	for name: String in ["crowd/bed_quiet", "crowd/bed_normal", "crowd/bed_loud"]:
		var p := AudioStreamPlayer.new()
		p.bus = &"Crowd"
		p.stream = GameAudio.stream(name, true)
		p.volume_db = -80.0
		add_child(p)
		_beds.append(p)
	for i: int in CROWD_PLAYERS:
		var p := AudioStreamPlayer.new()
		p.bus = &"Crowd"
		add_child(p)
		_crowd.append(p)
	for i: int in CHEER_PLAYERS:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"Crowd"
		p.unit_size = 40.0
		p.max_distance = 600.0
		add_child(p)
		_cheer.append(p)
	for i: int in SFX_PLAYERS:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.unit_size = 12.0
		p.max_distance = 300.0
		add_child(p)
		_sfx.append(p)
	for i: int in 3:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_flat.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	add_child(_music)
	_chant = AudioStreamPlayer3D.new()
	_chant.bus = &"Crowd"
	_chant.unit_size = 40.0
	_chant.max_distance = 600.0
	add_child(_chant)
	if audible:
		for p: AudioStreamPlayer in _beds:
			p.play()
	if audible:
		_preload()
	if Settings.voices and audible:
		var voices := DisplayServer.tts_get_voices_for_language("ko")
		_voice = voices[0] if not voices.is_empty() else ""


func _process(delta: float) -> void:
	if scene == null or scene.duel == null:
		return
	step(delta)


## One frame of listening (tests call it with the scene driven by hand).
func step(delta: float) -> void:
	var m := scene as MatchScene
	if m != null and m.crowd != null:
		excitement.fill = m.crowd.fill
	excitement.step(delta)
	_beat += delta * Crowd.BEATS_PER_SECOND
	_listen_pitch()
	_listen_play()
	var game := _game()
	if game != null:
		_listen_game(game)
		_mix_crowd(game)
		_cheering(game)


func _game() -> GameState:
	var m := scene as MatchScene
	return m.game if m != null else null


## Every sound a game may play, loaded now (a file first opened mid-game is a hitch).
func _preload() -> void:
	var prefixes: Array[String] = ["sfx/glove", "sfx/base_tag", "sfx/slide", "sfx/bounce_grass", "sfx/bounce_dirt", "sfx/swing", "sfx/swing_power"]
	for tier: int in range(1, 5):
		prefixes.append("sfx/bat_solid_%d" % tier)
	for tier: int in range(1, 4):
		prefixes.append("sfx/bat_jam_%d" % tier)
		prefixes.append("sfx/bat_end_%d" % tier)
		prefixes.append("sfx/mitt_%d" % tier)
	for prefix: String in prefixes:
		for name: String in GameAudio.variants(prefix):
			GameAudio.stream(name)
	for name: String in ["crowd/cheer", "crowd/cheer_long", "crowd/roar", "crowd/groan", "crowd/groan_big", "crowd/clap", "crowd/clap_light", "crowd/rise_2", "crowd/rise_4", "crowd/rise_6",
			"cheer/drum_low", "cheer/drum_high", "cheer/sticks", "cheer/whistle", "cheer/hey", "cheer/oh", "music/homerun", "music/win", "music/lose", "music/jingle_1", "music/jingle_2", "music/jingle_3",
			"music/organ_1", "music/organ_2", "music/organ_3", "music/organ_4", "music/organ_5", "music/organ_6"]:
		GameAudio.stream(name)


# --- Bat and mitt ---


func _listen_pitch() -> void:
	var d := scene.duel
	if d != _duel:
		_duel = d
		_contact_heard = false
		_arrival_heard = false
		_swing_heard = false
		_rise_heard = false
	if d.swing != null and not _swing_heard and d.time >= d.swing.contact_time - 0.06 and d.phase != PitchDuel.Phase.READY:
		_swing_heard = true
		if d.contact == null or not d.contact.made_contact:
			_play_at("sfx/swing_power" if d.swing.kind == SwingAttempt.Kind.POWER else "sfx/swing", _plate())
	if d.contact != null and d.contact.made_contact and not _contact_heard:
		_contact_heard = true
		_play_flat(bat_sound(d.contact.exit_speed_kmh(), d.swing.judgment if d.swing != null else &"good"), 0.0)
		var big := d.contact.launch_deg() >= RISE_LAUNCH and d.contact.exit_speed_kmh() >= RISE_SPEED and absf(d.contact.spray_deg()) <= 45.0
		if big and not _rise_heard:
			_rise_heard = true
			var hang := 2.0 * d.contact.velocity.z / 9.81
			_crowd_one("crowd/rise_%d" % (2 if hang < 3.0 else (4 if hang < 5.0 else 6)), -2.0)
	elif not _arrival_heard and not _contact_heard and d.result in [PitchDuel.Result.BALL, PitchDuel.Result.CALLED_STRIKE, PitchDuel.Result.SWINGING_STRIKE, PitchDuel.Result.FOUL_TIP]:
		_arrival_heard = true
		var speed := d.pitch.plate_speed_kmh() if d.pitch != null else 140.0
		_play_flat(mitt_sound(speed, _rng.next_float()), -2.0)
		if d.result == PitchDuel.Result.CALLED_STRIKE:
			_say("스트라이크" if scene.strikes < 2 else "스트라이크 아웃")


## The bat's sound for a contact: its tier by the exit speed, its kind by the timing (on time
## solid; early off the end; late jammed).
static func bat_sound(exit_kmh: float, judgment: StringName) -> String:
	var tier := 1
	for edge: float in BAT_TIERS:
		if exit_kmh >= edge:
			tier += 1
	match judgment:
		&"early":
			return "sfx/bat_end_%d" % mini(tier, 3)
		&"late":
			return "sfx/bat_jam_%d" % mini(tier, 3)
	return "sfx/bat_solid_%d" % tier


static func mitt_sound(speed_kmh: float, _roll: float) -> String:
	var tier := 1 if speed_kmh < MITT_TIERS.x else (2 if speed_kmh < MITT_TIERS.y else 3)
	return "sfx/mitt_%d" % tier


func _plate() -> Vector3:
	return Field.to_world(Vector3(0.0, 0.0, 1.0))


# --- A play ---


func _listen_play() -> void:
	var m := scene as MatchScene
	if m == null or m._play == null or m._play_time < 0.0:
		_play_t = -1.0
		return
	var t := m._play_time
	if _play_t < 0.0 or t < _play_t:
		_play_t = t
		_ball_z = m.ball_position(t).z
		_ball_vz = 0.0
		return
	var dt := t - _play_t
	if m._moves != null:
		for key: String in m._moves.by_key:
			for moment: PlayMoves.Moment in m._moves.by_key[key]:
				if moment.time <= _play_t or moment.time > t:
					continue
				match moment.kind:
					PlayMoves.Kind.CATCH:
						_play_at("sfx/glove", Field.to_world(moment.at))
					PlayMoves.Kind.TAG:
						_play_at("sfx/base_tag", Field.to_world(moment.at))
					PlayMoves.Kind.SLIDE:
						_play_at("sfx/slide", Field.to_world(moment.at))
	for c: PlayCall in m._play.calls:
		if c.time > _play_t and c.time <= t and c.margin < PlayOverlay.CLOSE:
			_say("아웃" if c.out else "세이프")
	# A bounce: the ball coming down turns up near the ground.
	if dt > 0.0:
		var ball := m.ball_position(t)
		var vz := (ball.z - _ball_z) / dt
		if _ball_vz < -2.0 and vz >= 0.0 and ball.z < 0.4:
			var ground := "dirt" if Vector2(ball.x, ball.y).length() < 29.0 and Vector2(ball.x, ball.y).length() > 17.0 or Vector2(ball.x, ball.y).length() < 4.0 else "grass"
			_play_at("sfx/bounce_" + ground, Field.to_world(ball))
		_ball_z = ball.z
		_ball_vz = vz
	_play_t = t


# --- The game: the crowd's reactions, jingles ---


## What changed since the last frame, and how the crowd takes it.
func _listen_game(g: GameState) -> void:
	var now := {"score0": g.score[0], "score1": g.score[1], "outs": g.outs, "inning": g.inning, "top": g.top, "over": g.over, "batter": g.batter_id()}
	var m := scene as MatchScene
	var hits := [m.scorer.book.hits[0], m.scorer.book.hits[1]] if m != null and m.scorer != null else [0, 0]
	now["hits0"] = hits[0]
	now["hits1"] = hits[1]
	if _snapshot.is_empty():
		_snapshot = now
		return
	var before := _snapshot
	_snapshot = now
	var batting := g.batting()
	if bool(now["over"]) and not bool(before["over"]):
		var mine := m.human_team if m != null else -1
		var happy := g.winner == (mine if mine >= 0 else 1)
		_music_one("music/win" if happy else "music/lose")
		return
	if int(now["inning"]) != int(before["inning"]) or bool(now["top"]) != bool(before["top"]):
		_music_one("music/jingle_%d" % (1 + _rng.next_int(3)))
		cheers.reset()
		return
	var side_scored := -1
	for t: int in 2:
		if int(now["score%d" % t]) > int(before["score%d" % t]):
			side_scored = t
	var home_run := scene.duel.result == PitchDuel.Result.HOME_RUN
	if side_scored >= 0:
		excitement.jolt(&"home_run" if home_run else &"run", side_scored)
		_react(side_scored, "crowd/roar" if home_run else "crowd/cheer_long", "crowd/groan_big" if home_run else "crowd/groan")
		if home_run and side_scored == GameState.HOME:
			_music_one("music/homerun", 0.6)
		return
	for t: int in 2:
		if int(now["hits%d" % t]) > int(before["hits%d" % t]):
			excitement.jolt(&"hit", t)
			_react(t, "crowd/cheer", "crowd/groan")
			return
	if int(now["outs"]) > int(before["outs"]) or (int(now["outs"]) < int(before["outs"]) and bool(now["top"]) == bool(before["top"])):
		var strikeout := scene.duel.result in [PitchDuel.Result.CALLED_STRIKE, PitchDuel.Result.SWINGING_STRIKE, PitchDuel.Result.FOUL_TIP]
		var fielding := 1 - batting
		excitement.jolt(&"strikeout" if strikeout else &"out", fielding)
		if strikeout:
			_react(fielding, "crowd/clap", "")
		elif fielding == GameState.HOME:
			_crowd_one("crowd/clap_light", -6.0)
		return
	if str(now["batter"]) != str(before["batter"]):
		# A new batter: the announcer, and now and then the organ.
		var batter := g.batting_team().player(g.batter_id())
		if batter != null:
			var slot := g.batting_team().slot_of(batter.id)
			var pos := g.batting_team().lineup[slot].position if slot >= 0 else Position.Kind.DH
			_say("%d번 타자, %s, %s" % [slot + 1, Position.name_of(pos), batter.name])
		# A home batter's own walk-up song from the local pack; otherwise now and then the organ.
		var walk_up := GameAudio.local("players/" + g.batter_id()) if audible and batting == GameState.HOME else null
		if walk_up != null:
			_count("walk_up")
			_music.stream = walk_up
			_music.volume_db = -4.0
			_music.play()
		elif _rng.chance(ORGAN_CHANCE):
			_music_one("music/organ_%d" % (1 + _rng.next_int(6)), 0.0, -6.0)


## A reaction: `good` heard from the fans of `side`, `bad` from the others; louder from the
## home fans (there are more of them).
func _react(side: int, good: String, bad: String) -> void:
	var home_fans_happy := side == GameState.HOME
	if good != "":
		_crowd_one(good, 0.0 if home_fans_happy else -7.0)
	if bad != "" and excitement.value(1 - side, _game(), _leverage()) > 0.3:
		_crowd_one(bad, 0.0 if not home_fans_happy else -7.0)


func _leverage() -> float:
	var mm := scene as ManagerMatch
	return mm.leverage if mm != null else 1.0


# --- The crowd's bed and the cheering ---


## The beds' volumes from the fans' excitement (the louder side counts), the whole by how full
## the park is.
func _mix_crowd(g: GameState) -> void:
	var e := maxf(excitement.value(0, g, _leverage()), excitement.value(1, g, _leverage()))
	var weights := bed_weights(e)
	var full := 0.45 + 0.55 * excitement.fill
	for i: int in 3:
		var db := linear_to_db(maxf(weights[i] * full, 0.0001))
		# Only a real change goes to the audio thread.
		if absf(_beds[i].volume_db - db) > 0.25:
			_beds[i].volume_db = db
	var m := scene as MatchScene
	var muffled := m != null and (m.pause_menu != null and m.pause_menu.visible or (m is ManagerMatch and (m as ManagerMatch).board_visible()))
	if muffled != _muffled:
		_muffled = muffled
		GameAudio.muffle_crowd(muffled)


## How much of each bed (quiet, normal, loud) for an excitement.
static func bed_weights(e: float) -> PackedFloat32Array:
	var loud := smoothstep(0.5, 0.85, e)
	var quiet := 1.0 - smoothstep(0.15, 0.5, e)
	var normal := clampf(1.0 - loud - quiet, 0.0, 1.0)
	return PackedFloat32Array([quiet, normal, loud])


## The batting side's drums and calls between pitches, on the visible crowd's beat.
func _cheering(g: GameState) -> void:
	var m := scene as MatchScene
	if m == null or m.crowd == null or g.over:
		return
	var waiting := scene.state == DuelScene.State.PRE_PITCH or scene.state == DuelScene.State.CHARGE
	if not waiting or m._play_time >= 0.0:
		cheers.reset()
		if _chant != null and _chant.playing:
			_chant.stop()
		return
	var side := g.batting()
	# A club's own chant from the local content pack goes instead of the drums.
	var chant := GameAudio.local("chants/" + g.teams[side].team_id, true) if audible else null
	if chant != null:
		if _chant.stream != chant or not _chant.playing:
			_chant.stream = chant
			var bag := PlaySim.base_xy(1 if side == GameState.HOME else 3)
			_chant.global_position = Field.to_world(Vector3(bag.x * 2.2, bag.y * 2.2, 8.0))
			_chant.play()
		return
	var e := excitement.value(side, g, _leverage())
	var full := g.balls == 3 and g.strikes == 2
	var risp := not g.base_empty(2) or not g.base_empty(3)
	var beat := m.crowd.beat() if m.crowd.beat() > 0.0 else _beat
	for sound: String in cheers.due(beat, func() -> int: return CheerSequencer.choose(e, full, risp, _rng.next_float())):
		_cheer_hit("cheer/" + sound, side, -3.0 + 6.0 * e)


func _cheer_hit(name: String, side: int, gain_db: float) -> void:
	_count(name)
	if not audible:
		return
	var p := _free3d(_cheer)
	p.stream = GameAudio.stream(name)
	# The home cheering section is on the first-base side (KBO), the visitors' on the third.
	var bag := PlaySim.base_xy(1 if side == GameState.HOME else 3)
	p.global_position = Field.to_world(Vector3(bag.x * 2.2, bag.y * 2.2, 8.0))
	p.volume_db = gain_db - (0.0 if side == GameState.HOME else 5.0)
	p.play()


# --- Players ---


func _count(name: String) -> void:
	played[name] = int(played.get(name, 0)) + 1


func _play_at(prefix: String, at: Vector3, gain_db: float = 0.0) -> void:
	_count(prefix)
	if not audible:
		return
	var s := GameAudio.pick(prefix, _rng.next_float())
	if s == null:
		return
	var p := _free3d(_sfx)
	p.stream = s
	p.global_position = at
	p.volume_db = gain_db
	p.pitch_scale = 1.0 + (_rng.next_float() - 0.5) * 0.06
	p.play()


func _play_flat(prefix: String, gain_db: float) -> void:
	_count(prefix)
	if not audible:
		return
	var s := GameAudio.pick(prefix, _rng.next_float())
	if s == null:
		return
	var p := _flat[0]
	for q: AudioStreamPlayer in _flat:
		if not q.playing:
			p = q
			break
	p.stream = s
	p.volume_db = gain_db
	p.play()


func _crowd_one(name: String, gain_db: float) -> void:
	_count(name)
	if not audible:
		return
	var s := GameAudio.stream(name)
	if s == null:
		return
	var p := _crowd[0]
	for q: AudioStreamPlayer in _crowd:
		if not q.playing:
			p = q
			break
	p.stream = s
	p.volume_db = gain_db
	p.play()


func _music_one(name: String, delay: float = 0.0, gain_db: float = -3.0) -> void:
	_count(name)
	if not audible:
		return
	var s := GameAudio.stream(name)
	if s == null:
		return
	_music.stream = s
	_music.volume_db = gain_db
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(_music.play)
	else:
		_music.play()


func _free3d(pool: Array[AudioStreamPlayer3D]) -> AudioStreamPlayer3D:
	for p: AudioStreamPlayer3D in pool:
		if not p.playing:
			return p
	return pool[0]


## The umpire or the announcer, by the system's Korean voice (none: nothing).
func _say(line: String) -> void:
	_count("voice:" + line)
	if not audible or _voice == "" or not Settings.voices:
		return
	DisplayServer.tts_speak(line, _voice, int(clampf(Settings.voice_volume * Settings.volume, 0.0, 1.0) * 100.0), 1.0, 1.05, 0, true)
