class_name QuickMatchScreen
extends Screen
## A quick game (docs/02 section 3, docs/05 section 5): the two clubs face each other across
## the screen, each with its strengths as bars and a list to pick another from; between them
## the game's length, which side the player takes (or watching), how — full action (he bats
## and pitches) or managing (the computer plays, he gives orders and steps in) — the park and
## the time of day.

static var away_index := 0
static var home_index := 1
static var side := "home"
static var style := "action"
## The park ("" for the home club's own) and the time of day (docs/13 S13).
static var park := ""
static var time := "day"
## The game the match screens read when they start from here; cleared when read.
static var pending := false

var _clubs: Array[Team] = []
var _strengths: Dictionary[String, Array] = {}


func setup() -> void:
	heading = "친선 경기"
	heading_latin = "EXHIBITION"
	heading_icon = "baseball"
	subheading = "두 팀을 선택하고 경기 조건을 정하세요"
	vantage = &"outfield"
	dock_id = "quick"


func build() -> void:
	Settings.ensure_loaded()
	if _clubs.is_empty():
		_clubs = RosterIO.load_pack(LeagueSession.PACK)
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	_club_panel(columns, "원정", away_index, func(i: int) -> void: away_index = i)
	_build_options(columns)
	_club_panel(columns, "홈", home_index, func(i: int) -> void: home_index = i)


func _build_options(parent: Control) -> void:
	var p := panel("경기 설정", "sliders-horizontal", parent, 620.0, "MATCH SETUP")
	var versus := UiKit.hbox(18)
	versus.alignment = BoxContainer.ALIGNMENT_CENTER
	versus.add_child(UiKit.club_mark(_clubs[away_index], 84.0))
	versus.add_child(UiKit.heading(_clubs[away_index].short_name, 28))
	versus.add_child(UiKit.number("VS", 52, Color(1.0, 1.0, 1.0, 0.9)))
	versus.add_child(UiKit.heading(_clubs[home_index].short_name, 28))
	versus.add_child(UiKit.club_mark(_clubs[home_index], 84.0))
	p.body.add_child(versus)
	p.body.add_child(UiKit.rule())
	_option(p, "이닝", ["1", "3", "6", "9"], ["1", "3", "6", "9"], str(Settings.innings), func(v: String) -> void: Settings.innings = int(v))
	if Settings.innings == 1:
		p.body.add_child(UiKit.label("1이닝 경기: 원정 팀으로 하면 공격과 수비를 한 번씩 합니다", 15, UiTheme.DIM, 500))
	_option(p, "플레이", ["away", "home", "watch"], ["원정 팀", "홈 팀", "관전"], side, func(v: String) -> void: side = v)
	_option(p, "방식", ["action", "manager"], ["풀 액션", "감독 지휘"], style, func(v: String) -> void: style = v)
	p.body.add_child(UiKit.label("풀 액션: 타격과 투구를 직접 조작 · 감독 지휘: 작전 지시와 승부처 개입", 15, UiTheme.DIM, 500))
	var park_ids: Array = [""]
	var park_names: Array = ["홈 구장"]
	for id: String in StadiumIO.ids():
		park_ids.append(id)
		park_names.append(StadiumIO.load_park(id).name)
	_option(p, "구장", park_ids, park_names, park, func(v: String) -> void: park = v)
	_option(p, "시간", ["day", "dusk", "night"], ["주간", "석양", "야간"], time, func(v: String) -> void: time = v)
	p.body.add_child(UiKit.spacer(0.0, 0.0, true))
	var start_button := UiKit.button("경기 시작", start, "play", "PrimaryButton")
	start_button.add_theme_font_size_override("font_size", 26)
	start_button.disabled = away_index == home_index
	p.body.add_child(start_button)
	if away_index == home_index:
		p.body.add_child(UiKit.label("서로 다른 두 팀을 선택하세요", 15, UiTheme.RED, 500))


func _option(p: GlassPanel, label: String, ids: Array, labels: Array, current: String, pick: Callable) -> void:
	var r := UiKit.hbox(12)
	p.body.add_child(r)
	var l := UiKit.label(label, 18, UiTheme.DIM, 600)
	l.custom_minimum_size.x = 90.0
	r.add_child(l)
	var grid := HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	r.add_child(grid)
	var group := ButtonGroup.new()
	for i: int in ids.size():
		var id := str(ids[i])
		var b := GameButton.make(str(labels[i]), func() -> void:
			pick.call(id)
			refresh(), "", "segment")
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = id == current
		grid.add_child(b)


## One side: the club chosen (emblem, name, strengths) over the list of all the clubs.
func _club_panel(parent: Control, label: String, current: int, pick: Callable) -> void:
	var team := _clubs[current]
	var p := GlassPanel.make(label, "users-three", 0.0, team.primary.lightened(0.25), "AWAY" if label == "원정" else "HOME")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var top := UiKit.hbox(16)
	p.body.add_child(top)
	top.add_child(UiKit.club_mark(team, 104.0))
	var words := UiKit.vbox(2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(UiKit.heading(team.name, 30))
	var s := strengths(team)
	words.add_child(UiKit.label("%d부 리그 · 종합 전력 %d" % [current / 10 + 1, roundi((float(s[0]) + float(s[1]) + float(s[2]) + float(s[3])) / 4.0)], 17, UiTheme.DIM, 500))
	top.add_child(words)
	for i: int in 4:
		p.body.add_child(StatBar.make(["컨택트", "파워", "투수력", "수비력"][i], float(s[i]), -1.0, 70.0))
	p.body.add_child(UiKit.rule())
	var table := DataTable.new()
	table.row_height = 34.0
	table.set_columns([["팀", 300.0, 0], ["리그", 60.0, 1], ["전력", 60.0, 2]])
	for i: int in _clubs.size():
		var c := strengths(_clubs[i])
		var overall := (float(c[0]) + float(c[1]) + float(c[2]) + float(c[3])) / 4.0
		table.add_row([_clubs[i].name, "%d부" % (i / 10 + 1), "%d" % roundi(overall)], i, {2: UiTheme.rating_color(overall)})
	table.selected = current
	table.row_pressed.connect(func(_row: int, tag: Variant) -> void:
		pick.call(int(tag))
		refresh())
	p.body.add_child(table)


## A club's strengths from its first team: contact, power, pitching, fielding (0..99).
func strengths(team: Team) -> Array:
	if _strengths.has(team.id):
		return _strengths[team.id]
	var contact := 0.0
	var power := 0.0
	var fielding := 0.0
	var pitching := 0.0
	var hitters := 0
	var pitchers := 0
	for p: Player in team.first_team():
		if p.is_pitcher():
			pitching += (p.pitching.control + p.pitching.composure) * 0.5
			pitchers += 1
		else:
			contact += p.batting.contact()
			power += p.batting.power()
			fielding += p.fielding.overall()
			hitters += 1
	var out := [contact / maxf(hitters, 1.0), power / maxf(hitters, 1.0), pitching / maxf(pitchers, 1.0), fielding / maxf(hitters, 1.0)]
	_strengths[team.id] = out
	return out


func start() -> void:
	if away_index == home_index:
		return
	pending = true
	var where := StadiumIO.load_park(park).name if park != "" else StadiumIO.load_park(MatchScene.home_park(_clubs[home_index].id)).name
	var when: String = {"day": "주간 경기", "dusk": "석양 경기", "night": "야간 경기"}.get(time, "")
	go("res://match/manager_match.tscn" if style == "manager" else "res://match/match.tscn",
		{"away": _clubs[away_index], "home": _clubs[home_index], "title": "친선 경기", "line": "%s · %s · %d이닝" % [where, when, Settings.innings]})


## The match screens' side for the player: 0 away, 1 home, −1 watching.
static func side_index() -> int:
	return {"away": 0, "home": 1, "watch": -1}.get(side, 1)
