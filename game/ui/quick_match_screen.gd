class_name QuickMatchScreen
extends Screen
## A quick game (docs/04 section 5): the two clubs face each other across
## the screen, each with its strengths as bars and a list to pick another from; between them
## the game's length, which side the player takes (or watching), how — full action (he bats
## and pitches) or managing (the computer plays, he gives orders and steps in) — the park and
## the time of day.

static var away_index := 0
static var home_index := 1
static var side := "home"
static var style := "action"
## The park ("" for the home club's own) and the time of day.
static var park := ""
static var time := "day"
## The game the match screens read when they start from here; cleared when read.
static var pending := false
## The roster pack the two clubs come from: "" the game's own fictional league, or the path of
## one in the local content pack (a real season, RosterIO.local_packs).
static var roster := ""

var _clubs: Array[Team] = []
var _strengths: Dictionary[String, Array] = {}


func setup() -> void:
	heading = "친선 경기"
	heading_latin = "EXHIBITION"
	heading_icon = "baseball"
	vantage = &"outfield"
	dock_id = "quick"


func build() -> void:
	Settings.ensure_loaded()
	if _clubs.is_empty():
		if roster != "" and not FileAccess.file_exists(roster):
			roster = ""
		_clubs = RosterIO.load_pack(roster_path())
		away_index = clampi(away_index, 0, _clubs.size() - 1)
		home_index = clampi(home_index, 0, _clubs.size() - 1)
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	_club_panel(columns, "원정", away_index, func(i: int) -> void: away_index = i)
	_build_options(columns)
	_club_panel(columns, "홈", home_index, func(i: int) -> void: home_index = i)


## The middle: the match-up, and the game's settings as selectors (◀ value ▶), as a game's
## exhibition screen sets them up.
func _build_options(parent: Control) -> void:
	var p := panel("경기 설정", "sliders-horizontal", parent, 560.0, "MATCH SETUP")
	var versus := UiKit.hbox(14)
	versus.alignment = BoxContainer.ALIGNMENT_CENTER
	versus.add_child(UiKit.club_mark(_clubs[away_index], 96.0))
	versus.add_child(UiKit.number("VS", 60, Color(1.0, 1.0, 1.0, 0.92)))
	versus.add_child(UiKit.club_mark(_clubs[home_index], 96.0))
	p.body.add_child(versus)
	var names := UiKit.hbox(0)
	p.body.add_child(names)
	for t: Team in [_clubs[away_index], _clubs[home_index]]:
		var n := UiKit.heading(t.name, 22)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.add_child(n)
	p.body.add_child(UiKit.rule())
	# A real season's clubs, when the local content pack has one.
	var packs := RosterIO.local_packs()
	if not packs.is_empty():
		var ids: Array = [""]
		var labels: Array = ["가상 리그"]
		for pair: Array in packs:
			ids.append(str(pair[0]))
			labels.append(str(pair[1]))
		p.body.add_child(UiKit.selector("로스터", ids, labels, roster, func(v: String) -> void:
			roster = v
			_clubs = []
			_strengths.clear()
			away_index = 0
			home_index = 1
			refresh()))
	p.body.add_child(UiKit.selector("이닝", ["1", "3", "6", "9"], ["1이닝", "3이닝", "6이닝", "9이닝"], str(Settings.innings), func(v: String) -> void:
		Settings.innings = int(v)
		refresh()))
	p.body.add_child(UiKit.selector("플레이", ["away", "home", "watch"], ["원정 팀", "홈 팀", "관전"], side, func(v: String) -> void:
		side = v
		refresh()))
	p.body.add_child(UiKit.selector("방식", ["action", "manager"], ["풀 액션", "감독 지휘"], style, func(v: String) -> void:
		style = v
		refresh()))
	var park_ids: Array = [""]
	var park_names: Array = ["홈 구장 (%s)" % MatchScene.home_def(_clubs[home_index]).name]
	for id: String in StadiumIO.ids():
		park_ids.append(id)
		park_names.append(StadiumIO.load_park(id).name)
	p.body.add_child(UiKit.selector("구장", park_ids, park_names, park, func(v: String) -> void:
		park = v
		refresh()))
	p.body.add_child(UiKit.selector("시간", ["day", "dusk", "night"], ["주간", "석양", "야간"], time, func(v: String) -> void:
		time = v
		refresh()))
	p.body.add_child(UiKit.spacer(0.0, 0.0, true))
	var start_button := UiKit.button("경기 시작", start, "play", "primary")
	start_button.add_theme_font_size_override("font_size", 28)
	start_button.disabled = away_index == home_index
	p.body.add_child(start_button)


## One side: a band in the club's colours with its emblem, name and strength, its best hitter
## standing in the uniform; its strengths as bars; the clubs to switch to as a grid of emblems.
func _club_panel(parent: Control, label: String, current: int, pick: Callable) -> void:
	var team := _clubs[current]
	var p := GlassPanel.make("", "", 0.0, team.primary.lightened(0.25), "")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var band := UiKit.band(team.primary, 236.0)
	p.body.add_child(band)
	var row := UiKit.hbox(10)
	band.get_child(1).add_child(row)
	var words := UiKit.vbox(2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	var top := UiKit.hbox(12)
	words.add_child(top)
	top.add_child(UiKit.club_mark(team, 104.0))
	var s := strengths(team)
	var overall := roundi((float(s[0]) + float(s[1]) + float(s[2]) + float(s[3])) / 4.0)
	var power := UiKit.tile(UiTheme.shown_text(overall), "전력", 92.0, 34)
	power.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(power)
	words.add_child(UiKit.latin("AWAY" if label == "원정" else "HOME", 18, UiTheme.ACCENT, true))
	words.add_child(UiKit.heading(team.name, 30))
	var star := _star(team)
	if star != null:
		var stage := PlayerStage.make(150.0, 220.0)
		stage.show_player(star, team, label == "홈")
		row.add_child(stage)
	var bars := UiKit.vbox(2)
	p.body.add_child(bars)
	for i: int in 4:
		var bar := StatBar.make(["컨택트", "파워", "투수력", "수비력"][i], float(s[i]), -1.0, 64.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bars.add_child(bar)
	p.body.add_child(UiKit.rule())
	var scroll := UiKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.body.add_child(scroll)
	scroll.add_child(UiKit.emblem_grid(_clubs, current, func(i: int) -> void:
		pick.call(i)
		refresh(), 5, 46.0))


## A club's best hitter (contact and power), to stand for it.
func _star(team: Team) -> Player:
	var best: Player = null
	var best_score := -1.0
	for p: Player in team.first_team():
		if not p.is_pitcher() and p.batting.contact() + p.batting.power() > best_score:
			best = p
			best_score = p.batting.contact() + p.batting.power()
	return best


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
	var where := StadiumIO.load_park(park).name if park != "" else MatchScene.home_def(_clubs[home_index]).name
	var when: String = {"day": "주간 경기", "dusk": "석양 경기", "night": "야간 경기"}.get(time, "")
	go("res://match/manager_match.tscn" if style == "manager" else "res://match/match.tscn",
		{"away": _clubs[away_index], "home": _clubs[home_index], "title": "친선 경기", "line": "%s · %s · %d이닝" % [where, when, Settings.innings]})


## The match screens' side for the player: 0 away, 1 home, −1 watching.
static func side_index() -> int:
	return {"away": 0, "home": 1, "watch": -1}.get(side, 1)


## The pack the clubs are read from.
static func roster_path() -> String:
	return roster if roster != "" else LeagueSession.PACK
