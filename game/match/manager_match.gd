class_name ManagerMatch
extends MatchScene
## 감독 지휘 (docs/02 sections 3 and 4.3–4.4, docs/05 sections 2.5 and 3.5, docs/13 S7-6): the
## computer plays both sides while the player manages one.
##
## - Plate appearances go by in summary on the situation board: pitches that decide nothing
##   are only counted, a strikeout or walk shows its result, and a ball in play is shown on
##   the field. A key moment (leverage 2 and up) is played out pitch by pitch.
## - F: orders for the coming plate appearance, the standing defence and baserunning,
##   substitutions and reservations. The game waits while the menu is open.
## - Enter: intervene, three times a game (five in the postseason): the player bats or
##   pitches this plate appearance himself.
## - 1·2·4 speed, Space pause, → skip this plate appearance, Shift+→ skip the half-inning.
##
## Start it with  ./dev play res://match/manager_match.tscn -- --team home|away
## (--postseason for five interventions, --interventions n with −1 for no limit). From the
## league screen it plays the player's game of the day (LeagueSession) and reports the result
## back to the season.

const INTERVENTIONS := 3
const POSTSEASON_INTERVENTIONS := 5
## Seconds on the board between summary pitches, after a pitch that decides nothing, and
## after a strikeout or walk.
const SUMMARY_GAP := 0.15
const SUMMARY_PITCH := 0.45
const SUMMARY_RESULT := 1.3

var my_team := 1
var interventions_left := INTERVENTIONS
## Seconds on the board between summary pitches, after one that decides nothing, and after a
## plate appearance's result (a mode may go faster).
var summary_gap := SUMMARY_GAP
var summary_pitch_time := SUMMARY_PITCH
var summary_result_time := SUMMARY_RESULT
var intervening := false
var speed := 1.0
var paused := false
## Every pitch live, as in watching.
var show_every_pitch := false
var reservations: Array[Reservation] = []
var reservation_presets: Array[Reservation] = []
var we: WinExpectancy
## The home team's chance of winning and the leverage of the plate appearance now up.
var win_chance := 0.5
var leverage := 1.0
var board: SituationBoard
var orders: OrdersPanel
var alert := ""
## The season game being played, when started from the league screen.
var league_game: ScheduledGame
var _recorded := false

## Skipping ahead: 0 no, 1 to the end of this plate appearance, 2 to the end of this half.
var _skip := 0
var _skip_key := ""
var _pa_key := ""
var _pa_over := false
## The plate appearance the player took over.
var _intervened_key := ""


func _ready() -> void:
	super._ready()
	we = WinExpectancy.for_league(LeagueEnvIO.load_default(), game.rules)
	reservation_presets = Reservation.presets()
	var layer := hud.get_parent()
	board = SituationBoard.new()
	board.scene = self
	layer.add_child(board)
	# Under the score display and the bottom bar, which stay readable over the board.
	layer.move_child(board, 0)
	orders = OrdersPanel.new()
	orders.scene = self
	layer.add_child(orders)
	set_auto_changes(true)
	if league_game != null:
		# Leaving a season game goes back to the league; the game stays to be played.
		for c: Dictionary in pause_menu.quit_requested.get_connections():
			pause_menu.quit_requested.disconnect(c["callable"])
		pause_menu.quit_requested.connect(leave_unplayed)


func _read_arguments() -> void:
	var quick := QuickMatchScreen.pending
	super._read_arguments()
	if quick:
		interventions_left = Settings.interventions
	if human_team >= 0:
		my_team = human_team
	human_team = -1
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	if args.has("postseason"):
		interventions_left = POSTSEASON_INTERVENTIONS
	if args.has("interventions"):
		interventions_left = int(str(args["interventions"]))


## A game from the league: the season's line-ups for the day (rotation, rest, condition).
func _start_game() -> void:
	var s := LeagueSession.season
	var g := LeagueSession.pending
	if s == null or g == null:
		super._start_game()
		return
	league_game = g
	var sim := s.prepare(g, true)
	game = sim.state
	resolver = sim.resolver as PhysicalResolver
	scorer = sim.scorer
	manager = sim.manager
	innings = game.rules.innings
	my_team = 0 if g.away == s.my_team else 1
	_play_at_home(g.home, g.day, LeagueSession.season.teams.get(g.home))
	if s.postseason_of(g) != null:
		interventions_left = POSTSEASON_INTERVENTIONS
	_chosen_team = my_team
	balls = 0
	strikes = 0


func own_team() -> int:
	return my_team


func post_game_hint() -> String:
	if league_game != null:
		return "Enter 리그로 돌아가기"
	return super.post_game_hint()


func _menu_key(code: Key) -> void:
	if game.over and league_game != null:
		back_to_league()
		return
	super._menu_key(code)


## The result goes into the season once the game is over; then back to the league screen.
func _record_result() -> void:
	if _recorded or league_game == null or not game.over:
		return
	_recorded = true
	LeagueSession.season.record(league_game, game, scorer.book)
	LeagueSession.pending = null


func leave_unplayed() -> void:
	LeagueSession.pending = null
	Loading.go(get_tree(), LeagueSession.SCREEN, {"title": "리그로 이동 중"})


func back_to_league() -> void:
	_record_result()
	Loading.go(get_tree(), LeagueSession.SCREEN, {"title": "리그로 이동 중"})


## The player's side never changes in this mode; F3 does nothing.
func set_mode(_new_mode: StringName) -> void:
	pass


func help_keys() -> String:
	if intervening:
		return super.help_keys()
	var left := "∞" if interventions_left < 0 else str(interventions_left)
	return "F 작전  Enter 개입(%s)  1·2·4 속도  Space 멈춤  → 타석 넘기기  Shift+→ 이닝 넘기기" % left


## Played out on the field pitch by pitch: the player's own plate appearance, a key moment,
## or every pitch if asked; not while skipping ahead.
func live() -> bool:
	if intervening:
		return true
	if _skip > 0:
		return false
	return show_every_pitch or leverage >= WinExpectancy.HIGH


## The card over the board while the game waits for the player (a reservation's alert): title
## first, then the lines under it.
func card_lines() -> PackedStringArray:
	if alert == "" or not paused:
		return PackedStringArray()
	return PackedStringArray(["예약", alert])


## The line at the right of the board's footer.
func board_note() -> String:
	return "개입 %s회 남음" % ("∞" if interventions_left < 0 else str(interventions_left))


func board_visible() -> bool:
	return not live() and (_play_time < 0.0 or _skip > 0) and not game.over and not broadcast.holding()


## The board says who is up and what the inning is: no cards for those here.
func _broadcast_between() -> bool:
	return false


## No replays while skipping ahead.
func _replay_wanted() -> bool:
	return _skip == 0


# --- Each frame ---


func step(delta: float) -> void:
	if orders.visible:
		return
	if game.over or menu.visible or pause_menu.visible:
		super.step(delta)
		return
	# The broadcast's own moments (the introduction, a replay) hold this game too.
	if broadcast.holding():
		broadcast.step(delta)
		return
	_note_plate_appearance()
	if paused:
		return
	if _skip > 0:
		_fast_forward()
		return
	var d := delta if intervening else delta * speed
	if live() or _between > 0.0 or _play_time >= 0.0:
		super.step(d)
		return
	state_time += d
	banner_time = maxf(banner_time - d, 0.0)
	match state:
		State.PRE_PITCH:
			if state_time >= summary_gap:
				summary_pitch()
		State.RESULT:
			if state_time >= (summary_result_time if _pa_over else summary_pitch_time):
				_after_result()
		_:
			super.step(d)


## A pitch decided at once, without being shown: the count moves on the board. A ball in play
## is then shown on the field; a foul is not.
func summary_pitch() -> void:
	decision = _ai_pitch_decision()
	duel.throw_pitch(decision)
	_ai_react()
	while duel.phase == PitchDuel.Phase.FLIGHT:
		duel.tick(TICK)
	_finish_pitch()
	if _play != null and (_play.foul or _skip > 0 or not show_in_summary(_play)):
		_end_play()


## Postseason games sell out.
func crowd_fill() -> float:
	var s := LeagueSession.season
	if s != null and league_game != null and s.postseason_of(league_game) != null:
		return 1.0
	return super.crowd_fill()


func shows_running_plays() -> bool:
	return live()


## Whether a ball in play during the summary is shown on the field (here: all of them).
func show_in_summary(_play_result: PlayResult) -> bool:
	return true


## Plays on without showing anything until the plate appearance or the half-inning is over.
func _fast_forward() -> void:
	for i: int in 80:
		if game.over:
			_skip = 0
			return
		if _skip_key != _skip_point():
			_skip = 0
			_between = 0.0
			return
		if _play_time >= 0.0:
			_end_play()
		elif state == State.RESULT:
			_between = 0.0
			_after_result()
		elif state == State.PRE_PITCH:
			_note_plate_appearance()
			if paused or intervening:
				_skip = 0
				return
			summary_pitch()
		else:
			# A pitch already on its way: let it finish.
			while duel.phase == PitchDuel.Phase.FLIGHT:
				duel.tick(TICK)
			_finish_pitch()


func _skip_point() -> String:
	if _skip == 2:
		return "%d%s" % [game.inning, game.top]
	return "%d%s%s" % [game.inning, game.top, game.batter_id()]


func skip(half: bool) -> void:
	if intervening or game.over:
		return
	_skip = 2 if half else 1
	_skip_key = _skip_point()
	paused = false


# --- Plate appearances ---


## At the start of each plate appearance: the win chance and leverage, and the reservations.
func _note_plate_appearance() -> void:
	if state != State.PRE_PITCH or _play_time >= 0.0 or game.over:
		return
	var key := _key_now()
	if key == _pa_key:
		return
	_pa_key = key
	_pa_over = false
	if intervening and key != _intervened_key:
		_end_intervention()
	win_chance = we.for_state(game)
	leverage = we.leverage_of(game)
	var r := Reservation.check(reservations, game, my_team, leverage)
	if r == null:
		if leverage >= WinExpectancy.HIGH and _skip == 0:
			banner = "승부처"
			banner_time = 1.6
		return
	match r.action:
		Reservation.Action.INTERVENE:
			if interventions_left != 0:
				intervene()
				return
			_notify(r.label)
		Reservation.Action.ORDER:
			resolver.tactics[my_team].order = r.order
			apply_orders_now()
		_:
			_notify(r.label)


func _notify(label: String) -> void:
	alert = "예약: %s   Enter 개입 · Space 계속" % label
	banner = ""
	banner_time = 0.0
	paused = true
	_skip = 0


func _apply(e: GameEvent) -> void:
	super._apply(e)
	if e.kind == GameEvent.Kind.PLATE_APPEARANCE:
		_pa_over = true
	if game.over:
		_record_result()


func _after_result() -> void:
	super._after_result()
	if not game.over:
		win_chance = we.for_state(game)


func _key_now() -> String:
	return "%d%s%s" % [game.inning, game.top, game.batter_id()]


## The player's plate appearance is over: the computer plays on.
func _end_intervention() -> void:
	intervening = false
	human_team = -1
	set_auto_changes(auto_changes)
	_sync_mode()
	_snap_camera()


## Takes this plate appearance: the player bats or pitches it himself.
func intervene() -> void:
	if intervening or interventions_left == 0 or game.over:
		return
	if interventions_left > 0:
		interventions_left -= 1
	intervening = true
	_intervened_key = _key_now()
	paused = false
	alert = ""
	_skip = 0
	human_team = my_team
	set_auto_changes(auto_changes)
	banner = "개입: 이번 타석은 직접 %s" % ("칩니다" if game.batting() == my_team else "던집니다")
	banner_time = 2.0
	_sync_mode()
	_snap_camera()


## Orders given between pitches count from this pitch: a steal or intentional walk happens
## now, a bunt is on for this pitch.
func apply_orders_now() -> void:
	if state != State.PRE_PITCH or _play_time >= 0.0 or game.over:
		return
	var changed := false
	for i: int in 10:
		var e := resolver.before_pitch(game)
		if e == null:
			break
		_apply(e)
		changed = true
		if e.kind != GameEvent.Kind.SUBSTITUTION and not game.over:
			banner = last_text
			banner_time = 2.2
	if changed and not game.over:
		_dress_for_half()
		_new_duel()
		_place_cast()


func open_orders() -> void:
	if game.over:
		return
	orders.open()


# --- Keys ---


func _unhandled_input(event: InputEvent) -> void:
	if skip_broadcast(event):
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and not game.over:
		if orders.visible:
			if key.keycode == KEY_F or key.keycode == KEY_ESCAPE:
				orders.close()
				apply_orders_now()
				get_viewport().set_input_as_handled()
			return
		if not pause_menu.visible and not menu.visible:
			var handled := true
			match key.keycode:
				KEY_ENTER:
					intervene()
				KEY_F:
					open_orders()
				KEY_1:
					speed = 1.0
				KEY_2:
					speed = 2.0
				KEY_4:
					speed = 4.0
				KEY_SPACE:
					handled = not intervening
					if handled:
						paused = not paused
						if not paused and alert != "":
							alert = ""
							banner_time = 0.0
				KEY_RIGHT:
					handled = not intervening
					if handled:
						skip(key.shift_pressed)
				_:
					handled = false
			if handled:
				get_viewport().set_input_as_handled()
				return
	super._unhandled_input(event)


func _redraw_overlays() -> void:
	super._redraw_overlays()
	if board == null:
		return
	# The board takes the place of the batting and pitching displays; its own middle shows
	# the banner.
	if board_visible():
		hud.visible = false
		pitch_track.visible = false
		pip_rect.visible = false
	board.queue_redraw()
