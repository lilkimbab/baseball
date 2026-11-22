class_name LeagueScreen
extends Screen
## The league mode (docs/02 sections 4 and 5, docs/13 S7): start a season with a club in the
## third division, then go day by day. Its tabs: today (the day's game as a match-up — played
## on screen as a managed game or settled at once — beside the division table, the postseason
## ladder or the season's end), the first team, the second team, scouting and traits. In the
## lists a player is picked with a click: he stands on the right with his main ratings and
## what can be done with him.

const GAME_CHOICES: Array[int] = [36, 72, 144]
const SEASON_TABS: Array[Array] = [["home", "오늘"], ["roster", "1군"], ["lineup", "라인업"], ["farm", "2군"], ["scout", "스카우트"], ["traits", "특성"], ["records", "기록실"]]
const FOCUS_NAMES := {"batting": "타격", "running": "주루", "fielding": "수비", "stuff": "구위", "control": "제구", "breaking": "변화"}

var message := ""
var _tab := "home"
var _games := 36
var _choice := ""
## The player picked in a list (his id), and the trait picked in the bag (its index).
var _picked := ""
var _picked_trait := -1
## The line-up tab (docs/08 R5): the row picked first ("L3" the fourth batter, "B<id>" a man
## on the bench, "R2" the third starter), and whether two batters trade order or positions.
var _lineup_pick := ""
var _swap_positions := false
## The man pinned to be compared with the next one picked (his id; docs/08 R5).
var _compare_id := ""
## The records room: which board (batting leaders, pitching leaders, the clubs) and which
## division (-1: the player's own).
var _records_view := "batting"
var _records_division := -1
## The second-team tab (docs/08 R6): its players or its league's table.
var _farm_view := "players"
## A new season (docs/08 R7): the fictional league or a season of the past; for the latter
## the pack and the scenario chosen ("" for a club of one's own choice).
var _setup_mode := "league"
var _pack_id := ""
var _scenario_id := ""
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
	content.add_child(UiKit.segmented(["league", "history"], ["가상 리그", "역사적 시즌"], _setup_mode, func(id: String) -> void:
		_setup_mode = id
		_choice = ""
		refresh()))
	if _setup_mode == "history":
		_build_history_setup()
		return
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
	var where := "%d부 리그" % (d + 1)
	if s.history != null:
		var sc := s.history.scenario(s.scenario_id)
		where = "역사적 시즌 %s%s" % [s.history.title, " · 목표 %s" % SeasonPack.goal_text(sc) if sc != null else ""]
	set_heading(team.name, "%s · %d년 %s %d일차 · %d승 %d패 %d무 · %d위" % [where, s.season_year, phase, s.day + 1, standing.wins, standing.losses, standing.ties, s.standings[d].rank_of(s.my_team)])
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
			_build_farm(s, team)
		"scout":
			_build_list("scout", s.club.candidates, s, team, "오늘의 영입 후보입니다. 하루에 한 명만 영입할 수 있습니다." + ("  (오늘은 이미 영입했습니다)" if s.club.signed_today else ""))
		"traits":
			_build_traits(s)
		"lineup":
			_build_lineup(s, team)
		"records":
			_build_records(s)
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
	if s.history != null:
		_build_history_end(parent, s)
		return
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


# --- Seasons of the past (docs/08 R7) ---


## The seasons there are to play again, the one picked with its rules and what really
## happened, its scenarios, or a club of one's own choice.
func _build_history_setup() -> void:
	set_heading("역사적 시즌", "지난 시즌을 그해 로스터와 규칙으로 다시 치릅니다")
	var packs := SeasonPack.available()
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var left := panel("시즌 선택", "calendar-blank", columns, 560.0, "SEASONS")
	var table := DataTable.new()
	table.row_height = 52.0
	table.set_columns([["시즌", 380.0, 0], ["경기", 90.0, 2]])
	var chosen: SeasonPack = null
	for pack: SeasonPack in packs:
		var at := table.add_row([pack.title, "%d" % pack.games], pack.id)
		if pack.id == _pack_id:
			table.selected = at
			chosen = pack
	table.row_pressed.connect(func(_row: int, tag: Variant) -> void:
		_pack_id = str(tag)
		_scenario_id = ""
		_choice = ""
		refresh())
	left.body.add_child(table)
	left.body.add_child(_wrapped("실제 KBO 시즌은 기록 수집기로 만든 팩을 content-local/seasons/에 넣으면 이 목록에 나옵니다.", 15))
	var right := panel("시즌 정보", "info", columns, 0.0, "SEASON")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if chosen == null:
		right.body.add_child(UiKit.label("왼쪽 목록에서 시즌을 선택하세요.", 20, UiTheme.DIM, 500))
		return
	right.body.add_child(UiKit.heading(chosen.title, 36))
	right.body.add_child(UiKit.label("%d경기 · 연장 %d회까지 · 외국인 %d명 · 1군 %d명%s" % [chosen.games, chosen.extra_innings, chosen.foreign_players, chosen.registered_roster, " · 아시아쿼터 %d명" % chosen.asia_quota if chosen.asia_quota > 0 else ""], 17, UiTheme.INK, 500))
	if chosen.note != "":
		right.body.add_child(_wrapped(chosen.note, 15))
	var clubs := chosen.clubs()
	var names: Dictionary[String, String] = {}
	for t: Team in clubs:
		names[t.id] = t.name
	if chosen.champion != "":
		right.body.add_child(UiKit.label("그해 우승: %s" % names.get(chosen.champion, chosen.champion), 17, UiTheme.ACCENT, 600))
	right.body.add_child(CenteredPanel.section("시나리오"))
	var group := UiKit.vbox(6)
	right.body.add_child(group)
	for sc: SeasonPack.Scenario in chosen.scenarios:
		var on := sc.id == _scenario_id
		var b := GameButton.make("%s  ·  %s  ·  목표: %s" % [sc.title, names.get(sc.team, sc.team), SeasonPack.goal_text(sc)], func() -> void:
			_scenario_id = "" if on else sc.id
			_choice = ""
			refresh(), "", "segment")
		b.toggle_mode = true
		b.button_pressed = on
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group.add_child(b)
		if on:
			group.add_child(_wrapped(sc.text, 15))
	if _scenario_id == "":
		right.body.add_child(CenteredPanel.section("또는 구단 직접 선택"))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		row.add_theme_constant_override("v_separation", 6)
		right.body.add_child(row)
		for t: Team in clubs:
			var actual := chosen.actual_of(t.id)
			var b := GameButton.make("%s (%d위)" % [t.short_name, int(actual[0])] if int(actual[0]) > 0 else t.short_name, func() -> void:
				_choice = t.id
				refresh(), "", "segment")
			b.toggle_mode = true
			b.button_pressed = t.id == _choice
			row.add_child(b)
	right.body.add_child(UiKit.spacer(0.0, 0.0, true))
	var start := UiKit.button("시즌 시작", func() -> void: begin_history(chosen, _scenario_id, _choice), "play", "primary")
	start.add_theme_font_size_override("font_size", 26)
	start.disabled = _scenario_id == "" and _choice == ""
	right.body.add_child(start)


## A grey note that wraps within its panel.
static func _wrapped(text: String, font_size: int) -> Label:
	var l := UiKit.label(text, font_size, UiTheme.DIM, 500)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 200.0
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Starts a season of the past (also used by tests).
func begin_history(pack: SeasonPack, scenario_id: String, team_id: String) -> void:
	LeagueSession.start_history(pack, scenario_id, team_id, _rng.next_int(1000000))
	LeagueSession.season.play_day()
	var sc := pack.scenario(scenario_id)
	message = "%s · %s" % [pack.title, "시나리오 「%s」: %s" % [sc.title, SeasonPack.goal_text(sc)] if sc != null else LeagueSession.season.teams[LeagueSession.season.my_team].name]
	_tab = "home"
	refresh()


## The end of a season of the past: this season's table beside the real one, the champions,
## the title holders then and now, and the scenario's verdict.
func _build_history_end(parent: Control, s: Season) -> void:
	var pack := s.history
	var p := panel("%s 결과" % pack.title, "trophy", parent, 0.0, "THEN AND NOW")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc := pack.scenario(s.scenario_id)
	var top := UiKit.hbox(12)
	p.body.add_child(top)
	var verdict := UiKit.vbox(2)
	verdict.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(verdict)
	if sc != null:
		var met := SeasonPack.goal_met(sc, s)
		verdict.add_child(UiKit.latin("SCENARIO", 18, tint, true))
		verdict.add_child(UiKit.heading("%s  %s" % [sc.title, "성공" if met else "실패"], 40, UiTheme.GREEN if met else UiTheme.RED))
		verdict.add_child(UiKit.label("목표: %s" % SeasonPack.goal_text(sc), 17, UiTheme.DIM, 500))
	var buttons := UiKit.vbox(6)
	buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(buttons)
	buttons.add_child(UiKit.button("같은 시즌 다시", func() -> void: begin_history(pack, s.scenario_id, s.my_team), "arrows-clockwise", "primary"))
	buttons.add_child(UiKit.button("다른 시즌 고르기", func() -> void:
		LeagueSession.season = null
		_setup_mode = "history"
		refresh(), "calendar-blank"))
	var table := DataTable.new()
	table.set_columns([["순위", 60.0, 1], ["팀", 160.0, 0], ["이번", 130.0, 2], ["실제 순위", 100.0, 2], ["실제", 130.0, 2], ["차이", 80.0, 2]])
	var rows := s.standings[0].ranked()
	for i: int in rows.size():
		var r := rows[i]
		var actual := pack.actual_of(r.team_id)
		var shift := int(actual[0]) - (i + 1) if int(actual[0]) > 0 else 0
		table.add_row(["%d" % (i + 1), (s.teams[r.team_id] as Team).short_name, "%d-%d-%d" % [r.wins, r.losses, r.ties], "%d위" % int(actual[0]) if int(actual[0]) > 0 else "-",
			"%d-%d-%d" % [int(actual[1]), int(actual[2]), int(actual[3])] if int(actual[0]) > 0 else "-", ("▲%d" % shift) if shift > 0 else (("▼%d" % -shift) if shift < 0 else "-")],
			r.team_id, {0: UiTheme.ACCENT, 1: tint if r.team_id == s.my_team else UiTheme.INK, 5: UiTheme.GREEN if shift > 0 else (UiTheme.RED if shift < 0 else UiTheme.DIM)})
	table.custom_minimum_size.y = 48.0 + 38.0 * rows.size()
	p.body.add_child(table)
	var now := s.champion_of(0)
	p.body.add_child(UiKit.label("우승  이번: %s  ·  실제: %s" % [(s.teams[now] as Team).name if now != "" else "-", (s.teams[pack.champion] as Team).name if s.teams.has(pack.champion) else "-"], 18, UiTheme.INK, 600))
	if not pack.leaders.is_empty():
		p.body.add_child(CenteredPanel.section("타이틀  실제 → 이번"))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 30)
		p.body.add_child(grid)
		var lines := PackedStringArray()
		for entry: Array in pack.leaders:
			var mine := ""
			for c: LeagueRecords.Category in LeagueRecords.batting_categories() + LeagueRecords.pitching_categories():
				if c.name == str(entry[0]):
					var board := LeagueRecords.leaders(s, 0, c, 1)
					if not board.is_empty():
						var who := (s.teams[board[0].team_id] as Team).player(board[0].player_id)
						mine = "%s %s" % [who.name if who != null else "", board[0].text]
			lines.append("%s  %s %s → %s" % [str(entry[0]), str(entry[1]), str(entry[2]), mine])
		for line: String in lines:
			grid.add_child(UiKit.label(line, 15, UiTheme.DIM, 500))


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
	# The room the scouts see in him (docs/08 R6), and his second-team numbers.
	if s.season_year - p.born <= 27 and p.potential >= 0.0:
		words.add_child(UiKit.label("잠재력 %s" % Development.stars_text(Development.stars(p, s.club.scout_level if s.club != null else 1)), 17, UiTheme.ACCENT, 600))
	if kind == "farm" and s.farm != null:
		words.add_child(UiKit.label("2군 " + farm_line(s, p), 15, UiTheme.DIM, 500))
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
	_compare_buttons(side.body, p, s)
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


# --- The second team (docs/08 R6) ---


## The second team: its men with their age, the room the scouts see in them, their numbers in
## the second teams' league and what they have grown this season; the moves the staff advise;
## and the second teams' table with last winter's comings and goings.
func _build_farm(s: Season, team: Team) -> void:
	var bar := UiKit.hbox(16)
	content.add_child(bar)
	bar.add_child(UiKit.segmented(["players", "table"], ["2군 선수", "퓨처스 순위 · 지난 겨울"], _farm_view, func(id: String) -> void:
		_farm_view = id
		refresh()))
	if _farm_view == "table":
		_build_farm_table(s, team)
		return
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var players := team.second_team()
	var p := panel("2군  %d명" % players.size(), "users-three", columns, 0.0, "FUTURES")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.body.add_child(UiKit.label("2군은 1군과 같은 날 상대 구단 2군과 경기합니다. 경기에 나가는 젊은 선수가 빨리 자랍니다.", 16, UiTheme.DIM, 500))
	var advice := RosterMoves.advice(s, team) if s.farm != null else ([] as Array[RosterMoves.Move])
	var advised: Dictionary[String, bool] = {}
	for m: RosterMoves.Move in advice:
		advised[m.up.id] = true
		var row := UiKit.hbox(10)
		row.add_child(UiKit.icon("arrow-u-up-left", 20.0, UiTheme.GREEN))
		row.add_child(UiKit.label("콜업 추천: %s ↔ %s (%s)" % [m.up.name, m.down.name, m.reason], 16, UiTheme.GREEN, 600))
		row.add_child(UiKit.spacer(0.0, 0.0, true))
		var move := m
		row.add_child(UiKit.button("맞바꾸기", func() -> void:
			if RosterMoves.apply(s, team, move):
				message = "%s 선수를 1군에 올리고 %s 선수를 2군으로 보냈습니다." % [move.up.name, move.down.name]
			refresh(), "swap"))
		p.body.add_child(row)
	var table := DataTable.new()
	table.set_columns([["포지션", 80.0, 1], ["선수", 200.0, 0], ["나이", 60.0, 1], ["OVR", 70.0, 2], ["잠재력", 120.0, 1], ["2군 기록", 300.0, 0], ["올해 성장", 100.0, 2]])
	var picked: Player = null
	var level := s.club.scout_level if s.club != null else 1
	for player: Player in players:
		var ovr := ClubRules.player_ovr(player, s.ovr, s.catalog)
		var role := String(player.role()) if player.is_pitcher() else Position.code(player.primary_position())
		var grown := float(s.grown.get(player.id, 0.0))
		var at := table.add_row([role, player.name + ("  ▲" if advised.has(player.id) else ""), "%d" % (s.season_year - player.born), str(roundi(ovr)),
			Development.stars_text(Development.stars(player, level)), farm_line(s, player), "+%.1f" % grown if grown >= 0.05 else "-"], player.id,
			{0: UiTheme.CYAN if player.is_pitcher() else UiTheme.GREEN, 1: UiTheme.GREEN if advised.has(player.id) else UiTheme.INK, 3: UiTheme.rating_color(ovr), 4: UiTheme.ACCENT, 6: UiTheme.GREEN})
		if player.id == _picked:
			table.selected = at
			picked = player
	table.row_pressed.connect(func(_row: int, tag: Variant) -> void:
		_picked = str(tag)
		refresh())
	p.body.add_child(table)
	if message != "":
		p.body.add_child(UiKit.label(message, 17, UiTheme.ACCENT, 600))
	_build_picked(columns, "farm", picked, s, team)


## A man's numbers in the second teams' league, in one line.
static func farm_line(s: Season, p: Player) -> String:
	if s.farm == null:
		return "-"
	if p.is_pitcher():
		var l := s.farm.pitching(p.id)
		if l.outs == 0:
			return "-"
		return "%s이닝 · 평균자책점 %.2f" % [l.innings_text(), l.era()]
	var b := s.farm.batting(p.id)
	if b.pa == 0:
		return "-"
	return "%d타석 · 타율 %s · OPS %s" % [b.pa, BattingLine.rate_text(b.average()), BattingLine.rate_text(b.ops())]


## The second teams' table of the player's division, and last winter's comings and goings.
func _build_farm_table(s: Season, team: Team) -> void:
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var d := s.division_of(s.my_team)
	var left := panel("퓨처스리그 %d부" % (d + 1), "ranking", columns, 0.0, "FUTURES LEAGUE")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if s.farm == null:
		left.body.add_child(UiKit.label("이 시즌에는 2군 리그가 없습니다.", 17, UiTheme.DIM, 500))
	else:
		var table := DataTable.new()
		table.set_columns([["순위", 60.0, 1], ["팀", 200.0, 0], ["경기", 70.0, 2], ["승", 60.0, 2], ["패", 60.0, 2], ["무", 60.0, 2], ["승률", 80.0, 2], ["게임차", 80.0, 2]])
		var standings := s.farm.standings[d]
		var rows := standings.ranked()
		for i: int in rows.size():
			var r := rows[i]
			var club: Team = s.teams[r.team_id]
			table.add_row(["%d" % (i + 1), club.short_name, str(r.games()), str(r.wins), str(r.losses), str(r.ties), BattingLine.rate_text(r.pct()) if r.wins + r.losses > 0 else "-", "-" if i == 0 else "%.1f" % standings.games_behind(r.team_id)],
				r.team_id, {0: UiTheme.ACCENT, 1: tint if r.team_id == s.my_team else UiTheme.INK})
		table.custom_minimum_size.y = 48.0 + 38.0 * rows.size()
		left.body.add_child(table)
	var right := panel("지난 겨울", "snowflake" if UiTheme.icon("snowflake") != null else "calendar-blank", columns, 640.0, "WINTER")
	var w := s.last_winter
	if w == null:
		right.body.add_child(UiKit.label("첫 시즌입니다. 시즌이 끝나면 은퇴·신인 드래프트·성장 결과가 여기에 나옵니다.", 16, UiTheme.DIM, 500))
		return
	var ours_out: Array = w.retired.filter(func(r: Array) -> bool: return str(r[0]) == team.id)
	var ours_in: Array = w.rookies.filter(func(r: Array) -> bool: return str(r[0]) == team.id)
	right.body.add_child(UiKit.label("리그 전체 은퇴 %d명 · 신인 %d명" % [w.retired.size(), w.rookies.size()], 17, UiTheme.INK, 600))
	right.body.add_child(CenteredPanel.section("우리 구단 은퇴"))
	if ours_out.is_empty():
		right.body.add_child(UiKit.label("없음", 16, UiTheme.DIM, 500))
	for r: Array in ours_out:
		right.body.add_child(UiKit.label("%s (%s · %d세)" % [str(r[1]), str(r[3]), int(r[2])], 16, UiTheme.INK, 500))
	right.body.add_child(CenteredPanel.section("우리 구단 신인"))
	for r: Array in ours_in:
		var p := team.player(str(r[1]))
		if p != null:
			right.body.add_child(UiKit.label("%s  %s · %d세  %s" % [p.name, String(p.role()) if p.is_pitcher() else Position.code(p.primary_position()), s.season_year - p.born, Development.stars_text(Development.stars(p, s.club.scout_level if s.club != null else 1))], 16, UiTheme.INK, 500))
	right.body.add_child(CenteredPanel.section("지난 시즌 가장 많이 자란 선수"))
	for r: Array in w.risers.slice(0, 5):
		var club: Team = s.teams.get(str(r[0]))
		var p := club.player(str(r[1])) if club != null else null
		if p != null:
			right.body.add_child(UiKit.label("%s (%s)  +%.1f" % [p.name, club.short_name, float(r[2])], 16, UiTheme.GREEN if club.id == team.id else UiTheme.INK, 500))


# --- The records room (docs/08 R5) ---


## The division's leaders in each category (the first five, qualifying men only for rates)
## or its clubs' batting and pitching side by side. A name opens his card.
func _build_records(s: Season) -> void:
	var d := _records_division if _records_division >= 0 else s.division_of(s.my_team)
	var bar := UiKit.hbox(16)
	content.add_child(bar)
	bar.add_child(UiKit.segmented(["batting", "pitching", "clubs"], ["타자 순위", "투수 순위", "팀 기록"], _records_view, func(id: String) -> void:
		_records_view = id
		refresh()))
	bar.add_child(UiKit.spacer(0.0, 0.0, true))
	var ids: Array = []
	var labels: Array = []
	for i: int in s.divisions.size():
		ids.append(str(i))
		labels.append("%d부" % (i + 1))
	bar.add_child(UiKit.segmented(ids, labels, str(d), func(id: String) -> void:
		_records_division = int(id)
		refresh()))
	var games := LeagueRecords.games_played(s, s.my_team)
	content.add_child(UiKit.label("규정타석 %d · 규정이닝 %d (팀 %d경기 기준, 비율 기록에만 적용)" % [LeagueRecords.qualifying_pa(s, s.my_team), LeagueRecords.qualifying_outs(s, s.my_team) / 3, games], 15, UiTheme.DIM, 500))
	var scroll := UiKit.scroll()
	content.add_child(scroll)
	if _records_view == "clubs":
		_build_club_records(scroll, s, d)
		return
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var categories := LeagueRecords.batting_categories() if _records_view == "batting" else LeagueRecords.pitching_categories()
	for c: LeagueRecords.Category in categories:
		_leader_card(grid, s, c, LeagueRecords.leaders(s, d, c, 5))


func _leader_card(parent: Control, s: Season, c: LeagueRecords.Category, board: Array[LeagueRecords.Entry]) -> void:
	var card := GlassPanel.make(c.name, "", 0.0, tint, "규정" if c.qualified else "")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	if board.is_empty():
		card.body.add_child(UiKit.label("아직 기록이 없습니다.", 16, UiTheme.DIM, 500))
		return
	for i: int in board.size():
		var e := board[i]
		var p := find_player(s, e.player_id)
		var club: Team = s.teams[e.team_id]
		var row := UiKit.hbox(10)
		card.body.add_child(row)
		var place := UiKit.latin("%d" % (i + 1), 20, UiTheme.ACCENT if i == 0 else UiTheme.DIM, true)
		place.custom_minimum_size.x = 22.0
		row.add_child(place)
		row.add_child(UiKit.club_mark(club, 24.0))
		var name := GameButton.make(p.name if p != null else e.player_id, func() -> void:
			if p != null:
				PlayerCard.open_for(self, p, s), "", "tab")
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if e.team_id == s.my_team:
			name.add_theme_color_override("font_color", tint)
		row.add_child(name)
		row.add_child(UiKit.latin(e.text, 22 if i == 0 else 20, Color.WHITE if i == 0 else UiTheme.INK, false))


## The clubs of a division in the order of the table, batting and pitching added up.
func _build_club_records(parent: Control, s: Season, d: int) -> void:
	var table := DataTable.new()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.set_columns([["순위", 60.0, 1], ["팀", 200.0, 0], ["경기", 70.0, 2], ["타율", 80.0, 2], ["OPS", 80.0, 2], ["홈런", 70.0, 2], ["득점", 70.0, 2], ["도루", 70.0, 2], ["평균자책점", 110.0, 2], ["실점", 70.0, 2], ["탈삼진", 80.0, 2], ["WHIP", 80.0, 2]])
	var rows := LeagueRecords.clubs(s, d)
	for i: int in rows.size():
		var team_id := str(rows[i][0])
		var bat: BattingLine = rows[i][1]
		var pitch: PitchingLine = rows[i][2]
		var club: Team = s.teams[team_id]
		var mine := team_id == s.my_team
		table.add_row(["%d" % (i + 1), club.short_name, str(LeagueRecords.games_played(s, team_id)),
			BattingLine.rate_text(bat.average()) if bat.ab > 0 else "-", BattingLine.rate_text(bat.ops()) if bat.pa > 0 else "-",
			str(bat.home_runs), str(bat.runs), str(bat.stolen_bases),
			"%.2f" % pitch.era() if pitch.outs > 0 else "-", str(pitch.runs), str(pitch.strikeouts), "%.2f" % pitch.whip() if pitch.outs > 0 else "-"],
			team_id, {0: UiTheme.ACCENT, 1: tint if mine else UiTheme.INK})
	table.custom_minimum_size.y = 48.0 + 38.0 * rows.size()
	var card := GlassPanel.make("%d부 팀 기록" % (d + 1), "table", 0.0, tint, "CLUBS")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.body.add_child(table)
	parent.add_child(card)


## Comparing two men (docs/08 R5): pin one, pick another, open the two side by side. While
## one is pinned his name stays in the panel with a way to let him go.
func _compare_buttons(parent: Control, p: Player, s: Season) -> void:
	var pinned := find_player(s, _compare_id)
	var row := UiKit.hbox(8)
	parent.add_child(row)
	if pinned == null or pinned.id == p.id:
		row.add_child(UiKit.button("비교 대상으로" if pinned == null else "비교 대상 해제", func() -> void:
			_compare_id = p.id if pinned == null else ""
			message = "%s 선수를 비교 대상으로 정했습니다. 비교할 선수를 고르세요." % p.name if pinned == null else ""
			# The next click picks the other man (in the line-up it would trade places).
			_lineup_pick = ""
			_picked = ""
			refresh(), "chart-polar"))
		return
	var compare := UiKit.button("%s 선수와 비교" % pinned.name, func() -> void: PlayerCompare.open_for(self, pinned, p, s), "chart-polar", "primary")
	compare.disabled = not PlayerCompare.comparable(pinned, p)
	if compare.disabled:
		compare.tooltip_text = "투수는 투수끼리, 타자는 타자끼리 비교합니다."
	row.add_child(compare)
	row.add_child(UiKit.button("해제", func() -> void:
		_compare_id = ""
		refresh(), "x"))


## A player of the league by id: on a club or among today's scouting candidates.
static func find_player(s: Season, id: String) -> Player:
	if id == "":
		return null
	for team_id: String in s.teams:
		var p := (s.teams[team_id] as Team).player(id)
		if p != null:
			return p
	for p: Player in s.club.candidates:
		if p.id == id:
			return p
	return null


# --- The line-up and the rotation (docs/08 R5) ---


## The batting order and positions (with the bench), the rotation, and the man picked. Pick a
## row and then another: two batters trade places in the order (or positions, in that mode),
## a bench man takes the place of the batter, two starters trade turns. The plan is the club's
## from the first change on; "자동" hands it back to the computer.
func _build_lineup(s: Season, team: Team) -> void:
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var plan := LineupPlan.current(team, AiManager.new(s.env, s.catalog, s.ovr), s.rules)
	var own := team.batting_plan.size() == 9
	var left := panel("타순 · 수비 위치", "list-numbers", columns, 0.0, "LINEUP")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.body.add_child(UiKit.label(("감독이 정한 라인업입니다." if own else "지금은 컴퓨터가 경기마다 정합니다. 바꾸면 그때부터 이 라인업으로 나갑니다.") + "  두 줄을 차례로 누르면 맞바뀝니다.", 16, UiTheme.DIM, 500))
	var table := DataTable.new()
	table.set_columns([["타순", 60.0, 1], ["포지션", 90.0, 1], ["선수", 220.0, 0], ["주포지션", 90.0, 1], ["OVR", 70.0, 2], ["컨디션", 90.0, 1]])
	var picked: Player = null
	for i: int in 9:
		var p := team.player(str(plan[i][0]))
		if p == null:
			continue
		var kind := Position.from_code(str(plan[i][1]))
		var ovr := ClubRules.player_ovr(p, s.ovr, s.catalog)
		var fits := kind == Position.Kind.DH or p.aptitude(kind) > 0.0
		var at := table.add_row(["%d" % (i + 1), Position.name_of(kind), p.name, Position.code(p.primary_position()), str(roundi(ovr)), s.condition_name(p.id)], "L%d" % i,
			{0: UiTheme.ACCENT, 1: UiTheme.GREEN if fits else UiTheme.RED, 4: UiTheme.rating_color(ovr)})
		if _lineup_pick == "L%d" % i:
			table.selected = at
			picked = p
	for p: Player in LineupPlan.bench(plan, team):
		var ovr := ClubRules.player_ovr(p, s.ovr, s.catalog)
		var at := table.add_row(["후보", "-", p.name, Position.code(p.primary_position()), str(roundi(ovr)), s.condition_name(p.id)], "B" + p.id,
			{0: UiTheme.DIM, 4: UiTheme.rating_color(ovr)})
		if _lineup_pick == "B" + p.id:
			table.selected = at
			picked = p
	table.row_pressed.connect(func(_row: int, tag: Variant) -> void: _lineup_pressed(str(tag), s, team))
	left.body.add_child(table)
	for line: String in LineupPlan.problems(plan, team):
		left.body.add_child(UiKit.label("⚠ " + line, 16, UiTheme.RED, 600))
	if message != "":
		left.body.add_child(UiKit.label(message, 17, UiTheme.ACCENT, 600))
	var actions := UiKit.hbox(8)
	left.body.add_child(actions)
	actions.add_child(UiKit.button("타순 맞바꾸기" + (" ✓" if not _swap_positions else ""), func() -> void:
		_swap_positions = false
		refresh(), "sort-ascending"))
	actions.add_child(UiKit.button("수비 위치 맞바꾸기" + (" ✓" if _swap_positions else ""), func() -> void:
		_swap_positions = true
		refresh(), "swap"))
	actions.add_child(UiKit.button("추천 라인업", func() -> void:
		team.batting_plan = []
		team.batting_plan = LineupPlan.current(team, AiManager.new(s.env, s.catalog, s.ovr), s.rules)
		message = "컴퓨터가 추천한 라인업으로 맞췄습니다."
		refresh(), "sparkle"))
	actions.add_child(UiKit.button("자동", func() -> void:
		team.batting_plan = []
		team.rotation_plan = PackedStringArray()
		message = "라인업과 로테이션을 컴퓨터에게 맡겼습니다."
		refresh(), "arrows-clockwise"))
	var right := UiKit.vbox(16)
	right.custom_minimum_size.x = 520.0
	columns.add_child(right)
	var rot := panel("투수 로테이션", "baseball", right, 0.0, "ROTATION")
	rot.body.add_child(UiKit.label("두 투수를 차례로 누르면 등판 순서가 맞바뀝니다.", 16, UiTheme.DIM, 500))
	var starters := DataTable.new()
	starters.set_columns([["순서", 60.0, 1], ["선수", 220.0, 0], ["OVR", 70.0, 2], ["컨디션", 90.0, 1]])
	var order := team.rotation()
	for i: int in order.size():
		var p := order[i]
		var ovr := ClubRules.player_ovr(p, s.ovr, s.catalog)
		var at := starters.add_row(["%d" % (i + 1), p.name, str(roundi(ovr)), s.condition_name(p.id)], "R%d" % i, {0: UiTheme.ACCENT, 2: UiTheme.rating_color(ovr)})
		if _lineup_pick == "R%d" % i:
			starters.selected = at
			picked = p
	starters.row_pressed.connect(func(_row: int, tag: Variant) -> void: _lineup_pressed(str(tag), s, team))
	# (In a column of panels a table takes no room of its own: give it its rows' height.)
	starters.custom_minimum_size.y = 48.0 + 38.0 * order.size()
	rot.body.add_child(starters)
	_build_picked(right, "lineup", picked, s, team)


func _lineup_pressed(tag: String, s: Season, team: Team) -> void:
	var first := _lineup_pick
	if first == "" or first == tag:
		_lineup_pick = "" if first == tag else tag
		refresh()
		return
	_lineup_pick = ""
	message = ""
	if first.begins_with("R") and tag.begins_with("R"):
		LineupPlan.swap_rotation(team, int(first.substr(1)), int(tag.substr(1)))
		message = "등판 순서를 바꿨습니다."
		refresh()
		return
	var plan := LineupPlan.current(team, AiManager.new(s.env, s.catalog, s.ovr), s.rules)
	if first.begins_with("L") and tag.begins_with("L"):
		if _swap_positions:
			LineupPlan.swap_positions(plan, int(first.substr(1)), int(tag.substr(1)))
			message = "수비 위치를 맞바꿨습니다."
		else:
			LineupPlan.swap_order(plan, int(first.substr(1)), int(tag.substr(1)))
			message = "타순을 맞바꿨습니다."
	elif first.begins_with("L") and tag.begins_with("B") or first.begins_with("B") and tag.begins_with("L"):
		var place := int((first if first.begins_with("L") else tag).substr(1))
		var who := (tag if tag.begins_with("B") else first).substr(1)
		LineupPlan.bring_in(plan, place, who)
		message = "%s 선수가 %d번 타순에 들어갑니다." % [team.player(who).name, place + 1]
	else:
		refresh()
		return
	team.batting_plan = plan
	refresh()


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
