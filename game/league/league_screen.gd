class_name LeagueScreen
extends Screen
## The league mode (docs/02 sections 4 and 5, docs/13 S7): start a season with a club in the
## third division, then go day by day. Its tabs: today (the day's game as a match-up — played
## on screen as a managed game or settled at once — beside the division table, the postseason
## ladder or the season's end), the first team, the second team, scouting and traits. In the
## lists a player is picked with a click: he stands on the right with his main ratings and
## what can be done with him.

const GAME_CHOICES: Array[int] = [36, 72, 144]
const SEASON_TABS: Array[Array] = [["home", "오늘"], ["roster", "1군"], ["farm", "2군"], ["scout", "스카우트"], ["traits", "특성"]]
const FOCUS_NAMES := {"batting": "타격", "running": "주루", "fielding": "수비", "stuff": "구위", "control": "제구", "breaking": "변화"}

var message := ""
var _tab := "home"
var _games := 36
var _choice := ""
## The player picked in a list (his id), and the trait picked in the bag (its index).
var _picked := ""
var _picked_trait := -1
var _rng := Rng.new(1)


func setup() -> void:
	heading = "리그 모드"
	heading_latin = "LEAGUE"
	vantage = &"dugout"
	dock_id = "league"


func _ready() -> void:
	_rng = Rng.new(int(Time.get_unix_time_from_system()) % 100000)
	if LeagueSession.season != null:
		LeagueSession.season.play_day()
		LeagueSession.autosave()
	super._ready()


func refresh() -> void:
	if is_inside_tree() and LeagueSession.season != null:
		LeagueSession.autosave()
	super.refresh()


func build() -> void:
	if LeagueSession.season == null:
		_build_setup()
	else:
		_build_season()


# --- A new season ---


func _build_setup() -> void:
	set_heading("리그 모드", "지휘할 구단을 선택하세요 · 3부 리그에서 시작합니다")
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var left := panel("구단 선택", "users-three", columns, 640.0, "SELECT CLUB")
	var table := DataTable.new()
	table.row_height = 52.0
	table.set_columns([["구단", 420.0, 0], ["전력", 90.0, 2]])
	var chosen: Team = null
	for i: int in range(20, mini(30, clubs.size())):
		var t := clubs[i]
		var power := _strength(t)
		var row := table.add_row([t.name, "%d" % roundi(power)], t.id, {1: UiTheme.rating_color(power)})
		if t.id == _choice:
			table.selected = row
			chosen = t
	table.row_pressed.connect(func(_row: int, tag: Variant) -> void:
		_choice = str(tag)
		refresh())
	left.body.add_child(table)
	var right := panel("새 시즌", "flag-pennant", columns, 0.0, "NEW SEASON")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if chosen != null:
		var top := UiKit.hbox(24)
		right.body.add_child(top)
		top.add_child(UiKit.club_mark(chosen, 180.0))
		var words := UiKit.vbox(6)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		words.add_child(UiKit.latin("YOUR CLUB", 18, tint, true))
		words.add_child(UiKit.heading(chosen.name, 44))
		words.add_child(StatBar.make("종합 전력", _strength(chosen), -1.0, 110.0))
		top.add_child(words)
	else:
		right.body.add_child(UiKit.label("왼쪽 목록에서 구단을 선택하세요.", 20, UiTheme.DIM, 500))
	right.body.add_child(UiKit.rule())
	choices("시즌 길이", ["36", "72", "144"], ["36경기", "72경기", "144경기"], str(_games), func(v: String) -> void: _games = int(v), right.body)
	right.body.add_child(UiKit.label("상위 4팀이 포스트시즌에 진출하고, 우승·준우승 팀은 상위 리그로 승격합니다.", 16, UiTheme.DIM, 500))
	right.body.add_child(UiKit.spacer(0.0, 0.0, true))
	var start := UiKit.button("시즌 시작", func() -> void: begin(_choice, _games), "play", "primary")
	start.add_theme_font_size_override("font_size", 26)
	start.disabled = _choice == ""
	right.body.add_child(start)


## A club's strength as one number: its first team's batting, pitching and fielding.
static func _strength(team: Team) -> float:
	var total := 0.0
	var n := 0
	for p: Player in team.first_team():
		total += (p.pitching.control + p.pitching.composure) * 0.5 if p.is_pitcher() else (p.batting.contact() + p.batting.power() + p.fielding.overall()) / 3.0
		n += 1
	return total / maxf(n, 1.0)


## Starts a season with a club (also used by tests).
func begin(team_id: String, games: int) -> void:
	LeagueSession.start(team_id, games, _rng.next_int(1000000))
	LeagueSession.season.play_day()
	message = "%s의 시즌이 시작되었습니다." % LeagueSession.season.teams[team_id].name
	_tab = "home"
	refresh()


# --- The season ---


func _build_season() -> void:
	var s := LeagueSession.season
	var team: Team = s.teams[s.my_team]
	var d := s.division_of(s.my_team)
	var standing := s.standings[d].row(s.my_team)
	var phase: String = ["정규 시즌", "포스트시즌", "시즌 종료"][s.phase]
	set_heading(team.name, "%d부 리그 · %d년 %s %d일차 · %d승 %d패 %d무 · %d위" % [d + 1, s.season_year, phase, s.day + 1, standing.wins, standing.losses, standing.ties, s.standings[d].rank_of(s.my_team)])
	if tab_bar != null:
		var ids: Array = []
		var labels: Array = []
		for pair: Array in SEASON_TABS:
			ids.append(pair[0])
			labels.append(pair[1])
		var tabs := UiKit.tabs(ids, labels, _tab, func(id: String) -> void:
			_tab = id
			_picked = ""
			_picked_trait = -1
			refresh())
		for b: Node in tabs.get_children():
			(b as GameButton).tint = tint
		tab_bar.add_child(tabs)
	match _tab:
		"roster":
			_build_list("roster", team.first_team(), s, team, "훈련은 하루 %d명까지 지정할 수 있습니다." % s.club_rules.train_per_day)
		"farm":
			_build_list("farm", team.second_team(), s, team, "2군 선수를 1군에 등록하거나 방출할 수 있습니다.")
		"scout":
			_build_list("scout", s.club.candidates, s, team, "오늘의 영입 후보입니다. 하루에 한 명만 영입할 수 있습니다." + ("  (오늘은 이미 영입했습니다)" if s.club.signed_today else ""))
		"traits":
			_build_traits(s)
		_:
			_build_home(s, team, d)


func _build_home(s: Season, team: Team, d: int) -> void:
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var left := UiKit.vbox(16)
	left.custom_minimum_size.x = 800.0
	columns.add_child(left)
	_build_today(left, s)
	_build_club(left, s, team, d)
	match s.phase:
		Season.Phase.REGULAR:
			_build_table(columns, s)
		Season.Phase.POSTSEASON:
			_build_ladder(columns, s)
		Season.Phase.OVER:
			_build_end(columns, s)


func _build_today(parent: Control, s: Season) -> void:
	var p := panel("오늘의 경기", "calendar-blank", parent, 0.0, "DAY %d" % (s.day + 1))
	var g := s.my_game_today()
	if g != null:
		var row := UiKit.hbox(18)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		p.body.add_child(row)
		row.add_child(UiKit.club_side(s.teams[g.away], "AWAY", 92.0, 24))
		if g.played:
			row.add_child(UiKit.number("%d : %d" % [g.away_score, g.home_score], 64, Color.WHITE))
		else:
			row.add_child(UiKit.number("VS", 56, Color(1.0, 1.0, 1.0, 0.9)))
		row.add_child(UiKit.club_side(s.teams[g.home], "HOME", 92.0, 24))
		var post := s.postseason_of(g)
		if post != null:
			p.body.add_child(_centered("%s %d차전" % [post.round_name(), g.game_in_series], UiTheme.ACCENT))
		if g.played:
			var word := _result_word(g)
			p.body.add_child(_centered({"승": "승리", "패": "패배", "무": "무승부"}[word], {"승": UiTheme.GREEN, "패": UiTheme.RED, "무": UiTheme.DIM}[word], 24))
	elif s.phase != Season.Phase.OVER:
		p.body.add_child(UiKit.label("오늘은 경기가 없습니다.", 20, UiTheme.DIM, 500))
	else:
		p.body.add_child(UiKit.label("시즌이 종료되었습니다. 오른쪽에서 결과를 확인하세요.", 20, UiTheme.DIM, 500))
	var actions := UiKit.hbox(10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	p.body.add_child(actions)
	if g != null and not g.played:
		var play := UiKit.button("경기 시작", play_on_screen, "play", "primary", 260.0)
		play.add_theme_font_size_override("font_size", 24)
		actions.add_child(play)
		actions.add_child(UiKit.button("빠른 결과", quick_result, "fast-forward"))
	elif s.phase != Season.Phase.OVER:
		actions.add_child(UiKit.button("다음 날", next_day, "caret-right", "primary", 200.0))
	if s.phase != Season.Phase.OVER:
		actions.add_child(UiKit.button("다음 경기까지", to_next_game, "skip-forward"))
		actions.add_child(UiKit.button("정규 시즌 끝까지" if s.phase == Season.Phase.REGULAR else "포스트시즌 끝까지", to_phase_end, "fast-forward"))
	if message != "":
		p.body.add_child(_centered(message, UiTheme.ACCENT))


func _centered(text: String, colour: Color, font_size: int = 18) -> Label:
	var l := UiKit.label(text, font_size, colour, 600)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## The club at a glance (points, the first team's cost against the cap, team colours) and its
## last games.
func _build_club(parent: Control, s: Season, team: Team, d: int) -> void:
	var p := panel("구단 현황", "chart-bar", parent, 0.0, "CLUB")
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var c := s.club
	var r := s.club_rules
	var colours := PackedStringArray()
	for a: ClubRules.ColorDef in TeamColors.active(team, c, r, s.ovr, s.catalog):
		colours.append(a.name)
	var figures := UiKit.hbox(0)
	p.body.add_child(figures)
	for pair: Array in [["%d" % c.points, "구단 포인트"], ["%d / %d" % [r.first_team_cost(team, s.ovr, s.catalog), r.cost_cap(d)], "1군 코스트"], ["%d" % team.first_team().size(), "1군 등록"]]:
		var f := UiKit.figure(str(pair[0]), str(pair[1]), UiTheme.INK, 30)
		f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		figures.add_child(f)
	p.body.add_child(UiKit.label("팀 컬러: %s" % (", ".join(colours) if not colours.is_empty() else "없음"), 16, UiTheme.DIM, 500))
	p.body.add_child(UiKit.rule())
	p.body.add_child(UiKit.caption("최근 경기"))
	var recent: Array[ScheduledGame] = []
	for sched: Schedule in s.schedules:
		for game: ScheduledGame in sched.games:
			if game.played and game.involves(s.my_team):
				recent.append(game)
	var strip := UiKit.hbox(8)
	p.body.add_child(strip)
	for game: ScheduledGame in recent.slice(maxi(recent.size() - 7, 0)):
		var other: Team = s.teams[game.opponent_of(s.my_team)]
		var word := _result_word(game)
		var cell := UiKit.well(8.0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		strip.add_child(cell)
		var box := UiKit.vbox(0)
		cell.add_child(box)
		var result := UiKit.heading(word, 20, {"승": UiTheme.GREEN, "패": UiTheme.RED, "무": UiTheme.DIM}[word])
		result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(result)
		var score := UiKit.latin("%d-%d" % [game.runs_of(s.my_team), game.runs_against(s.my_team)], 22, Color.WHITE)
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(score)
		var who := UiKit.label("%s %s" % ["vs" if game.home == s.my_team else "@", other.short_name], 14, UiTheme.DIM, 500)
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(who)
	if recent.is_empty():
		p.body.add_child(UiKit.label("아직 치른 경기가 없습니다.", 16, UiTheme.DIM, 500))


func _result_word(g: ScheduledGame) -> String:
	var s := LeagueSession.season
	if g.is_tie():
		return "무"
	return "승" if g.winner() == s.my_team else "패"


func _build_table(parent: Control, s: Season) -> void:
	var d := s.division_of(s.my_team)
	var p := panel("%d부 리그 순위" % (d + 1), "ranking", parent, 0.0, "STANDINGS")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var table := DataTable.new()
	table.row_height = 46.0
	table.set_columns([["순위", 60.0, 1], ["구단", 300.0, 0], ["승", 60.0, 2], ["패", 60.0, 2], ["무", 60.0, 2], ["승률", 90.0, 2], ["게임차", 90.0, 2], ["연속", 90.0, 2]])
	var i := 0
	for row: StandingsRow in s.standings[d].ranked():
		i += 1
		var colours := {0: UiTheme.ACCENT if i <= 4 else UiTheme.DIM}
		var at := table.add_row([str(i), s.teams[row.team_id].name, str(row.wins), str(row.losses), str(row.ties), row.pct_text(), "%.1f" % s.standings[d].games_behind(row.team_id), row.streak_text()], row.team_id, colours)
		if row.team_id == s.my_team:
			table.selected = at
	p.body.add_child(table)
	p.body.add_child(UiKit.label("상위 4팀 포스트시즌 진출 · 하위 2팀 강등(1부 제외) · 포스트시즌 우승·준우승 팀 승격", 15, UiTheme.DIM, 500))


func _build_ladder(parent: Control, s: Season) -> void:
	var d := s.division_of(s.my_team)
	var post := s.postseasons[d]
	var p := panel("%d부 포스트시즌" % (d + 1), "trophy", parent, 0.0, "POSTSEASON")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i: int in post.seeds.size():
		var row := UiKit.hbox(12)
		p.body.add_child(row)
		row.add_child(UiKit.number("%d" % (i + 1), 30, UiTheme.ACCENT))
		row.add_child(UiKit.club_mark(s.teams[post.seeds[i]], 44.0))
		row.add_child(UiKit.heading(s.teams[post.seeds[i]].name, 22, Color.WHITE if post.seeds[i] == s.my_team else Color(1.0, 1.0, 1.0, 0.75)))
	p.body.add_child(UiKit.rule())
	for r: int in post.rounds.size():
		var sr := post.rounds[r]
		var state := ("  ·  %s 승리" % s.teams[sr.winner()].short_name) if sr.finished() else ""
		var well := UiKit.well(12.0)
		p.body.add_child(well)
		well.add_child(UiKit.label("%s (%d전 %d선승)   %s  %d - %d  %s%s" % [Postseason.ROUND_NAMES[r], sr.length(), sr.wins_needed, s.teams[sr.high].short_name, sr.high_wins, sr.low_wins, s.teams[sr.low].short_name, state], 19, UiTheme.INK, 600))
	if not post.seeds.has(s.my_team):
		p.body.add_child(UiKit.label("포스트시즌에 진출하지 못했습니다.", 18, UiTheme.DIM, 500))


func _build_end(parent: Control, s: Season) -> void:
	var d := s.division_of(s.my_team)
	var p := panel("%d년 시즌 결과" % s.season_year, "trophy", parent, 0.0, "FINAL")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var moves := s.movements()
	var up: PackedStringArray = moves[d][0]
	var down: PackedStringArray = moves[d][1]
	var verdict := "잔류"
	if up.has(s.my_team):
		verdict = "%d부 리그 승격" % d
	elif down.has(s.my_team):
		verdict = "%d부 리그 강등" % (d + 2)
	elif d == 0 and s.postseasons[0].champion() == s.my_team:
		verdict = "1부 리그 우승"
	p.body.add_child(UiKit.latin("RESULT", 18, tint, true))
	p.body.add_child(UiKit.heading(verdict, 44, UiTheme.ACCENT))
	for div: int in s.divisions.size():
		var post := s.postseasons[div]
		p.body.add_child(UiKit.label("%d부 리그   우승 %s  ·  준우승 %s" % [div + 1, s.teams[post.champion()].name, s.teams[post.runner_up()].name], 18, UiTheme.INK if div == d else UiTheme.DIM, 600))
	p.body.add_child(UiKit.rule())
	var awards := SeasonAwards.for_division(s, d, s.season_year)
	p.body.add_child(UiKit.caption("%d부 리그 시상" % (d + 1)))
	for a: SeasonAwards.Award in [awards.mvp, awards.pitcher, awards.rookie]:
		if a != null:
			p.body.add_child(UiKit.label(awards.line(a), 17, UiTheme.INK, 600))
	for a: SeasonAwards.Award in awards.titles:
		p.body.add_child(UiKit.label("%s  %s  %s" % [a.title, awards._name(a.player_id), a.text], 15, UiTheme.DIM, 500))
	p.body.add_child(UiKit.spacer(0.0, 0.0, true))
	p.body.add_child(UiKit.button("다음 시즌 시작", func() -> void:
		LeagueSession.next_season(_rng.next_int(1000000))
		LeagueSession.season.play_day()
		message = "%d년 시즌이 시작되었습니다." % LeagueSession.season.season_year
		refresh(), "play", "primary"))


# --- The club's players ---


func _player_line(s: Season, p: Player) -> Array[String]:
	var ovr := ClubRules.player_ovr(p, s.ovr, s.catalog)
	var role := String(p.role()) if p.is_pitcher() else Position.code(p.primary_position())
	var tr := ""
	if s.club.traits.has(p.id):
		var item := s.club.traits[p.id]
		tr = "%s %d" % [s.club_rules.traits[item.x].name, item.y + 1]
	return [role, p.name + (" ★" if p.is_foreign() else ""), s.club_rules.grade_of(ovr).name, str(roundi(ovr)), s.condition_name(p.id), tr]


## A list of players (the first team, the second team or the day's candidates) with the one
## picked standing beside it.
func _build_list(kind: String, players: Array[Player], s: Season, team: Team, note: String) -> void:
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var titles := {"roster": ["1군 로스터", "ROSTER"], "farm": ["2군", "FARM"], "scout": ["스카우트", "SCOUTING"]}
	var p := panel("%s  %d명" % [titles[kind][0], players.size()], "users-three", columns, 0.0, str(titles[kind][1]))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.body.add_child(UiKit.label(note, 16, UiTheme.DIM, 500))
	var table := DataTable.new()
	table.set_columns([["포지션", 80.0, 1], ["선수", 230.0, 0], ["등급", 70.0, 1], ["OVR", 70.0, 2], ["나이" if kind == "scout" else "컨디션", 90.0, 1], ["특성", 150.0, 0], ["훈련", 90.0, 1]])
	var picked: Player = null
	for player: Player in players:
		var cells: Array = _player_line(s, player)
		var ovr := float(cells[3])
		if kind == "scout":
			cells[4] = "%d세" % (s.season_year - player.born)
		var focus := s.club.training.get(player.id, "") as String
		cells.append(str(FOCUS_NAMES.get(focus, "-")) if kind == "roster" else "-")
		var at := table.add_row(cells, player.id, {0: UiTheme.CYAN if player.is_pitcher() else UiTheme.GREEN, 2: UiTheme.ACCENT, 3: UiTheme.rating_color(ovr), 6: UiTheme.ACCENT})
		if player.id == _picked:
			table.selected = at
			picked = player
	table.row_pressed.connect(func(_row: int, tag: Variant) -> void:
		_picked = str(tag)
		refresh())
	p.body.add_child(table)
	if message != "":
		p.body.add_child(UiKit.label(message, 17, UiTheme.ACCENT, 600))
	_build_picked(columns, kind, picked, s, team)


## The player picked in a list: the man, his main ratings, and what can be done with him.
func _build_picked(parent: Control, kind: String, p: Player, s: Season, team: Team) -> void:
	var side := panel("선수 정보", "identification-card", parent, 520.0, "PLAYER")
	if p == null:
		side.body.add_child(UiKit.label("목록에서 선수를 선택하세요.", 18, UiTheme.DIM, 500))
		return
	var ovr := ClubRules.player_ovr(p, s.ovr, s.catalog)
	var top := UiKit.hbox(8)
	side.body.add_child(top)
	var stage := PlayerStage.make(250.0, 360.0)
	stage.show_player(p, team)
	top.add_child(stage)
	var words := UiKit.vbox(2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_child(UiKit.latin("No.%d" % p.number, 22, tint, true))
	words.add_child(UiKit.heading(p.name, 34))
	var role := ("선발 투수" if p.role() == &"SP" else "구원 투수") if p.is_pitcher() else Position.name_of(p.primary_position())
	words.add_child(UiKit.label("%s · %d세" % [role, s.season_year - p.born], 17, UiTheme.DIM, 500))
	words.add_child(UiKit.label("%dcm · %dkg" % [roundi(p.height_cm), roundi(p.weight_kg)], 17, UiTheme.DIM, 500))
	var figures := UiKit.hbox(18)
	figures.add_child(UiKit.figure("%d" % roundi(ovr), "OVR", UiTheme.rating_color(ovr), 44))
	figures.add_child(UiKit.figure(s.club_rules.grade_of(ovr).name, "등급", UiTheme.ACCENT, 44))
	words.add_child(figures)
	top.add_child(words)
	if p.is_pitcher():
		side.body.add_child(StatBar.make("구위", p.pitching.stuff(s.catalog), -1.0, 100.0))
		side.body.add_child(StatBar.make("제구", p.pitching.control, -1.0, 100.0))
		side.body.add_child(StatBar.make("체력", p.pitching.stamina, -1.0, 100.0))
		side.body.add_child(StatBar.make("변화구", p.pitching.breaking(s.catalog), -1.0, 100.0))
	else:
		side.body.add_child(StatBar.make("컨택트", p.batting.contact(), -1.0, 100.0))
		side.body.add_child(StatBar.make("파워", p.batting.power(), -1.0, 100.0))
		side.body.add_child(StatBar.make("선구안", p.batting.eye, -1.0, 100.0))
		side.body.add_child(StatBar.make("주력", p.batting.speed, -1.0, 100.0))
		side.body.add_child(StatBar.make("수비", p.fielding.overall(), -1.0, 100.0))
	side.body.add_child(UiKit.spacer(0.0, 0.0, true))
	var actions := UiKit.hbox(8)
	side.body.add_child(actions)
	actions.add_child(UiKit.button("선수 카드", func() -> void: PlayerCard.open_for(self, p, s), "identification-card"))
	match kind:
		"roster":
			var focus := s.club.training.get(p.id, "") as String
			actions.add_child(UiKit.button("훈련: %s" % str(FOCUS_NAMES.get(focus, "없음")), func() -> void:
				_cycle_training(s, p)
				refresh(), "barbell"))
			actions.add_child(UiKit.button("말소", func() -> void:
				team.unregister(p.id, s.day)
				message = "%s 선수를 말소했습니다. %d일 뒤 다시 등록할 수 있습니다." % [p.name, Team.RECALL_DAYS]
				_picked = ""
				refresh(), "arrow-right"))
		"farm":
			actions.add_child(UiKit.button("1군 등록", func() -> void:
				message = register(p)
				refresh(), "plus", "primary"))
			actions.add_child(UiKit.button("방출", func() -> void:
				s.club.release(p.id, team, s.club_rules)
				message = "%s 선수를 방출했습니다." % p.name
				_picked = ""
				refresh(), "trash"))
		"scout":
			var sign := UiKit.button("영입", func() -> void:
				var signed := s.club.sign(s.club.candidates.find(p), team, s.club_rules)
				message = "%s 선수를 영입했습니다." % signed.name if signed != null else "영입할 수 없습니다."
				_picked = ""
				refresh(), "handshake", "primary")
			sign.disabled = s.club.signed_today
			actions.add_child(sign)


## Puts a second-team player on the first team, within the roster rules and the cost cap.
func register(p: Player) -> String:
	var s := LeagueSession.season
	var team: Team = s.teams[s.my_team]
	var problem := team.registration_problem(p.id, s.day, s.rules)
	if problem != "":
		return "등록할 수 없다: " + problem
	var cost := s.club_rules.first_team_cost(team, s.ovr, s.catalog) + s.club_rules.grade_of(ClubRules.player_ovr(p, s.ovr, s.catalog)).cost
	var cap := s.club_rules.cost_cap(s.division_of(s.my_team))
	if cost > cap:
		return "등록할 수 없다: 1군 코스트 %d이 상한 %d을 넘는다" % [cost, cap]
	team.register(p.id, s.day, s.rules)
	return "%s 1군 등록." % p.name


func _build_traits(s: Season) -> void:
	var c := s.club
	var r := s.club_rules
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var p := panel("보유 특성  %d개" % c.bag.size(), "sparkle", columns, 0.0, "TRAITS")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.body.add_child(UiKit.label("같은 특성, 같은 단계 두 개를 합성하면 한 단계 올라갑니다(최대 3단계).", 16, UiTheme.DIM, 500))
	var table := DataTable.new()
	table.set_columns([["특성", 200.0, 0], ["단계", 70.0, 1], ["대상", 90.0, 1], ["효과", 520.0, 0]])
	for i: int in c.bag.size():
		var item := c.bag[i]
		var def := r.traits[item.x]
		var at := table.add_row([def.name, "%d" % (item.y + 1), "타자" if def.kind == &"batter" else "투수", def.note], i, {1: UiTheme.ACCENT})
		if i == _picked_trait:
			table.selected = at
	table.row_pressed.connect(func(_row: int, tag: Variant) -> void:
		_picked_trait = int(tag)
		refresh())
	p.body.add_child(table)
	var side := panel("특성 관리", "sliders-horizontal", columns, 460.0, "MANAGE")
	side.body.add_child(UiKit.figure("%d" % c.points, "구단 포인트", UiTheme.ACCENT, 40))
	side.body.add_child(UiKit.button("특성 뽑기 (%d 포인트)" % int(r.points.get("trait", 0)), func() -> void:
		var pick := c.buy_trait(r, _rng)
		message = ("%s 특성을 획득했습니다." % r.traits[pick].name) if pick >= 0 else "포인트가 부족합니다."
		refresh(), "gift", "primary"))
	var pair := c.mergeable(r)
	if pair.x >= 0:
		side.body.add_child(UiKit.button("합성: %s %d단계 → %d단계" % [r.traits[c.bag[pair.x].x].name, c.bag[pair.x].y + 1, c.bag[pair.x].y + 2], func() -> void:
			c.merge(pair.x, pair.y, r)
			_picked_trait = -1
			refresh(), "stack"))
	var equip := UiKit.button("선택한 특성 장착", func() -> void:
		message = equip_best(_picked_trait)
		_picked_trait = -1
		refresh(), "check")
	equip.disabled = _picked_trait < 0 or _picked_trait >= c.bag.size()
	side.body.add_child(equip)
	side.body.add_child(UiKit.label("장착하면 해당 유형의 1군 선수 중 특성이 없는 최고 선수에게 붙습니다.", 15, UiTheme.DIM, 500))
	if message != "":
		side.body.add_child(UiKit.label(message, 17, UiTheme.ACCENT, 600))


## Puts a bag trait on the first-team player of the right kind who has none, the best first.
func equip_best(index: int) -> String:
	var s := LeagueSession.season
	var team: Team = s.teams[s.my_team]
	var def := s.club_rules.traits[s.club.bag[index].x]
	var best: Player = null
	var best_ovr := -1.0
	for p: Player in team.first_team():
		if s.club.traits.has(p.id) or (def.kind == &"pitcher") != p.is_pitcher():
			continue
		var o := ClubRules.player_ovr(p, s.ovr, s.catalog)
		if o > best_ovr:
			best_ovr = o
			best = p
	if best == null or not s.club.equip(best, index, s.club_rules):
		return "장착할 선수가 없다."
	return "%s에게 %s 장착." % [best.name, def.name]


func _cycle_training(s: Season, p: Player) -> void:
	var options: Array[String] = ["stuff", "control", "breaking"] if p.is_pitcher() else ["batting", "running", "fielding"]
	var now := s.club.training.get(p.id, "") as String
	var i := options.find(now)
	if i == options.size() - 1:
		s.club.training.erase(p.id)
		return
	var next := options[i + 1]
	if not s.club.assign_training(p.id, next, s.club_rules):
		message = "훈련은 하루 %d명까지 지정할 수 있습니다." % s.club_rules.train_per_day


# --- Days and games ---


func play_on_screen() -> void:
	var s := LeagueSession.season
	var g := s.my_game_today()
	if g == null or g.played:
		return
	LeagueSession.pending = g
	var d := s.division_of(s.my_team)
	go(LeagueSession.MATCH, {"away": s.teams[g.away], "home": s.teams[g.home], "title": "%d부 리그" % (d + 1),
		"line": "%d년 시즌 %d일차 · %s" % [s.season_year, s.day + 1, MatchScene.home_def(s.teams[g.home]).name]})


## Settles today's game at once.
func quick_result() -> void:
	var s := LeagueSession.season
	var g := s.my_game_today()
	if g == null or g.played:
		return
	var sim := s.prepare(g)
	sim.play()
	s.record(g, sim.state, sim.scorer.book)
	message = "빠른 결과: %d-%d %s" % [g.runs_of(s.my_team), g.runs_against(s.my_team), _result_word(g)]
	refresh()


func next_day() -> void:
	var s := LeagueSession.season
	var g := s.my_game_today()
	if g != null and not g.played:
		message = "오늘 경기를 먼저 진행해야 합니다."
		refresh()
		return
	s.advance()
	s.play_day()
	message = ""
	refresh()


## Days go by (our games settled at once) until our next game is today.
func to_next_game() -> void:
	var s := LeagueSession.season
	var guard := 0
	while s.phase != Season.Phase.OVER and guard < 400:
		var g := s.my_game_today()
		if g != null and not g.played:
			break
		s.advance()
		s.play_day()
		guard += 1
	refresh()


## The rest of the regular season (or of the postseason) at once.
func to_phase_end() -> void:
	var s := LeagueSession.season
	var phase := s.phase
	var guard := 0
	while s.phase == phase and guard < 400:
		s.play_day(true)
		s.advance()
		guard += 1
	if s.phase != Season.Phase.OVER:
		s.play_day()
	message = "포스트시즌이 시작되었습니다." if s.phase == Season.Phase.POSTSEASON else "시즌이 종료되었습니다."
	refresh()
