class_name RetireScreen
extends Screen
## His retirement ceremony: the man in his uniform on the left; in the middle
## his career — seasons, clubs, his first-team totals, each season's line; on the right the
## hall of fame: in or not, by which marks, and what the marks are. The career is closed.

var _result: Array = []


func setup() -> void:
	heading = "은퇴식"
	heading_latin = "RETIREMENT"
	vantage = &"field"
	dock_id = "career"
	back = CareerSession.HUB


func _ready() -> void:
	# (Retired at his park first, as a rule: FarewellScene; here directly, the same settling up.)
	_result = CareerSession.retire() if CareerSession.career != null and not CareerSession.career.retired else _summary()
	super._ready()


## The same summary for a career already closed.
static func _summary() -> Array:
	var c := CareerSession.career
	if c == null:
		return []
	var sum := CareerContract.totals(c)
	var met := PackedStringArray()
	for entry: Variant in HallOfFame.load_list():
		var e: Dictionary = entry
		if str(e.get("name", "")) == c.player.name and int(e.get("years", 0)) == c.pro_years:
			met = PackedStringArray(e.get("marks", []))
	return [sum[0], sum[1], met, c.titles_won.size()]


## The settling up (CareerLegacy), laid out to be read at a glance (the user, 2026-11-23: "make
## the record easy to see, no empty space"): a band across the top in his last club's colours —
## emblem, name, years, his grade with its badges, his four big numbers; under it the man, his
## first-team numbers and his seasons; at the right his honours as cards — titles, championships,
## all-star games, commemorative balls; his clubs; his money; the farewell tour's gifts; the hall
## of fame.
func build() -> void:
	var c := CareerSession.career
	var cs := CareerSession.career_season
	if c == null or cs == null or _result.is_empty():
		var p := panel("은퇴식", "user-circle", null, 0.0, "RETIREMENT")
		p.body.add_child(UiKit.label("은퇴할 수 있는 커리어가 없습니다. 시즌이 끝난 겨울에 은퇴할 수 있습니다.", 20, UiTheme.DIM, 500))
		return
	var team: Team = cs.season.teams[c.team_id]
	var first := int(c.seasons[0][0]) if not c.seasons.is_empty() else cs.season.season_year
	set_heading("%s 은퇴식" % c.player.name, "프로 %d시즌 · %d–%d · %s" % [c.pro_years, first, cs.season.season_year, cs.rules.position_names.get(c.position, c.position)])
	var bat: BattingLine = _result[0]
	var pitch: PitchingLine = _result[1]
	var met: PackedStringArray = _result[2]
	content.add_child(_hero(c, team, bat, pitch, met))
	var columns := UiKit.hbox(14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var stage := PlayerStage.make(260.0, 460.0)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.show_player(c.player, team)
	columns.add_child(stage)
	_build_career(columns, c, bat, pitch)
	_build_honours(columns, c, cs, met)


## The band: who he was and what his career came to.
func _hero(c: CareerPlayer, team: Team, bat: BattingLine, pitch: PitchingLine, met: PackedStringArray) -> Control:
	var band := UiKit.band(team.primary, 128.0)
	var row := UiKit.hbox(18)
	band.get_child(1).add_child(row)
	row.add_child(UiKit.club_mark(team, 92.0))
	var words := UiKit.vbox(0)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(words)
	words.add_child(UiKit.latin("CAREER GRADE", 16, Color(1, 1, 1, 0.75), true))
	words.add_child(UiKit.heading(c.legacy_grade if c.legacy_grade != "" else "-", 46))
	var marks := UiKit.hbox(8)
	words.add_child(marks)
	marks.add_child(UiKit.badge("결산 보상 +%dP" % c.legacy_reward, Color(1.0, 1.0, 1.0, 0.92)))
	if not met.is_empty():
		marks.add_child(UiKit.badge("명예의 전당", Color(0.62, 0.95, 1.0)))
	if c.number_retired:
		marks.add_child(UiKit.badge("등번호 %d 영구결번" % c.player.number, Color(0.93, 0.33, 0.3), false))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	var big: Array = [["%d" % pitch.wins, "승"], ["%d" % pitch.saves, "세이브"], ["%d" % pitch.strikeouts, "탈삼진"], ["%.2f" % pitch.era() if pitch.outs > 0 else "-", "평균자책점"]] if c.is_pitcher() else \
		[["%d" % bat.hits, "안타"], ["%d" % bat.home_runs, "홈런"], ["%d" % bat.rbi, "타점"], [BattingLine.rate_text(bat.average()), "타율"]]
	for f: Array in big:
		var fig := UiKit.figure(str(f[0]), str(f[1]), Color.WHITE, 40)
		fig.custom_minimum_size.x = 130.0
		row.add_child(fig)
	return band


func _build_career(parent: Control, c: CareerPlayer, bat: BattingLine, pitch: PitchingLine) -> void:
	var p := panel("1군 통산", "chart-bar", parent, 0.0, "CAREER")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	p.body.add_child(grid)
	var figures: Array = [["%d" % pitch.games, "경기"], ["%d" % pitch.starts, "선발"], ["%d" % pitch.losses, "패"], ["%d" % pitch.holds, "홀드"], [pitch.innings_text(), "이닝"], ["%d" % pitch.walks, "볼넷"], ["%.2f" % pitch.whip() if pitch.outs > 0 else "-", "WHIP"], ["%d" % pitch.home_runs, "피홈런"]] if c.is_pitcher() else \
		[["%d" % bat.games, "경기"], ["%d" % bat.pa, "타석"], ["%d" % bat.doubles, "2루타"], ["%d" % bat.triples, "3루타"], ["%d" % bat.stolen_bases, "도루"], ["%d" % bat.walks, "볼넷"], [BattingLine.rate_text(bat.ops()), "OPS"], ["%d" % bat.runs, "득점"]]
	for f: Array in figures:
		var t := UiKit.tile(str(f[0]), str(f[1]), 0.0, 24)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(t)
	p.body.add_child(CenteredPanel.section("시즌별"))
	var table := DataTable.new()
	table.row_height = 30.0
	table.set_columns([["연도", 64.0, 1], ["구단", 150.0, 0], ["1군", 64.0, 2], ["기록", 250.0, 0]])
	for r: Variant in c.seasons:
		var line: Array = r
		table.add_row([str(int(line[0])), str(line[1]), "%d일" % int(line[2]), str(line[3])], str(line[0]))
	table.custom_minimum_size.y = 36.0 + 30.0 * c.seasons.size()
	var scroll := UiKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(table)
	p.body.add_child(scroll)


## His honours as cards, his clubs, his money, the tour's gifts and the hall of fame.
func _build_honours(parent: Control, c: CareerPlayer, cs: CareerSeason, met: PackedStringArray) -> void:
	var p := panel("영광의 기록", "trophy", parent, 620.0, "HONOURS")
	var scroll := UiKit.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.body.add_child(scroll)
	var body := UiKit.vbox(10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	# The trophies: each title with its count and years, the championships in gold, the all-star
	# games, the commemorative balls.
	var cards := GridContainer.new()
	cards.columns = 3
	cards.add_theme_constant_override("h_separation", 8)
	cards.add_theme_constant_override("v_separation", 8)
	body.add_child(cards)
	var by_name := {}
	for t: Variant in c.titles_won:
		var row: Array = t
		if not by_name.has(row[1]):
			by_name[row[1]] = []
		(by_name[row[1]] as Array).append(str(int(row[0])))
	if not c.championships.is_empty():
		cards.add_child(_honour_card("trophy", "한국시리즈 우승", c.championships.size(), " · ".join(PackedStringArray(c.championships.map(func(y: Variant) -> String: return str(int(y))))), UiTheme.GOLD))
	for name: Variant in by_name:
		var years: Array = by_name[name]
		cards.add_child(_honour_card("medal", str(name), years.size(), " · ".join(PackedStringArray(years)), Color(1.0, 0.86, 0.5)))
	cards.add_child(_honour_card("star", "올스타", c.all_stars, "선정", Color(0.62, 0.8, 1.0)))
	cards.add_child(_honour_card("baseball", "기념구", c.milestones.size(), "개", Color(0.95, 0.95, 0.95)))
	# His clubs, each with its emblem and years.
	body.add_child(CenteredPanel.section("거쳐 간 구단"))
	var clubs := HFlowContainer.new()
	clubs.add_theme_constant_override("h_separation", 8)
	clubs.add_theme_constant_override("v_separation", 8)
	body.add_child(clubs)
	for club: Array in CareerLegacy.clubs(c):
		var team: Team = _team_named(cs, str(club[0]))
		var chip := UiKit.well(8.0)
		var line := UiKit.hbox(8)
		chip.add_child(line)
		if team != null:
			line.add_child(UiKit.club_mark(team, 36.0))
		var words := UiKit.vbox(-2)
		words.add_child(UiKit.label(str(club[0]), 16, Color.WHITE, 700))
		words.add_child(UiKit.latin("%d – %d" % [int(club[1]), int(club[2])], 15, UiTheme.DIM))
		line.add_child(words)
		clubs.add_child(chip)
	# His money.
	body.add_child(CenteredPanel.section("계약과 수입"))
	var money := UiKit.hbox(8)
	body.add_child(money)
	var biggest := 0
	for d: Variant in c.deals:
		var text := str((d as Array)[1])
		var at := text.find("총액 ")
		if at >= 0:
			biggest = maxi(biggest, _money_in(text.substr(at + 3)))
	for pair: Array in [[FreeAgency.money(c.earned), "누적 수입"], [FreeAgency.money(maxi(c.best_salary, c.salary)), "최고 연봉"], [FreeAgency.money(biggest) if biggest > 0 else "-", "최대 계약"]]:
		var t := UiKit.tile(str(pair[0]), str(pair[1]), 0.0, 22)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		money.add_child(t)
	# The farewell tour's gifts.
	if not c.tour_gifts.is_empty():
		body.add_child(CenteredPanel.section("은퇴 투어 작별 선물 %d개" % c.tour_gifts.size()))
		var gifts := GridContainer.new()
		gifts.columns = 2
		gifts.add_theme_constant_override("h_separation", 8)
		gifts.add_theme_constant_override("v_separation", 6)
		body.add_child(gifts)
		for g: Variant in c.tour_gifts:
			var gift: Array = g
			var club: Team = cs.season.teams.get(str(gift[0]))
			var chip := UiKit.well(6.0)
			chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var line := UiKit.hbox(8)
			chip.add_child(line)
			if club != null:
				line.add_child(UiKit.club_mark(club, 30.0))
			line.add_child(UiKit.label(str(gift[1]), 15, UiTheme.INK, 600))
			gifts.add_child(chip)
	# The hall of fame, as a banner.
	var hall := UiKit.band(Color(0.2, 0.55, 0.7) if not met.is_empty() else Color(0.3, 0.32, 0.36), 0.0)
	body.add_child(hall)
	var col := UiKit.vbox(4)
	hall.get_child(1).add_child(col)
	col.add_child(UiKit.heading("명예의 전당 헌액" if not met.is_empty() else "명예의 전당 · 기준 미달", 24, Color.WHITE))
	if not met.is_empty():
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 6)
		chips.add_theme_constant_override("v_separation", 6)
		col.add_child(chips)
		for m: String in met:
			chips.add_child(UiKit.badge(m, Color(0.62, 0.95, 1.0)))
	var rule := UiKit.label(HallOfFame.MARKS_TEXT, 13, Color(1, 1, 1, 0.65), 500)
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule.custom_minimum_size.x = 200.0
	col.add_child(rule)
	var foot := UiKit.hbox(10)
	p.body.add_child(foot)
	foot.add_child(UiKit.button("은퇴식 다시 보기", func() -> void: go(CareerSession.FAREWELL, {"title": "은퇴식"}), "play"))
	var close := UiKit.button("커리어 마치기", func() -> void: go(CareerSession.HUB), "check", "primary")
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(close)


## A trophy card: its icon and colour, the honour, how many times, when.
func _honour_card(icon_name: String, name: String, count: int, years: String, colour: Color) -> PanelContainer:
	var well := UiKit.well(10.0)
	well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := UiKit.hbox(10)
	well.add_child(row)
	row.add_child(UiKit.icon(icon_name, 34.0, colour if count > 0 else UiTheme.DIM))
	var words := UiKit.vbox(-2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	var head := UiKit.hbox(6)
	words.add_child(head)
	head.add_child(UiKit.label(name, 16, Color.WHITE, 700))
	head.add_child(UiKit.number("×%d" % count, 22, colour if count > 0 else UiTheme.DIM))
	var when := UiKit.label(years, 13, UiTheme.DIM, 500)
	when.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	when.custom_minimum_size.x = 100.0
	words.add_child(when)
	return well


func _team_named(cs: CareerSeason, name: String) -> Team:
	for id: String in cs.season.teams:
		if (cs.season.teams[id] as Team).name == name:
			return cs.season.teams[id]
	return null


## "96억 원 (…" → 960000 (10,000 won).
static func _money_in(text: String) -> int:
	var eok := 0
	var man := 0
	var head := text.get_slice(" (", 0).replace(",", "").replace(" 원", "")
	if head.contains("억"):
		eok = int(head.get_slice("억", 0))
		head = head.get_slice("억", 1).strip_edges()
	if head.contains("만"):
		man = int(head.get_slice("만", 0))
	return eok * 10000 + man
