class_name CareerScreen
extends Control
## The career's screen between games (docs/02 section 6, docs/13 S8-3, S8-5): the player's
## card (place, ratings, growth points, popularity, his numbers on both teams), today's game
## (played on screen with only his scenes, or at once), the last game's report, growth (spend
## each field's points on its ratings), and his division's table.
##
##   ./dev play res://career/creation_screen.tscn   (then 커리어 시작)

const RATING_NAMES := {
	"contact": "컨택", "power": "파워", "eye": "선구안", "speed": "주력", "baserunning": "주루",
	"range": "수비 범위", "hands": "포구", "arm": "송구", "accuracy": "송구 정확도",
	"control": "제구", "stamina": "체력", "velocity": "구속", "movement": "구위·변화", "command": "로케이션",
}
const FIELD_NAMES := {"batting": "타격", "fielding": "수비", "running": "주루", "pitching": "투구"}

var message := ""
var _content: HBoxContainer


func _ready() -> void:
	theme = UiTheme.theme()
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_content = HBoxContainer.new()
	_content.position = Vector2(32.0, 28.0)
	_content.add_theme_constant_override("separation", 28)
	add_child(_content)
	get_viewport().size_changed.connect(_fit)
	_fit()
	refresh()


func _fit() -> void:
	var screen := get_viewport().get_visible_rect().size
	var k := UiTheme.scale_for(screen.y)
	scale = Vector2(k, k)
	size = screen / k


func refresh() -> void:
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	if is_inside_tree():
		CareerSession.autosave()
	var cs := CareerSession.career_season
	if cs == null:
		var col := _column(800.0)
		_line(col, "진행 중인 커리어가 없다.", UiTheme.DIM)
		_button(col, "선수 만들기", func() -> void: get_tree().change_scene_to_file(CareerSession.CREATE))
		return
	_build_card(_column(600.0), cs)
	_build_growth(_column(560.0), cs)
	_build_table(_column(560.0), cs)


func _build_card(col: VBoxContainer, cs: CareerSeason) -> void:
	var c := cs.career
	var p := c.player
	var s := cs.season
	var team: Team = s.teams[c.team_id]
	var type := cs.rules.type_by_id(c.type_id)
	_title(col, "%s  #%d" % [p.name, p.number])
	_line(col, "%s · %s · %s %s" % [cs.rules.position_names.get(c.position, c.position), type.name if type != null else "", team.name, "1군" if c.first_team else "2군"], UiTheme.GOLD)
	var phase: String = ["정규 시즌", "포스트시즌", "시즌 종료"][s.phase]
	var avg := 0.0
	for x: float in c.ratings:
		avg += x
	avg = avg / c.ratings.size() if not c.ratings.is_empty() else 0.0
	_line(col, "%d년 %s · %d일째 · 인기도 %d · 포인트 %d%s" % [s.season_year, phase, s.day + 1, roundi(c.popularity), c.points, ("  · 평균 평점 %.1f" % avg) if avg > 0.0 else ""], UiTheme.INK)
	var gp := PackedStringArray()
	for field: String in CareerPlayer.FIELDS:
		gp.append("%s %d" % [FIELD_NAMES[field], roundi(float(c.gp.get(field, 0.0)))])
	_line(col, "성장 포인트 · " + " · ".join(gp), UiTheme.INK, 18)
	var first := _lines(s.book, p.id)
	var futures := _lines(cs.futures_book, p.id)
	_line(col, "1군: " + first, UiTheme.DIM, 17)
	_line(col, "2군: " + futures, UiTheme.DIM, 17)
	if cs.all_star_today:
		_line(col, "올스타전에 뽑혔다!", UiTheme.GOLD)
		_button(col, "올스타전 하기 (내 장면만)", func() -> void:
			cs.special = "all_star"
			get_tree().change_scene_to_file(CareerSession.MATCH))
		_button(col, "올스타전 빠른 진행", func() -> void:
			CareerSession.last_report = cs.quick_all_star()
			refresh())
	if cs.derby_waiting:
		_line(col, "홈런 더비에 나간다 (아웃 %d개까지)" % int(cs.rules.all_star.get("derby_outs", 10)), UiTheme.GOLD)
		_button(col, "홈런 더비 직접 치기", func() -> void: get_tree().change_scene_to_file(CareerSession.DERBY))
		_button(col, "홈런 더비 빠른 결과", func() -> void:
			cs.quick_derby()
			refresh())
	if cs.has_game():
		var g := cs.club_game()
		var other: Team = s.teams[g.opponent_of(c.team_id)]
		_line(col, "오늘: %s vs %s (%s)" % ["1군" if c.first_team else "2군", other.name, "홈" if g.home == c.team_id else "원정"], UiTheme.INK)
		_button(col, "경기하기 (내 장면만)", play_on_screen)
		_button(col, "빠른 진행", quick)
	elif s.phase != Season.Phase.OVER:
		_line(col, "오늘은 경기가 없다." if cs.club_game() == null or not c.first_team else "오늘 경기는 끝났다.", UiTheme.DIM)
		_button(col, "다음 날", next_day)
	if s.phase != Season.Phase.OVER:
		_button(col, "시즌 끝까지 빠른 진행", to_end)
	else:
		_line(col, "시즌이 끝났다.", UiTheme.GOLD)
	_button(col, "능력치 보기", func() -> void: PlayerCard.open_for(self, c.player, s))
	_button(col, "허브로", func() -> void: get_tree().change_scene_to_file(Screen.HUB))
	var r := CareerSession.last_report
	if r != null:
		var earned := PackedStringArray()
		for field: String in r.gp:
			if r.gp[field] > 0.0:
				earned.append("%s +%d" % [FIELD_NAMES[field], roundi(r.gp[field])])
		_line(col, "지난 경기: %s · 목표 %s %s" % [r.line, r.goal, "달성" if r.goal_met else "실패"], UiTheme.INK, 17)
		if r.rating > 0.0:
			var medal := GameRating.MEDALS[r.medal]
			_line(col, "평점 %.1f%s%s" % [r.rating, ("  %s메달" % medal) if medal != "" else "", ("  · 보상 " + r.reward) if r.reward != "" else ""], UiTheme.GOLD if r.medal > 0 else UiTheme.INK, 18)
		_line(col, "얻은 성장 포인트: " + (", ".join(earned) if not earned.is_empty() else "없음"), UiTheme.INK, 17)
		if r.called_up:
			_line(col, "1군에 등록됐다!", UiTheme.GOLD)
		if r.sent_down:
			_line(col, "2군으로 내려갔다.", UiTheme.RED)
		for change: String in r.evolved:
			_line(col, "구종 진화: " + change, UiTheme.GOLD)
	if message != "":
		_line(col, message, UiTheme.GOLD, 17)
	for entry: String in cs.log:
		_line(col, entry, UiTheme.DIM, 15)


func _lines(book: StatBook, id: String) -> String:
	var parts := PackedStringArray()
	var b: BattingLine = book.batting.get(id)
	if b != null and b.pa > 0:
		parts.append("%d경기 타율 %s %d홈런 %d타점 OPS %s" % [b.games, BattingLine.rate_text(b.average()), b.home_runs, b.rbi, BattingLine.rate_text(b.ops())])
	var p: PitchingLine = book.pitching.get(id)
	if p != null and p.outs > 0:
		parts.append("%d경기 %s이닝 %d승 %d패 %d세이브 평균자책점 %.2f" % [p.games, p.innings_text(), p.wins, p.losses, p.saves, p.era()])
	return " / ".join(parts) if not parts.is_empty() else "기록 없음"


func _build_growth(col: VBoxContainer, cs: CareerSeason) -> void:
	var c := cs.career
	_title(col, "성장")
	_line(col, "분야의 포인트는 그 분야 능력치에만 쓴다. 높을수록 비싸고, 유형의 강점은 20% 싸다.", UiTheme.DIM, 15)
	var fields: Array[String] = []
	if c.is_pitcher():
		fields.append("pitching")
	else:
		fields.append_array(["batting", "running", "fielding"])
	for field: String in fields:
		_line(col, "%s · %d포인트" % [FIELD_NAMES[field], roundi(float(c.gp.get(field, 0.0)))], UiTheme.GOLD, 18)
		var ratings: PackedStringArray = cs.rules.ratings[field] if cs.rules.ratings.has(field) else PackedStringArray()
		for rating: String in ratings:
			var row := HBoxContainer.new()
			col.add_child(row)
			var value := Growth.value(c.player, rating)
			var shown := "%.1fkm/h" % c.player.pitching.fastball_speed() if rating == "velocity" else str(roundi(value))
			_cell(row, str(RATING_NAMES.get(rating, rating)), 130.0)
			_cell(row, shown, 90.0)
			var price := Growth.cost(c, rating, cs.rules)
			_cell(row, "다음 %d" % ceili(price), 90.0)
			var b := Button.new()
			b.text = "+"
			b.disabled = float(c.gp.get(field, 0.0)) < price
			b.pressed.connect(func() -> void:
				Growth.raise(c, rating, cs.rules)
				refresh())
			row.add_child(b)
	if c.is_pitcher():
		_build_pitches(col, cs)


## A pitcher's pitches, how often he has thrown each (they evolve with use), and new ones to
## learn with pitching points.
func _build_pitches(col: VBoxContainer, cs: CareerSeason) -> void:
	var c := cs.career
	var catalog := cs.season.catalog
	_line(col, "구종 (많이 던지고 능력치가 오르면 진화)", UiTheme.GOLD, 18)
	for a: ArsenalPitch in c.player.pitching.arsenal:
		var t: PitchType = catalog.get(a.type)
		_line(col, "%s %dkm/h · 변화 %d · 로케이션 %d · %d구" % [t.label if t != null else String(a.type), roundi(a.velo_avg), roundi(a.movement), roundi(a.command), int(c.pitch_uses.get(a.type, 0))], UiTheme.INK, 16)
	for id: StringName in PitchEvolution.learnable(c, cs.rules):
		var t: PitchType = catalog.get(id)
		var b := Button.new()
		b.text = "새 구종: %s (투구 %d포인트)" % [t.label if t != null else String(id), roundi(cs.rules.new_pitch_gp)]
		b.disabled = float(c.gp.get("pitching", 0.0)) < cs.rules.new_pitch_gp
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func() -> void:
			PitchEvolution.learn(c, id, cs.rules, catalog)
			refresh())
		col.add_child(b)


func _build_table(col: VBoxContainer, cs: CareerSeason) -> void:
	var s := cs.season
	var d := s.division_of(cs.career.team_id)
	_title(col, "%d부 순위" % (d + 1))
	var i := 0
	for row: StandingsRow in s.standings[d].ranked():
		i += 1
		var mine := row.team_id == cs.career.team_id
		_line(col, "%d  %s  %d승 %d패 %d무  %s" % [i, s.teams[row.team_id].name, row.wins, row.losses, row.ties, row.pct_text()], UiTheme.GOLD if mine else UiTheme.INK, 17)


# --- Actions ---


func play_on_screen() -> void:
	get_tree().change_scene_to_file(CareerSession.MATCH)


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
	message = "시즌이 끝났다."
	refresh()


# --- Building blocks ---


func _column(width: float) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(width, 0.0)
	col.add_theme_constant_override("separation", 6)
	_content.add_child(col)
	return col


func _title(col: VBoxContainer, line: String) -> void:
	var l := Label.new()
	l.text = line
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", UiTheme.GOLD)
	col.add_child(l)


func _line(col: Control, line: String, color: Color, font_size: int = 20) -> void:
	var l := Label.new()
	l.text = line
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	col.add_child(l)


func _cell(row: HBoxContainer, line: String, width: float) -> void:
	var l := Label.new()
	l.text = line
	l.custom_minimum_size = Vector2(width, 0.0)
	l.add_theme_font_size_override("font_size", 17)
	row.add_child(l)


func _button(col: VBoxContainer, label: String, action: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(action)
	col.add_child(b)
