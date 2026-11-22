class_name CareerScreen
extends Screen
## The career's screen between games (docs/02 section 6, docs/13 S8-3, S8-5). Its tabs: today
## (the player standing beside the day's game — played on screen with only his scenes, or at
## once — the last game's report and his numbers on both teams), growth (each field's points
## spent on its ratings; a pitcher's pitches) and his division's table.

const RATING_NAMES := {
	"contact": "컨택트", "power": "파워", "eye": "선구안", "speed": "주력",
	"range": "수비 범위", "hands": "포구", "arm": "송구 파워", "accuracy": "송구 정확도",
	"control": "제구", "stamina": "체력", "velocity": "구속", "movement": "구위",
}
const FIELD_NAMES := {"batting": "타격", "fielding": "수비", "running": "주루", "pitching": "투구"}
const FIELD_ICONS := {"batting": "baseball-helmet", "fielding": "shield", "running": "sneaker-move", "pitching": "person-simple-throw"}
const CAREER_TABS: Array[Array] = [["home", "오늘"], ["growth", "성장"], ["table", "순위"]]

var message := ""
var _tab := "home"


func setup() -> void:
	heading = "커리어 모드"
	heading_latin = "CAREER"
	vantage = &"field"
	dock_id = "career"


func refresh() -> void:
	if is_inside_tree() and CareerSession.career_season != null:
		CareerSession.settle_points()
		Achievements.check_career(CareerSession.career_season, CareerSession.last_report)
		CareerSession.autosave()
	super.refresh()


func build() -> void:
	var cs := CareerSession.career_season
	if cs == null:
		var p := panel("커리어 모드", "user-circle", null, 0.0, "CAREER")
		p.body.add_child(UiKit.label("진행 중인 커리어가 없습니다.", 20, UiTheme.DIM, 500))
		p.body.add_child(UiKit.button("선수 생성", func() -> void: go(CareerSession.CREATE), "plus", "primary", 320.0))
		return
	CareerSession.settle_points()
	var c := cs.career
	var s := cs.season
	var team: Team = s.teams[c.team_id]
	var phase: String = ["정규 시즌", "포스트시즌", "시즌 종료"][s.phase]
	set_heading(c.player.name, "%s · %s · %d년 %s %d일차" % [team.name, "1군" if c.first_team else "2군", s.season_year, phase, s.day + 1])
	if tab_bar != null:
		var ids: Array = []
		var labels: Array = []
		for pair: Array in CAREER_TABS:
			ids.append(pair[0])
			labels.append(pair[1])
		var tabs := UiKit.tabs(ids, labels, _tab, func(id: String) -> void:
			_tab = id
			refresh())
		for b: Node in tabs.get_children():
			(b as GameButton).tint = tint
		tab_bar.add_child(tabs)
	match _tab:
		"growth":
			_build_growth(cs)
		"table":
			_build_table(cs)
		_:
			_build_home(cs, team)


# --- Today ---


func _build_home(cs: CareerSeason, team: Team) -> void:
	var c := cs.career
	var p := c.player
	var s := cs.season
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	# The man himself.
	var left := UiKit.vbox(6)
	left.custom_minimum_size.x = 440.0
	columns.add_child(left)
	var stage := PlayerStage.make(440.0, 520.0)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.show_player(p, team)
	left.add_child(stage)
	var type := cs.rules.type_by_id(c.type_id)
	var name_row := UiKit.hbox(12)
	left.add_child(name_row)
	name_row.add_child(UiKit.club_mark(team, 72.0))
	var words := UiKit.vbox(-2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(UiKit.latin("No.%d  ·  %s" % [p.number, "FIRST TEAM" if c.first_team else "FARM TEAM"], 17, tint, true))
	words.add_child(UiKit.heading(p.name, 38))
	words.add_child(UiKit.label("%s · %s" % [cs.rules.position_names.get(c.position, c.position), type.name if type != null else ""], 16, UiTheme.DIM, 500))
	name_row.add_child(words)
	name_row.add_child(UiKit.button("선수 카드", func() -> void: PlayerCard.open_for(self, p, s), "identification-card"))

	var middle := UiKit.vbox(16)
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(middle)
	_build_today(middle, cs, team)
	_build_report(middle, cs)
	_build_numbers(columns, cs)


func _build_today(parent: Control, cs: CareerSeason, team: Team) -> void:
	var c := cs.career
	var s := cs.season
	var p := panel("오늘의 일정", "calendar-blank", parent, 0.0, "DAY %d" % (s.day + 1))
	if cs.all_star_today:
		p.body.add_child(UiKit.heading("올스타전에 선발되었습니다", 24, UiTheme.ACCENT))
		var row := UiKit.hbox(10)
		p.body.add_child(row)
		row.add_child(UiKit.button("올스타전 출전", func() -> void:
			cs.special = "all_star"
			go(CareerSession.MATCH, {"title": "올스타전"}), "star", "primary"))
		row.add_child(UiKit.button("빠른 진행", func() -> void:
			CareerSession.last_report = cs.quick_all_star()
			refresh(), "fast-forward"))
	if cs.derby_waiting:
		p.body.add_child(UiKit.heading("홈런 더비 (아웃 %d개)" % int(cs.rules.all_star.get("derby_outs", 10)), 24, UiTheme.ACCENT))
		var row := UiKit.hbox(10)
		p.body.add_child(row)
		row.add_child(UiKit.button("홈런 더비 출전", func() -> void: go(CareerSession.DERBY, {"title": "홈런 더비"}), "fire", "primary"))
		row.add_child(UiKit.button("빠른 결과", func() -> void:
			cs.quick_derby()
			refresh(), "fast-forward"))
	var actions := UiKit.hbox(10)
	if cs.has_game():
		var g := cs.club_game()
		var row := UiKit.hbox(18)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		p.body.add_child(row)
		row.add_child(UiKit.club_side(s.teams[g.away], "AWAY", 84.0, 22))
		row.add_child(UiKit.number("VS", 50, Color(1.0, 1.0, 1.0, 0.9)))
		row.add_child(UiKit.club_side(s.teams[g.home], "HOME", 84.0, 22))
		var play := UiKit.button("경기 출전", play_on_screen, "play", "primary", 240.0)
		play.add_theme_font_size_override("font_size", 24)
		actions.add_child(play)
		actions.add_child(UiKit.button("빠른 진행", quick, "fast-forward"))
	elif s.phase != Season.Phase.OVER:
		p.body.add_child(UiKit.label("오늘은 경기가 없습니다." if cs.club_game() == null or not c.first_team else "오늘 경기가 종료되었습니다.", 19, UiTheme.DIM, 500))
		actions.add_child(UiKit.button("다음 날", next_day, "caret-right", "primary", 200.0))
	else:
		p.body.add_child(UiKit.heading("시즌이 종료되었습니다", 24, UiTheme.ACCENT))
	if s.phase != Season.Phase.OVER:
		actions.add_child(UiKit.button("시즌 끝까지 진행", to_end, "skip-forward"))
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	p.body.add_child(actions)
	if message != "":
		p.body.add_child(UiKit.label(message, 17, UiTheme.ACCENT, 600))
	_build_schedule(p, cs, team)


## The club's next games as a row of cards (the reference's schedule strip): the other club's
## emblem, home or away, the day.
func _build_schedule(p: GlassPanel, cs: CareerSeason, team: Team) -> void:
	var s := cs.season
	var ahead: Array[ScheduledGame] = []
	for sched: Schedule in s.schedules:
		for g: ScheduledGame in sched.games:
			if not g.played and g.involves(team.id) and g.day > s.day:
				ahead.append(g)
	ahead.sort_custom(func(x: ScheduledGame, y: ScheduledGame) -> bool: return x.day < y.day)
	if ahead.is_empty():
		return
	p.body.add_child(UiKit.rule())
	var row := UiKit.hbox(8)
	p.body.add_child(row)
	for g: ScheduledGame in ahead.slice(0, 5):
		var other: Team = s.teams[g.opponent_of(team.id)]
		var cell := UiKit.well(8.0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cell)
		var box := UiKit.vbox(2)
		cell.add_child(box)
		var mark := UiKit.club_mark(other, 44.0)
		box.add_child(mark)
		var where := UiKit.label("%s %s" % ["vs" if g.home == team.id else "@", other.short_name], 15, Color.WHITE, 600)
		where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(where)
		var day := UiKit.latin("DAY %d" % (g.day + 1), 14, UiTheme.DIM, true)
		day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(day)


## The last game: his line, the goal, the rating and medal, what he earned.
func _build_report(parent: Control, cs: CareerSeason) -> void:
	var p := panel("지난 경기", "article", parent, 0.0, "LAST GAME")
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var r := CareerSession.last_report
	if r == null:
		p.body.add_child(UiKit.label("아직 치른 경기가 없습니다.", 18, UiTheme.DIM, 500))
	else:
		var top := UiKit.hbox(20)
		p.body.add_child(top)
		if r.rating > 0.0:
			top.add_child(UiKit.figure("%.1f" % r.rating, "평점", UiTheme.ACCENT if r.medal > 0 else UiTheme.INK, 48))
			var medal := GameRating.MEDALS[r.medal]
			if medal != "":
				top.add_child(UiKit.figure(medal, "메달", UiTheme.ACCENT, 40))
		var words := UiKit.vbox(4)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		words.add_child(UiKit.label(r.line, 19, UiTheme.INK, 600))
		words.add_child(UiKit.label("목표: %s  —  %s" % [r.goal, "달성" if r.goal_met else "실패"], 17, UiTheme.GREEN if r.goal_met else UiTheme.DIM, 600))
		if r.reward != "":
			words.add_child(UiKit.label("보상: " + r.reward, 17, UiTheme.ACCENT, 600))
		top.add_child(words)
		var earned := PackedStringArray()
		for field: String in r.gp:
			if r.gp[field] > 0.0:
				earned.append("%s +%d" % [FIELD_NAMES[field], roundi(r.gp[field])])
		p.body.add_child(UiKit.label("획득 성장 포인트: " + (", ".join(earned) if not earned.is_empty() else "없음"), 17, UiTheme.INK, 500))
		if r.called_up:
			p.body.add_child(UiKit.heading("1군에 등록되었습니다!", 22, UiTheme.ACCENT))
		if r.sent_down:
			p.body.add_child(UiKit.heading("2군으로 내려갔습니다.", 22, UiTheme.RED))
		for change: String in r.evolved:
			p.body.add_child(UiKit.label("구종 진화: " + change, 17, UiTheme.ACCENT, 600))
	if not cs.log.is_empty():
		p.body.add_child(UiKit.rule())
		var scroll := UiKit.scroll()
		p.body.add_child(scroll)
		var lines := UiKit.vbox(2)
		lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(lines)
		for entry: String in cs.log:
			lines.add_child(UiKit.label(entry, 15, UiTheme.DIM, 500))


## His standing (popularity, points, average rating), growth points, and his numbers.
func _build_numbers(parent: Control, cs: CareerSeason) -> void:
	var c := cs.career
	var p := panel("선수 현황", "chart-bar", parent, 460.0, "STATUS")
	var avg := 0.0
	for x: float in c.ratings:
		avg += x
	avg = avg / c.ratings.size() if not c.ratings.is_empty() else 0.0
	var figures := UiKit.hbox(0)
	p.body.add_child(figures)
	figures.add_theme_constant_override("separation", 8)
	for pair: Array in [["%d" % roundi(c.popularity), "인기도"], ["%d" % c.ratings.size(), "출전 경기"], ["%.1f" % avg if avg > 0.0 else "-", "평균 평점"]]:
		var f := UiKit.tile(str(pair[0]), str(pair[1]), 0.0, 30)
		f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		figures.add_child(f)
	p.body.add_child(UiKit.rule())
	p.body.add_child(UiKit.caption("성장 포인트"))
	var fields: Array[String] = ["batting", "running", "fielding"]
	if c.is_pitcher():
		fields = ["pitching"]
	var gp := UiKit.hbox(0)
	p.body.add_child(gp)
	for field: String in fields:
		var f := UiKit.figure("%d" % roundi(float(c.gp.get(field, 0.0))), FIELD_NAMES[field], tint, 30)
		f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gp.add_child(f)
	p.body.add_child(UiKit.button("성장 탭으로", func() -> void:
		_tab = "growth"
		refresh(), "chart-line-up"))
	p.body.add_child(UiKit.rule())
	# His season where he plays now, in big figures.
	var book: StatBook = cs.season.book if c.first_team else cs.futures_book
	p.body.add_child(CenteredPanel.section("%s 시즌 기록" % ("1군" if c.first_team else "2군")))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	p.body.add_child(grid)
	for pair: Array in _season_figures(book, c.player.id, c.is_pitcher()):
		var t := UiKit.tile(str(pair[0]), str(pair[1]), 0.0, 28)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(t)


## His season in six figures: a hitter's games, average, home runs, runs batted in, steals, OPS;
## a pitcher's games, wins, losses, saves, innings, earned-run average.
static func _season_figures(book: StatBook, id: String, pitcher: bool) -> Array:
	if pitcher:
		var q: PitchingLine = book.pitching.get(id)
		if q == null or q.outs == 0:
			return [["0", "경기"], ["-", "승"], ["-", "패"], ["-", "세이브"], ["-", "이닝"], ["-", "평균자책점"]]
		return [["%d" % q.games, "경기"], ["%d" % q.wins, "승"], ["%d" % q.losses, "패"], ["%d" % q.saves, "세이브"], [q.innings_text(), "이닝"], ["%.2f" % q.era(), "평균자책점"]]
	var b: BattingLine = book.batting.get(id)
	if b == null or b.pa == 0:
		return [["0", "경기"], ["-", "타율"], ["-", "홈런"], ["-", "타점"], ["-", "도루"], ["-", "OPS"]]
	return [["%d" % b.games, "경기"], [BattingLine.rate_text(b.average()), "타율"], ["%d" % b.home_runs, "홈런"], ["%d" % b.rbi, "타점"], ["%d" % b.stolen_bases, "도루"], [BattingLine.rate_text(b.ops()), "OPS"]]


# --- Growth ---


func _build_growth(cs: CareerSeason) -> void:
	var c := cs.career
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var fields: Array[String] = ["batting", "running", "fielding"]
	if c.is_pitcher():
		fields = ["pitching"]
	for field: String in fields:
		var have := float(c.gp.get(field, 0.0))
		var p := panel(FIELD_NAMES[field], FIELD_ICONS[field], columns, 0.0, "%d GP" % roundi(have))
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ratings: PackedStringArray = cs.rules.ratings[field] if cs.rules.ratings.has(field) else PackedStringArray()
		for rating: String in ratings:
			var row := UiKit.hbox(10)
			p.body.add_child(row)
			var value := Growth.value(c.player, rating)
			if rating == "velocity":
				var l := UiKit.label(str(RATING_NAMES.get(rating, rating)), 17, UiTheme.DIM, 600)
				l.custom_minimum_size.x = 150.0
				row.add_child(l)
				var v := UiKit.number("%.1f km/h" % c.player.pitching.fastball_speed(), 24, Color.WHITE)
				v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(v)
			else:
				row.add_child(StatBar.make(str(RATING_NAMES.get(rating, rating)), value))
			var price := Growth.cost(c, rating, cs.rules)
			var up := UiKit.button("+ %d" % ceili(price), func() -> void:
				Growth.raise(c, rating, cs.rules)
				refresh(), "", "primary" if have >= price else "")
			up.disabled = have < price
			up.custom_minimum_size.x = 96.0
			up.tooltip_text = "성장 포인트 %d 사용" % ceili(price)
			row.add_child(up)
	if c.is_pitcher():
		_build_pitches(columns, cs)


## A pitcher's pitches, how often he has thrown each (they evolve with use), and new ones to
## learn with pitching points.
func _build_pitches(parent: Control, cs: CareerSeason) -> void:
	var c := cs.career
	var catalog := cs.season.catalog
	var p := panel("구종", "baseball", parent, 0.0, "PITCHES")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for a: ArsenalPitch in c.player.pitching.arsenal:
		var t: PitchType = catalog.get(a.type)
		var well := UiKit.well(10.0)
		p.body.add_child(well)
		var box := UiKit.vbox(2)
		well.add_child(box)
		var head_row := UiKit.hbox(10)
		box.add_child(head_row)
		var name := UiKit.heading(t.label if t != null else String(a.type), 20)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head_row.add_child(name)
		head_row.add_child(UiKit.latin("%d km/h  ·  %d구" % [roundi(a.velo_avg), int(c.pitch_uses.get(a.type, 0))], 18, UiTheme.DIM))
		box.add_child(StatBar.make("변화", a.movement, -1.0, 90.0))
		box.add_child(StatBar.make("제구", a.command, -1.0, 90.0))
	for id: StringName in PitchEvolution.learnable(c, cs.rules):
		var t: PitchType = catalog.get(id)
		var b := UiKit.button("새 구종: %s (%d GP)" % [t.label if t != null else String(id), roundi(cs.rules.new_pitch_gp)], func() -> void:
			PitchEvolution.learn(c, id, cs.rules, catalog)
			refresh(), "plus")
		b.disabled = float(c.gp.get("pitching", 0.0)) < cs.rules.new_pitch_gp
		p.body.add_child(b)


func _build_table(cs: CareerSeason) -> void:
	var s := cs.season
	var d := s.division_of(cs.career.team_id)
	var p := panel("%d부 리그 순위" % (d + 1), "ranking", null, 0.0, "STANDINGS")
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var table := DataTable.new()
	table.row_height = 46.0
	table.set_columns([["순위", 70.0, 1], ["구단", 360.0, 0], ["승", 70.0, 2], ["패", 70.0, 2], ["무", 70.0, 2], ["승률", 100.0, 2], ["게임차", 100.0, 2], ["연속", 100.0, 2]])
	var i := 0
	for row: StandingsRow in s.standings[d].ranked():
		i += 1
		var at := table.add_row([str(i), s.teams[row.team_id].name, str(row.wins), str(row.losses), str(row.ties), row.pct_text(), "%.1f" % s.standings[d].games_behind(row.team_id), row.streak_text()], row.team_id, {0: UiTheme.ACCENT if i <= 4 else UiTheme.DIM})
		if row.team_id == cs.career.team_id:
			table.selected = at
	p.body.add_child(table)


# --- Actions ---


func play_on_screen() -> void:
	var cs := CareerSession.career_season
	var g := cs.club_game()
	var info := {"title": "커리어 · %s" % cs.career.player.name}
	if g != null:
		info["away"] = cs.season.teams[g.away]
		info["home"] = cs.season.teams[g.home]
		info["line"] = "%d년 시즌 %d일차" % [cs.season.season_year, cs.season.day + 1]
	go(CareerSession.MATCH, info)


func quick() -> void:
	var cs := CareerSession.career_season
	if not cs.has_game():
		return
	CareerSession.last_report = cs.quick()
	refresh()


func next_day() -> void:
	CareerSession.career_season.next_day()
	refresh()


## The rest of the season with his games settled at once.
func to_end() -> void:
	var cs := CareerSession.career_season
	var guard := 0
	while not cs.season.finished() and guard < 500:
		if cs.all_star_today:
			cs.quick_all_star()
		if cs.derby_waiting:
			cs.quick_derby()
		if cs.has_game():
			CareerSession.last_report = cs.quick()
		cs.next_day()
		guard += 1
	message = "시즌이 종료되었습니다."
	refresh()
