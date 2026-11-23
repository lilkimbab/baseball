class_name DraftScreen
extends Screen
## Draft day (신인 드래프트; docs/08 R8-3; the user, 2026-11-23: "a KBO-style draft-day
## screen"): the clubs' order on the left, the picks called one by one on a board in the middle
## (round, pick, club, the man, his school and position), and his own card on the right. When
## his name is called the board stops and his card turns into the club's: the round and pick,
## the club, the bonus. Not called in eleven rounds: a developmental contract offered by a club.
## He signs and his first pro season begins.

## Seconds between two picks called; the board shows the latest ROWS.
const STEP := 0.22
const ROWS := 14

var _draft: Draft
var _shown := 0
var _clock := 0.0
var _stopped := false
var _board: VBoxContainer
var _card: VBoxContainer
var _clubs: Dictionary[String, Team] = {}


func setup() -> void:
	heading = "신인 드래프트"
	heading_latin = "KBO DRAFT"
	vantage = &"field"
	dock_id = "career"
	back = CareerSession.HUB


func _ready() -> void:
	_draft = CareerSession.hold_draft()
	for t: Team in LeagueSession.league_clubs():
		_clubs[t.id] = t
	super._ready()


func build() -> void:
	if _draft == null:
		var p := panel("신인 드래프트", "list-numbers", null, 0.0, "DRAFT")
		p.body.add_child(UiKit.label("고교 시즌을 마친 뒤에 열립니다.", 20, UiTheme.DIM, 500))
		return
	set_heading("%d KBO 신인 드래프트" % (_draft.year + 1), "%d개 구단 · %d라운드 · 전년도 성적 역순" % [_draft.order.size(), Draft.ROUNDS])
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	# The order.
	var order := panel("지명 순서", "list-numbers", columns, 300.0, "ORDER")
	for i: int in _draft.order.size():
		var row := UiKit.hbox(10)
		row.add_child(UiKit.number("%d" % (i + 1), 24, UiTheme.ACCENT))
		var club: Team = _clubs.get(_draft.order[i])
		if club != null:
			row.add_child(UiKit.club_mark(club, 34.0))
			row.add_child(UiKit.label(club.name, 17, UiTheme.INK, 600))
		order.body.add_child(row)
	# The board.
	var board := panel("지명 현황", "ranking", columns, 0.0, "BOARD")
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board = UiKit.vbox(4)
	board.body.add_child(_board)
	var actions := UiKit.hbox(10)
	board.body.add_child(actions)
	actions.add_child(UiKit.button("내 차례까지", skip_to_mine, "fast-forward"))
	actions.add_child(UiKit.button("끝까지", skip_to_end, "skip-forward"))
	# His card.
	var mine := panel("나의 드래프트", "user-circle", columns, 460.0, "MY PICK")
	_card = UiKit.vbox(10)
	mine.body.add_child(_card)
	_fill_board()
	_fill_card()


func _process(delta: float) -> void:
	if _draft == null or _stopped or _shown >= _draft.picks.size():
		return
	_clock += delta
	if _clock < STEP:
		return
	_clock = 0.0
	_shown += 1
	if _draft.picks[_shown - 1].mine:
		_stopped = true
	_fill_board()
	_fill_card()


## The latest picks called, newest at the top; his own in the club's colour.
func _fill_board() -> void:
	if _board == null:
		return
	for c: Node in _board.get_children():
		c.queue_free()
	var from := maxi(_shown - ROWS, 0)
	for i: int in range(_shown - 1, from - 1, -1):
		var p := _draft.picks[i]
		var row := UiKit.hbox(12)
		var tag := UiKit.label("%d라운드 %d순위" % [p.round, p.number], 16, UiTheme.ACCENT if p.mine else UiTheme.DIM, 600)
		tag.custom_minimum_size.x = 130.0
		row.add_child(tag)
		var club: Team = _clubs.get(p.team_id)
		if club != null:
			row.add_child(UiKit.club_mark(club, 30.0))
		var who := UiKit.label(p.name, 19, UiTheme.ACCENT if p.mine else Color.WHITE, 700)
		who.custom_minimum_size.x = 140.0
		row.add_child(who)
		row.add_child(UiKit.label("%s · %s" % [p.school, p.position], 16, UiTheme.DIM, 500))
		_board.add_child(row)
	if _shown == 0:
		_board.add_child(UiKit.label("곧 1라운드 지명이 시작됩니다.", 18, UiTheme.DIM, 500))


## His card: waiting, picked (the club, round and pick, bonus), or not picked (the offer).
func _fill_card() -> void:
	if _card == null:
		return
	for c: Node in _card.get_children():
		c.queue_free()
	var c := CareerSession.career
	var his := _draft.his
	var called := his != null and _shown >= his.overall
	var over := _shown >= _draft.picks.size()
	_card.add_child(UiKit.heading(c.player.name, 36))
	_card.add_child(UiKit.label("%s 3학년 · %s" % [_school_name(), CareerSession.career_season.rules.position_names.get(c.position, c.position)], 17, UiTheme.DIM, 500))
	if called:
		var club: Team = _clubs.get(his.team_id)
		var row := UiKit.hbox(14)
		row.add_child(UiKit.club_mark(club, 120.0))
		var words := UiKit.vbox(2)
		words.add_child(UiKit.latin("ROUND %d · PICK %d" % [his.round, his.number], 17, tint, true))
		words.add_child(UiKit.heading(club.name if club != null else his.team_id, 30))
		words.add_child(UiKit.label("%d라운드 %d순위 (전체 %d번)" % [his.round, his.number, his.overall], 18, UiTheme.INK, 600))
		row.add_child(words)
		_card.add_child(row)
		_card.add_child(UiKit.label("계약금 %s" % Draft.money_text(his.bonus), 24, UiTheme.ACCENT, 700))
		_card.add_child(UiKit.button("입단 계약", sign, "handshake", "primary", 320.0))
	elif over:
		var club: Team = _clubs.get(_draft.developmental_team)
		_card.add_child(UiKit.heading("지명받지 못했습니다", 26, UiTheme.DIM))
		if club != null:
			_card.add_child(UiKit.club_side(club, "OFFER", 84.0, 22))
			_card.add_child(UiKit.label("%s에서 육성선수 계약을 제안했습니다 (계약금 %s)." % [club.name, Draft.money_text(Draft.DEVELOPMENTAL_BONUS)], 18, UiTheme.INK, 500))
			_card.add_child(UiKit.button("육성선수 계약", sign, "check", "primary", 320.0))
	else:
		_card.add_child(UiKit.label("이름이 불리기를 기다리고 있습니다...", 19, UiTheme.INK, 500))
		if _shown > 0:
			var p := _draft.picks[_shown - 1]
			_card.add_child(UiKit.label("지금 %d라운드 %d순위까지" % [p.round, p.number], 16, UiTheme.DIM, 500))


func _school_name() -> String:
	var cs := CareerSession.career_season
	var team: Team = cs.season.teams.get(cs.career.team_id) if cs != null else null
	return team.name if team != null else ""


func skip_to_mine() -> void:
	if _draft == null:
		return
	_shown = _draft.his.overall if _draft.his != null else _draft.picks.size()
	_stopped = _draft.his != null
	refresh()


func skip_to_end() -> void:
	if _draft == null:
		return
	_shown = _draft.picks.size()
	_stopped = true
	refresh()


## Signs and starts his first pro season.
func sign() -> void:
	CareerSession.turn_pro()
	CareerSession.autosave()
	go(CareerSession.HUB, {"title": "프로 첫 시즌"})
