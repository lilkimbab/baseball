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
## The catcher gives the sign for this long (s) before he sets up; his mitt goes for the
## ball over the last CATCHER_REACH_TIME s of its flight; a pitch arriving lower than
## BLOCK_BELOW (m) is blocked; framing draws a caught pitch at most FRAME_PULL (m) inward.
const SIGN_TIME := 1.2
const CATCHER_REACH_TIME := 0.25
const BLOCK_BELOW := 0.18
const FRAME_PULL := 0.04
## After this long (s) into a result the catcher is still, and is left as he is.
const CATCHER_SETTLED := 0.45
## A sprint (m/s): running poses are drawn from a jog at 0 to a sprint at this speed.
const SPRINT := 8.0


## Advances a puppet's running stride by this frame at `speed` m/s and returns where in the
## stride he is: one step per unit, steps lengthening from about a metre at a jog to two at a
## sprint, so the feet keep pace with the ground (docs/13 S12: no foot sliding).
func _stride(p: Puppet, speed: float) -> float:
	var step := lerpf(1.0, 2.0, clampf(speed / SPRINT, 0.0, 1.0))
	_strides[p] = _strides.get(p, 0.0) + speed * _frame_time / step
	return _strides[p]


## The umpires hold up the infield fly call this long (s) into the play.
const INFIELD_FLY_SIGNAL := 1.6
## The plate umpire calls time for this long (s) when play stops for a substitution.
const TIME_SIGNAL := 1.6


## Rounds of moving the glove hand by how far its pocket is from the ball.
const CATCH_IK_PASSES := 5
## The most (m) a catch moves the body toward a ball out of the arm's reach.
const MAX_BODY_SHIFT := 0.6
## Fielders step in this far (m) over the last CREEP_LEAD seconds before the release.
const CREEP := 0.6
const CREEP_LEAD := 0.7
## Runners' secondary lead: SHUFFLES shuffle steps of SHUFFLE m, each SHUFFLE_TIME s.
const SHUFFLE := 0.55
const SHUFFLES := 2
const SHUFFLE_TIME := 0.3
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
var scorebug: Scorebug
var bottom_bar: BottomBar
var pitch_track: PitchTrack
var play_overlay: PlayOverlay
var pause_menu: PauseMenu
var post_game: PostGame
## The pitch clock (KBO 2026: 18 s with the bases empty, 23 s with runners) runs only while
## the player chooses his pitch; seconds left, negative when not running.
var pitch_clock_on := true
## Started from the quick game menu: leaving goes back to the hub.
var from_menu := false
var pitch_clock := -1.0
## The computer also makes the player's team's pitching changes and pinch hits.
var auto_changes := true
## Where and when a ball in the air first comes down (for the landing ring).
var landing_known := false
var landing_point := Vector3.ZERO
var landing_time := 0.0
var commentary: Commentary
var _last_pitch_result: PitchDuel.Result = PitchDuel.Result.NONE
## The small second view (docs/13 S6-5).
var pip_viewport: SubViewport
var pip_camera: Camera3D
var pip_rect: TextureRect


## A pitch of this plate appearance, for the pitch track.
class TrackedPitch:
	extends RefCounted
	var x := 0.0
	var z := 0.0
	var family: StringName = &"fastball"

## This plate appearance's pitches, and each pitcher's pitches by cell (0..8, 9 = outside).
var pa_pitches: Array[TrackedPitch] = []
var pitcher_cells: Dictionary[String, PackedInt32Array] = {}
var _clear_track := false
var menu: SubstitutionPanel
## One line per event, for the play-by-play panel.
var log := PackedStringArray()
var last_text := ""
## What the last event did (runs, outs), for modes that judge it.
var last_outcome: FlowOutcome

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
## Who catches, throws and slides when in the play being shown (S12).
var _moves: PlayMoves
## Where each fielder stood and each runner led off when the pitch began, and how far into
## the creep and the secondary lead the last poses were.
var _stands: Dictionary[Position.Kind, Vector2] = {}
var _leads: Array[Vector2] = []
var _cast_k := -1.0
var _cast_lead := -1.0
var _pending: Array[GameEvent] = []
## Who was on each base when the play started (their tracks are keyed by id).
var _runners_at_start: Array[String] = ["", "", ""]
var _batter_at_start := ""
var _between := 0.0
var _half_key := ""
## Seconds since the plate umpire called time (negative: he has not).
var _time_called := -1.0
## The play being shown is a steal or a pickoff (RunningPlay), not a ball in play.
var _running := false
## Where each running puppet is in his stride (steps).
var _strides: Dictionary[Puppet, float] = {}
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
	scorebug = Scorebug.new()
	scorebug.scene = self
	layer.add_child(scorebug)
	bottom_bar = BottomBar.new()
	bottom_bar.scene = self
	layer.add_child(bottom_bar)
	pitch_track = PitchTrack.new()
	pitch_track.scene = self
	layer.add_child(pitch_track)
	play_overlay = PlayOverlay.new()
	play_overlay.scene = self
	layer.add_child(play_overlay)
	post_game = PostGame.new()
	post_game.scene = self
	layer.add_child(post_game)
	pause_menu = PauseMenu.new()
	pause_menu.scene = self
	layer.add_child(pause_menu)
	pause_menu.wants_substitutions.connect(func() -> void: toggle_menu(true))
	pause_menu.quit_requested.connect(leave)
	commentary = CommentaryIO.load_default()
	_build_pip(layer)
	# The duel's own count and help line give way to the scoreboard and the bottom bar.
	var duel_hud := hud as DuelHud
	duel_hud.show_count = false
	duel_hud.show_help = false
	duel_hud.bottom_reserved = BottomBar.HEIGHT + 20.0
	menu = SubstitutionPanel.new()
	menu.scene = self
	layer.add_child(menu)
	var _showing := _drain()
	_new_duel()
	_place_cast()
	_sync_mode()


## Command-line choices: -- --innings 3|6|9 --team home|away|watch --seed n
func _read_arguments() -> void:
	Settings.ensure_loaded()
	pitch_clock_on = Settings.pitch_clock
	auto_changes = Settings.auto_changes
	if QuickMatchScreen.pending:
		QuickMatchScreen.pending = false
		from_menu = true
		innings = Settings.innings
		human_team = QuickMatchScreen.side_index()
		away_index = QuickMatchScreen.away_index
		home_index = QuickMatchScreen.home_index
		return
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
		set_auto_changes(auto_changes)
		_sync_mode()
		_snap_camera()


## The pitch clock: it runs while the player chooses and times his pitch; running out is a
## ball (KBO 2026 rules; it can be turned off in the pause menu).
func _run_pitch_clock(delta: float) -> void:
	var choosing := human_pitches() and _play_time < 0.0 and _between <= 0.0 \
		and (state == State.PRE_PITCH or state == State.CHARGE or state == State.ACCURACY)
	if not pitch_clock_on or not choosing:
		pitch_clock = -1.0
		return
	if pitch_clock < 0.0:
		pitch_clock = float(game.rules.pitch_clock_runners if game.runners_on() > 0 else game.rules.pitch_clock_empty)
	pitch_clock -= delta
	if pitch_clock > 0.0:
		return
	pitch_clock = -1.0
	_apply(GameEvent.pitch(GameEvent.Call.BALL))
	banner = "투구 시간 위반 · 볼"
	banner_time = 2.0
	_enter(State.RESULT)


## The timing call shows for a moment after the swing, not through the whole play.
func swing_feedback_visible() -> bool:
	return _play_time < 0.0 or _play_time < 0.9


func help_keys() -> String:
	return "Space 번트   F 작전·교체   F3 관전   Esc 종료"


func selected_type() -> PitchType:
	if _arsenal.is_empty():
		return super.selected_type()
	return _arsenal[clampi(selected_pitch, 0, _arsenal.size() - 1)].type


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and (key.keycode == KEY_ESCAPE or key.keycode == KEY_ENTER):
		_menu_key(key.keycode)
		get_viewport().set_input_as_handled()
		return
	if pause_menu.visible or menu.visible:
		return
	super._unhandled_input(event)
	if key != null and key.pressed and not key.echo and key.keycode == KEY_SPACE:
		bunt()
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F:
		toggle_menu()
	if key != null and key.keycode == KEY_TAB and not key.echo:
		bottom_bar.detail = key.pressed
	if key != null and key.pressed and not key.echo and key.keycode == KEY_C:
		pitch_track.show_spread = not pitch_track.show_spread


## Esc pauses (or closes what is open, or leaves a finished game); Enter replays one.
func _menu_key(code: Key) -> void:
	if game.over:
		if code == KEY_ENTER:
			if from_menu:
				QuickMatchScreen.pending = true
			get_tree().reload_current_scene()
		else:
			leave()
		return
	if code != KEY_ESCAPE:
		return
	if menu.visible:
		menu.close()
	elif pause_menu.visible:
		pause_menu.close()
	else:
		pause_menu.open()


## Opens or closes the manager's menu. It opens only between pitches (or from the pause
## menu); the game waits.
func toggle_menu(from_pause: bool = false) -> void:
	if menu.visible:
		menu.close()
		return
	if state == State.PRE_PITCH and _play_time < 0.0 and not game.over:
		menu.open()
	elif from_pause:
		banner = "교체는 투구 사이에만 할 수 있습니다"
		banner_time = 2.0
		pause_menu.open()


func set_auto_changes(on: bool) -> void:
	auto_changes = on
	manager.manual_team = -1 if on or own_team() < 0 else own_team()


## Out of the game: back to the hub when there is one to go back to, else the program ends.
func leave() -> void:
	if from_menu or ResourceLoader.exists(Screen.HUB) and get_tree().current_scene == self and OS.get_cmdline_user_args().is_empty():
		get_tree().change_scene_to_file(Screen.HUB)
	else:
		get_tree().quit()


## What the screen after the game says the keys do.
func post_game_hint() -> String:
	return "Enter 다시 하기   ·   Esc 끝내기"


## The player's club (0 away, 1 home), or −1 when he only watches.
func own_team() -> int:
	return human_team


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
	_apply_forms()
	_pitch_count += 1
	if _clear_track:
		pa_pitches.clear()
		_clear_track = false
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


var _form_key := ""
var _people_key := ""


## A figure takes the player's height and build (docs/13 S11-1).
func _set_body(puppet: Puppet, p: Player, kind: Position.Kind) -> void:
	var model := puppet as SkinnedPuppet
	if model == null or p == null:
		return
	model.set_body(p.height_cm / 100.0, SkinnedPuppet.build_for(p.height_cm, p.weight_kg, kind))
	model.set_hair(1 + absi(hash(p.id)) % 4, hair_color_of(p))
	model.helmet_flaps = &"both" if p.bats == &"S" else &"left"
	model.set_face(p.id)


## The club's letter on the cap and helmet (fictional clubs: the first letter of the name).
func _logo(puppet: Puppet, team: int) -> void:
	var model := puppet as SkinnedPuppet
	if model == null or _styles.is_empty():
		return
	var name := game.teams[team].short_name
	model.set_logo(name.substr(0, 1) if name != "" else "", _styles[team].trim)


## Hair colour: nearly black for the local players; the foreign players' run from black to
## brown to fair (A).
static func hair_color_of(p: Player) -> Color:
	if p.origin != &"foreign":
		return Color(0.06, 0.05, 0.045)
	var shades: Array[Color] = [Color(0.06, 0.05, 0.045), Color(0.18, 0.11, 0.06), Color(0.32, 0.22, 0.12), Color(0.55, 0.42, 0.24)]
	return shades[absi(hash(p.id + ":hair")) % shades.size()]


## The pitcher's and the batter's own forms (docs/13 S10-5): recorded deliveries and swings
## from the local pack, chosen per player (FormCatalog). With runners on, the delivery is from
## the set position.
func _apply_forms() -> void:
	if game.over:
		return
	var pitcher_player := game.fielding_team().player(game.pitcher_id())
	var batter_player := game.batting_team().player(game.batter_id())
	var people := "%s/%s" % [game.pitcher_id(), game.batter_id()]
	if people != _people_key:
		# A new batter or pitcher: his body, and the batter's name and number on his back.
		_people_key = people
		_set_body(pitcher, pitcher_player, Position.Kind.P)
		_set_body(batter, batter_player, Position.Kind.DH)
		if batter_player != null and not _styles.is_empty():
			_dress(batter, _style_for(game.batting()), batter_player.number, batter_player.name, true)
	if not use_motion:
		return
	var pf := FormCatalog.pitch_form(pitcher_player)
	var sf := FormCatalog.swing_form(batter_player, pitcher_player.throws if pitcher_player != null else &"R")
	var key := "%s/%s" % [pf, sf]
	if key != _form_key and (pf != "" or sf != ""):
		_form_key = key
		var p_clip := MotionLibrary.find(&"pitch", StringName(pf) if pf != "" else &"default")
		var s_clip := MotionLibrary.find(&"swing", StringName(sf) if sf != "" else &"default")
		var high := MotionLibrary.find(&"swing", StringName(sf + "_high")) if sf != "" else null
		var low := MotionLibrary.find(&"swing", StringName(sf + "_low")) if sf != "" else null
		set_motion(p_clip, s_clip, high, low)
		_box = Field.to_field(batter.position)
		_box.x = -absf(_box.x)
	if pitch_motion != null:
		pitch_motion.use_stretch(game.runners_on() > 0)


func _ai_pitch_decision() -> PitchDecision:
	return resolver.tire(game, resolver.controllers[game.fielding()].choose_pitch(game, duel))


func _ai_react() -> void:
	if resolver.is_bunting():
		AiBatter.bunt(duel, _ai_rng)
	elif not resolver.batter_takes(game):
		resolver.controllers[game.batting()].react(game, duel)


func _finish_on_contact() -> bool:
	return true


func _umpire_busy() -> bool:
	return _time_called >= 0.0


func _finish_pitch() -> void:
	if swing_motion != null:
		swing_motion.relax()
	_track_pitch()
	_last_pitch_result = duel.result
	_note_landing()
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
		_moves = PlayMoves.read(play.timeline, play.calls)
		_play_time = 0.0
		_pending = events
		_runners_at_start = [_id_on(1), _id_on(2), _id_on(3)]
		_batter_at_start = game.batter_id()
		_enter(State.RESULT)
		return
	if play != null and play.foul:
		# Show the foul's flight briefly.
		_play = play
		_moves = PlayMoves.read(play.timeline, play.calls)
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
	if pause_menu != null and pause_menu.visible:
		return
	_run_pitch_clock(delta)
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
	_running = false
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
	last_outcome = out
	scorer.record(game, e, out)
	manager.note_change(game, e)
	if e.kind == GameEvent.Kind.PLATE_APPEARANCE:
		_clear_track = true
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
	var pick := log.size()
	match e.kind:
		GameEvent.Kind.PLATE_APPEARANCE:
			var p := team.player(batter_id)
			var key := Commentary.key_for(e.result, _last_pitch_result)
			return commentary.line(key, pick, p.name if p != null else batter_id, GameSim.play_text(e, out), e.fielders, out.scored.size())
		GameEvent.Kind.STEAL, GameEvent.Kind.PICKOFF:
			var m := e.moves[0]
			var runner := team.player(out.runner_ids[0]) if not out.runner_ids.is_empty() else null
			var who := runner.name if runner != null else ""
			var base := m.out_at if m.is_out() else m.to
			if e.kind == GameEvent.Kind.PICKOFF:
				return commentary.line("pickoff", pick, "", "", "", 0, who, base)
			return commentary.line("caught_stealing" if m.is_out() else "steal", pick, "", "", "", out.scored.size(), who, mini(base, 4))
		GameEvent.Kind.WILD_PITCH:
			return commentary.line("wild_pitch", pick, "", "", "", out.scored.size())
		GameEvent.Kind.PASSED_BALL:
			return commentary.line("passed_ball", pick, "", "", "", out.scored.size())
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
	if _drain():
		return
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
## substitutions, an intentional walk, a pickoff or a steal. True when a steal or a pickoff is
## being shown as a play: the rest waits until it is over.
func _drain() -> bool:
	for i: int in 40:
		if game.over:
			return false
		var e := resolver.before_pitch(game)
		if e == null:
			return false
		if _show_running(e):
			return true
		_apply(e)
		if e.kind == GameEvent.Kind.SUBSTITUTION:
			_time_called = 0.0
		elif not game.over:
			banner = last_text
			banner_time = 2.2
	return false


## Shows a steal or a pickoff as a play (docs/13 S12) before it counts: the pitch or the
## pickoff throw, the catcher's throw, the cover man, the slide and the call. A double steal
## and a throw that gets away are only reported.
func _show_running(e: GameEvent) -> bool:
	var play: PlayResult = null
	if e.kind == GameEvent.Kind.PICKOFF and e.moves.size() == 1 and game.runner_on(1) != null:
		play = RunningPlay.pickoff(game.runner_on(1).player_id, _stands.get(Position.Kind.B1, PlaySim.base_xy(1)), resolver.motion)
	elif e.kind == GameEvent.Kind.STEAL and e.moves.size() == 1 and e.fielders != "E2":
		var m := e.moves[0]
		if m.from < 1 or m.from > 2 or game.runner_on(m.from) == null:
			return false
		var cover := Position.Kind.SS if m.from == 1 else Position.Kind.B3
		var margin := resolver.steal_margin(game, m.from)
		play = RunningPlay.steal(m.from, game.runner_on(m.from).player_id, not m.is_out(), margin, cover, _stands.get(cover, PlaySim.base_xy(m.from + 1)), resolver.motion)
	if play == null:
		return false
	# Everyone where they stand for the pitch, the new batter in the box.
	var hitter := game.batting_team().player(game.batter_id())
	var pitcher_player := game.fielding_team().player(game.pitcher_id())
	var throws := pitcher_player.throws if pitcher_player != null else &"R"
	settings.bats_left = hitter != null and hitter.batting_side(throws) == &"L"
	settings.throws_left = throws == &"L"
	_apply_forms()
	_place_cast()
	_play = play
	_moves = PlayMoves.read(play.timeline, play.calls, false)
	_running = true
	_play_time = 0.0
	_pending.clear()
	_pending.append(e)
	_runners_at_start = [_id_on(1), _id_on(2), _id_on(3)]
	_batter_at_start = ""
	_enter(State.RESULT)
	return true


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
	# Each club in its own uniform: the home side in white, the visitors in their road
	# uniform (docs/13 S11-9). Without the clubs (a test game) the plain pair.
	var away := _club(0)
	var home := _club(1)
	if away != null and home != null:
		_styles = [UniformStyle.for_team(away, false), UniformStyle.for_team(home, true)]
	else:
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
	for kind: Position.Kind in fielders:
		_set_body(fielders[kind], field_team.player(field_team.fielder_at(kind)), kind)
		_logo(fielders[kind], game.fielding())
		var model := fielders[kind] as SkinnedPuppet
		if model != null:
			model.glove_kind = &"outfield" if Position.OUTFIELD.has(kind) else (&"first_base" if kind == Position.Kind.B1 else &"glove")
	_set_body(catcher, field_team.player(field_team.fielder_at(Position.Kind.C)), Position.Kind.C)
	_logo(catcher, game.fielding())
	_logo(pitcher, game.fielding())
	_logo(batter, game.batting())
	_people_key = ""
	for r: Puppet in runner_puppets:
		_dress(r, _style_for(game.batting()), 0, "", true)
	for c: Puppet in coaches:
		_dress(c, _style_for(game.batting()), 70, "", false)
	_dress(on_deck, _style_for(game.batting()), 0, "", true)


func _style_for(team: int) -> UniformStyle:
	var s := _styles[team]
	var copy := UniformStyle.make(s.jersey, s.pants, s.trim, s.ink, s.wordmark)
	copy.cap = s.cap
	copy.socks = s.socks
	copy.jersey_pinstripes = s.jersey_pinstripes
	copy.pants_pinstripes = s.pants_pinstripes
	copy.pinstripe = s.pinstripe
	copy.patch = s.patch
	copy.pants_stripe = s.pants_stripe
	return copy


## The club playing as away (0) or home (1): from the roster pack, the league or the career.
func _club(side: int) -> Team:
	var id := game.teams[side].team_id
	for t: Team in _clubs:
		if t.id == id:
			return t
	if LeagueSession.season != null and LeagueSession.season.teams.has(id):
		return LeagueSession.season.teams[id]
	if CareerSession.season != null and CareerSession.season.teams.has(id):
		return CareerSession.season.teams[id]
	return null


## Fielders' and runners' part in each pitch (docs/13 S12): as the pitcher delivers, the
## fielders take two steps in and drop into their crouch, and the runners shuffle out to a
## secondary lead. Poses change only while they move.
func _pose_cast() -> void:
	if _pitch_clock < 0.0 or game.over:
		return
	var release := release_time()
	var k := smoothstep(release - CREEP_LEAD, release, _pitch_clock)
	var lead := clampf((_pitch_clock - release) / SHUFFLE_TIME, 0.0, float(SHUFFLES))
	if absf(k - _cast_k) < 0.02 and absf(lead - _cast_lead) < 0.02:
		return
	_cast_k = k
	_cast_lead = lead
	for kind: Position.Kind in _stands:
		var f := fielders[kind]
		var p := _stands[kind]
		var at := p + (Vector2(0.0, 0.5) - p).normalized() * (CREEP * k)
		f.position = Field.to_world(Vector3(at.x, at.y, 0.0))
		f.frame_time = _frame_time
		f.apply(PuppetClips.creep(k, CREEP))
	for i: int in 3:
		var r := runner_puppets[i]
		if not r.visible or i >= _leads.size():
			continue
		var toward := (PlaySim.base_xy(i + 2) - PlaySim.base_xy(i + 1)).normalized()
		var at := _leads[i] + toward * (SHUFFLE * lead)
		r.position = Field.to_world(Vector3(at.x, at.y, 0.0))
		var side := signf(r.to_local(r.position + Field.to_world(Vector3(toward.x, toward.y, 0.0)) - Field.to_world(Vector3.ZERO)).x)
		var step := lead - floorf(lead) if lead < float(SHUFFLES) else 1.0
		r.frame_time = _frame_time
		r.apply(PuppetClips.shuffle(step, SHUFFLE, side) if lead > 0.0 else PuppetClips.lead_off())


## Puts everyone where they stand before a pitch.
func _place_cast() -> void:
	var bats_left := settings.bats_left
	var at := resolver.alignment.positions(game, resolver.fence, bats_left, resolver.is_bunting(), resolver.tactics[game.fielding()])
	for kind: Position.Kind in fielders:
		if kind == Position.Kind.P or kind == Position.Kind.C:
			continue
		var f := fielders[kind]
		var p: Vector2 = at.get(kind, Vector2.ZERO)
		f.position = Field.to_world(Vector3(p.x, p.y, 0.0))
		f.rotation.y = _yaw_toward(p, Vector2(0.0, 0.5))
		f.apply(PuppetClips.fielder_ready())
		f.visible = true
		_stands[kind] = p
	_cast_k = 0.0
	_cast_lead = 0.0
	_leads.clear()
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
		while _leads.size() <= i:
			_leads.append(Vector2.ZERO)
		_leads[i] = lead
		r.position = Field.to_world(Vector3(lead.x, lead.y, 0.0))
		r.rotation.y = _yaw_toward(lead, Vector2.ZERO)
		r.apply(PuppetClips.lead_off())
	var next_up := game.batting_team()
	on_deck.position = Field.to_world(Vector3(11.0 if game.batting() == GameState.HOME else -11.0, -1.5, 0.0))
	on_deck.visible = next_up.lineup.size() > 0


## The catcher's part in each pitch (docs/13 S12-4). He puts down the sign, then sets up
## where the pitch is meant to go (his body shifts toward the side and his mitt shows the
## height). As the ball comes in his mitt goes to where it really arrives, and once it is in he
## draws it a little toward the zone (framing). A pitch in the dirt he drops to his knees to
## block.
func _show_target() -> void:
	if _play_time >= 0.0 or game.over:
		return
	var showing := state == State.WINDUP or (state == State.LIVE and duel.phase == PitchDuel.Phase.FLIGHT)
	var aim := decision.target if showing and decision != null else Vector3(0.0, 0.0, 0.75)
	if human_pitches() and state != State.LIVE and state != State.WINDUP:
		aim = target
	if state != State.RESULT:
		catcher.position = Field.to_world(Vector3(clampf(aim.x * 0.7, -0.45, 0.45), -1.15, 0.0))
	catcher.frame_time = _frame_time
	var pose := PuppetClips.catcher(aim.z)
	if state == State.PRE_PITCH and not human_pitches() and state_time < SIGN_TIME:
		pose = PuppetClips.catcher_sign()
	if state == State.RESULT and state_time > CATCHER_SETTLED:
		return
	var ball := _catcher_ball()
	if not ball.is_finite():
		catcher.apply(pose)
		return
	if duel.bounced or ball.z < BLOCK_BELOW:
		pose = PuppetClips.catcher_block()
	var coming := (duel.ball.pos.y - PitchDuel.CATCH_Y) / maxf(-duel.ball.vel.y, 1.0) if state == State.LIVE else 0.0
	var reach := 1.0 - smoothstep(0.0, CATCHER_REACH_TIME, coming)
	catch_at(catcher, pose, catcher.to_local(Field.to_world(ball)), reach)


## Where the catcher means to take the pitch, in field coordinates: where it will cross his
## catching plane while it is on its way, where it is (drawn toward the zone) once he has it,
## or nowhere (INF) when it was hit or hit the batter.
func _catcher_ball() -> Vector3:
	var hit := duel.contact != null and duel.contact.made_contact
	if hit or duel.result == PitchDuel.Result.HIT_BY_PITCH:
		return Vector3.INF
	if state == State.LIVE and duel.phase == PitchDuel.Phase.FLIGHT:
		var b := duel.ball
		var left := maxf((b.pos.y - PitchDuel.CATCH_Y) / maxf(-b.vel.y, 1.0), 0.0)
		var at := b.pos + b.vel * left + Vector3(0.0, 0.0, -4.9 * left * left)
		at.z = maxf(at.z, 0.05)
		return at
	if state == State.RESULT:
		var held := duel.ball.pos
		if duel.bounced:
			return held
		# Framing: a short pull toward the middle of the zone just after the catch.
		var middle := Vector3(0.0, held.y, (duel.zone.bottom + duel.zone.top) * 0.5)
		var pull := (middle - held).limit_length(FRAME_PULL) * smoothstep(0.05, 0.3, state_time)
		return held + pull
	return Vector3.INF


## The fielder going after the ball in the current play (DH when none).
func chasing_fielder() -> Position.Kind:
	if _play == null or _play.direction < 1 or _play.direction > 9:
		return Position.Kind.DH
	return (_play.direction - 1) as Position.Kind


## The runners (and the batter) in the current play.
func runner_ids_in_play() -> Array[String]:
	var ids: Array[String] = []
	for id: String in _runners_at_start:
		if id != "":
			ids.append(id)
	if _batter_at_start != "":
		ids.append(_batter_at_start)
	return ids


## His place in the batting order (1..9) for the team at bat.
func order_of(id: String) -> int:
	return game.batting_team().slot_of(id) + 1


func ball_position(t: float) -> Vector3:
	return _ball_at(_play.timeline, t) if _play != null else Vector3.ZERO


## Where the batted ball first comes down, when it goes up in the air.
func _note_landing() -> void:
	landing_known = false
	if duel.path == null or duel.path.events.is_empty() or duel.contact == null:
		return
	if duel.contact.launch_deg() < 10.0:
		return
	var first := duel.path.events[0]
	if first.kind != BallEvent.Kind.BOUNCE:
		return
	landing_known = true
	landing_point = first.pos
	landing_time = first.time


static func _yaw_toward(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return -atan2(d.x, d.y)


# --- Showing the play ---


func refresh(delta: float) -> void:
	_show_target()
	if _play_time >= 0.0 and _play != null:
		_frame_time = delta
		_show_play(_play_time)
		_move_camera_play(delta)
		hud.queue_redraw()
		_redraw_overlays()
		return
	super.refresh(delta)
	_pose_cast()
	for u: Puppet in base_umpires:
		signal_call(u, null)
	if _time_called >= 0.0:
		_time_called += delta
		signal_call(umpire, PuppetClips.umpire_signal(&"time", _time_called) if _time_called < TIME_SIGNAL else null)
		if _time_called >= TIME_SIGNAL:
			_time_called = -1.0
	_redraw_overlays()


func _redraw_overlays() -> void:
	# After the game only the scoreboard and the summary remain.
	hud.visible = not game.over
	pitch_track.visible = not game.over
	scorebug.queue_redraw()
	bottom_bar.queue_redraw()
	pitch_track.queue_redraw()
	play_overlay.queue_redraw()
	post_game.queue_redraw()
	_update_pip()


## Notes where the pitch crossed the plate, for the pitch track.
func _track_pitch() -> void:
	if duel.pitch == null:
		return
	var t := TrackedPitch.new()
	t.x = duel.pitch.plate_pos.x
	t.z = duel.pitch.plate_pos.z
	t.family = duel.decision.type.family
	pa_pitches.append(t)
	var id := game.pitcher_id()
	if not pitcher_cells.has(id):
		var fresh := PackedInt32Array()
		fresh.resize(10)
		pitcher_cells[id] = fresh
	var cell := AiPitcher.cell_of(duel.zone, Vector3(t.x, Field.PLATE_FRONT_Y, t.z))
	var cells := pitcher_cells[id]
	cells[cell if cell >= 0 else 9] += 1
	pitcher_cells[id] = cells


# --- Picture in picture (docs/13 S6-5) ---


const PIP_SIZE := Vector2(384.0, 216.0)
var _pip_frame := 0


func _build_pip(layer: Node) -> void:
	pip_viewport = SubViewport.new()
	pip_viewport.size = Vector2i(400, 225)
	pip_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(pip_viewport)
	pip_camera = Camera3D.new()
	pip_camera.fov = 24.0
	pip_camera.far = 400.0
	pip_viewport.add_child(pip_camera)
	pip_camera.current = true
	pip_rect = TextureRect.new()
	pip_rect.texture = pip_viewport.get_texture()
	pip_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pip_rect.stretch_mode = TextureRect.STRETCH_SCALE
	pip_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(pip_rect)


## While a pitch is being set up and thrown: the lead runner taking his lead, or with the
## bases empty the pitcher from the side.
func _update_pip() -> void:
	var showing := _play_time < 0.0 and not game.over and (state == State.PRE_PITCH or state == State.WINDUP or state == State.LIVE)
	pip_rect.visible = showing
	# Drawn every other frame: half the cost, and a small view does not need more.
	_pip_frame += 1
	pip_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if showing and _pip_frame % 2 == 0 else SubViewport.UPDATE_DISABLED
	if not showing:
		return
	var k := UiTheme.scale_for(get_viewport().get_visible_rect().size.y)
	var screen := get_viewport().get_visible_rect().size
	pip_rect.size = PIP_SIZE * k
	pip_rect.position = Vector2(screen.x - (PIP_SIZE.x + 16.0) * k, 16.0 * k)
	var from := Vector3(-15.0, 13.0, 2.2)
	var look := Vector3(0.0, Field.RUBBER_Y, 1.3)
	for base: int in [3, 2, 1]:
		if game.base_empty(base):
			continue
		var bag := PlaySim.base_xy(base)
		var lead := bag + (PlaySim.base_xy(base + 1) - bag).normalized() * resolver.motion.leads[base - 1]
		look = Vector3(lead.x, lead.y, 1.0)
		# From foul ground behind the runner's base, a little up.
		var out := Vector2(bag.x, bag.y).normalized() * 12.0 + Vector2(signf(bag.x) * 4.0, -3.0)
		from = Vector3(bag.x + out.x, bag.y + out.y, 3.0)
		break
	pip_camera.look_at_from_position(Field.to_world(from), Field.to_world(look))


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
	_umpire_signals(t)


## The umpires' calls during a play: the base umpire nearest a close play signals safe or out,
## the plate umpire signals a foul ball, a base umpire circles his hand for a home run.
func _umpire_signals(t: float) -> void:
	var calls: Dictionary[Puppet, PuppetPose] = {}
	for c: PlayCall in _play.calls:
		if t < c.time or t > c.time + 1.6:
			continue
		var base := PlaySim.base_xy(c.base)
		var nearest := -1
		var best := INF
		for i: int in base_umpires.size():
			var u := Field.to_field(base_umpires[i].position)
			var d := Vector2(u.x - base.x, u.y - base.y).length()
			if d < best:
				best = d
				nearest = i
		if nearest >= 0:
			# At the plate the plate umpire makes the call.
			var who := umpire if c.base == 4 else base_umpires[nearest]
			calls[who] = PuppetClips.umpire_signal(&"out" if c.out else &"safe", t - c.time)
	if _play.result == PaResult.Kind.HOME_RUN and t > 1.0:
		calls[base_umpires[0]] = PuppetClips.umpire_signal(&"home_run", t - 1.0)
	if _play.foul:
		calls[umpire] = PuppetClips.umpire_signal(&"foul", t)
	if _play.infield_fly and t < INFIELD_FLY_SIGNAL:
		# Declared while the ball is up, by all of them.
		for u: Puppet in base_umpires:
			calls[u] = PuppetClips.umpire_signal(&"infield_fly", t)
		calls[umpire] = PuppetClips.umpire_signal(&"infield_fly", t)
	var everyone: Array[Puppet] = [umpire]
	everyone.append_array(base_umpires)
	for u: Puppet in everyone:
		signal_call(u, calls.get(u) as PuppetPose)


## Moves a puppet along its track: throwing, catching or sliding at its moments (docs/13
## S12), otherwise running at its pace facing the way it goes, or ready facing the ball.
func _move_puppet(p: Puppet, tl: PlayTimeline, key: String, t: float) -> void:
	var now := tl.position(key, t)
	var ahead := tl.position(key, t + 0.1)
	p.position = Field.to_world(Vector3(now.x, now.y, 0.0))
	var step := Vector2(ahead.x - now.x, ahead.y - now.y)
	var speed := step.length() / 0.1
	p.frame_time = _frame_time
	var here := Vector2(now.x, now.y)
	var m: PlayMoves.Moment = _moves.now(key, t) if _moves != null else null
	# On a steal the pitcher delivers and the catcher waits in his crouch for the pitch.
	if _running and key == "F:P" and t < RunningPlay.STEAL_LEAD_IN + 0.4 and _play.calls[0].base != 1:
		p.rotation.y = PI
		p.apply(PuppetClips.pitch(t - RunningPlay.STEAL_LEAD_IN + PuppetClips.PITCH_RELEASE))
		return
	if _running and key == "F:C" and t < RunningPlay.STEAL_LEAD_IN + RunningPlay.PITCH_FLIGHT:
		p.rotation.y = 0.0
		catch_at(p, PuppetClips.catcher(), p.to_local(Field.to_world(_ball_at(tl, t))), smoothstep(-0.3, -0.05, t - RunningPlay.STEAL_LEAD_IN - RunningPlay.PITCH_FLIGHT))
		return
	if m != null:
		match m.kind:
			PlayMoves.Kind.THROW:
				p.rotation.y = _yaw_toward(here, Vector2(m.at.x, m.at.y))
				p.apply(PuppetClips.throw_at(t - m.time))
				return
			PlayMoves.Kind.TAG:
				# Down to the bag with the ball in the glove, where the runner's foot comes.
				if here.distance_to(Vector2(m.at.x, m.at.y)) > 0.3:
					p.rotation.y = _yaw_toward(here, Vector2(m.at.x, m.at.y))
				var dt := t - m.time
				catch_at(p, PuppetClips.ground_catch(), p.to_local(Field.to_world(m.at)), smoothstep(-0.25, -0.05, dt) * (1.0 - smoothstep(0.2, 0.4, dt)))
				return
			PlayMoves.Kind.SLIDE:
				if here.distance_to(Vector2(m.at.x, m.at.y)) > 0.3:
					p.rotation.y = _yaw_toward(here, Vector2(m.at.x, m.at.y))
				var down := PuppetClips.head_first() if m.head_first else PuppetClips.slide()
				p.apply(down if t >= m.time - (0.3 if m.head_first else 0.15) else PuppetClips.run_at(_stride(p, speed), 1.0))
				return
			PlayMoves.Kind.CATCH:
				# Square to where the ball comes from; it may be off to one side of him.
				var coming := m.at - _ball_at(tl, m.time - 0.1)
				var from := Vector2(-coming.x, -coming.y)
				if from.length() < 0.05:
					from = Vector2(m.at.x - now.x, m.at.y - now.y)
				if from.length() > 0.05:
					p.rotation.y = _yaw_toward(Vector2.ZERO, from)
				# On the run his legs keep running under the catch.
				var legs := PuppetClips.run_at(_stride(p, speed), speed / SPRINT) if speed > RUN_POSE_SPEED else null
				catch(p, _ball_at(tl, t), t - m.time, legs)
				return
	if speed > RUN_POSE_SPEED:
		p.rotation.y = _yaw_toward(Vector2.ZERO, step)
		p.apply(PuppetClips.run_at(_stride(p, speed), speed / SPRINT))
	else:
		var ball := _ball_at(tl, t)
		p.rotation.y = _yaw_toward(here, Vector2(ball.x, ball.y))
		p.apply(PuppetClips.lead_off() if key.begins_with("R:") else PuppetClips.fielder_ready())


## Poses a fielder catching the ball at `ball` (field coordinates), dt seconds from the
## moment it arrives: a ground ball, a chest-high or an overhead catch, or a dive for one wide
## of him. The glove hand is then drawn to the ball itself (catch IK, docs/13 S12-8): from just
## before the ball arrives till just after, the glove's pocket is where the ball is.
static func catch(p: Puppet, ball: Vector3, dt: float, legs: PuppetPose = null) -> void:
	var local := p.to_local(Field.to_world(ball))
	var pose := PuppetClips.catch_for(local, ball.z)
	if legs != null and absf(local.x) <= PuppetClips.DIVE_WIDTH:
		pose.hips = legs.hips
		pose.hips_yaw = legs.hips_yaw
		pose.r_foot = legs.r_foot
		pose.l_foot = legs.l_foot
	catch_at(p, pose, local, smoothstep(-0.3, -0.05, dt) * (1.0 - smoothstep(0.1, 0.25, dt)))


## Poses p as `pose` with the glove's pocket drawn to `local` (in p's space) by `reach` (0 the
## pose as it is, 1 the pocket on the point).
static func catch_at(p: Puppet, pose: PuppetPose, local: Vector3, reach: float) -> void:
	p.apply(pose)
	if reach <= 0.0:
		return
	var base := pose.blend(pose, 0.0)
	var arm := (p.upper_arm + p.lower_arm) * 0.97
	for i: int in CATCH_IK_PASSES:
		pose.l_hand += local - p.glove_pocket()
		# Out of the arm's reach the body goes to the ball: lower for a grounder, up off the
		# ground for one over his head, over toward one wide of him.
		var shoulder: Vector3 = p.joints[&"LeftUpperArm"]
		var over := shoulder.distance_to(pose.l_hand) - arm
		if over > 0.0:
			var shift := ((pose.l_hand - shoulder).normalized() * over).limit_length(MAX_BODY_SHIFT)
			pose.hips += shift
			pose.hips.y = maxf(pose.hips.y, 0.4)
			pose.r_hand += shift
		p.apply(pose)
	if reach < 1.0:
		p.apply(base.blend(pose, reach))


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
	# Once the catcher has it the ball is in his mitt, wherever he takes it.
	if state == State.RESULT and _catcher_ball().is_finite() and not duel.bounced:
		ball_actor.show_at(Field.to_field(catcher.global_transform * catcher.glove_pocket()))


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
