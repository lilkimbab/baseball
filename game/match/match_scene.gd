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
## Fielders drifting back slower than this (m/s) under a fly ball backpedal; faster, they turn
## and run. Running puppets turn at most TURN_RATE rad/s: a first step, not a snap.
const BACKPEDAL_BELOW := 4.5
const TURN_RATE := 10.0


## Turns p toward `yaw` at `rate` rad/s at most: nobody faces about in a single frame.
func _turn(p: Puppet, yaw: float, rate: float = TURN_RATE) -> void:
	var gap := wrapf(yaw - p.rotation.y, -PI, PI)
	p.rotation.y += clampf(gap, -rate * _frame_time, rate * _frame_time)


## How fast (rad/s) a fielder squares up to a catch, a throw or a tag: half a turn in a
## seventh of a second. (These used to snap to the new facing in one frame: a fielder spun
## round 90 to 170 degrees between two frames 1.5 times a play.)
const QUICK_TURN := 22.0


## Recorded running by motion matching (approved proposal 4): the frame of the CMU runs that
## best fits where he is going — his speed and where the timeline has him in 0.2 and 0.4 s,
## in his own heading — played on and blended. False when the local pack has no recordings.
func _run_matched(p: Puppet, tl: PlayTimeline, key: String, t: float, here: Vector2, step: Vector2) -> bool:
	var mm := MotionMatcher.shared()
	if mm == null:
		return false
	var pb: MotionMatcher.Playback = _playbacks.get(p)
	if pb == null or _play_time - float(_playback_used.get(p, -9.0)) > 0.3:
		pb = MotionMatcher.Playback.new(mm)
		_playbacks[p] = pb
	_playback_used[p] = _play_time
	var heading := Basis(Vector3.UP, p.rotation.y).inverse()
	var local := func(field: Vector2) -> Vector2:
		var w := heading * (Field.to_world(Vector3(field.x, field.y, 0.0)) - Field.to_world(Vector3.ZERO))
		return Vector2(w.x, w.z)
	var soon := tl.position(key, t + 0.2)
	var later := tl.position(key, t + 0.4)
	var vel: Vector2 = local.call(step / 0.1)
	var p1: Vector2 = local.call(Vector2(soon.x, soon.y) - here)
	var p2: Vector2 = local.call(Vector2(later.x, later.y) - here)
	var frame := pb.step(_frame_time, vel, p1, p2)
	p.apply_joints(frame, mm.clips[pb.clip])
	return true


## A sprint (m/s): running poses are drawn from a jog at 0 to a sprint at this speed.
const SPRINT := 8.0


## Advances a puppet's running stride by this frame at `speed` m/s and returns where in the
## stride he is: one step per unit, steps lengthening from about a metre at a jog to two at a
## sprint, so the feet keep pace with the ground (docs/13 S12: no foot sliding).
func _stride(p: Puppet, speed: float) -> float:
	var step := lerpf(1.0, 2.0, clampf(speed / SPRINT, 0.0, 1.0))
	_strides[p] = _strides.get(p, 0.0) + speed * _frame_time / step
	return _strides[p]


## Seconds the crowd cheers a hit or a run, and claps an out.
const CHEER_TIME := 3.0
const CLAP_TIME := 1.6
## The umpires hold up the infield fly call this long (s) into the play.
const INFIELD_FLY_SIGNAL := 1.6
## The plate umpire calls time for this long (s) when play stops for a substitution.
const TIME_SIGNAL := 1.6


## Rounds of moving the glove hand by how far its pocket is from the ball.
const CATCH_IK_PASSES := 5
## The most (m) a catch moves the body toward a ball out of the arm's reach.
const MAX_BODY_SHIFT := 0.6
## The most a catch lifts him off the ground (m): a jump at the wall (the play has balls
## caught up to 2.9 m high).
const MAX_LEAP := 0.6
## Fielders step in this far (m) over the last CREEP_LEAD seconds before the release.
const CREEP := 0.6
const CREEP_LEAD := 0.7
## Runners' secondary lead: SHUFFLES shuffle steps of SHUFFLE m, each SHUFFLE_TIME s.
const SHUFFLE := 0.55
const SHUFFLES := 2
const SHUFFLE_TIME := 0.3
const ROSTER_PACK := "res://data/rosters/fiction-2026.json"
## The pack this game's two clubs come from (a quick game may pick a real season's from the
## local content pack; `-- --pack <path>` on the command line).
var roster_pack := ROSTER_PACK

@export var innings := 3
## Which team the player controls: 0 away, 1 home, -1 watch.
@export var human_team := 1
## The park to play in; empty for the home club's own (home_park).
@export var stadium_id := ""
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
## What the finished game paid the person playing ("승리 +150P"), for the screen after it.
var profile_lines := PackedStringArray()
var _profile_paid := false
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
var _club_cache: Array[Team] = []
## The broadcast's moments between pitches (docs/13 S16) and their cards.
var broadcast := Broadcast.new()
var broadcast_cards: BroadcastCards
var _seen_batter := ""
var _seen_pitcher := PackedStringArray(["", ""])
## The batting side's runs, hits and men left on at the start of the half (for its summary).
var _half_start := Vector3i.ZERO
## The play kept for its replay, and the stretch of it replayed.
var _replay_play: PlayResult
var _replay_moves: PlayMoves
var _replay_window := Vector2.ZERO
var _end_shown := false
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
var _dropped_bat: MeshInstance3D
## The batter lets go of the bat this long (s) into the play.
const BAT_DROPPED_AT := 0.2
## Seconds since the plate umpire called time (negative: he has not).
var _time_called := -1.0
var crowd: Crowd
## What the crowd last reacted to (runs and hits for each side, outs) and how long the
## reaction lasts yet.
var _crowd_seen := PackedInt32Array([0, 0, 0, 0, 0])
var _cheer_left := 0.0
var _clap_left := 0.0
var board_screen: ScoreboardScreen
var _board_clock := 0.0
var _board_shown := ""
## The play being shown is a steal or a pickoff (RunningPlay), not a ball in play; and it
## opens with its own pitch (a computer runner's steal) rather than at the catch.
var _running := false
var _running_pitch := false
## Each puppet's motion-matched running, and when it was last used.
var _playbacks: Dictionary[Puppet, MotionMatcher.Playback] = {}
var _playback_used: Dictionary[Puppet, float] = {}
## Where each running puppet is in his stride (steps).
var _strides: Dictionary[Puppet, float] = {}
## Where a right-handed batter stands in the box (field coordinates).
var _box := Vector3(-1.05, 0.25, 0.0)


func _ready() -> void:
	_read_arguments()
	_start_game()
	super._ready()
	_apply_weather()
	_box = Field.to_field(batter.position)
	_box.x = -absf(_box.x)
	_build_officials()
	_build_dropped_bat()
	_build_bullpen()
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
	_build_crowd()
	# The park's scoreboard shows this game.
	if park.scoreboard != null:
		board_screen = ScoreboardScreen.new()
		board_screen.scene = self
		board_screen.size = Vector2(park.scoreboard.size)
		park.scoreboard.add_child(board_screen)
	post_game = PostGame.new()
	post_game.scene = self
	layer.add_child(post_game)
	pause_menu = PauseMenu.new()
	pause_menu.scene = self
	layer.add_child(pause_menu)
	pause_menu.wants_substitutions.connect(func() -> void: toggle_menu(true))
	pause_menu.quit_requested.connect(leave)
	commentary = CommentaryIO.load_default()
	broadcast_cards = BroadcastCards.new()
	broadcast_cards.scene = self
	layer.add_child(broadcast_cards)
	broadcast.enabled = Settings.broadcast and DisplayServer.get_name() != "headless"
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
	_seen_batter = game.batter_id()
	_seen_pitcher = PackedStringArray([game.teams[0].pitcher_id, game.teams[1].pitcher_id])
	_half_start = _half_numbers()
	_push_pregame()


## Command-line choices: -- --innings 3|6|9 --team home|away|watch --seed n
func _read_arguments() -> void:
	Settings.ensure_loaded()
	Settings.apply_rendering(get_tree())
	pitch_clock_on = Settings.pitch_clock
	auto_changes = Settings.auto_changes
	if QuickMatchScreen.pending:
		QuickMatchScreen.pending = false
		from_menu = true
		innings = Settings.innings
		human_team = QuickMatchScreen.side_index()
		away_index = QuickMatchScreen.away_index
		home_index = QuickMatchScreen.home_index
		roster_pack = QuickMatchScreen.roster_path()
		stadium_id = QuickMatchScreen.park
		time_of_day = StringName(QuickMatchScreen.time)
		return
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	if args.has("innings"):
		innings = int(str(args["innings"]))
	if args.has("team"):
		human_team = {"away": 0, "home": 1, "watch": -1}.get(str(args["team"]), human_team)
	if args.has("seed"):
		seed_value = int(str(args["seed"]))
	if args.has("park"):
		stadium_id = str(args["park"])
	if args.has("time"):
		time_of_day = StringName(str(args["time"]))
	if args.has("pack"):
		roster_pack = str(args["pack"])
	if args.has("away"):
		away_index = int(str(args["away"]))
	if args.has("home"):
		home_index = int(str(args["home"]))


func _start_game() -> void:
	var catalog_all := PitchCatalogIO.load_default()
	var env := LeagueEnvIO.load_default()
	var ovr := LeagueEnvIO.load_overall()
	_clubs = RosterIO.load_pack(roster_pack)
	_club_cache = []
	var away :=_clubs[clampi(away_index, 0, _clubs.size() - 1)]
	var home := _clubs[clampi(home_index, 0, _clubs.size() - 1)]
	var rules := RuleSet.kbo_2026() if innings >= 9 else RuleSet.short_game(innings)
	if innings <= 2:
		# A practice game (one inning: bat in the top, pitch in the bottom as the visitors)
		# ends when its innings do, tied or not.
		rules.extra_inning_limit = innings
	manager = AiManager.new(env, catalog_all, ovr)
	manager.use_bullpen_plan(away)
	manager.use_bullpen_plan(home)
	game = GameState.new()
	game.rules = rules
	game.teams = [manager.make_lineup(away, rules, away.next_starter().id), manager.make_lineup(home, rules, home.next_starter().id)]
	resolver = PhysicalResolver.new(env, catalog_all, manager, Rng.new(seed_value).fork(5))
	# The home club's park, drawn and played in alike.
	stadium = StadiumIO.load_park(stadium_id) if stadium_id != "" else home_def(home)
	resolver.use_park(stadium)
	scorer = Scorer.new()
	GameFlow.start(game)
	scorer.start(game)
	manager.start_game(game)
	_chosen_team = human_team if human_team >= 0 else 1
	balls = 0
	strikes = 0


## When a season's game is played (docs/13 S13): weekday games at 18:30 under the lights,
## Saturday's at 17:00, Sunday's at 14:00. The week runs Tuesday to Sunday, Monday off.
static func time_for(game_day: int) -> StringName:
	match Schedule.calendar_day(game_day) % 7:
		4:
			return &"dusk"
		5:
			return &"day"
	return &"night"


# --- The crowd (docs/13 S14) ---


## How full the park is: night games on weekdays draw fewer than weekend ones.
func crowd_fill() -> float:
	return 0.6 if time_of_day == &"night" else 0.85


func _build_crowd() -> void:
	crowd = Crowd.new(park)
	crowd.fill = crowd_fill()
	crowd.density = [0.3, 0.6, 1.0][clampi(Settings.quality, 0, 2)]
	crowd.seed_value = seed_value
	for side: int in 2:
		var t := _club(side)
		if t == null:
			continue
		var jersey := UniformStyle.for_team(t, side == 1).jersey
		var colours: Array[Color] = [jersey, t.primary, t.primary, t.accent]
		if side == 1:
			crowd.home_colours = colours
		else:
			crowd.away_colours = colours
	add_child(crowd)


## The crowd follows the game: the batting side's cheering section is on its feet, cheers with
## its arms up when its team gets a hit or a run, and the fielding side's claps an out.
func _crowd_react(delta: float) -> void:
	if crowd == null or game == null:
		return
	crowd.tick(delta)
	var hits := scorer.book.hits
	var now := PackedInt32Array([game.score[0], game.score[1], hits[0], hits[1], game.outs])
	var batting := game.batting()
	if now[batting] > _crowd_seen[batting] or now[2 + batting] > _crowd_seen[2 + batting]:
		_cheer_left = CHEER_TIME
	if now[4] > _crowd_seen[4]:
		_clap_left = CLAP_TIME
	_crowd_seen = now
	_cheer_left = maxf(_cheer_left - delta, 0.0)
	_clap_left = maxf(_clap_left - delta, 0.0)
	var home_bats := batting == GameState.HOME and not game.over
	var away_bats := batting == GameState.AWAY and not game.over
	var up := Crowd.State.CHEERING if _cheer_left > 0.0 else Crowd.State.STANDING
	var fielding_mood := Crowd.State.CLAPPING if _clap_left > 0.0 else Crowd.State.SEATED
	crowd.set_zone(Crowd.Zone.HOME_CHEER, up if home_bats else fielding_mood)
	crowd.set_zone(Crowd.Zone.AWAY_CHEER, up if away_bats else fielding_mood)
	var side_cheer := _cheer_left > 0.0
	crowd.set_zone(Crowd.Zone.FIRST, Crowd.State.CHEERING if side_cheer and home_bats else Crowd.State.SEATED)
	crowd.set_zone(Crowd.Zone.THIRD, Crowd.State.CHEERING if side_cheer and away_bats else Crowd.State.SEATED)


## A season's game in the home club's park at its time of day.
func _play_at_home(home_club: String, game_day: int, club: Team = null) -> void:
	stadium = home_def(club) if club != null else StadiumIO.load_park(home_park(home_club))
	resolver.use_park(stadium)
	time_of_day = time_for(game_day)
	game_day_of_season = game_day


# --- The weather (docs/08 R3) ---


## The day of the season this game is played on (a quick game: one drawn from its seed).
var game_day_of_season := -1
var weather: Weather


## Draws this game's weather and puts it into everything that feels it: the air and the wind
## the ball flies through (the resolver's and the scene's physics alike), the outfielders'
## depth, the flags, the light, and a line at the start of the game.
func _apply_weather() -> void:
	var day := game_day_of_season if game_day_of_season >= 0 else posmod(seed_value * 7, 180)
	var park_def := stadium if stadium != null else park.def
	weather = Weather.for_game(park_def, day, time_of_day, Rng.new(hash("%s:%d:%d" % [park_def.id, day, seed_value])))
	resolver.cfg = weather.physics(PhysicsConfigIO.load_default(), park_def.orientation_deg)
	resolver.wind_out = weather.wind_out(park_def.orientation_deg)
	cfg = resolver.cfg
	park.show_wind(resolver.cfg.wind)
	if lighting != null:
		lighting.set_cover(weather.cover)
	last_text = "오늘 날씨 · " + weather.describe(park_def.orientation_deg)


## A club's own park: one of the park models (home_park), standing in a setting of its own —
## one of the kinds of backdrop, laid out from the club's id — with seats and walls in the
## club's colours. Seventeen models by thirteen settings: no two clubs have the same home.
static func home_def(team: Team) -> StadiumDef:
	var def := StadiumIO.load_park(home_park(team.id))
	def.place_seed = team.id
	if def.roof != &"dome":
		var kinds: Array = Backdrop.KINDS.keys()
		def.backdrop = kinds[absi(hash(team.id + ":view")) % kinds.size()]
	var colour := team.primary if team.primary.get_luminance() < 0.6 else team.accent
	def.seat_color = colour.lerp(Color(0.3, 0.33, 0.4), 0.3)
	def.wall_color = colour.darkened(0.55)
	def.name = "%s %s" % [team.short_name, def.name]
	return def


## The park a club plays its home games in: each club has one of the parks, always the same.
static func home_park(club_id: String) -> String:
	var ids := StadiumIO.ids()
	if ids.is_empty():
		return StadiumIO.DEFAULT
	return ids[absi(hash(club_id)) % ids.size()]


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
	return (_play_time < 0.0 or _play_time < 0.9) and highlight() == null


func plate_marks_visible() -> bool:
	return _play_time < 0.0


func help_keys() -> String:
	if steal_base() > 0:
		return "Shift 도루(투수가 움직일 때 떼기)   Space 번트   F 작전·교체   Esc 종료"
	return "Space 번트   F 작전·교체   F3 관전   Esc 종료"


func selected_type() -> PitchType:
	if _arsenal.is_empty():
		return super.selected_type()
	return _arsenal[clampi(selected_pitch, 0, _arsenal.size() - 1)].type


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if skip_broadcast(event):
		return
	if key != null and key.pressed and not key.echo and (key.keycode == KEY_ESCAPE or key.keycode == KEY_ENTER):
		_menu_key(key.keycode)
		get_viewport().set_input_as_handled()
		return
	if pause_menu.visible or menu.visible:
		return
	if key != null and not key.echo and choice_key(key.keycode, key.pressed):
		get_viewport().set_input_as_handled()
		return
	if key != null and not key.echo and manual_key(key.keycode, key.pressed):
		get_viewport().set_input_as_handled()
		return
	if key != null and not key.echo and key.keycode == KEY_SHIFT and steal_key(key.pressed):
		get_viewport().set_input_as_handled()
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


# --- The player's throw and running during a play (docs/05 2.3, 2.4; docs/13 S12) ---


## Seconds to fill the throw gauge to the top of its green zone.
const THROW_CHARGE_TIME := 0.6
## The choice stays open this long (s) after the first fielder has the ball.
const DECIDE_GRACE := 0.2
const THROW_KEYS := {KEY_RIGHT: 1, KEY_UP: 2, KEY_LEFT: 3, KEY_DOWN: 4}

## What the player has chosen in this play, and whether he still can: until the first
## fielder has the ball (`_decide_at`), keys pressed early count (pre-input).
var _choice: PlayChoice
var _choice_open := false
var _decide_at := 0.0
## The throw gauge while an arrow key is held (−1 when none is), and the base it is for.
var _charge := -1.0
var _charge_base := 0


# --- Highlights and the player's own fielding (docs/05 2.3, 3.4) ---

## The slow-motion moments of the play being shown (PlayHighlight), the player's balls in play
## since the last one, real seconds the picture still stands, how fast the play ran in the
## last step, and whether the camera was on the highlight in the last frame.
var _highlights: Array[PlayHighlight] = []
var _rested := PlayHighlight.REST
var _freeze := 0.0
var _pace := 1.0
var _close := false
## The player's own fielder (null when the fielders field by themselves): his until
## `_manual_until`, when a team-mate has the ball instead. Once he has it the player has
## THROW_WAIT s to press a throw key (THROW_HOLD s to let go of one held).
var _manual: ManualFielding
var _manual_until := 0.0
const THROW_WAIT := 0.35
const THROW_HOLD := 0.8
## Where a test pushes the player's fielder (field x, y); NAN: the keys.
var manual_push := Vector2(NAN, NAN)


## The highlight the play is in now, or null.
func highlight() -> PlayHighlight:
	if _play == null or _play_time < 0.0:
		return null
	for h: PlayHighlight in _highlights:
		if h.showing(_play_time):
			return h
	return null


## The bat is still on the ball: the batter finishes his swing in the slow picture.
func _contact_shown() -> bool:
	var h := highlight()
	return h != null and h.kind == PlayHighlight.Kind.CONTACT


## Looks for the play's slow-motion moments: only for the player at bat, watching the other
## side field.
func _find_highlights() -> void:
	_highlights.clear()
	_freeze = 0.0
	_close = false
	if not _controls_running() or _play == null or _play.foul:
		return
	var exit := duel.contact.exit_speed_kmh() if duel.contact != null else 0.0
	if Settings.highlights:
		_highlights = PlayHighlight.of(_play, exit, _rested)
	_rested = 0 if not _highlights.is_empty() else _rested + 1
	if not _highlights.is_empty() and _highlights[0].kind == PlayHighlight.Kind.CONTACT:
		_freeze = _highlights[0].freeze


## How fast the play runs in this step (1 its own speed, 0 while the picture stands still).
func _play_pace(delta: float) -> float:
	if _freeze > 0.0:
		_freeze -= delta
		return 0.0
	var h := highlight()
	return h.pace_at(_play_time) if h != null else 1.0


## The player's own fielder in this play, if he fields by hand: the one the ball is hit to.
## The play is worked out again as it goes if he never gets to it (a team-mate backs him up);
## that is what is shown until he does.
## The own fielder takes the ball without the catch key (tools that steer him).
var manual_auto_catch := false


func _open_manual() -> void:
	_manual = null
	if not Settings.manual_fielding or not _controls_fielding() or _play == null or _play.foul:
		return
	var kind := chasing_fielder()
	if kind == Position.Kind.DH or _play.result == PaResult.Kind.HOME_RUN or resolver.last_context == null:
		return
	var ctx := resolver.last_context
	_manual = ManualFielding.make(ctx.fielders[kind], resolver.motion, ctx.field)
	_manual.auto_catch = manual_auto_catch
	_manual.write(_choice)
	_replay()
	# His until a team-mate has it, or the ball is dead.
	_manual_until = _play.timeline.duration
	var ball: PackedVector4Array = _play.timeline.tracks.get("ball", PackedVector4Array())
	if not _play.timeline.throws.is_empty():
		_manual_until = _play.timeline.throws[0][0].x
	elif not ball.is_empty():
		_manual_until = ball[ball.size() - 1].x
	for key: String in _moves.by_key:
		if not key.begins_with("F:"):
			continue
		for m: PlayMoves.Moment in _moves.by_key[key]:
			if m.kind == PlayMoves.Kind.CATCH:
				_manual_until = minf(_manual_until, m.time)
	_choice_open = true
	_decide_at = INF


## The player's own fielder is still his to move (he has not got the ball, nor has anyone).
func manual_chasing() -> bool:
	return _manual != null and not _manual.got and _play_time < _manual_until


func manual_fielder() -> ManualFielding:
	return _manual


## Where the player pushes his fielder, in field x and y: W away from the camera, S toward
## it, A and D to its left and right.
func _manual_wish() -> Vector2:
	if not is_nan(manual_push.x):
		return manual_push
	var push := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		push.y += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		push.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		push.x += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		push.x -= 1.0
	if push == Vector2.ZERO:
		return push
	var ahead := Field.to_field(camera.global_position - camera.global_basis.z) - Field.to_field(camera.global_position)
	var forward := Vector2(ahead.x, ahead.y).normalized()
	if forward == Vector2.ZERO:
		forward = Vector2(0.0, 1.0)
	return (forward * push.y + Vector2(forward.y, -forward.x) * push.x).normalized()


## Space: the player's fielder dives (or leaps) for the ball. True when the key was his.
func manual_key(code: Key, pressed: bool) -> bool:
	if _manual == null or (code != KEY_SPACE and code != KEY_C):
		return false
	if pressed and manual_chasing():
		if code == KEY_C:
			_manual.press_catch(_play_time)
		else:
			_manual.dive(_play_time, duel.path)
	return true


func _tick_manual(dt: float) -> void:
	if _manual == null or not _choice_open:
		return
	if not _manual.got:
		if _play_time < _manual_until:
			if _manual.step(_play_time, dt, _manual_wish(), duel.path):
				# He has it: the throw goes where the player says (or already said).
				_decide_at = _play_time if _choice.throw_to > 0 else _play_time + THROW_WAIT
		elif _decide_at == INF:
			# A team-mate has it: the play goes on as it was going.
			_decide_at = _play_time + DECIDE_GRACE
		return
	# With the ball: he waits a moment for the throw key, longer while one is held.
	if _choice.throw_to > 0:
		_decide_at = minf(_decide_at, _play_time)
	elif _charge >= 0.0:
		_decide_at = maxf(_decide_at, minf(_manual.got_time + THROW_HOLD, _play_time + 0.05))


## Where everyone is shown now (track key to field position), for taking up a play worked
## out again without anyone jumping.
func _shown_places() -> Dictionary[String, Vector3]:
	var places: Dictionary[String, Vector3] = {}
	if _play == null or _play_time <= 0.0:
		return places
	for key: String in _play.timeline.tracks:
		if key != "ball":
			places[key] = _play.timeline.position(key, _play_time)
	if _manual != null:
		places["F:%s" % Position.code(_manual.kind)] = Vector3(_manual.pos.x, _manual.pos.y, 0.0)
	return places


## Works the play out again with what the player has chosen so far and goes on from there.
func _replay() -> void:
	var places := _shown_places()
	if _manual != null:
		_manual.write(_choice, _play_time)
	var events := resolver.replay_ball(game, duel, _choice)
	_play = resolver.last_play
	if not places.is_empty():
		# Runners the new play leaves on their bases go back to them.
		for i: int in 3:
			var key := "R:%s" % _runners_at_start[i]
			if _runners_at_start[i] != "" and places.has(key) and not _play.timeline.tracks.has(key):
				var bag := PlaySim.base_xy(i + 1)
				_play.timeline.add(key, 0.0, Vector3(bag.x, bag.y, 0.0))
		var length := _play.timeline.duration
		_play.timeline = PlayTimeline.stitched(_play.timeline, _play_time, places)
		_play.timeline.duration = length
	# (Read from the timeline as it will be shown, after the stitch.)
	_moves = PlayMoves.read(_play.timeline, _play.calls)
	_pending = events


# --- The player's steal (docs/05 2.4) ---


## The jump a runner gets by letting go of the key against the pitcher's first move (the
## start of the delivery): best within GOOD_GO s of it, worse the later; early, the pitcher
## sees him leave. Seconds better than a computer runner's start.
const GOOD_GO := 0.15
const BEST_JUMP := 0.15
const LATE_COST := 0.5
const EARLY_JUMP := -0.3

var _steal_held := false
var _steal_from := 0
## The jump of the steal on this pitch (NAN when there is none), and the pitch clock when he
## went.
var _steal_jump := NAN
var _steal_go_at := 0.0


## The base the player's runner could steal from now (0 when none can): first with second
## open, else second with third open and fewer than two out.
func steal_base() -> int:
	if not human_bats() or _play_time >= 0.0 or not (state == State.PRE_PITCH or state == State.WINDUP):
		return 0
	for base: int in [1, 2]:
		if game.runner_on(base) != null and game.base_empty(base + 1) and not (base == 2 and game.outs == 2):
			return base
	return 0


func steal_jump() -> float:
	return _steal_jump


## Shift held, then let go as the pitcher starts his delivery. True when the key was taken.
func steal_key(pressed: bool) -> bool:
	if pressed:
		var base := steal_base()
		if base == 0 or not is_nan(_steal_jump):
			return false
		_steal_held = true
		_steal_from = base
		return true
	if not _steal_held:
		return false
	_steal_held = false
	if state == State.LIVE or (_pitch_clock >= 0.0 and _pitch_clock > release_time()):
		return true
	_steal_jump = EARLY_JUMP if _pitch_clock < 0.0 else BEST_JUMP - LATE_COST * maxf(_pitch_clock - GOOD_GO, 0.0)
	_steal_go_at = maxf(_pitch_clock, 0.0)
	resolver.human_steal = _steal_from
	banner = "도루 시도!"
	banner_time = 1.2
	return true


## After a pitch the catcher held: the player's runner, already going, is thrown on.
func _finish_steal() -> bool:
	var jump := _steal_jump
	_steal_jump = NAN
	_steal_held = false
	if is_nan(jump) or game.over or game.runner_on(_steal_from) == null:
		return false
	var e := resolver.human_steal_event(game, _steal_from, jump)
	if e == null:
		return false
	if e.fielders == "E2":
		_apply(e)
		banner = last_text
		banner_time = 2.2
		return false
	var m := e.moves[0]
	var cover := Position.Kind.SS if _steal_from == 1 else Position.Kind.B3
	var margin := resolver.steal_margin(game, _steal_from) + jump
	var play := RunningPlay.steal(_steal_from, game.runner_on(_steal_from).player_id, not m.is_out(), margin, cover, _stands.get(cover, PlaySim.base_xy(_steal_from + 1)), resolver.motion, false)
	_play = play
	_moves = PlayMoves.read(play.timeline, play.calls, false)
	_running = true
	_running_pitch = false
	_play_time = 0.0
	_pending.clear()
	_pending.append(e)
	_runners_at_start = [_id_on(1), _id_on(2), _id_on(3)]
	_batter_at_start = ""
	_enter(State.RESULT)
	return true


## The player's team is in the field / at bat in this play.
func _controls_fielding() -> bool:
	return human_team >= 0 and game.fielding() == human_team and not _running


func _controls_running() -> bool:
	return human_team >= 0 and game.batting() == human_team and not _running


func choice_open() -> bool:
	return _choice_open


func choice() -> PlayChoice:
	return _choice


## Where the throw gauge is (0 to PlayChoice.FULL), or −1 when no throw key is held.
func charge() -> float:
	return _charge


func charging_base() -> int:
	return _charge_base


func _open_choice() -> void:
	_choice = PlayChoice.new()
	_charge = -1.0
	_choice_open = false
	if not (_controls_fielding() or _controls_running()):
		return
	# Open until the first fielder has the ball, and a moment after.
	var first := INF
	for key: String in _moves.by_key:
		if not key.begins_with("F:"):
			continue
		for m: PlayMoves.Moment in _moves.by_key[key]:
			if m.kind == PlayMoves.Kind.CATCH:
				first = minf(first, m.time)
	if first == INF:
		return
	_decide_at = first + DECIDE_GRACE
	_choice_open = true


## A key during a play: an arrow held and let go to throw (fielding), E or Q for the runners
## (batting). True when it was taken.
func choice_key(code: Key, pressed: bool) -> bool:
	if not _choice_open:
		return false
	if _controls_fielding() and THROW_KEYS.has(code):
		var base: int = THROW_KEYS[code]
		if pressed:
			_charge = 0.0
			_charge_base = base
		elif _charge >= 0.0 and base == _charge_base:
			_choice.throw_to = base
			_choice.gauge = _charge
			_charge = -1.0
		return true
	if _controls_running() and (code == KEY_E or code == KEY_Q):
		if pressed:
			_choice.running = 1 if code == KEY_E else -1
		return true
	return false


func _tick_choice(delta: float) -> void:
	if not _choice_open:
		return
	if _charge >= 0.0:
		_charge = minf(_charge + delta * PlayChoice.GREEN.y / THROW_CHARGE_TIME, PlayChoice.FULL)
	if _play_time >= _decide_at:
		_lock_choice()


## The fielder has the ball: the play goes on with what the player chose. A key still held
## throws where it points, with the gauge where it is.
func _lock_choice() -> void:
	_choice_open = false
	if _charge >= 0.0:
		_choice.throw_to = _charge_base
		_choice.gauge = _charge
		_charge = -1.0
	if not _choice.has_any():
		return
	_replay()
	# From here the fielders play it out by themselves.
	_manual = null


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
		Loading.go(get_tree(), Screen.HUB, {"title": "로비로 이동 중"})
	else:
		get_tree().quit()


## What the screen after the game says the keys do (key, then what it does; PostGame shows
## them as key caps, and what the game paid above them).
func post_game_hint() -> String:
	return "Enter 다시 하기   Esc 끝내기"


## The game is over: points and experience for the person playing (Profile), once. Not when
## he only watched, and not without a display (tests leave the profile alone).
func _pay_profile() -> void:
	if _profile_paid or game == null or not game.over:
		return
	_profile_paid = true
	var mine := own_team()
	if mine < 0 or DisplayServer.get_name() == "headless" or Profile.tool_run():
		return
	var bat := scorer.book.team_batting(mine)
	var pit := scorer.book.team_pitching(mine)
	profile_lines = Profile.record_game(game.winner == mine, {"hits": bat.hits, "home_runs": bat.home_runs, "runs": game.score[mine], "strikeouts": pit.strikeouts}, profile_share(), played_level())
	profile_lines.append_array(Achievements.note_game(feats, game, scorer.book, played_level(), stadium.id if stadium != null else ""))


## What the achievements count of this game (GameFeats), from its first event.
var feats: GameFeats
## The easiest difficulty the person played a pitch at in this game (−1: none yet).
var _person_level := -1


## Whose lines count for the achievements ("" his whole side; a career, the player's own).
func feats_player() -> String:
	return ""


## The difficulty this game pays at: the easiest he played a pitch at; a game he only watched
## or managed without stepping in pays 프로's at most (Difficulty.reward).
func played_level() -> int:
	if _person_level >= 0:
		return _person_level
	return mini(Difficulty.by_id(Settings.difficulty), Difficulty.Level.PRO)


## How much of a full game's points this one pays: the share of nine innings played (a
## three-inning game paid as much as nine, and was the quickest way to the shop).
func profile_share() -> float:
	return clampf(float(game.rules.innings) / 9.0, 0.3, 1.0) if game != null else 1.0


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
	_person_flags()
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


## The club's letter on the cap and helmet (the first letter of its nickname in English).
func _logo(puppet: Puppet, team: int) -> void:
	var model := puppet as SkinnedPuppet
	if model == null or _styles.is_empty():
		return
	model.set_logo(_styles[team].cap_letter, _styles[team].cap_ink())


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
	if play != null:
		# Hit (or fouled off): the runner's start went into the play, or he goes back.
		_steal_jump = NAN
		_steal_held = false
	banner = _pitch_banner(events)
	if play != null and not play.foul:
		# How a ball in play turns out is seen, not told beforehand (the line comes when the
		# play is over); only what the umpire declares while the ball is in the air is.
		banner = "인필드 플라이" if play.infield_fly else ""
	banner_time = 2.4
	if play != null and not play.foul:
		_play = play
		_moves = PlayMoves.read(play.timeline, play.calls)
		_play_time = 0.0
		_pending = events
		_runners_at_start = [_id_on(1), _id_on(2), _id_on(3)]
		_batter_at_start = game.batter_id()
		# Everyone eases from how he stood at contact into the play (the pitcher's follow-
		# through, the infielders' ready crouch, the batter's swing).
		_doing.clear()
		for p: Puppet in _cast():
			_doing[p] = &"between"
		_box_left = -1.0
		_open_choice()
		_open_manual()
		_find_highlights()
		# The picture cuts to the play's camera at contact, as a broadcast does (it swooped in
		# from the pitching camera out in centre field, ten metres a frame).
		_cut = true
		_drop_bat()
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
	# A pitch that got by the catcher is shown before the runners move up.
	var loose: GameEvent = null
	for e: GameEvent in events:
		if e.kind == GameEvent.Kind.WILD_PITCH or e.kind == GameEvent.Kind.PASSED_BALL:
			loose = e
			continue
		if loose == null:
			_apply(e)
	if loose != null and shows_running_plays() and _show_loose_ball(events, loose):
		return
	if loose != null and not shows_running_plays():
		var after := false
		for e: GameEvent in events:
			after = after or e == loose
			if after:
				_apply(e)
	if _finish_steal():
		return
	_enter(State.RESULT)


## Steals, pickoffs and wild pitches are shown on the field (not only reported) when the game
## is being watched pitch by pitch; a manager's summary only reports them.
func shows_running_plays() -> bool:
	return true


## Shows a wild pitch or passed ball: the events from `loose` on wait until it is over.
func _show_loose_ball(events: Array[GameEvent], loose: GameEvent) -> bool:
	var runners: Array[String] = [_id_on(1), _id_on(2), _id_on(3)]
	var side := -1.0 if duel.ball.pos.x < 0.0 else 1.0
	_play = RunningPlay.loose_ball(runners, duel.ball.pos, side, resolver.motion)
	_moves = PlayMoves.read(_play.timeline, _play.calls, false)
	_running = true
	_running_pitch = false
	_play_time = 0.0
	_pending.clear()
	var after := false
	for e: GameEvent in events:
		after = after or e == loose
		if after:
			_pending.append(e)
	_runners_at_start = runners
	_batter_at_start = ""
	_steal_jump = NAN
	_enter(State.RESULT)
	return true


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
	if broadcast.holding():
		broadcast.step(delta)
		return
	_run_pitch_clock(delta)
	if game.over and broadcast.enabled and not _end_shown:
		_end_shown = true
		var seg := Broadcast.segment(Broadcast.Kind.GAME_END)
		seg.shots = [Broadcast.Shot.make(0.0, Vector3(0.0, -30.0, 14.0), Vector3(0.0, 20.0, 1.0), 50.0, Vector3(0.0, -42.0, 22.0), Vector3(0.0, 30.0, 0.0), 54.0)]
		broadcast.push(seg)
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
		_pace = _play_pace(delta)
		var dt := delta * _pace
		_play_time += dt
		if _contact_shown():
			# The swing goes on through the ball, as slowly as the picture.
			_swing_clock += dt
			if swing_motion != null:
				swing_motion.advance(dt)
		_tick_manual(dt)
		_tick_choice(delta)
		state_time = 0.0
		banner_time = maxf(banner_time - delta, 0.0)
		if _play_time >= _play.timeline.duration + PLAY_TAIL:
			_end_play()
		return
	super.step(delta)


func _end_play() -> void:
	_play_time = -1.0
	_doing.clear()
	_manual = null
	_highlights.clear()
	_pace = 1.0
	_dropped_bat.visible = false
	_running = false
	_running_pitch = false
	_choice_open = false
	_charge = -1.0
	for e: GameEvent in _pending:
		_apply(e)
	_pending.clear()
	if _play != null and not _play.foul:
		banner = last_text
		banner_time = 2.6
	if _play != null and broadcast.enabled and _replay_wanted():
		if _play.result == PaResult.Kind.HOME_RUN:
			_push_replay(_play, &"home_run")
		elif _play.hard_made and _play.hard_odds <= PlayHighlight.DOUBTFUL_CATCH:
			_push_replay(_play, &"catch")
	_play = null
	_enter(State.RESULT)


## Applies an event to the game and the books.
func _apply(e: GameEvent) -> void:
	var batter := game.batter_id()
	var out := GameFlow.apply(game, e)
	last_outcome = out
	if feats == null and own_team() >= 0:
		feats = GameFeats.for_side(own_team(), feats_player())
	if feats != null:
		feats.note(game, e, out)
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
			# The wind is part of the story of a long fly (docs/08 R3): carried out by it, or
			# held up by it at the wall.
			var wind: float = resolver.wind_out if resolver != null else 0.0
			var deep: bool = duel != null and duel.contact != null and duel.contact.exit_speed_kmh() > 150.0
			if key == "home_run" and wind > 2.5:
				key = "home_run_wind"
			elif key == "fly_out" and wind < -2.5 and deep:
				key = "fly_out_wind"
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
				var line := "%s 투수 교체: %s" % [t.short_name, who.name if who != null else e.in_id]
				# (The event is applied by now: how warm he came in is known.)
				var warm := float(game.entered_warmth.get(e.in_id, 1.0))
				if warm < 0.6:
					line += " — 몸을 다 풀지 못하고 올라옵니다"
				elif warm >= 0.95:
					line += " — 불펜에서 충분히 몸을 풀었습니다"
				return line
			return "%s 교체: %s" % [t.short_name, who.name if who != null else e.in_id]
	return ""


## The duel HUD's mode follows the player's role this half-inning.
func _sync_mode() -> void:
	mode = &"bat" if human_bats() else (&"pitch" if human_pitches() else &"watch")
	# Taken over in the middle of a plate appearance (an intervention): this pitch is his too.
	if duel != null and duel.phase == PitchDuel.Phase.READY:
		if human_bats() and resolver.person_bats != game.batting():
			duel.settings.dodge = 0.0
			Difficulty.for_batter(duel.settings, resolver.difficulty)
		if human_pitches() and resolver.person_pitches != game.fielding():
			Difficulty.for_pitcher(duel.settings, resolver.difficulty)
	_person_flags()


## A tired arm's ring closes quicker, and a cold reliever's (DuelScene._roll_gauge): up to a
## quarter at the end of his limit. With a runner in scoring position the pressure tells too,
## the more the less composed he is (위기관리, PitchingRatings.composure): up to an eighth quicker.
func gauge_pace() -> float:
	if game == null:
		return 1.0
	var team := game.fielding_team()
	var pitcher := team.player(game.pitcher_id())
	if pitcher == null or pitcher.pitching == null:
		return 1.0
	var pace := 1.0 + 0.25 * clampf(StatResolver.fatigue(game, team, pitcher, true), 0.0, 1.0)
	if game.runner_on(2) != null or game.runner_on(3) != null:
		pace += 0.125 * (1.0 - clampf(pitcher.pitching.composure / 99.0, 0.0, 1.0))
	return pace


## The command of the pitch picked on the wheel (each pitch of his arsenal has its own).
func pitch_command() -> float:
	if selected_pitch >= 0 and selected_pitch < _arsenal.size():
		return _arsenal[selected_pitch].command
	return settings.command


## Tells the resolver which of the coming duel the person makes (his swing, his pitch), and
## at what difficulty (Difficulty, from the settings).
func _person_flags() -> void:
	if resolver == null or game == null:
		return
	resolver.difficulty = Difficulty.by_id(Settings.difficulty)
	resolver.person_bats = game.batting() if human_bats() else -1
	resolver.person_pitches = game.fielding() if human_pitches() else -1
	if human_bats() or human_pitches():
		_person_level = resolver.difficulty if _person_level < 0 else mini(_person_level, resolver.difficulty)


func _after_result() -> void:
	if _drain():
		return
	if game.over:
		return
	var half := _half_name()
	var new_half := half != _half_key
	if new_half:
		_half_key = half
		_dress_for_half()
		if _broadcast_between():
			_push_half()
		else:
			banner = half
			banner_time = TRANSITION
			_between = TRANSITION
	_new_duel()
	_enter(State.PRE_PITCH)
	_place_cast()
	_sync_mode()
	_snap_camera()
	_push_people(new_half)


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
	if not shows_running_plays():
		return false
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
	_running_pitch = true
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


# --- The bullpens (docs/08 R4) ---

## The player's own pitch is made as tired, and as cold, as his pitcher is (the computer's
## pitches are, in _ai_pitch_decision).
func _begin_windup() -> void:
	super._begin_windup()
	if human_pitches() and decision != null and resolver != null:
		resolver.tire(game, decision)


## A pitcher for each bullpen mound, throwing while his manager has him warming up: the away
## side's in left field, the home side's in right. Posed thirty times a second, and only
## when the camera can see him.
var _bullpen_puppets: Array[Puppet] = []
var _bullpen_who: PackedStringArray = PackedStringArray()
var _bullpen_clock := 0.0
var _bullpen_due := 0.0
const BULLPEN_RATE := 1.0 / 30.0
## A delivery, then a breath and the ball back from the catcher.
const BULLPEN_CYCLE := PuppetClips.PITCH_LENGTH + 2.2


func _build_bullpen() -> void:
	for i: int in 4:
		var p := _add_puppet(Vector3.ZERO, 0.0, Color(0.93, 0.93, 0.95), Color(0.1, 0.15, 0.35), use_models)
		p.visible = false
		_bullpen_puppets.append(p)
		_bullpen_who.append("")


## The mound for team t's lane-th man: [centre, facing], or [] when the park has none.
func _bullpen_spot(t: int, lane: int) -> Array:
	var side := 1.0 if t == GameState.HOME else -1.0
	for spot: Array in park.bullpen_spots:
		if float(spot[0]) == side and int(spot[1]) == lane:
			return [spot[2], spot[3]]
	return []


func _show_bullpen(delta: float) -> void:
	if _bullpen_puppets.is_empty() or game == null:
		return
	_bullpen_clock += delta
	_bullpen_due -= delta
	var pose_now := _bullpen_due <= 0.0
	if pose_now:
		_bullpen_due = BULLPEN_RATE
	for t: int in 2:
		for lane: int in 2:
			var i := t * 2 + lane
			var p := _bullpen_puppets[i]
			var id := game.warming[t][lane] if lane < game.warming[t].size() else ""
			var spot := _bullpen_spot(t, lane) if id != "" else []
			if id == "" or spot.is_empty() or game.over:
				p.visible = false
				_bullpen_who[i] = ""
				continue
			if _bullpen_who[i] != id:
				_bullpen_who[i] = id
				var who := game.teams[t].player(id)
				_dress(p, _style_for(t), who.number if who != null else 0, who.name if who != null else "", false)
				_set_body(p, who, Position.Kind.P)
				_logo(p, t)
				var centre: Vector2 = spot[0]
				var facing: float = spot[1]
				p.position = Field.to_world(Vector3(centre.x, centre.y, Field.MOUND_HEIGHT))
				p.rotation.y = -atan2(sin(facing), cos(facing))
				p.left_grip = Puppet.Grip.GLOVE
				# Standing ready from the first frame, seen or not (never the model's own pose).
				p.apply(PuppetClips.standing())
			p.visible = true
			# Only posed while the camera that is drawing can see him.
			var view := get_viewport().get_camera_3d()
			if not pose_now or view == null or not view.is_position_in_frustum(p.global_position + Vector3.UP):
				continue
			var phase := fmod(_bullpen_clock + lane * 1.7 + t * 0.9, BULLPEN_CYCLE)
			p.frame_time = BULLPEN_RATE
			p.apply(PuppetClips.pitch(phase) if phase < PuppetClips.PITCH_LENGTH else PuppetClips.standing())


## The bat the batter lets go of when he runs, left lying by the plate during the play.
func _build_dropped_bat() -> void:
	_dropped_bat = MeshInstance3D.new()
	_dropped_bat.mesh = BatWood.mesh()
	_dropped_bat.material_override = BatWood.material()
	_dropped_bat.visible = false
	add_child(_dropped_bat)


## Lays the bat down where the batter stood, pointing roughly back toward the dugout he
## came from, at a slant that changes from play to play.
func _drop_bat() -> void:
	var at := batter.position + Field.to_world(Vector3(0.35, 0.3, 0.0)) - Field.to_world(Vector3.ZERO)
	var yaw := PI * 0.5 + (float(_pitch_count % 7) - 3.0) * 0.25
	_dropped_bat.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, PI * 0.5), Vector3(at.x, 0.034, at.z))


func _build_officials() -> void:
	fielders[Position.Kind.P] = pitcher
	fielders[Position.Kind.C] = catcher
	# Base umpires stand behind first and third, outside the line; the second-base umpire
	# behind the bag, or inside the infield with runners on. Each crew member has his number.
	var crew: Array[int] = [14, 36, 52]
	for spot: Vector3 in [Vector3(23.6, 19.4, 0.0), Vector3(-3.0, 44.0, 0.0), Vector3(-23.6, 19.4, 0.0)]:
		var u := _add_puppet(spot, 0.0, Color(0.08, 0.08, 0.09), Color(0.05, 0.05, 0.06), use_models)
		dress_umpire(u, crew[base_umpires.size()], false)
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
	return _styles[team].copy()


## The club playing as away (0) or home (1): from the roster pack, the league or the career.
## The club playing as a side (its colours and emblem for the HUD), looked up once.
func club(side: int) -> Team:
	if _club_cache.size() != 2:
		_club_cache = [_club(0), _club(1)]
	return _club_cache[side]


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
	var stealing := not is_nan(_steal_jump)
	if absf(k - _cast_k) < 0.02 and absf(lead - _cast_lead) < 0.02 and not stealing:
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
		if stealing and i + 1 == _steal_from:
			# The player's runner is off with the pitcher's first move.
			var ran := minf(maxf(_pitch_clock - _steal_go_at, 0.0) * RunningPlay.RUNNER_SPEED, Field.BASE_DISTANCE * 0.7)
			var going := _leads[i] + toward * ran
			r.position = Field.to_world(Vector3(going.x, going.y, 0.0))
			_turn(r, _yaw_toward(Vector2.ZERO, toward))
			r.frame_time = _frame_time
			r.apply(PuppetClips.run_at(_stride(r, RunningPlay.RUNNER_SPEED), 1.0))
			continue
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
	# He stays where he is and takes the ball where it comes (not giving the target away by
	# moving to it).
	catcher.position = Field.to_world(Vector3(0.0, -1.15, 0.0))
	catcher.frame_time = _frame_time
	var pose := PuppetClips.catcher()
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
	if broadcast.current != null and not broadcast.holding():
		broadcast.step(delta)
	broadcast_cards.queue_redraw()
	if broadcast.showing(Broadcast.Kind.REPLAY) and _replay_play != null:
		_show_replay()
		_crowd_react(delta)
		_redraw_overlays()
		return
	_show_target()
	_crowd_react(delta)
	# The scoreboard redraws when what it shows changes (about once a pitch).
	_board_clock -= delta
	if board_screen != null and _board_clock <= 0.0:
		_board_clock = 0.25
		var now := board_screen.signature()
		if now != _board_shown:
			_board_shown = now
			board_screen.queue_redraw()
			park.scoreboard.render_target_update_mode = SubViewport.UPDATE_ONCE
	_show_bullpen(delta)
	if _play_time >= 0.0 and _play != null:
		_frame_time = delta * _pace
		_show_aim_props()
		_show_play(_play_time)
		_move_camera_play(delta)
		hud.queue_redraw()
		_redraw_overlays()
		return
	super.refresh(delta)
	_pose_cast()
	# What everyone looks like now, for easing into the next play.
	for p: Puppet in _cast():
		p.ease_step(delta)
	for u: Puppet in base_umpires:
		signal_call(u, null)
	if _time_called >= 0.0:
		_time_called += delta
		signal_call(umpire, PuppetClips.umpire_signal(&"time", _time_called) if _time_called < TIME_SIGNAL else null)
		if _time_called >= TIME_SIGNAL:
			_time_called = -1.0
	_redraw_overlays()


func _redraw_overlays() -> void:
	_pay_profile()
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
	var swinging := _contact_shown()
	_dropped_bat.visible = not swinging and not _running and _batter_at_start != "" and not _play.foul and t > BAT_DROPPED_AT
	for kind: Position.Kind in fielders:
		var key := "F:%s" % Position.code(kind)
		if _manual != null and kind == _manual.kind:
			_show_own(fielders[kind], t)
		elif tl.tracks.has(key):
			_move_puppet(fielders[kind], tl, key, t)
	ball_actor.show_at(shown_ball(t))
	for i: int in 3:
		var id := _runners_at_start[i]
		if id != "" and tl.tracks.has("R:%s" % id):
			runner_puppets[i].visible = true
			_move_puppet(runner_puppets[i], tl, "R:%s" % id, t)
	var batter_key := "R:%s" % _batter_at_start
	if swinging:
		_box_left = -1.0
		_show_swing(t)
	elif tl.tracks.has(batter_key):
		batter.scale.x = 1.0
		_move_puppet(batter, tl, batter_key, t)
		# He runs from where he stood in the box, not from the middle of the plate (he jumped
		# a metre and more to it at contact), from the moment he is first shown running (after
		# a slow-motion swing the play has gone on without him).
		if _box_left < 0.0:
			_box_left = t
		var box := Vector3(_box.x * (-1.0 if settings.bats_left else 1.0), _box.y, 0.0)
		var start := tl.position(batter_key, _box_left)
		var off := (box - Vector3(start.x, start.y, 0.0)) * (1.0 - smoothstep(_box_left, _box_left + BOX_LEAVING, t))
		batter.position += Field.to_world(off) - Field.to_world(Vector3.ZERO)
	_umpire_signals(t)


## Seconds over which the batter's path out of the box joins his run to first, and the play
## time he was first shown leaving it (−1 until then).
const BOX_LEAVING := 0.9
var _box_left := -1.0


## The batter in the box, finishing his swing (the contact highlight).
func _show_swing(t: float) -> void:
	batter.frame_time = _frame_time
	batter.look_at_world(Field.to_world(_ball_at(_play.timeline, t)))
	if swing_motion != null:
		batter.apply_joints(swing_motion.frame(), swing_motion.clip, _reach * swing_motion.reach_weight())
	elif _swing_clock >= 0.0:
		batter.apply(PuppetClips.swing(_swing_clock - _swing_lead, _swing_lead, _swing_height))
	_ease_change(batter, &"swing")


## The figures whose poses ease from one thing to the next: the fielders, runners and batter.
func _cast() -> Array[Puppet]:
	var all: Array[Puppet] = []
	for kind: Position.Kind in fielders:
		all.append(fielders[kind])
	all.append_array(runner_puppets)
	all.append(batter)
	return all


## Where the ball is shown: in the player's own fielder's glove once he has it, until the
## play goes on from there.
func shown_ball(t: float) -> Vector3:
	if _play == null:
		return Vector3.ZERO
	if _manual != null and _manual.got:
		var p: Puppet = fielders[_manual.kind]
		return Field.to_field(p.global_transform * p.glove_pocket())
	var flying := _ball_at(_play.timeline, t)
	if _moves == null or _running:
		return flying
	# Who has the ball: the last fielder to take it, until he lets it go. It is in his glove,
	# and in his throwing hand from the start of the throw. (It used to float on a straight
	# line from where he caught it to where he would let it go, a metre and more from him.)
	var holder := ""
	var since := -INF
	for key: String in _moves.by_key:
		if not key.begins_with("F:"):
			continue
		for m: PlayMoves.Moment in _moves.by_key[key]:
			if (m.kind == PlayMoves.Kind.CATCH or m.kind == PlayMoves.Kind.TAG) and m.time <= t and m.time > since:
				since = m.time
				holder = key
	if holder == "":
		return flying
	# The next throw after he took it (from the play's own throws: who is shown throwing it
	# is a guess, PlayMoves._nearest).
	var release := INF
	var from := Vector3.ZERO
	for th: PackedVector4Array in _play.timeline.throws:
		if th[0].x >= since - 0.001 and th[0].x < release:
			release = th[0].x
			from = Vector3(th[0].y, th[0].z, th[0].w)
	var p: Puppet = fielders[Position.from_code(holder.substr(2))]
	var at := Field.to_field(p.global_position)
	var throws_it := release < INF and Vector2(at.x - from.x, at.y - from.y).length() < 2.5
	if t < release - THROW_HAND_FROM or (t < release and not throws_it):
		var glove := Field.to_field(p.global_transform * p.glove_pocket())
		# Into the glove over a moment, from where it was flying (a glove not quite at the
		# ball took it from a metre off in one frame).
		return flying.lerp(glove, smoothstep(since, since + CATCH_JOINS, t)) if t < since + CATCH_JOINS else glove
	if t < release:
		return Field.to_field(p.global_transform * p.ball_spot(&"RightHand"))
	if not throws_it:
		return flying
	# Just let go: out of the hand onto the throw's line.
	var hand := Field.to_field(p.global_transform * p.ball_spot(&"RightHand"))
	return hand.lerp(flying, smoothstep(release, release + THROW_JOINS, t))


## Seconds before a release the ball is in the throwing hand, and after it until it is on the
## throw's own line.
const THROW_HAND_FROM := 0.3
const THROW_JOINS := 0.1
const CATCH_JOINS := 0.06


## The player's own fielder: where the player has taken him, running, set, diving, or with
## the ball.
func _show_own(p: Puppet, t: float) -> void:
	_ease_change(p, _pose_own(p, t))


func _pose_own(p: Puppet, t: float) -> StringName:
	var mf := _manual
	p.position = Field.to_world(Vector3(mf.pos.x, mf.pos.y, 0.0))
	p.frame_time = _frame_time
	var ball := duel.path.position_at(t)
	var speed := mf.velocity.length()
	if mf.got:
		catch(p, mf.got_at, minf(t - mf.got_time, 0.08))
		return &"got"
	if mf.diving(t):
		# Laid out the way he went, side on to it; up for one over his head.
		var across := Vector2(-mf.dive_toward.y, mf.dive_toward.x)
		if across.dot(-mf.pos) < 0.0:
			across = -across
		_turn(p, _yaw_toward(Vector2.ZERO, across), QUICK_TURN)
		var local := p.to_local(Field.to_world(ball))
		var reach := smoothstep(0.0, ManualFielding.DIVE_FROM + 0.08, t - mf.dive_time)
		var side := p.to_local(Field.to_world(Vector3(mf.pos.x + mf.dive_toward.x, mf.pos.y + mf.dive_toward.y, 0.0))).x
		catch_at(p, PuppetClips.overhead_catch() if ball.z > 1.6 else PuppetClips.dive(signf(side)), local, reach if local.length() < 2.6 else 0.0)
		return &"dive"
	if speed > RUN_POSE_SPEED:
		var to_ball := Vector2(ball.x, ball.y) - mf.pos
		if ball.z > 3.0 and speed < BACKPEDAL_BELOW and mf.velocity.dot(to_ball) < -0.5 * speed * to_ball.length():
			_turn(p, _yaw_toward(mf.pos, Vector2(ball.x, ball.y)))
			p.apply(PuppetClips.backpedal(-_stride(p, speed)))
			return &"backpedal"
		_turn(p, _yaw_toward(Vector2.ZERO, mf.velocity))
		p.apply(PuppetClips.run_at(_stride(p, speed), speed / SPRINT))
		return &"run"
	_turn(p, _yaw_toward(mf.pos, Vector2(ball.x, ball.y)), QUICK_TURN)
	p.apply(PuppetClips.fielder_ready())
	return &"ready"


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
	_ease_change(p, _pose_on_track(p, tl, key, t))


## What each figure was doing in the last frame (the kind of pose it was given), and how long
## a change from one to another is eased over (s). A change of what someone is doing used to
## be a jump between two poses in one frame: into a dive, up from a slide, out of a catch.
var _doing: Dictionary[Puppet, StringName] = {}
const POSE_EASE := 0.16


## Eases p from the pose it was in when what it is doing changes, and moves its easing on.
## Within one thing a pose can still jump (a catch on the run whose glove has to go a long way
## down at once): a jump of the hips that size in one frame is eased too.
func _ease_change(p: Puppet, doing: StringName) -> void:
	var was: StringName = _doing.get(p, &"")
	var hips := p.shown_hips_height()
	if was != &"" and was != doing:
		p.ease_from_shown(POSE_EASE)
	elif was != &"" and _frame_time > 0.0 and absf(hips - float(_hips_shown.get(p, hips))) > HIP_JUMP:
		p.ease_from_shown(POSE_EASE * 0.6)
	_doing[p] = doing
	_hips_shown[p] = p.shown_hips_height()
	p.ease_step(_frame_time)


## The height of each figure's hips in the last frame, and the most they may move in one
## frame before it is eased (m).
var _hips_shown: Dictionary[Puppet, float] = {}
const HIP_JUMP := 0.14


## Poses p as the play's timeline has him at t and says what kind of pose it is.
func _pose_on_track(p: Puppet, tl: PlayTimeline, key: String, t: float) -> StringName:
	var now := tl.position(key, t)
	var ahead := tl.position(key, t + 0.1)
	p.position = Field.to_world(Vector3(now.x, now.y, 0.0))
	var step := Vector2(ahead.x - now.x, ahead.y - now.y)
	var speed := step.length() / 0.1
	p.frame_time = _frame_time
	var here := Vector2(now.x, now.y)
	var m: PlayMoves.Moment = _moves.now(key, t) if _moves != null else null
	# On a steal the pitcher delivers and the catcher waits in his crouch for the pitch.
	if _running_pitch and key == "F:P" and t < RunningPlay.STEAL_LEAD_IN + 0.4 and _play.calls[0].base != 1:
		p.rotation.y = PI
		p.apply(PuppetClips.pitch(t - RunningPlay.STEAL_LEAD_IN + PuppetClips.PITCH_RELEASE))
		return &"steal_pitch"
	if _running_pitch and key == "F:C" and t < RunningPlay.STEAL_LEAD_IN + RunningPlay.PITCH_FLIGHT:
		p.rotation.y = 0.0
		catch_at(p, PuppetClips.catcher(), p.to_local(Field.to_world(_ball_at(tl, t))), smoothstep(-0.3, -0.05, t - RunningPlay.STEAL_LEAD_IN - RunningPlay.PITCH_FLIGHT))
		return &"steal_catch"
	if m != null:
		match m.kind:
			PlayMoves.Kind.THROW:
				_turn(p, _yaw_toward(here, Vector2(m.at.x, m.at.y)), QUICK_TURN)
				p.apply(PuppetClips.throw_styled(t - m.time, m.style))
				return &"throw"
			PlayMoves.Kind.TAG:
				# Down to the bag with the ball in the glove, where the runner's foot comes.
				if here.distance_to(Vector2(m.at.x, m.at.y)) > 0.3:
					_turn(p, _yaw_toward(here, Vector2(m.at.x, m.at.y)), QUICK_TURN)
				var dt := t - m.time
				catch_at(p, PuppetClips.ground_catch(), p.to_local(Field.to_world(m.at)), smoothstep(-0.25, -0.05, dt) * (1.0 - smoothstep(0.2, 0.4, dt)))
				return &"tag"
			PlayMoves.Kind.SLIDE:
				if here.distance_to(Vector2(m.at.x, m.at.y)) > 0.3:
					_turn(p, _yaw_toward(here, Vector2(m.at.x, m.at.y)), QUICK_TURN)
				var down := PuppetClips.head_first() if m.head_first else PuppetClips.slide()
				p.apply(down if t >= m.time - (0.3 if m.head_first else 0.15) else PuppetClips.run_at(_stride(p, speed), 1.0))
				return &"slide" if t >= m.time - (0.3 if m.head_first else 0.15) else &"run"
			PlayMoves.Kind.MISS:
				# A dive at a ball that goes by: laid out toward it, the glove short of it.
				var by := Vector2(m.at.x, m.at.y)
				var across := Vector2(-(by - here).y, (by - here).x)
				if across.dot(-here) < 0.0:
					across = -across
				if across.length() > 0.05:
					_turn(p, _yaw_toward(Vector2.ZERO, across), QUICK_TURN)
				var local := p.to_local(Field.to_world(m.at))
				var down := PuppetClips.overhead_catch() if m.at.z > 1.6 else PuppetClips.dive(signf(local.x))
				catch_at(p, down, local, smoothstep(-0.3, -0.05, t - m.time) * 0.7)
				return &"miss"
			PlayMoves.Kind.CATCH:
				# Square to where the ball comes from; it may be off to one side of him.
				var coming := m.at - _ball_at(tl, m.time - 0.1)
				var from := Vector2(-coming.x, -coming.y)
				if from.length() < 0.05:
					from = Vector2(m.at.x - now.x, m.at.y - now.y)
				if from.length() > 0.05:
					_turn(p, _yaw_toward(Vector2.ZERO, from), QUICK_TURN)
				# The first baseman takes a throw on the bag with a stretch toward it.
				if key == "F:1B" and Vector2(m.at.x, m.at.y).distance_to(PlaySim.base_xy(1)) < 1.0 and m.at.z > 0.6:
					var reach := smoothstep(-0.3, -0.05, t - m.time) * (1.0 - smoothstep(0.1, 0.25, t - m.time))
					catch_at(p, PuppetClips.first_base_stretch(), p.to_local(Field.to_world(_ball_at(tl, t))), reach)
					return &"stretch"
				# On the run his legs keep running under the catch. His glove goes to where the ball
				# is taken and stays there through the catch (reaching up the ball's path, a
				# fielder was lifted off his feet after a fly ball still metres over his head; the
				# ball is then in the glove, shown_ball).
				var legs := PuppetClips.run_at(_stride(p, speed), speed / SPRINT) if speed > RUN_POSE_SPEED else null
				var aim := m.at
				catch(p, aim, t - m.time, legs)
				# (Which catch it is: he may go from one to another as the ball comes.)
				# (Running into it or set for it: his legs differ, so that is a change too.)
				return StringName("catch_%s%s" % [PuppetClips.catch_kind(p.to_local(Field.to_world(aim)), aim.z), "_on_the_run" if legs != null else ""])
	if speed > RUN_POSE_SPEED:
		# Drifting back under a fly ball a fielder faces it and backpedals; otherwise he turns
		# and runs.
		var ball := _ball_at(tl, t)
		var to_ball := Vector2(ball.x - now.x, ball.y - now.y)
		if key.begins_with("F:") and ball.z > 3.0 and speed < BACKPEDAL_BELOW and step.dot(to_ball) < -0.5 * step.length() * to_ball.length():
			_turn(p, _yaw_toward(here, Vector2(ball.x, ball.y)))
			p.apply(PuppetClips.backpedal(-_stride(p, speed)))
			return &"backpedal"
		_turn(p, _yaw_toward(Vector2.ZERO, step))
		if _run_matched(p, tl, key, t, here, step):
			return &"matched"
		p.apply(PuppetClips.run_at(_stride(p, speed), speed / SPRINT))
		return &"run"
	var ball := _ball_at(tl, t)
	_turn(p, _yaw_toward(here, Vector2(ball.x, ball.y)), QUICK_TURN)
	p.apply(PuppetClips.lead_off() if key.begins_with("R:") else PuppetClips.fielder_ready())
	return &"ready"


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
	# How far the body has gone toward the ball over all the passes: no more than
	# MAX_BODY_SHIFT, and no higher off the ground than a jump (MAX_LEAP). (Each pass could move
	# it MAX_BODY_SHIFT, so five of them lifted a fielder three metres into the air.)
	var moved := Vector3.ZERO
	for i: int in CATCH_IK_PASSES:
		pose.l_hand += local - p.glove_pocket()
		# Out of the arm's reach the body goes to the ball: lower for a grounder, up off the
		# ground for one over his head, over toward one wide of him.
		var shoulder: Vector3 = p.joints[&"LeftUpperArm"]
		var over := shoulder.distance_to(pose.l_hand) - arm
		if over > 0.0:
			var want := (moved + (pose.l_hand - shoulder).normalized() * over).limit_length(MAX_BODY_SHIFT)
			want.y = minf(want.y, MAX_LEAP)
			var shift := want - moved
			moved = want
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
	var ball := shown_ball(_play_time)
	catcher.visible = true
	umpire.visible = true
	var h := highlight()
	if h != null:
		_close_camera(h, ball, delta)
		return
	# High behind home plate, inside the backstop, turning to keep the ball in view.
	var from := Vector3(clampf(ball.x * 0.1, -5.0, 5.0), -14.0, 16.0)
	# (A pop-up over the plate is looked up at further, or it goes out of the top.)
	var target := Vector3(ball.x, maxf(ball.y, 12.0), maxf(ball.z * (0.85 if ball.y < 20.0 else 0.7), 0.0))
	if _manual != null and _manual.got:
		# He has it: back to the whole field, for the throw.
		pass
	elif _manual != null:
		# The player's own fielder: the camera stands behind him (on the plate's side) and
		# above, near enough for him to be steered, with him and where the ball is going both
		# in the picture. (From behind the plate he was a few pixels tall in the outfield.)
		var own := Vector2(_manual.pos.x, _manual.pos.y)
		var going := landing_point if landing_known and _play_time < landing_time else Vector3(ball.x, ball.y, 0.0)
		var spot := Vector2(going.x, going.y)
		var focus := own.lerp(spot, 0.5)
		var toward := focus.normalized() if focus.length() > 5.0 else Vector2(0.0, 1.0)
		var back := clampf(MANUAL_CAMERA_BACK + own.distance_to(spot) * 0.6, MANUAL_CAMERA_BACK, 45.0)
		var stand := focus - toward * back
		from = Vector3(stand.x, stand.y, 8.0 + back * 0.35)
		# Looking down on the field: he and the ring where the ball comes down stay in the
		# picture, and a high fly goes out of the top of it for a moment (looking up after it,
		# the camera showed the stands and the sky and lost him).
		target = Vector3(focus.x, focus.y, clampf(ball.z * 0.25, 0.0, 3.0))
	# Back from a close-up the picture cuts, as a broadcast does.
	var cut := _close or _cut
	_close = false
	_cut = false
	_follow_target = target if cut else _follow_target.lerp(target, clampf(delta * 4.0, 0.0, 1.0))
	camera.position = Field.to_world(from) if cut else camera.position.lerp(Field.to_world(from), clampf(delta * 2.5, 0.0, 1.0))
	camera.fov = 48.0 if cut else lerpf(camera.fov, 48.0, clampf(delta * 2.5, 0.0, 1.0))
	camera.look_at(Field.to_world(_follow_target))


## The next camera move is a cut, not a follow.
var _cut := false


## The close camera on a chance stands this far (m) from the spot.
const CHANCE_CAMERA_DISTANCE := 9.5


func ctx_field() -> AnalyticField:
	return resolver.field if resolver != null else null


## The camera stands at least this far (m) behind the middle of a play the player fields
## himself (further when he is far from the ball).
const MANUAL_CAMERA_BACK := 18.0


## The camera of a highlight: beside the plate, on the bat and the ball, turning after the
## ball as it leaves; or a few metres in from the fielder going for the ball, on him.
func _close_camera(h: PlayHighlight, ball: Vector3, delta: float) -> void:
	var cut := not _close or _cut
	_close = true
	_cut = false
	var eye := Vector3.ZERO
	var look := Vector3.ZERO
	var fov := 26.0
	if h.kind == PlayHighlight.Kind.CONTACT:
		# From the open side, in front of the batter: his chest, the bat and the ball.
		var hit := _play.timeline.position("ball", 0.0)
		var side := -signf(Field.to_field(batter.global_position).x)
		if side == 0.0:
			side = 1.0
		eye = Vector3(side * 2.9, 3.3, 1.35)
		# On him through the swing: the ball leaves the picture on its own (the camera went
		# after it into the sky and he was gone from the shot). The play's camera picks the
		# ball up when the slow part ends.
		var after := smoothstep(0.02, h.until, _play_time)
		var at_contact := Vector3(hit.x - side * 0.25, hit.y, hit.z + 0.1)
		look = at_contact.lerp(Vector3(ball.x, ball.y, minf(ball.z, at_contact.z + 0.6)), after * 0.25)
		fov = lerpf(27.0, 31.0, after)
	else:
		# From the side of the ball's path, a little toward the plate, at about his height,
		# on the spot where he gets to it (or does not): he comes into it and the ball comes
		# across it. (Between him and the plate, the ball came at the camera, through it, and
		# the camera turned after it away from him.)
		var spot := Vector2(h.at.x, h.at.y)
		var before := _play.timeline.position("ball", maxf(h.until - PlayHighlight.CHANCE_AFTER - 0.25, 0.0))
		var coming := spot - Vector2(before.x, before.y)
		if coming.length() < 0.5:
			coming = spot
		coming = coming.normalized()
		var side := Vector2(-coming.y, coming.x)
		var home := -spot.normalized() if spot.length() > 1.0 else Vector2(0.0, -1.0)
		if side.dot(home) < 0.0:
			side = -side
		var from_dir := (side * 0.85 + home * 0.45).normalized()
		# Further off when he comes from far away, so that he is in it from the start.
		var man_then := _play.timeline.position(h.key, h.from)
		var away := maxf(CHANCE_CAMERA_DISTANCE, spot.distance_to(Vector2(man_then.x, man_then.y)) * 1.4 + 4.0)
		var stand := spot + from_dir * away
		if ctx_field() != null and stand.length() > 1.0:
			var edge := ctx_field().boundary_distance(rad_to_deg(atan2(stand.x, stand.y))) - 1.5
			if stand.length() > edge:
				stand = stand.normalized() * edge
		eye = Vector3(stand.x, stand.y, 1.6)
		var man := _play.timeline.position(h.key, _play_time)
		var aim := Vector3(spot.x, spot.y, clampf(h.at.z, 0.6, 1.8))
		# Between him and the spot: both are in the picture as he comes into it.
		look = aim.lerp(Vector3(man.x, man.y, 1.0), 0.5)
		fov = 34.0
	_follow_target = look if cut else _follow_target.lerp(look, clampf(delta * 9.0, 0.0, 1.0))
	camera.position = Field.to_world(eye)
	camera.fov = fov
	camera.look_at(Field.to_world(_follow_target))


func _show_ball() -> void:
	if _play_time >= 0.0 and _play != null:
		return
	super._show_ball()
	# Once the catcher has it the ball is in his mitt, wherever he takes it.
	if state == State.RESULT and _catcher_ball().is_finite() and not duel.bounced:
		ball_actor.show_at(Field.to_field(catcher.global_transform * catcher.glove_pocket()))


## (The batting camera is straight behind the plate for a batter of either hand.)
func _camera_preset() -> Array:
	return PITCH_CAMERA if human_pitches() else bat_camera()


# --- The broadcast's moments (docs/11 section 6, docs/13 S16) ---


## A broadcast moment that holds the game is skipped with Space, Enter or a click (before the
## keys mean anything else: in the manager's game Space pauses and Enter takes the at-bat).
## True when the event was used for that.
func skip_broadcast(event: InputEvent) -> bool:
	if not broadcast.holding() or pause_menu.visible or menu.visible:
		return false
	var key := event as InputEventKey
	var click := event as InputEventMouseButton
	if (key != null and key.pressed and not key.echo and key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]) or (click != null and click.pressed):
		broadcast.skip()
		get_viewport().set_input_as_handled()
		return true
	return false


## The cards between plays (the inning, the batter, a new pitcher) are shown: not in the
## manager's quick game, whose board says all of it.
func _broadcast_between() -> bool:
	return broadcast.enabled


## A replay is shown after this play.
func _replay_wanted() -> bool:
	return true


## The batting side's runs, hits and men left on base so far.
func _half_numbers() -> Vector3i:
	var t := game.batting()
	return Vector3i(game.score[t], scorer.book.hits[t], scorer.book.left_on_base[t])


## Before the first pitch: the park from the air with the match-up, the home starter on the
## mound, the visitors' order.
func _push_pregame() -> void:
	if not broadcast.enabled:
		return
	var data := {"park": stadium.name if stadium != null else "", "starter": game.teams[1].pitcher_id}
	if weather != null:
		data["weather"] = weather.describe((stadium if stadium != null else park.def).orientation_deg)
	for side: int in 2:
		data["record%d" % side] = _record_text(side)
	var seg := Broadcast.segment(Broadcast.Kind.PREGAME, data)
	var centre := Vector3(0.0, 45.0, 0.0)
	seg.shots = [
		Broadcast.Shot.make(0.0, Vector3(-120.0, 10.0, 62.0), centre, 55.0, Vector3(-55.0, -110.0, 48.0), centre, 50.0),
		Broadcast.Shot.make(4.5, Vector3(2.8, 12.6, 2.2), Vector3(0.0, Field.RUBBER_Y, 1.6), 28.0, Vector3(2.2, 13.4, 2.0), Vector3(0.0, Field.RUBBER_Y, 1.6), 22.0),
		Broadcast.Shot.make(7.5, Vector3(0.0, -34.0, 13.0), Vector3(0.0, 30.0, 2.0), 50.0, Vector3(0.0, -28.0, 11.0), Vector3(0.0, 30.0, 2.0), 46.0),
	]
	broadcast.push(seg)


## A club's record this season ("12승 8패 1무"), or "" outside a season.
func _record_text(side: int) -> String:
	var s := _season()
	if s == null:
		return ""
	var d := s.division_of(game.teams[side].team_id)
	if d < 0:
		return ""
	var r := s.standings[d].row(game.teams[side].team_id)
	return "%d승 %d패 %d무" % [r.wins, r.losses, r.ties]


## The season this game belongs to (a league or career game), or null.
func _season() -> Season:
	if get("league_game") != null and LeagueSession.season != null:
		return LeagueSession.season
	if self is CareerMatch and CareerSession.season != null:
		return CareerSession.season
	return null


## The inning's card, with the half just over.
func _push_half() -> void:
	var data := {}
	var now := _half_numbers()
	if game.inning > 1 or not game.top:
		# The half just over was the other side's.
		var t := 1 - game.batting()
		var end := Vector3i(game.score[t], scorer.book.hits[t], scorer.book.left_on_base[t])
		var d := end - _half_start
		data["summary"] = "%d회%s  %s  ·  %d득점 · %d안타 · 잔루 %d" % [game.inning if not game.top else game.inning - 1, "초" if not game.top else "말", game.teams[t].short_name, d.x, d.y, d.z]
	_half_start = now
	# The last play's line has had its time; the card takes the screen.
	banner_time = 0.0
	var seg := Broadcast.segment(Broadcast.Kind.HALF, data)
	seg.shots = [Broadcast.Shot.make(0.0, Vector3(0.0, -48.0, 30.0), Vector3(0.0, 40.0, 0.0), 52.0, Vector3(0.0, -40.0, 26.0), Vector3(0.0, 40.0, 0.0), 50.0)]
	broadcast.push(seg)


## The batter coming up and a new pitcher: their cards (a close-up that holds the game unless
## the player is the one batting). Not in the manager's quick games (_broadcast_between).
func _push_people(new_half: bool) -> void:
	if not _broadcast_between():
		return
	var f := game.fielding()
	if game.teams[f].pitcher_id != _seen_pitcher[f] and _seen_pitcher[f] != "" and not new_half:
		var seg := Broadcast.segment(Broadcast.Kind.PITCHER_CHANGE, {"id": game.teams[f].pitcher_id})
		seg.shots = [Broadcast.Shot.make(0.0, Vector3(4.0, 12.5, 2.0), Vector3(0.0, Field.RUBBER_Y, 1.6), 28.0, Vector3(3.4, 13.2, 1.9), Vector3(0.0, Field.RUBBER_Y, 1.6), 24.0)]
		broadcast.push(seg)
	_seen_pitcher[f] = game.teams[f].pitcher_id
	if game.batter_id() != _seen_batter:
		var holds := not human_bats()
		if holds:
			banner_time = 0.0
		var seg := Broadcast.segment(Broadcast.Kind.BATTER, {"id": game.batter_id()}, holds)
		if holds:
			var bx := _box.x * (-1.0 if settings.bats_left else 1.0)
			seg.shots = [Broadcast.Shot.make(0.0, Vector3(bx + 1.4, 5.2, 1.6), Vector3(bx, 0.0, 1.4), 26.0, Vector3(bx + 1.2, 4.8, 1.6), Vector3(bx, 0.0, 1.45), 22.0)]
		broadcast.push(seg)
	_seen_batter = game.batter_id()


## What a man's card says under his name: today, and his season when there is one.
func broadcast_lines(p: Player) -> PackedStringArray:
	var out := PackedStringArray()
	var s := _season()
	if p.is_pitcher() and game.teams[game.fielding()].player(p.id) != null and game.pitcher_id() == p.id:
		var today := scorer.book.pitch(p.id)
		out.append("오늘 %s이닝 %d실점" % [today.innings_text(), today.runs] if today.outs > 0 else (String(p.role()) + " · " + ("좌투" if p.throws == &"L" else "우투")))
		if s != null and s.book.pitching.has(p.id):
			var l: PitchingLine = s.book.pitching[p.id]
			out.append("시즌 %d승 %d패 · 평균자책점 %.2f" % [l.wins, l.losses, l.era()])
		return out
	out.append("오늘 " + BottomBar.today_batting(scorer.book.bat(p.id)))
	if s != null and s.book.batting.has(p.id):
		var b: BattingLine = s.book.batting[p.id]
		out.append("시즌 타율 %s · %d홈런 · %d타점" % [BattingLine.rate_text(b.average()), b.home_runs, b.rbi])
	return out


## A home run again, slower, from the side of the field it went to; a catch that could have
## gone either way, close by the fielder.
func _push_replay(play: PlayResult, kind: StringName) -> void:
	_replay_play = play
	_replay_moves = _moves
	_replay_kind = kind
	var tl := play.timeline
	if kind == &"catch":
		_replay_window = Vector2(maxf(play.hard_time - 1.8, 0.0), minf(play.hard_time + 1.2, tl.duration))
	else:
		_replay_window = Vector2(0.0, minf(tl.duration, 4.5 * REPLAY_PACE))
	broadcast.push(Broadcast.segment(Broadcast.Kind.REPLAY, {"kind": kind}))


var _replay_kind := &"home_run"


## The replay is shown at this pace.
const REPLAY_PACE := 0.7


func _show_replay() -> void:
	var t := _replay_window.x + broadcast.time * REPLAY_PACE
	if t > _replay_window.y:
		t = _replay_window.y
	var keep_play := _play
	var keep_moves := _moves
	_play = _replay_play
	_moves = _replay_moves
	_frame_time = 1.0 / 60.0 * REPLAY_PACE
	_show_play(t)
	var ball := _ball_at(_play.timeline, t)
	_play = keep_play
	_moves = keep_moves
	if _replay_kind == &"catch":
		# Close by the catch, from the plate's side and a little off, the ball coming in.
		var spot := _replay_play.hard_at
		var flat := Vector2(spot.x, spot.y)
		var back := flat.normalized() if flat.length() > 1.0 else Vector2(0.0, 1.0)
		var off := Vector2(-back.y, back.x) * 4.0
		var stand := flat - back * 10.0 + off
		camera.fov = 34.0
		camera.look_at_from_position(Field.to_world(Vector3(stand.x, stand.y, 2.6)), Field.to_world(Vector3(spot.x, spot.y, 1.0).lerp(ball, 0.35)))
	else:
		# Over the batter's shoulder, following the ball out with the field kept under it (from
		# low in foul ground the picture was all sky).
		var side := 1.0 if ball.x >= 0.0 else -1.0
		var from := Vector3(-side * 3.0, -7.0, 3.4)
		camera.fov = 55.0
		camera.look_at_from_position(Field.to_world(from), Field.to_world(Vector3(ball.x, ball.y, clampf(ball.z * 0.45, 0.5, 14.0))))
	catcher.visible = true
	umpire.visible = true
	if broadcast.time + 1.0 / 60.0 >= broadcast.current.duration:
		_replay_play = null
		_place_cast()


## The broadcast's camera when one of its moments has a shot; the game's own otherwise.
func _move_camera(delta: float) -> void:
	var cam := broadcast.camera()
	if not cam.is_empty() and not broadcast.showing(Broadcast.Kind.REPLAY):
		camera.fov = float(cam[2])
		camera.look_at_from_position(Field.to_world(cam[0]), Field.to_world(cam[1]))
		catcher.visible = true
		umpire.visible = true
		return
	super._move_camera(delta)
