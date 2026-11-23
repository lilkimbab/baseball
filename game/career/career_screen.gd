class_name CareerScreen
extends Screen
## The career's screen between games. Its tabs: today
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
const CAREER_TABS: Array[Array] = [["home", "오늘"], ["growth", "성장"], ["money", "계약·투자"], ["records", "기록"], ["table", "순위"]]

var message := ""
var _tab := "home"


func setup() -> void:
	heading = "전설의 시작"
	heading_latin = "CAREER"
	vantage = &"field"
	dock_id = "career"


func refresh() -> void:
	if is_inside_tree() and CareerSession.career_season != null:
		CareerSession.settle_points()
		Achievements.check_career(CareerSession.career_season, CareerSession.last_report)
		CareerSession.autosave()
	super.refresh()
	play_cues.call_deferred()


func _ready() -> void:
	super._ready()
	play_cues.call_deferred()


## The career's cutscenes waiting (CareerSeason.cues: the draft, a trade, a call-up, the
## awards, a championship, a contract), one after another over this screen.
func play_cues() -> void:
	var cs := CareerSession.career_season
	if cs == null or cs.cues.is_empty() or Ceremony.showing or not is_inside_tree():
		return
	var list: Array = []
	for c: Array in cs.cues:
		var team: Team = cs.season.teams.get(cs.career.team_id)
		var from: Team = cs.season.teams.get(str(c[4])) if str(c[4]) != "" else null
		list.append([c[0], c[1], c[2], c[3], team, from, cs.career.player])
	cs.cues.clear()
	Ceremony.play_all(self, list)


func build() -> void:
	var cs := CareerSession.career_season
	if cs == null or (cs.career != null and cs.career.retired):
		var row := UiKit.hbox(20)
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(row)
		var p := panel("전설의 시작", "user-circle", row, 0.0, "CAREER")
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if cs != null:
			p.body.add_child(UiKit.heading("%s 선수는 은퇴했습니다" % cs.career.player.name, 26, UiTheme.ACCENT))
			for line: String in Array(cs.log).slice(maxi(cs.log.size() - 3, 0)):
				p.body.add_child(UiKit.label(line, 17, UiTheme.INK, 500))
			p.body.add_child(UiKit.button("은퇴 결산 보기", func() -> void: go(CareerSession.RETIRE), "trophy"))
		else:
			p.body.add_child(UiKit.label("진행 중인 커리어가 없습니다.", 20, UiTheme.DIM, 500))
		p.body.add_child(UiKit.button("선수 생성", func() -> void: go(CareerSession.CREATE), "plus", "primary", 320.0))
		_build_hall(row)
		return
	CareerSession.settle_points()
	var c := cs.career
	var s := cs.season
	var team: Team = s.teams[c.team_id]
	var phase: String = ["정규 시즌", "포스트시즌", "시즌 종료"][s.phase]
	if s.school:
		phase = ["주말리그", "왕중왕전", "시즌 종료"][s.phase]
		set_heading(c.player.name, "%s 3학년 · %d년 고교리그 %s %d일차" % [team.name, s.season_year, phase, s.day + 1])
	else:
		set_heading(c.player.name, "%s · %s · %d년 %s %d일차" % [team.name, "1군" if c.first_team else "2군", s.season_year, phase, s.day + 1])
	if tab_bar != null:
		var ids: Array = []
		var labels: Array = []
		for pair: Array in CAREER_TABS:
			ids.append(pair[0])
			labels.append(pair[1])
			if pair[0] == "growth" and c.is_pitcher():
				ids.append("pitches")
				labels.append("구종 상점")
		var tabs := UiKit.tabs(ids, labels, _tab, func(id: String) -> void:
			_tab = id
			refresh())
		for b: Node in tabs.get_children():
			(b as GameButton).tint = tint
		tab_bar.add_child(tabs)
	match _tab:
		"growth":
			_build_growth(cs)
		"pitches":
			_build_pitch_shop(cs)
		"money":
			_build_money(cs)
		"records":
			_build_records(cs)
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
	words.add_child(UiKit.latin("No.%d  ·  %s" % [p.number, "HIGH SCHOOL" if s.school else ("FIRST TEAM" if c.first_team else "FARM TEAM")], 17, tint, true))
	words.add_child(UiKit.heading(p.name, 38))
	words.add_child(UiKit.label("%s · %s" % [cs.rules.position_names.get(c.position, c.position), type.name if type != null else ""], 16, UiTheme.DIM, 500))
	name_row.add_child(words)
	name_row.add_child(UiKit.button("선수 카드", func() -> void: PlayerCard.open_for(self, p, s), "identification-card"))

	# The winter of his free agency has a screen of its own (the stove league).
	if not s.school and s.finished():
		CareerSession.start_winter()
	if _fa_hub_active(cs):
		_build_fa_hub(columns, cs)
		return
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
		row.add_child(UiKit.club_side(cs.side_team(g.away), "AWAY", 84.0, 22))
		row.add_child(UiKit.number("VS", 50, Color(1.0, 1.0, 1.0, 0.9)))
		row.add_child(UiKit.club_side(cs.side_team(g.home), "HOME", 84.0, 22))
		var play := UiKit.button("경기 출전", play_on_screen, "play", "primary", 240.0)
		play.add_theme_font_size_override("font_size", 24)
		actions.add_child(play)
		actions.add_child(UiKit.button("빠른 진행", quick, "fast-forward"))
	elif s.phase != Season.Phase.OVER:
		var hurt := s.injuries.is_out(c.player.id)
		var why := "오늘은 경기가 없습니다."
		if hurt:
			why = "부상자 명단 (%s) · 복귀까지 %d일" % [s.injuries.cause_of(c.player.id), s.injuries.days_left(c.player.id)]
		elif cs.club_game() != null:
			why = "오늘 경기가 종료되었습니다."
		p.body.add_child(UiKit.label(why, 19, UiTheme.ACCENT if hurt else UiTheme.DIM, 500))
		actions.add_child(UiKit.button("다음 날", next_day, "caret-right", "primary", 200.0))
	elif s.school:
		# The school season is over: the draft decides where he goes.
		p.body.add_child(UiKit.heading("고교 시즌이 끝났습니다", 24, UiTheme.ACCENT))
		p.body.add_child(UiKit.label("이제 신인 드래프트입니다. 구단은 고를 수 없고, 지명한 구단에 입단합니다.", 18, UiTheme.INK, 500))
		var draft := UiKit.button("드래프트 날", func() -> void: go(CareerSession.DRAFT, {"title": "신인 드래프트"}), "list-numbers", "primary", 280.0)
		draft.add_theme_font_size_override("font_size", 24)
		actions.add_child(draft)
	else:
		# The winter: his new contract (or a release, or free agency), then the next season.
		CareerSession.start_winter()
		p.body.add_child(UiKit.heading("%d년 시즌 종료 · 겨울" % s.season_year, 24, UiTheme.ACCENT))
		for line: String in cs.winter_lines:
			p.body.add_child(UiKit.label(line, 18, UiTheme.ACCENT if line.begins_with("구단이 은퇴를") else UiTheme.INK, 500))
		if cs.career.final_season:
			# His farewell tour is over: the ceremony (CareerLegacy).
			var farewell := UiKit.button("은퇴식", func() -> void: go(CareerSession.FAREWELL, {"title": "은퇴식"}), "trophy", "primary", 240.0)
			farewell.add_theme_font_size_override("font_size", 22)
			actions.add_child(farewell)
		elif not _fa_hub_active(cs):
			var go_on := UiKit.button("다음 시즌", func() -> void:
				CareerSession.next_season()
				message = ""
				refresh(), "caret-right", "primary", 240.0)
			go_on.add_theme_font_size_override("font_size", 22)
			actions.add_child(go_on)
			# A veteran may announce his last season: a farewell tour, the clubs' gifts on the road.
			if s.season_year + 1 - cs.career.player.born >= 33:
				var tour := UiKit.button("은퇴 투어 발표", func() -> void:
					CareerLegacy.announce(cs)
					message = "다음 시즌이 마지막 시즌입니다. 원정 구장마다 상대 구단이 작별 선물을 준비합니다."
					CareerSession.next_season()
					refresh(), "flag-pennant")
				tour.tooltip_text = "다음 시즌을 마지막으로 은퇴합니다"
				actions.add_child(tour)
		# He may hang up his spikes in any winter (a second press: no going back).
		if not cs.career.final_season:
			var retire := UiKit.button("은퇴", func() -> void: pass, "flag-pennant", "danger")
			retire.pressed.connect(func() -> void:
				if retire.text == "은퇴":
					retire.text = "정말 은퇴합니다 (되돌릴 수 없음)"
					return
				go(CareerSession.FAREWELL, {"title": "은퇴식"}))
			actions.add_child(retire)
	if s.phase != Season.Phase.OVER:
		actions.add_child(UiKit.button("시즌 끝까지 진행", to_end, "skip-forward"))
		if c.final_season:
			p.body.add_child(UiKit.label("은퇴 투어 · 마지막 시즌 (작별 선물 %d개)" % c.tour_gifts.size(), 17, UiTheme.ACCENT, 700))
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
	# A starter's turns marked (CareerSeason.on_turn): today's game, if still to play, is the first.
	var starter := cs.career.is_pitcher() and cs.career.position == "SP"
	var first := 1 if cs.has_game() else 0
	var shown := ahead.slice(0, 5)
	for i: int in shown.size():
		var g: ScheduledGame = shown[i]
		var other: Team = s.teams[g.opponent_of(team.id)]
		var turn := starter and cs.on_turn(first + i)
		var cell: PanelContainer = UiKit.well(8.0)
		if turn:
			cell = PanelContainer.new()
			cell.add_theme_stylebox_override(&"panel", UiTheme.flat(Color(UiTheme.ACCENT, 0.14), 6, Color(UiTheme.ACCENT, 0.9), 2, 8.0))
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
		if turn:
			var mine := UiKit.label("선발 등판", 14, UiTheme.ACCENT, 700)
			mine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(mine)


## The last game: his line, the goal, the rating and medal, what he earned.
func _build_report(parent: Control, cs: CareerSeason) -> void:
	var p := panel("지난 경기", "article", parent, 0.0, "LAST GAME")
	var r := CareerSession.last_report
	# (Before his first game there is nothing to fill it: as tall as its line then.)
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL if r != null or not cs.log.is_empty() else Control.SIZE_SHRINK_BEGIN
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
		words.add_child(UiKit.label("목표 %s · %s" % [r.goal, "달성" if r.goal_met else "실패"], 17, UiTheme.GREEN if r.goal_met else UiTheme.DIM, 600))
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
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		p.body.add_child(scroll)
		var lines := UiKit.vbox(2)
		lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(lines)
		# The newest first, and wrapped: a long line (a free agent's deal) must not push the
		# columns off the screen (the user, 2026-11-23).
		var recent := Array(cs.log).slice(maxi(cs.log.size() - 40, 0))
		recent.reverse()
		for entry: String in recent:
			var l := UiKit.label(entry, 15, UiTheme.DIM, 500)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lines.add_child(l)


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
	# A pro's contract: this year's salary, his money, his years and the FA clock.
	if not cs.season.school:
		var deal := UiKit.hbox(0)
		deal.add_theme_constant_override("separation", 8)
		p.body.add_child(deal)
		var fa := CareerFA.seasons_counted(c, cs.season.total_days())
		var clock := "%d년 남음" % c.contract_years if c.contract_years > 0 else "%d/%d" % [mini(fa, CareerFA.need_seasons(c)), CareerFA.need_seasons(c)]
		for pair: Array in [[FreeAgency.money(c.salary), "연봉"], [FreeAgency.money(c.money), "보유 금액"], [clock, "계약 기간" if c.contract_years > 0 else "FA 시즌"]]:
			var f := UiKit.tile(str(pair[0]), str(pair[1]), 0.0, 22)
			f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			deal.add_child(f)
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
	p.body.add_child(CenteredPanel.section("%s 시즌 기록" % ("고교" if cs.season.school else ("1군" if c.first_team else "2군"))))
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
	_growth_card(columns, cs)
	var fields: Array[String] = ["batting", "running", "fielding"]
	if c.is_pitcher():
		fields = ["pitching"]
	# One panel, a section a field (three thin panels were left mostly empty: the user, 2026-11-23).
	var p := panel("능력치 성장" if not c.is_pitcher() else FIELD_NAMES["pitching"], "chart-line-up" if not c.is_pitcher() else FIELD_ICONS["pitching"], columns, 0.0, "GROWTH")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for field: String in fields:
		var have := float(c.gp.get(field, 0.0))
		if not c.is_pitcher():
			if field != "batting":
				p.body.add_child(UiKit.rule())
			var head := UiKit.hbox(8)
			p.body.add_child(head)
			head.add_child(UiKit.icon(FIELD_ICONS[field], 22.0, tint))
			head.add_child(UiKit.label(FIELD_NAMES[field], 19, Color.WHITE, 700))
			head.add_child(UiKit.latin("%d GP" % roundi(have), 18, tint, true))
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
			var top := value >= Growth.TOP
			var price := Growth.cost(c, rating, cs.rules)
			var up := UiKit.button("최고" if top else "+ %d" % ceili(price), func() -> void:
				Growth.raise(c, rating, cs.rules)
				refresh(), "", "primary" if have >= price and not top else "")
			up.disabled = top or have < price
			up.custom_minimum_size = Vector2(96.0, 46.0)
			up.add_theme_font_size_override("font_size", 20)
			up.tooltip_text = "이미 최고치입니다" if top else "성장 포인트 %d 사용" % ceili(price)
			row.add_child(up)
		if c.is_pitcher():
			p.body.add_child(UiKit.rule())
			p.body.add_child(UiKit.caption("보유 구종"))
			_arsenal_grid(p.body, cs)


## The man as a card beside his ratings: his overall in its tier's colour, his shape on the radar,
## what his points buy now (so neither column is left half empty: the user, 2026-11-23).
func _growth_card(parent: Control, cs: CareerSeason) -> void:
	var c := cs.career
	var p := panel("선수", "user-circle", parent, 400.0, "PLAYER")
	var raw := ClubRules.player_ovr(c.player, cs.season.ovr, cs.season.catalog)
	var top := UiKit.hbox(14)
	p.body.add_child(top)
	var ovr := UiKit.number("%d" % roundi(UiTheme.shown(raw)), 72, UiTheme.rating_color(raw))
	top.add_child(ovr)
	var who := UiKit.vbox(2)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(who)
	who.add_child(UiKit.latin("OVERALL", 16, UiTheme.DIM, true))
	var type := cs.rules.type_by_id(c.type_id)
	who.add_child(UiKit.label("%s · %s" % [cs.rules.position_names.get(c.position, c.position), type.name if type != null else ""], 19, Color.WHITE, 700))
	var radar: RadarChart
	var p2 := c.player
	if c.is_pitcher():
		radar = RadarChart.make(PackedStringArray(["구위", "제구", "체력", "위기관리", "변화구"]), PackedFloat32Array([p2.pitching.stuff(cs.season.catalog), p2.pitching.control, p2.pitching.stamina, p2.pitching.composure, p2.pitching.breaking(cs.season.catalog)]), 320.0)
	else:
		radar = RadarChart.make(PackedStringArray(["컨택트", "파워", "선구안", "주력", "수비"]), PackedFloat32Array([p2.batting.contact(), p2.batting.power(), p2.batting.eye, (p2.batting.speed + p2.batting.baserunning) * 0.5, p2.fielding.overall()]), 320.0)
	radar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.body.add_child(radar)
	p.body.add_child(UiKit.spacer(0.0, 0.0, true))
	var tiles := UiKit.hbox(8)
	p.body.add_child(tiles)
	var bonus := roundi((CareerMoney.growth_share(cs) - 1.0) * 100.0)
	var points := 0.0
	for field: String in c.gp:
		points += float(c.gp[field])
	for pair: Array in [["%d" % roundi(points), "보유 GP"], ["+%d%%" % bonus if bonus > 0 else "없음", "트레이닝"]]:
		var t := UiKit.tile(str(pair[0]), str(pair[1]), 0.0, 24)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tiles.add_child(t)
	var tip := UiKit.label("높이 올라갈수록 비용이 커집니다. 최고치는 99입니다.", 15, UiTheme.DIM, 500)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.body.add_child(tip)


## A pitcher's pitches as cards: speed, how often thrown (they evolve with use), movement and
## command; new ones are learned in the pitch shop (its own tab).
func _arsenal_grid(parent: Control, cs: CareerSeason) -> void:
	var c := cs.career
	var catalog := cs.season.catalog
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	parent.add_child(grid)
	for a: ArsenalPitch in c.player.pitching.arsenal:
		var t: PitchType = catalog.get(a.type)
		var well := UiKit.well(10.0)
		well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(well)
		var box := UiKit.vbox(4)
		well.add_child(box)
		var head_row := UiKit.hbox(8)
		box.add_child(head_row)
		var name := UiKit.heading(t.label if t != null else String(a.type), 20)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head_row.add_child(name)
		head_row.add_child(UiKit.latin("%d km/h · %d구" % [roundi(a.velo_avg), int(c.pitch_uses.get(a.type, 0))], 16, UiTheme.DIM))
		if t != null:
			head_row.add_child(UiKit.badge(str(FAMILY_NAMES.get(t.family, "")), FAMILY_COLOURS.get(t.family, UiTheme.DIM)))
		box.add_child(StatBar.make("변화", a.movement, -1.0, 90.0))
		box.add_child(StatBar.make("제구", a.command, -1.0, 90.0))
	parent.add_child(UiKit.spacer(0.0, 0.0, true))
	var learn := PitchEvolution.learnable(c, cs.rules)
	if not learn.is_empty():
		parent.add_child(UiKit.button("구종 상점 (%d종)" % learn.size(), func() -> void:
			_tab = "pitches"
			refresh(), "storefront"))


const FAMILY_NAMES := {&"fastball": "패스트볼", &"breaking": "브레이킹", &"offspeed": "오프스피드"}
const FAMILY_COLOURS := {&"fastball": Color(0.93, 0.36, 0.32), &"breaking": Color(0.35, 0.62, 1.0), &"offspeed": Color(0.4, 0.8, 0.5)}
## A line on each pitch for the shop.
const PITCH_NOTES := {
	&"four_seam": "가장 빠르고 곧은 직구입니다.",
	&"two_seam": "팔 쪽으로 휘며 가라앉는 빠른 공. 땅볼을 끌어냅니다.",
	&"cutter": "빠르게 오다 끝에서 짧게 꺾입니다. 배트 중심을 피합니다.",
	&"slider": "가장 많이 쓰는 옆으로 휘는 변화구. 헛스윙을 부릅니다.",
	&"sweeper": "옆으로 크게 쓸고 나가는 슬라이더입니다.",
	&"curve": "크게 떨어지는 느린 변화구. 타이밍을 빼앗습니다.",
	&"changeup": "직구처럼 던지지만 느리게 가라앉습니다.",
	&"splitter": "직구처럼 오다 홈 앞에서 뚝 떨어집니다.",
	&"rising_fastball": "회전이 많아 떠오르는 듯한 직구입니다.",
	&"hard_slider": "빠르고 짧게 꺾이는 고속 슬라이더입니다.",
	&"power_curve": "빠르고 날카롭게 떨어지는 커브입니다.",
	&"circle_change": "팔 쪽으로 휘며 떨어지는 체인지업입니다.",
	&"sinker": "무겁게 가라앉는 빠른 공. 땅볼이 늘어납니다.",
	&"forkball": "회전이 거의 없이 크게 떨어지는 공입니다.",
	&"knuckle_curve": "손끝으로 채어 던지는 날카로운 커브입니다.",
	&"slurve": "슬라이더와 커브의 중간, 옆으로 크게 떨어집니다.",
	&"screwball": "팔 쪽으로 휘며 떨어지는 보기 드문 공입니다.",
	&"knuckleball": "회전 없이 흔들리며 들어옵니다. 예측이 어렵습니다.",
}


## The pitch shop (the user, 2026-11-23: "the new pitches crowd the growth page — make it a shop"):
## every pitch he can still learn as a card — its kind, the speed it would have from his arm, its
## spin and a line on it — bought with pitching points, or, for a pro, with a course of lessons.
func _build_pitch_shop(cs: CareerSeason) -> void:
	var c := cs.career
	var catalog := cs.season.catalog
	var p := panel("구종 상점", "storefront", content, 0.0, "PITCH SHOP")
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head := UiKit.hbox(8)
	p.body.add_child(head)
	var gp := float(c.gp.get("pitching", 0.0))
	var tiles: Array = [["%d GP" % roundi(gp), "보유 투구 포인트"], ["%d / %d" % [c.player.pitching.arsenal.size(), cs.rules.max_pitches], "보유 구종"]]
	if not cs.season.school:
		tiles.append([FreeAgency.money(c.money) + " 원", "보유 금액"])
	for pair: Array in tiles:
		var t := UiKit.tile(str(pair[0]), str(pair[1]), 0.0, 24)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
	var about := UiKit.label("새 구종은 처음엔 조금 약하고, 많이 던질수록 좋아집니다.", 15, UiTheme.DIM, 500)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.body.add_child(about)
	if message != "":
		p.body.add_child(UiKit.label(message, 16, UiTheme.ACCENT, 700))
	var learn := PitchEvolution.learnable(c, cs.rules)
	if learn.is_empty():
		p.body.add_child(UiKit.heading("구종을 최대 %d개까지 익혔습니다" % cs.rules.max_pitches, 22, UiTheme.DIM))
		return
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var fastball := c.player.pitching.fastball_speed()
	for id: StringName in learn:
		var t: PitchType = catalog.get(id)
		var well := UiKit.well(12.0)
		well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(well)
		var box := UiKit.vbox(6)
		well.add_child(box)
		var top := UiKit.hbox(8)
		box.add_child(top)
		var name := UiKit.heading(t.label if t != null else String(id), 22)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name)
		if t != null:
			top.add_child(UiKit.badge(str(FAMILY_NAMES.get(t.family, "")), FAMILY_COLOURS.get(t.family, UiTheme.DIM)))
			var speed := t.speed_kmh + (fastball - 145.0) * 0.8
			box.add_child(UiKit.latin("예상 %d km/h  ·  %s rpm" % [roundi(speed), str(roundi(t.spin_rpm))], 16, UiTheme.INK))
		var note := UiKit.label(str(PITCH_NOTES.get(id, "")), 14, UiTheme.DIM, 500)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.y = 40.0
		box.add_child(note)
		var buy := UiKit.hbox(8)
		box.add_child(buy)
		var label := t.label if t != null else String(id)
		var with_points := UiKit.button("%d GP" % roundi(cs.rules.new_pitch_gp), func() -> void:
			if PitchEvolution.learn(c, id, cs.rules, catalog):
				message = "%s을(를) 익혔습니다." % label
			refresh(), "", "")
		with_points.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		with_points.custom_minimum_size.y = 42.0
		with_points.add_theme_font_size_override("font_size", 18)
		with_points.disabled = gp < cs.rules.new_pitch_gp
		with_points.tooltip_text = "투구 포인트가 부족합니다" if with_points.disabled else "투구 포인트로 익힙니다"
		buy.add_child(with_points)
		if not cs.season.school:
			var lesson := UiKit.button("%s 원" % FreeAgency.money(CareerContract.LESSON_PRICE), func() -> void:
				if CareerContract.lesson(cs, id):
					message = "%s 레슨을 받아 새 구종을 익혔습니다." % label
				refresh(), "", "gold")
			lesson.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lesson.custom_minimum_size.y = 42.0
			lesson.add_theme_font_size_override("font_size", 18)
			lesson.disabled = c.money < CareerContract.LESSON_PRICE
			lesson.tooltip_text = "보유 금액이 부족합니다" if lesson.disabled else "투구 아카데미 레슨을 받습니다"
			buy.add_child(lesson)


## His records: each season's line (first team and second), his first-team
## totals, and this season's games one by one.
func _build_records(cs: CareerSeason) -> void:
	var c := cs.career
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var left := panel("시즌별 기록", "chart-bar", columns, 0.0, "SEASONS")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var table := DataTable.new()
	table.row_height = 34.0
	table.set_columns([["연도", 80.0, 1], ["구단", 200.0, 0], ["1군 일수", 100.0, 2], ["기록", 520.0, 0]])
	for row: Variant in c.seasons:
		var r: Array = row
		table.add_row([str(int(r[0])), str(r[1]), str(int(r[2])), str(r[3])], str(r[0]))
	if not cs.season.school:
		table.add_row([str(cs.season.season_year), cs.season.teams[c.team_id].name, str(cs.first_team_days), CareerContract.season_line(cs) + " (진행 중)"], "now")
	table.custom_minimum_size.y = 48.0 + 34.0 * (c.seasons.size() + 1)
	left.body.add_child(table)
	var sum := CareerContract.totals(c, cs)
	var bat: BattingLine = sum[0]
	var pitch: PitchingLine = sum[1]
	left.body.add_child(UiKit.caption("1군 통산"))
	var tiles := UiKit.hbox(8)
	left.body.add_child(tiles)
	var figures: Array = [["%d" % pitch.wins, "승"], ["%d" % pitch.losses, "패"], ["%d" % pitch.saves, "세이브"], ["%.2f" % pitch.era() if pitch.outs > 0 else "-", "평균자책점"], ["%d" % pitch.strikeouts, "탈삼진"]] if c.is_pitcher() else \
		[["%d" % bat.games, "경기"], ["%d" % bat.hits, "안타"], ["%d" % bat.home_runs, "홈런"], ["%d" % bat.rbi, "타점"], [BattingLine.rate_text(bat.average()), "타율"], [BattingLine.rate_text(bat.ops()), "OPS"]]
	for f: Array in figures:
		var t := UiKit.tile(str(f[0]), str(f[1]), 0.0, 26)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tiles.add_child(t)
	# The commemorative balls (Milestones): a first hit, 100 hits, a first win …
	if c.first_team or not c.milestones.is_empty():
		left.body.add_child(UiKit.caption("기념구  %d개" % c.milestones.size()))
		var shelf := BallShelf.new()
		shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.body.add_child(shelf)
		shelf.fill(c, sum)
	var right := panel("경기별 기록", "list-numbers", columns, 620.0, "GAME LOG")
	var log: Array = cs.season.game_logs.get(c.player.id, [])
	if log.is_empty():
		right.body.add_child(UiKit.label("이번 시즌 경기 기록이 아직 없습니다.", 16, UiTheme.DIM, 500))
	var games := DataTable.new()
	games.row_height = 32.0
	games.set_columns([["일", 60.0, 1], ["상대", 180.0, 0], ["", 40.0, 1], ["구분", 60.0, 1], ["기록", 260.0, 0]])
	for i: int in range(log.size() - 1, maxi(log.size() - 40, 0) - 1, -1):
		var e: Array = log[i]
		var other := cs.side_team(str(e[1])) if cs.season.teams.has(str(e[1])) or cs.farm_mode() else null
		var other_name := other.name if other != null else str(e[1])
		if cs.season.teams.has(str(e[1])):
			other_name = cs.season.teams[str(e[1])].name
		games.add_row([str(int(e[0]) + 1), ("vs " if int(e[2]) == 1 else "@ ") + other_name, str(e[3]), str(e[6]), GameLog.text(e)], str(i), {2: UiTheme.GREEN if str(e[3]) == "승" else (UiTheme.RED if str(e[3]) == "패" else UiTheme.DIM)})
	games.custom_minimum_size.y = 48.0 + 32.0 * mini(log.size(), 40)
	var scroll := UiKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(games)
	right.body.add_child(scroll)


## The hall of fame of the person's careers.
func _build_hall(parent: Control) -> void:
	var p := panel("명예의 전당", "trophy", parent, 620.0, "HALL OF FAME")
	var list := HallOfFame.load_list()
	if list.is_empty():
		p.body.add_child(UiKit.label("아직 헌액된 선수가 없습니다.", 18, UiTheme.DIM, 500))
	for entry: Variant in list:
		var e: Dictionary = entry
		p.body.add_child(UiKit.heading("%s · %s" % [str(e.get("name", "")), str(e.get("club", ""))], 22))
		p.body.add_child(UiKit.label("%s (%d년 은퇴)" % [str(e.get("line", "")), int(e.get("retired", 0))], 16, UiTheme.INK, 500))
		p.body.add_child(UiKit.label("헌액: %s" % ", ".join(PackedStringArray(e.get("marks", []))), 15, UiTheme.ACCENT, 600))
	p.body.add_child(UiKit.rule())
	p.body.add_child(UiKit.caption("헌액 기준"))
	p.body.add_child(UiKit.label(HallOfFame.MARKS_TEXT, 15, UiTheme.DIM, 500))


func _build_table(cs: CareerSeason) -> void:
	var s := cs.season
	var d := s.division_of(cs.career.team_id)
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	# The first teams' table, and beside it the futures league's (north and south) with his
	# second team marked.
	if cs.farm_mode():
		_build_futures_table(cs, columns)
	var p := panel("%s 순위" % LeagueScreen.league_name(cs.season, d), "ranking", columns, 0.0, "STANDINGS")
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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


func _build_futures_table(cs: CareerSeason, parent: Control) -> void:
	var s := cs.season
	var p := panel("퓨처스리그", "ranking", parent, 0.0, "FUTURES LEAGUE")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var standings := s.farm.standings[0]
	for group: Array in [["북부리그", s.farm.north], ["남부리그", s.farm.south]]:
		var ids: PackedStringArray = group[1]
		p.body.add_child(UiKit.caption(str(group[0])))
		var table := DataTable.new()
		table.set_columns([["순위", 60.0, 1], ["팀", 260.0, 0], ["승", 60.0, 2], ["패", 60.0, 2], ["무", 60.0, 2], ["승률", 80.0, 2]])
		var rows: Array[StandingsRow] = []
		for r: StandingsRow in standings.ranked():
			if ids.has(r.team_id):
				rows.append(r)
		for i: int in rows.size():
			var r := rows[i]
			var side := s.farm.team_of(s, r.team_id)
			var at := table.add_row(["%d" % (i + 1), side.name if side != null else r.team_id, str(r.wins), str(r.losses), str(r.ties), BattingLine.rate_text(r.pct()) if r.wins + r.losses > 0 else "-"], r.team_id, {0: UiTheme.ACCENT})
			if r.team_id == cs.career.team_id:
				table.selected = at
		table.custom_minimum_size.y = 48.0 + 38.0 * rows.size()
		p.body.add_child(table)


# --- Actions ---


func play_on_screen() -> void:
	var cs := CareerSession.career_season
	var g := cs.club_game()
	var info := {"title": "전설의 시작 · %s" % cs.career.player.name}
	if g != null:
		info["away"] = cs.side_team(g.away)
		info["home"] = cs.side_team(g.home)
		info["line"] = "%d년 시즌 %d일차" % [cs.season.season_year, cs.season.day + 1]
	go(CareerSession.MATCH, info)


func quick() -> void:
	var cs := CareerSession.career_season
	if not cs.has_game():
		return
	CareerSession.last_report = cs.quick()
	refresh()


func next_day() -> void:
	var cs := CareerSession.career_season
	cs.next_day()
	# A starter's days between his turns go by on their own (the user, 2026-11-23).
	var skipped := cs.skip_rest_days()
	message = "선발 로테이션: 등판하지 않는 %d일을 진행했습니다." % skipped if skipped > 0 else ""
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


# --- Free agency in the winter (CareerFA): the stove league ---


func _fa_hub_active(cs: CareerSeason) -> bool:
	return not cs.season.school and cs.season.finished() and (not cs.extension.is_empty() or cs.fa_state in ["eligible", "declared"])


const GRADE_COLOURS := {"A": Color(0.93, 0.33, 0.3), "B": Color(0.35, 0.62, 1.0), "C": Color(0.62, 0.65, 0.7)}
const ROLE_COLOURS := {"주전 보장": Color(0.34, 0.82, 0.45), "주전 경쟁": Color(0.35, 0.62, 1.0), "백업 역할": Color(0.62, 0.65, 0.7)}


## The stove league: his free agency as a screen of its own (as sports games give theirs) —
## the head with his grade, his price and his agent; then his club's offer before free agency,
## the choice to file, or the clubs' offers side by side.
func _build_fa_hub(parent: Control, cs: CareerSeason) -> void:
	var c := cs.career
	var s := cs.season
	var p := panel("%d 스토브리그" % (s.season_year + 1), "handshake", parent, 0.0, "FREE AGENCY")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# The head: grade, price, agent.
	var head := UiKit.hbox(10)
	p.body.add_child(head)
	var title := UiKit.heading("FA 자격 취득" if cs.fa_state != "" else "비FA 다년계약 제안", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if cs.fa_grade != "":
		head.add_child(UiKit.badge("%s등급" % cs.fa_grade, GRADE_COLOURS.get(cs.fa_grade, UiTheme.DIM)))
	head.add_child(UiKit.badge("예상 연평균 %s 원" % FreeAgency.money(CareerFA.asking(cs)), Color(1.0, 1.0, 1.0, 0.85)))
	if cs.agent:
		head.add_child(UiKit.badge("에이전트 선임", Color(0.55, 0.85, 0.65)))
	# The winter's news for him, in a line each.
	if not cs.winter_lines.is_empty():
		var news := UiKit.hbox(14)
		p.body.add_child(news)
		for line: String in cs.winter_lines:
			news.add_child(UiKit.label(line, 14, UiTheme.DIM, 500))
	p.body.add_child(UiKit.rule())
	if not cs.extension.is_empty():
		_build_extension(p.body, cs)
	elif cs.fa_state == "eligible":
		_build_fa_choice(p.body, cs)
	else:
		_build_fa_offers(p.body, cs)
	if message != "":
		p.body.add_child(UiKit.label(message, 16, UiTheme.ACCENT, 600))
	p.body.add_child(UiKit.spacer(0.0, 0.0, true))
	# He may still hang up his spikes (a second press: no going back).
	var foot := UiKit.hbox(10)
	foot.alignment = BoxContainer.ALIGNMENT_END
	p.body.add_child(foot)
	var retire := UiKit.button("은퇴", func() -> void: pass, "flag-pennant", "danger")
	retire.pressed.connect(func() -> void:
		if retire.text == "은퇴":
			retire.text = "정말 은퇴합니다 (되돌릴 수 없음)"
			return
		go(CareerSession.FAREWELL, {"title": "은퇴식"}))
	foot.add_child(retire)


## His club's offer before free agency: the deal large, what it means, take it or wait.
func _build_extension(body: Control, cs: CareerSeason) -> void:
	var team: Team = cs.season.teams[cs.career.team_id]
	body.add_child(UiKit.label("%s에서 FA 자격 취득 1년 전, 다년계약을 먼저 제안했습니다. 수락하면 계약 기간 동안 연봉이 고정되고, FA는 계약이 끝난 뒤 신청할 수 있습니다." % team.name, 16, UiTheme.INK, 500))
	var offer := {"club": team.id, "years": int(cs.extension[0]), "bonus": int(cs.extension[1]), "annual": int(cs.extension[2]), "option": [], "role": "", "status": "", "asks": 0, "rank": cs.season.standings[0].rank_of(team.id)}
	var card := _fa_card(cs, offer, -1)
	card.custom_minimum_size.x = 620.0
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(card)
	var row := UiKit.hbox(10)
	body.add_child(row)
	var take := UiKit.button("계약 수락", func() -> void:
		CareerFA.accept_extension(cs)
		message = "다년계약에 서명했습니다."
		refresh(), "handshake", "gold")
	take.add_theme_font_size_override("font_size", 20)
	row.add_child(take)
	row.add_child(UiKit.button("거절 (FA 도전)", func() -> void:
		cs.extension = []
		refresh(), "x"))


## File or stay, and the agent: three cards side by side.
func _build_fa_choice(body: Control, cs: CareerSeason) -> void:
	var c := cs.career
	if cs.fa_grade != "C":
		body.add_child(UiKit.label("%s등급 FA를 영입하는 구단은 원소속 구단에 보상선수와 보상금을 내야 하므로, 영입을 주저하는 구단이 있을 수 있습니다." % cs.fa_grade, 15, UiTheme.DIM, 500))
	var row := UiKit.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	row.add_child(_choice_card("handshake", "FA 신청", "여러 구단의 제안을 비교하고 재협상할 수 있습니다.", "FA 신청", "primary", func() -> void:
		CareerFA.declare(cs, Rng.new(hash("fa:%s:%d" % [c.player.id, cs.season.season_year])))
		refresh(), false))
	row.add_child(_choice_card("house", "잔류", "연봉 %s 원에 1년 재계약. 자격은 내년에도 유지됩니다." % FreeAgency.money(c.salary), "1년 재계약", "button", func() -> void:
		CareerFA.stay(cs)
		refresh(), false))
	row.add_child(_choice_card("user", "에이전트", "수수료 %d%%. 더 좋은 조건을 끌어냅니다." % roundi(CareerFA.AGENT_FEE * 100.0), "에이전트 선임 완료" if cs.agent else "에이전트 선임", "button", func() -> void:
		CareerFA.hire_agent(cs)
		message = "에이전트를 선임했습니다."
		refresh(), cs.agent))
	# What the papers say: the clubs interested (his own one besides).
	var keen := CareerFA.interested(cs)
	body.add_child(CenteredPanel.section("관심을 보이는 구단 %d곳" % keen.size()))
	if keen.is_empty():
		body.add_child(UiKit.label("아직 다른 구단의 관심은 확인되지 않았습니다. 원소속 구단의 제안은 받을 수 있습니다.", 15, UiTheme.DIM, 500))
	var clubs := UiKit.hbox(10)
	body.add_child(clubs)
	for id: String in keen:
		var team: Team = cs.season.teams[id]
		var chip := UiKit.well(8.0)
		var line := UiKit.hbox(8)
		chip.add_child(line)
		line.add_child(UiKit.club_mark(team, 34.0))
		var words := UiKit.vbox(-2)
		words.add_child(UiKit.label(team.name, 16, Color.WHITE, 700))
		words.add_child(UiKit.label("지난 시즌 %d위" % cs.season.standings[0].rank_of(id), 13, UiTheme.DIM, 500))
		line.add_child(words)
		clubs.add_child(chip)


func _choice_card(icon_name: String, title: String, about: String, action: String, look: String, pick: Callable, done: bool) -> PanelContainer:
	var well := UiKit.well(16.0)
	well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := UiKit.vbox(10)
	well.add_child(box)
	box.add_child(UiKit.icon(icon_name, 40.0, tint))
	box.add_child(UiKit.heading(title, 26))
	var words := UiKit.label(about, 16, UiTheme.INK, 500)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.custom_minimum_size.x = 220.0
	box.add_child(words)
	box.add_child(UiKit.spacer(0.0, 0.0, true))
	var b := UiKit.button(action, pick, "check" if done else "", look)
	b.add_theme_font_size_override("font_size", 20)
	b.disabled = done
	box.add_child(b)
	return well


## The offers, two to a row, the best deal first.
func _build_fa_offers(body: Control, cs: CareerSeason) -> void:
	var order: Array[int] = []
	for i: int in cs.fa_offers.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return FreeAgency.total_of(CareerFA.deal_of(cs.fa_offers[a])) > FreeAgency.total_of(CareerFA.deal_of(cs.fa_offers[b])))
	var top := UiKit.hbox(10)
	body.add_child(top)
	var count := UiKit.label("구단 제안 %d건 · 계약 총액 순" % cs.fa_offers.size(), 17, Color.WHITE, 700)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(count)
	if not cs.agent:
		var agent := UiKit.button("에이전트 선임 (수수료 %d%%)" % roundi(CareerFA.AGENT_FEE * 100.0), func() -> void:
			CareerFA.hire_agent(cs)
			message = "에이전트를 선임했습니다. 구단별 협상 여지를 알려 주고 더 좋은 조건을 이끌어 냅니다."
			refresh(), "user")
		top.add_child(agent)
	var scroll := UiKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 470.0
	# (It takes the panel's height; the foot's spacer only what is left.)
	scroll.size_flags_stretch_ratio = 20.0
	body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for i: int in order:
		var card := _fa_card(cs, cs.fa_offers[i], i)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(card)
	# Every club walked away: a year with his own club at this winter's salary.
	if cs.fa_offers.all(func(o: Dictionary) -> bool: return str(o["status"]) == "withdrawn"):
		body.add_child(UiKit.label("모든 구단과의 협상이 결렬됐습니다.", 17, UiTheme.RED, 700))
		body.add_child(UiKit.button("원소속 구단과 1년 계약 (연봉 %s 원)" % FreeAgency.money(cs.career.salary), func() -> void:
			CareerFA.stay(cs)
			refresh(), "house"))


## A club's offer as a card: a band in its colours (emblem, name, its place last season, what he
## would be there), the total and the years large, the bonus, the salary and the option in
## tiles, the agent's word, and the answers. `index` −1: shown only (the extension).
func _fa_card(cs: CareerSeason, o: Dictionary, index: int) -> PanelContainer:
	var club: Team = cs.season.teams[str(o["club"])]
	var own := str(o["club"]) == cs.career.team_id
	var status := str(o["status"])
	var well := UiKit.well(0.0)
	var box := UiKit.vbox(0)
	well.add_child(box)
	var band := UiKit.band(club.primary, 74.0)
	box.add_child(band)
	var top := UiKit.hbox(12)
	band.get_child(1).add_child(top)
	top.add_child(UiKit.club_mark(club, 46.0))
	var words := UiKit.vbox(-2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(words)
	words.add_child(UiKit.label(club.name, 21, Color.WHITE, 800))
	words.add_child(UiKit.label("%s지난 시즌 %d위" % ["원소속 구단 · " if own else "", int(o["rank"])], 14, Color(1, 1, 1, 0.75), 600))
	if str(o.get("role", "")) != "":
		top.add_child(UiKit.badge(str(o["role"]), ROLE_COLOURS.get(str(o["role"]), UiTheme.DIM)))
	var inner := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 14)
	box.add_child(inner)
	var col := UiKit.vbox(10)
	inner.add_child(col)
	# The deal: the total and the years large.
	var deal := CareerFA.deal_of(o)
	var big := UiKit.hbox(16)
	col.add_child(big)
	var total := UiKit.vbox(-4)
	total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total.add_child(UiKit.caption("계약 총액"))
	total.add_child(UiKit.number("%s 원" % FreeAgency.money(FreeAgency.total_of(deal)), 36, Color.WHITE))
	big.add_child(total)
	var years := UiKit.vbox(-4)
	var y_caption := UiKit.caption("계약 기간")
	y_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	years.add_child(y_caption)
	var y_number := UiKit.number("%d년" % int(deal[0]), 36, Color.WHITE)
	y_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	years.add_child(y_number)
	big.add_child(years)
	var tiles := UiKit.hbox(8)
	col.add_child(tiles)
	var parts: Array = [[FreeAgency.money(int(deal[1])), "계약금"], [FreeAgency.money(int(deal[2])), "연봉"]]
	var option: Array = o.get("option", [])
	if not option.is_empty():
		parts.append([FreeAgency.money(int(option[0])), "옵션 (연)"])
	for part: Array in parts:
		var t := UiKit.tile(str(part[0]), str(part[1]), 0.0, 20)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tiles.add_child(t)
	if not option.is_empty():
		col.add_child(UiKit.label(CareerFA.option_text(option), 14, UiTheme.DIM, 500))
	if index < 0:
		return well
	# The answers, and the agent's word on how far it can still go.
	var foot := UiKit.hbox(8)
	col.add_child(foot)
	var room := CareerFA.room_word(cs, o)
	var hint := UiKit.label(room, 14, UiTheme.GREEN if room == "협상 여지 큼" else UiTheme.DIM, 600)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(hint)
	if status == "withdrawn":
		foot.add_child(UiKit.badge("협상 결렬", UiTheme.RED))
		well.modulate.a = 0.5
		return well
	if status == "final":
		foot.add_child(UiKit.badge("최종 제안", Color(1.0, 1.0, 1.0, 0.8)))
	else:
		var more := UiKit.button("재협상 (%d회 남음)" % int(o["asks"]), func() -> void:
			message = CareerFA.ask_more(cs, index, Rng.new(hash("ask:%s:%d:%d" % [cs.career.player.id, index, int(o["asks"])])))
			refresh(), "chart-line-up")
		more.add_theme_font_size_override("font_size", 16)
		more.disabled = int(o["asks"]) <= 0
		foot.add_child(more)
	var id := str(o["club"])
	var sign := UiKit.button("계약 체결", func() -> void:
		CareerSession.next_season(id)
		message = ""
		refresh(), "handshake", "gold")
	sign.add_theme_font_size_override("font_size", 17)
	foot.add_child(sign)
	return well


# --- His contract and his money (CareerFA, CareerMoney) ---


const INVEST_KINDS: Array = [["training", "트레이닝", "barbell", "성장 포인트가 늘어납니다"],
	["conditioning", "컨디셔닝", "shield", "부상 기간과 노쇠가 줄어듭니다"],
	["donations", "사회 공헌", "gift", "인기도가 올라 올스타·FA에 유리합니다"]]


func _build_money(cs: CareerSeason) -> void:
	var c := cs.career
	var s := cs.season
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	# The deal and the money; under it his gear (both as tall as what is in them).
	var stack := UiKit.vbox(16)
	columns.add_child(stack)
	var left := panel("계약", "handshake", stack, 440.0, "CONTRACT")
	left.body.add_child(UiKit.heading(CareerFA.contract_line(c) if not s.school else "고교 선수", 22, UiTheme.ACCENT))
	var tiles := UiKit.hbox(8)
	left.body.add_child(tiles)
	for pair: Array in [[FreeAgency.money(c.salary), "연봉"], [FreeAgency.money(c.money), "보유 금액"], [FreeAgency.money(c.earned), "누적 수입"]]:
		var t := UiKit.tile(str(pair[0]), str(pair[1]), 0.0, 22)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tiles.add_child(t)
	if not s.school:
		c.player.salary = c.salary if c.contract_years <= 0 else c.player.salary
		FreeAgency.ensure(s)
		var everyone: Array[int] = []
		for id: String in s.teams:
			for q: Player in (s.teams[id] as Team).players:
				if q.origin == &"":
					everyone.append(q.salary)
		everyone.sort()
		everyone.reverse()
		left.body.add_child(UiKit.label("리그 연봉 순위 %d위 / %d명" % [everyone.find(c.player.salary) + 1, everyone.size()], 17, UiTheme.INK, 600))
		var need := CareerFA.need_seasons(c)
		var counted := CareerFA.seasons_counted(c, s.total_days())
		left.body.add_child(UiKit.rule())
		left.body.add_child(UiKit.caption("FA"))
		if c.contract_years > 0:
			left.body.add_child(UiKit.label("계약 만료 후 FA 자격 (%d/%d시즌)" % [counted, need], 16, UiTheme.INK, 500))
		else:
			left.body.add_child(UiKit.label("%s FA까지 %d시즌 남음 (1군 등록일 %d%% 이상인 시즌만 인정)" % ["첫" if c.fa_count == 0 else "%d번째" % (c.fa_count + 1), maxi(need - counted, 0), roundi(CareerContract.FA_DAYS_SHARE * 100.0)], 16, UiTheme.INK, 500))
		left.body.add_child(_season_pips(mini(counted, need), need))
		if not c.contract_option.is_empty():
			left.body.add_child(UiKit.rule())
			left.body.add_child(UiKit.caption("옵션"))
			left.body.add_child(UiKit.label(CareerFA.option_text(c.contract_option), 16, UiTheme.INK, 600))
			left.body.add_child(UiKit.label("이번 시즌 달성 (겨울에 지급)" if CareerFA.option_met(cs, c.contract_option) else "아직 미달성 (시즌 종료 후 확정)", 15, UiTheme.GREEN if CareerFA.option_met(cs, c.contract_option) else UiTheme.DIM, 600))
	# What his money buys.
	var middle := panel("개인 투자", "coins", columns, 0.0, "INVEST")
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.body.add_child(UiKit.label("연봉이 오를수록 더 좋은 지원을 받습니다. 모두 시즌 단위입니다.", 16, UiTheme.INK, 500))
	var goal := CareerMoney.next_goal(cs)
	if goal != "":
		middle.body.add_child(UiKit.label("다음 목표: %s" % goal, 15, UiTheme.ACCENT, 700))
	for kind: Array in INVEST_KINDS:
		var head := UiKit.hbox(8)
		middle.body.add_child(head)
		head.add_child(UiKit.icon(str(kind[2]), 22.0, tint))
		head.add_child(UiKit.label(str(kind[1]), 19, Color.WHITE, 700))
		var about := UiKit.label(str(kind[3]), 14, UiTheme.DIM, 500)
		about.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(about)
		var row := UiKit.hbox(8)
		middle.body.add_child(row)
		var list := CareerMoney.catalog(str(kind[0]))
		for level: int in range(1, list.size() + 1):
			row.add_child(_invest_card(cs, str(kind[0]), level))
	if message != "":
		middle.body.add_child(UiKit.label(message, 16, UiTheme.ACCENT, 600))
	# Gear: the shop takes his money too.
	var right := panel("장비", "shopping-cart", stack, 440.0, "GEAR")
	right.body.add_child(UiKit.label("상점 장비는 보유 금액으로도 살 수 있습니다 (1P = %s 원)." % FreeAgency.money(CareerMoney.SHOP_RATE), 15, UiTheme.INK, 500))
	if c.gear.is_empty():
		right.body.add_child(UiKit.label("보유한 장비가 없습니다.", 15, UiTheme.DIM, 500))
	for name: String in c.gear:
		right.body.add_child(UiKit.label("%s  ·  %s" % [name, str(RATING_NAMES.get(c.gear[name], c.gear[name]))], 15, UiTheme.INK, 600))
	right.body.add_child(UiKit.button("상점으로", func() -> void: go("res://ui/shop_screen.tscn"), "storefront"))


## One grade of an investment: its name, price and effect, and the way to take it.
func _invest_card(cs: CareerSeason, kind: String, level: int) -> PanelContainer:
	var item: Array = CareerMoney.catalog(kind)[level - 1]
	var have := CareerMoney.grade(cs, kind)
	var well := UiKit.well(8.0)
	well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := UiKit.vbox(2)
	well.add_child(box)
	box.add_child(UiKit.latin(["STANDARD", "PRO", "ELITE"][level - 1], 14, ProductStage.GRADE_RINGS[level - 1], true))
	box.add_child(UiKit.label(str(item[0]), 17, Color.WHITE, 700))
	var effect := ""
	match kind:
		"training":
			effect = "성장 포인트 +%d%%" % roundi(float(item[2]) * 100.0)
		"conditioning":
			effect = "부상 기간 -%d%% · 노쇠 -%d%%" % [roundi(float(item[2]) * 100.0), roundi(float(item[3]) * 100.0)]
		_:
			effect = "인기도 +%d" % int(item[2])
	box.add_child(UiKit.label(effect, 14, UiTheme.GREEN, 600))
	var why := CareerMoney.problem(cs, kind, level)
	var on := kind != "donations" and have == level
	var label := "이용 중" if on else "%s 원" % FreeAgency.money(CareerMoney.price_now(cs, kind, level))
	var b := UiKit.button(label, func() -> void:
		message = CareerMoney.buy(cs, kind, level)
		CareerSession.autosave()
		Achievements.check_career(cs)
		refresh(), "check" if on else "coins", "gold" if why == "" else "button")
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size.y = 40.0
	b.disabled = why != ""
	if why != "" and not on:
		b.tooltip_text = why
	box.add_child(b)
	if why != "" and not on and why.ends_with("부족"):
		box.add_child(UiKit.label(why, 13, UiTheme.DIM, 500))
	if on:
		well.modulate = Color(1.0, 0.97, 0.85)
	return well


## The free agency clock as a row of pips, one a season (filled when counted).
func _season_pips(counted: int, need: int) -> Control:
	var row := UiKit.hbox(4)
	for i: int in need:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(0.0, 12.0)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pip.color = Color(tint, 0.95) if i < counted else Color(1.0, 1.0, 1.0, 0.12)
		row.add_child(pip)
	var words := UiKit.latin("%d / %d" % [counted, need], 16, UiTheme.INK, true)
	words.custom_minimum_size.x = 56.0
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(words)
	return row
