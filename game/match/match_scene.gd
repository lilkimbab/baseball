class_name MatchScene
extends DuelScene
## Stage S5: a whole game (docs/13 S5-10). Each pitch is played out as in the duel, by the
## player or the computer; a ball in play is run by PlaySim and shown from its key frames;
## GameFlow and the Scorer keep the game. The player controls one team: he bats when it bats
## and pitches when it fields. Fielding and running are automatic for now (the throw and
## running controls of docs/05 2.3-2.4 come with stage S12's fielding motion).

## Seconds a finished play stays on screen before the result is applied.
const PLAY_TAIL := 0.9
## Pause between half-innings.
const TRANSITION := 2.0
## Puppet speed (m/s) above which the run cycle plays.
const RUN_POSE_SPEED := 0.8
const ROSTER_PACK := "res://data/rosters/fiction-2026.json"

@export var innings := 3
## Which team the player controls: 0 away, 1 home, -1 watch.
@export var human_team := 1
## Clubs from the roster pack (their order in it).
@export var away_index := 0
@export var home_index := 1

var game: GameState
var resolver: PhysicalResolver
var scorer: Scorer
var manager: AiManager
var match_hud: MatchHud
var menu: SubstitutionPanel
## One line per event, for the play-by-play panel.
var log := PackedStringArray()
var last_text := ""

var fielders: Dictionary[Position.Kind, Puppet] = {}
var runner_puppets: Array[Puppet] = []
var base_umpires: Array[Puppet] = []
var coaches: Array[Puppet] = []
var on_deck: Puppet

var _clubs: Array[Team] = []
var _styles: Array[UniformStyle] = []
var _chosen_team := 1
var _arsenal: Array[AiPitcher.Option] = []
var _play: PlayResult
var _play_time := -1.0
var _pending: Array[GameEvent] = []
## Who was on each base when the play started (their tracks are keyed by id).
var _runners_at_start: Array[String] = ["", "", ""]
var _batter_at_start := ""
var _between := 0.0
var _half_key := ""
var _phase := 0.0
## Where a right-handed batter stands in the box (field coordinates).
var _box := Vector3(-1.05, 0.25, 0.0)


func _ready() -> void:
	_read_arguments()
	_start_game()
	super._ready()
	_box = Field.to_field(batter.position)
	_box.x = -absf(_box.x)
	_build_officials()
	_half_key = _half_name()
	_dress_for_half()
	var layer := hud.get_parent()
	match_hud = MatchHud.new()
	match_hud.scene = self
	layer.add_child(match_hud)
	menu = SubstitutionPanel.new()
	menu.scene = self
	layer.add_child(menu)
	_drain()
	_new_duel()
	_place_cast()
	_sync_mode()


## Command-line choices: -- --innings 3|6|9 --team home|away|watch --seed n
func _read_arguments() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	if args.has("innings"):
		innings = int(str(args["innings"]))
	if args.has("team"):
		human_team = {"away": 0, "home": 1, "watch": -1}.get(str(args["team"]), human_team)
	if args.has("seed"):
		seed_value = int(str(args["seed"]))


func _start_game() -> void:
	var catalog_all := PitchCatalogIO.load_default()
	var env := LeagueEnvIO.load_default()
	var ovr := LeagueEnvIO.load_overall()
	_clubs = RosterIO.load_pack(ROSTER_PACK)
	var away := _clubs[clampi(away_index, 0, _clubs.size() - 1)]
	var home := _clubs[clampi(home_index, 0, _clubs.size() - 1)]
	var rules := RuleSet.kbo_2026() if innings >= 9 else RuleSet.short_game(innings)
	manager = AiManager.new(env, catalog_all, ovr)
	game = GameState.new()
	game.rules = rules
	game.teams = [manager.make_lineup(away, rules, away.next_starter().id), manager.make_lineup(home, rules, home.next_starter().id)]
	resolver = PhysicalResolver.new(env, catalog_all, manager, Rng.new(seed_value).fork(5))
	scorer = Scorer.new()
	GameFlow.start(game)
	scorer.start(game)
	manager.start_game(game)
	_chosen_team = human_team if human_team >= 0 else 1
	balls = 0
	strikes = 0


# --- Who does what ---


func human_bats() -> bool:
	return game != null and human_team >= 0 and game.batting() == human_team and not game.over


func human_pitches() -> bool:
	return game != null and human_team >= 0 and game.fielding() == human_team and not game.over


func set_mode(new_mode: StringName) -> void:
	# F3 toggles watching; the player's side is fixed for the game.
	if new_mode == &"watch":
		human_team = -1 if human_team >= 0 else _chosen_team
		_sync_mode()
		_snap_camera()


func help_keys() -> String:
	return "Space 번트   F 작전·교체   F3 관전   Esc 종료"


func selected_type() -> PitchType:
	if _arsenal.is_empty():
		return super.selected_type()
	return _arsenal[clampi(selected_pitch, 0, _arsenal.size() - 1)].type


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_SPACE:
		bunt()
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F:
		toggle_menu()


## Opens or closes the manager's menu. It opens only between pitches; the game waits.
func toggle_menu() -> void:
	if menu.visible:
		menu.close()
		return
	if state == State.PRE_PITCH and _play_time < 0.0 and not game.over:
		menu.open()


## A substitution the player chose in the menu.
func substitute(event: GameEvent) -> void:
	_apply(event)
	_dress_for_half()
	_new_duel()
	_place_cast()


## Squares to bunt at the pitch on its way (the player's Space key, docs/05 2.2).
func bunt() -> void:
	if not human_bats() or state != State.LIVE or duel.phase != PitchDuel.Phase.FLIGHT:
		return
	if duel.swing_at(duel.ideal_contact_time, SwingAttempt.Kind.BUNT, Vector2(aim_point.x, aim_point.z), true):
		duel.swing.bunt_angle = 20.0 if aim_point.x > 0.0 else -20.0
		_begin_swing_pose()


# --- The pitch, through the resolver ---


func _new_duel() -> void:
	if game == null:
		return
	_pitch_count += 1
	var release_point := settings.release_point
	duel = resolver.new_duel(game)
	duel.settings.release_point = release_point
	settings = duel.settings
	_pitch_clock = -1.0
	_swing_clock = -1.0
	_load_started = false
	_swing_shown = false
	var pitcher_player := game.fielding_team().player(game.pitcher_id())
	_arsenal = AiPitcher.options_for(pitcher_player, catalog)
	pitch_ids.clear()
	for o: AiPitcher.Option in _arsenal:
		pitch_ids.append(o.type.id)
	selected_pitch = clampi(selected_pitch, 0, maxi(pitch_ids.size() - 1, 0))
	target = duel.zone.center()
	aim_point = duel.zone.center()


func _ai_pitch_decision() -> PitchDecision:
	return resolver.tire(game, resolver.controllers[game.fielding()].choose_pitch(game, duel))


func _ai_react() -> void:
	if resolver.is_bunting():
		AiBatter.bunt(duel, _ai_rng)
	else:
		resolver.controllers[game.batting()].react(game, duel)


func _finish_on_contact() -> bool:
	return true


func _finish_pitch() -> void:
	if swing_motion != null:
		swing_motion.relax()
	resolver.last_play = null
	var events := resolver.after_pitch(game, duel)
	var play := resolver.last_play
	banner = _pitch_banner(events)
	if play != null and play.infield_fly:
		# The umpire declares it while the ball is in the air.
		banner = "인필드 플라이"
	banner_time = 2.4
	if play != null and not play.foul:
		_play = play
		_play_time = 0.0
		_pending = events
		_runners_at_start = [_id_on(1), _id_on(2), _id_on(3)]
		_batter_at_start = game.batter_id()
		_enter(State.RESULT)
		return
	if play != null and play.foul:
		# Show the foul's flight briefly.
		_play = play
		_play_time = 0.0
		_pending = events
		_runners_at_start = [_id_on(1), _id_on(2), _id_on(3)]
		_batter_at_start = game.batter_id()
		_enter(State.RESULT)
		return
	for e: GameEvent in events:
		_apply(e)
	_enter(State.RESULT)


func _id_on(base: int) -> String:
	var r := game.runner_on(base)
	return r.player_id if r != null else ""


func _pitch_banner(events: Array[GameEvent]) -> String:
	for e: GameEvent in events:
		if e.kind == GameEvent.Kind.PLATE_APPEARANCE:
			return PaResult.text(e.result)
	match duel.result:
		PitchDuel.Result.BALL:
			return "볼넷" if balls >= 3 else "볼"
		PitchDuel.Result.CALLED_STRIKE:
			return "삼진" if strikes >= 2 else "스트라이크"
		PitchDuel.Result.SWINGING_STRIKE, PitchDuel.Result.FOUL_TIP:
			return "삼진" if strikes >= 2 else "헛스윙"
		PitchDuel.Result.FOUL:
			return "파울"
	return ""


func step(delta: float) -> void:
	if menu != null and menu.visible:
		return
	if game.over:
		state_time += delta
		banner_time = maxf(banner_time - delta, 0.0)
		return
	if _between > 0.0:
		_between -= delta
		banner_time = maxf(banner_time - delta, 0.0)
		return
	if _play_time >= 0.0:
		_play_time += delta
		state_time = 0.0
		banner_time = maxf(banner_time - delta, 0.0)
		if _play_time >= _play.timeline.duration + PLAY_TAIL:
			_end_play()
		return
	super.step(delta)


func _end_play() -> void:
	_play_time = -1.0
	for e: GameEvent in _pending:
		_apply(e)
	_pending.clear()
	if _play != null and not _play.foul:
		banner = last_text
		banner_time = 2.6
	_play = null
	_enter(State.RESULT)


## Applies an event to the game and the books.
func _apply(e: GameEvent) -> void:
	var batter := game.batter_id()
	var out := GameFlow.apply(game, e)
	scorer.record(game, e, out)
	manager.note_change(game, e)
	var text := _describe(e, out, batter)
	if text != "":
		last_text = text
		log.append(text)
	balls = game.balls
	strikes = game.strikes
	if game.over:
		scorer.finish(game)
		banner = "경기 종료  %s %d : %d %s" % [game.teams[0].short_name, game.score[0], game.score[1], game.teams[1].short_name]
		banner_time = 1e9


func _describe(e: GameEvent, out: FlowOutcome, batter_id: String) -> String:
	var team := game.teams[out.batting_before]
	match e.kind:
		GameEvent.Kind.PLATE_APPEARANCE:
			var p := team.player(batter_id)
			var text := "%s: %s" % [p.name if p != null else batter_id, GameSim.play_text(e, out)]
			if out.scored.size() > 0:
				text += ", %d점" % out.scored.size()
			return text
		GameEvent.Kind.STEAL:
			return "도루 성공" if not e.moves[0].is_out() else "도루 실패"
		GameEvent.Kind.PICKOFF:
			return "견제사"
		GameEvent.Kind.WILD_PITCH:
			return "폭투"
		GameEvent.Kind.PASSED_BALL:
			return "포일"
		GameEvent.Kind.SUBSTITUTION:
			var t := game.teams[e.team]
			var who := t.player(e.in_id)
			if e.change == GameEvent.Change.PITCHER:
				return "%s 투수 교체: %s" % [t.short_name, who.name if who != null else e.in_id]
			return "%s 교체: %s" % [t.short_name, who.name if who != null else e.in_id]
	return ""


## The duel HUD's mode follows the player's role this half-inning.
func _sync_mode() -> void:
	mode = &"bat" if human_bats() else (&"pitch" if human_pitches() else &"watch")


func _after_result() -> void:
	_drain()
	if game.over:
		return
	var half := _half_name()
	if half != _half_key:
		_half_key = half
		_dress_for_half()
		banner = half
		banner_time = TRANSITION
		_between = TRANSITION
	_new_duel()
	_enter(State.PRE_PITCH)
	_place_cast()
	_sync_mode()
	_snap_camera()


## Everything before the next pitch: the end of a plate appearance on a full count,
## substitutions, an intentional walk, a pickoff or a steal.
func _drain() -> void:
	for i: int in 40:
		if game.over:
			return
		var e := resolver.before_pitch(game)
		if e == null:
			return
		_apply(e)
		if e.kind != GameEvent.Kind.SUBSTITUTION:
			banner = last_text
			banner_time = 2.2


func _half_name() -> String:
	return "%d회%s" % [game.inning, "초" if game.top else "말"]


# --- Cast ---


func _build_fielders() -> void:
	var colors := Color(0.93, 0.93, 0.95)
	for kind: Position.Kind in [Position.Kind.B1, Position.Kind.B2, Position.Kind.B3, Position.Kind.SS, Position.Kind.LF, Position.Kind.CF, Position.Kind.RF]:
		var f := _add_puppet(Vector3.ZERO, 0.0, colors, Color(0.1, 0.15, 0.35), use_models)
		f.left_grip = Puppet.Grip.GLOVE
		f.apply(PuppetClips.fielder_ready())
		fielders[kind] = f
	for i: int in 3:
		var r := _add_puppet(Vector3.ZERO, 0.0, colors, Color(0.1, 0.15, 0.35), use_models)
		r.headgear = &"helmet"
		r.show_glove = false
		r.visible = false
		runner_puppets.append(r)


func _build_officials() -> void:
	fielders[Position.Kind.P] = pitcher
	fielders[Position.Kind.C] = catcher
	var officials := UniformStyle.make(Color(0.07, 0.07, 0.08), Color(0.34, 0.35, 0.37), Color(0.07, 0.07, 0.08), Color(0.07, 0.07, 0.08), "")
	# Base umpires stand behind first and third, outside the line; the second-base umpire
	# behind the bag, or inside the infield with runners on.
	for spot: Vector3 in [Vector3(23.6, 19.4, 0.0), Vector3(-3.0, 44.0, 0.0), Vector3(-23.6, 19.4, 0.0)]:
		var u := _add_puppet(spot, 0.0, Color(0.08, 0.08, 0.09), Color(0.05, 0.05, 0.06), use_models)
		_dress(u, UniformStyle.make(officials.jersey, officials.pants, officials.trim, officials.ink, ""), 0, "", false)
		u.show_glove = false
		u.apply(PuppetClips.umpire())
		u.rotation.y = _yaw_toward(Vector2(spot.x, spot.y), Vector2.ZERO)
		base_umpires.append(u)
	# Coaches in their boxes beside first and third.
	for spot: Vector3 in [Vector3(25.0, 13.0, 0.0), Vector3(-25.0, 13.0, 0.0)]:
		var c := _add_puppet(spot, 0.0, Color(0.9, 0.9, 0.9), Color(0.1, 0.1, 0.1), use_models)
		c.show_glove = false
		c.apply(PuppetClips.stance())
		c.rotation.y = _yaw_toward(Vector2(spot.x, spot.y), Vector2.ZERO)
		coaches.append(c)
	on_deck = _add_puppet(Vector3(-11.0, -1.5, 0.0), 0.0, Color(0.9, 0.9, 0.9), Color(0.1, 0.1, 0.1), use_models)
	on_deck.show_bat = true
	on_deck.headgear = &"helmet"
	on_deck.show_glove = false
	on_deck.apply(PuppetClips.stance())


## Home in white with navy, visitors in black with orange: the fielding side on the field,
## the batting side at bat, on the bases and in the coaching boxes.
func _dress_for_half() -> void:
	_styles = [
		UniformStyle.make(Color(0.08, 0.08, 0.09), Color(0.9, 0.9, 0.91), Color(0.95, 0.45, 0.08), Color(0.95, 0.45, 0.08), "Comets"),
		UniformStyle.make(Color(0.94, 0.94, 0.96), Color(0.92, 0.92, 0.94), Color(0.1, 0.15, 0.35), Color(0.1, 0.15, 0.35), "Harbor"),
	]
	_styles[0].cap = Color(0.07, 0.07, 0.08)
	_styles[0].pants_pinstripes = true
	var field_team := game.fielding_team()
	for kind: Position.Kind in fielders:
		var p := field_team.player(field_team.fielder_at(kind))
		_dress(fielders[kind], _style_for(game.fielding()), p.number if p != null else 0, p.name if p != null else "", false)
	var bat_team := game.batting_team()
	var b := bat_team.player(game.batter_id())
	_dress(batter, _style_for(game.batting()), b.number if b != null else 0, b.name if b != null else "", true)
	for r: Puppet in runner_puppets:
		_dress(r, _style_for(game.batting()), 0, "", true)
	for c: Puppet in coaches:
		_dress(c, _style_for(game.batting()), 70, "", false)
	_dress(on_deck, _style_for(game.batting()), 0, "", true)


func _style_for(team: int) -> UniformStyle:
	var s := _styles[team]
	var copy := UniformStyle.make(s.jersey, s.pants, s.trim, s.ink, s.wordmark)
	copy.cap = s.cap
	copy.pants_pinstripes = s.pants_pinstripes
	return copy


## Puts everyone where they stand before a pitch.
func _place_cast() -> void:
	var bats_left := settings.bats_left
	var at := resolver.alignment.positions(game, resolver.fence, bats_left, resolver.is_bunting())
	for kind: Position.Kind in fielders:
		if kind == Position.Kind.P or kind == Position.Kind.C:
			continue
		var f := fielders[kind]
		var p: Vector2 = at.get(kind, Vector2.ZERO)
		f.position = Field.to_world(Vector3(p.x, p.y, 0.0))
		f.rotation.y = _yaw_toward(p, Vector2(0.0, 0.5))
		f.apply(PuppetClips.fielder_ready())
		f.visible = true
	pitcher.position = Field.to_world(Vector3(0.0, Field.RUBBER_Y - (0.06 if pitch_motion != null else 0.0), Field.MOUND_HEIGHT))
	pitcher.rotation.y = PI
	pitcher.scale.x = -1.0 if settings.throws_left else 1.0
	catcher.position = Field.to_world(Vector3(0.0, -1.15, 0.0))
	catcher.rotation.y = 0.0
	catcher.apply(PuppetClips.catcher())
	# The plate umpire looks over the catcher's shoulder from the slot between catcher and
	# batter: behind the catcher's left shoulder for a right-handed batter.
	umpire.position = Field.to_world(Vector3(0.3 if bats_left else -0.3, -2.3, 0.0))
	# The batter stands in the box on his side; a left-hander is the mirror image.
	var side := -1.0 if bats_left else 1.0
	batter.scale.x = side
	batter.position = Field.to_world(Vector3(_box.x * side, _box.y, 0.0))
	batter.rotation.y = -PI / 2.0 if not bats_left else PI / 2.0
	for i: int in 3:
		var r := runner_puppets[i]
		var on := game.runner_on(i + 1)
		r.visible = on != null
		if on == null:
			continue
		var base := PlaySim.base_xy(i + 1)
		var toward := (PlaySim.base_xy(i + 2) - base).normalized()
		var lead := base + toward * resolver.motion.leads[i]
		r.position = Field.to_world(Vector3(lead.x, lead.y, 0.0))
		r.rotation.y = _yaw_toward(lead, Vector2.ZERO)
		r.apply(PuppetClips.fielder_ready())
	var next_up := game.batting_team()
	on_deck.position = Field.to_world(Vector3(11.0 if game.batting() == GameState.HOME else -11.0, -1.5, 0.0))
	on_deck.visible = next_up.lineup.size() > 0


## The catcher sets up where the pitch is meant to go: his body shifts toward the side and
## his mitt shows the height, from the moment the sign is given until the ball arrives.
func _show_target() -> void:
	if _play_time >= 0.0 or game.over:
		return
	var showing := state == State.WINDUP or (state == State.LIVE and duel.phase == PitchDuel.Phase.FLIGHT)
	var aim := decision.target if showing and decision != null else Vector3(0.0, 0.0, 0.75)
	if human_pitches() and state != State.LIVE and state != State.WINDUP:
		aim = target
	catcher.position = Field.to_world(Vector3(clampf(aim.x * 0.7, -0.45, 0.45), -1.15, 0.0))
	catcher.apply(PuppetClips.catcher(aim.z))


static func _yaw_toward(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return -atan2(d.x, d.y)


# --- Showing the play ---


func refresh(delta: float) -> void:
	_show_target()
	if _play_time >= 0.0 and _play != null:
		_frame_time = delta
		_phase += delta * 2.6
		_show_play(_play_time)
		_move_camera_play(delta)
		hud.queue_redraw()
		match_hud.queue_redraw()
		return
	super.refresh(delta)
	match_hud.queue_redraw()


func _show_play(t: float) -> void:
	var tl := _play.timeline
	ball_actor.show_at(_ball_at(tl, t))
	for kind: Position.Kind in fielders:
		var key := "F:%s" % Position.code(kind)
		if tl.tracks.has(key):
			_move_puppet(fielders[kind], tl, key, t)
	for i: int in 3:
		var id := _runners_at_start[i]
		if id != "" and tl.tracks.has("R:%s" % id):
			runner_puppets[i].visible = true
			_move_puppet(runner_puppets[i], tl, "R:%s" % id, t)
	var batter_key := "R:%s" % _batter_at_start
	if tl.tracks.has(batter_key):
		batter.scale.x = 1.0
		_move_puppet(batter, tl, batter_key, t)


## Moves a puppet along its track, facing the way it goes, running or standing.
func _move_puppet(p: Puppet, tl: PlayTimeline, key: String, t: float) -> void:
	var now := tl.position(key, t)
	var ahead := tl.position(key, t + 0.1)
	p.position = Field.to_world(Vector3(now.x, now.y, 0.0))
	var step := Vector2(ahead.x - now.x, ahead.y - now.y)
	p.frame_time = _frame_time
	if step.length() / 0.1 > RUN_POSE_SPEED:
		p.rotation.y = _yaw_toward(Vector2.ZERO, step)
		p.apply(PuppetClips.run(_phase))
	else:
		var ball := _ball_at(tl, t)
		p.rotation.y = _yaw_toward(Vector2(now.x, now.y), Vector2(ball.x, ball.y))
		p.apply(PuppetClips.fielder_ready())


## The ball's position from the key frames, with throws drawn as arcs.
func _ball_at(tl: PlayTimeline, t: float) -> Vector3:
	var p := tl.position("ball", t)
	for th: PackedVector4Array in tl.throws:
		var a := th[0]
		var b := th[1]
		if t > a.x and t < b.x:
			var f := (t - a.x) / (b.x - a.x)
			var d := Vector2(b.y - a.y, b.z - a.z).length()
			p.z += 4.0 * minf(d / 14.0, 6.0) * f * (1.0 - f)
	return p


func _move_camera_play(delta: float) -> void:
	# High behind home plate, inside the backstop, turning to keep the ball in view.
	var ball := _ball_at(_play.timeline, _play_time)
	var from := Vector3(clampf(ball.x * 0.1, -5.0, 5.0), -14.0, 16.0)
	_follow_target = _follow_target.lerp(Vector3(ball.x, maxf(ball.y, 12.0), maxf(ball.z * 0.7, 0.0)), clampf(delta * 4.0, 0.0, 1.0))
	camera.position = camera.position.lerp(Field.to_world(from), clampf(delta * 2.5, 0.0, 1.0))
	camera.fov = lerpf(camera.fov, 48.0, clampf(delta * 2.5, 0.0, 1.0))
	camera.look_at(Field.to_world(_follow_target))
	catcher.visible = true
	umpire.visible = true


func _show_ball() -> void:
	if _play_time >= 0.0 and _play != null:
		return
	super._show_ball()


## The batting camera stands behind the batter's back shoulder: mirrored for a left-handed
## batter, as a broadcast does.
func _camera_preset() -> Array:
	if human_pitches():
		return PITCH_CAMERA
	if settings.bats_left:
		var from: Vector3 = BAT_CAMERA[0]
		var to: Vector3 = BAT_CAMERA[1]
		return [Vector3(-from.x, from.y, from.z), Vector3(-to.x, to.y, to.z), BAT_CAMERA[2]]
	return BAT_CAMERA
