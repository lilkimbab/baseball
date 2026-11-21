class_name QuickMatchScreen
extends Screen
## A quick game (docs/02 section 3, docs/05 section 5): two clubs, 3, 6 or 9 innings, which side
## the player takes (or watching), and how — full action (he bats and pitches) or managing
## (the computer plays, he gives orders and steps in).

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


func build() -> void:
	Settings.ensure_loaded()
	if _clubs.is_empty():
		_clubs = RosterIO.load_pack(LeagueSession.PACK)
	title("빠른 경기")
	var ids: Array = []
	var names: Array = []
	for i: int in _clubs.size():
		ids.append(str(i))
		names.append(_clubs[i].short_name)
	_club_grid("원정", away_index, func(i: int) -> void: away_index = i)
	_club_grid("홈", home_index, func(i: int) -> void: home_index = i)
	choices("이닝", ["1", "3", "6", "9"], ["1이닝(원정이면 치고 던지기 한 번씩)", "3이닝", "6이닝", "9이닝"], str(Settings.innings), func(v: String) -> void: Settings.innings = int(v))
	choices("내 편", ["away", "home", "watch"], ["원정", "홈", "관전"], side, func(v: String) -> void: side = v)
	choices("방식", ["action", "manager"], ["풀 액션(직접 치고 던진다)", "감독 지휘(작전과 개입)"], style, func(v: String) -> void: style = v)
	var park_ids: Array = [""]
	var park_names: Array = ["홈 구장"]
	for id: String in StadiumIO.ids():
		park_ids.append(id)
		park_names.append(StadiumIO.load_park(id).name)
	choices("구장", park_ids, park_names, park, func(v: String) -> void: park = v)
	choices("시간", ["day", "dusk", "night"], ["낮 14시", "해 질 녘 17시", "밤 18시 30분"], time, func(v: String) -> void: time = v)
	var r := row()
	button("경기 시작", start, r, 300.0)
	button("허브로", func() -> void: go(HUB), r, 200.0)


func _club_grid(label: String, current: int, pick: Callable) -> void:
	line(label, UiTheme.DIM, 18)
	var grid := GridContainer.new()
	grid.columns = 10
	content.add_child(grid)
	for i: int in _clubs.size():
		var b := Button.new()
		b.text = ("● " if i == current else "") + _clubs[i].short_name
		b.add_theme_font_size_override("font_size", 15)
		var idx := i
		b.pressed.connect(func() -> void:
			pick.call(idx)
			refresh())
		grid.add_child(b)


func start() -> void:
	if away_index == home_index:
		return
	pending = true
	go("res://match/manager_match.tscn" if style == "manager" else "res://match/match.tscn")


## The match screens' side for the player: 0 away, 1 home, −1 watching.
static func side_index() -> int:
	return {"away": 0, "home": 1, "watch": -1}.get(side, 1)
