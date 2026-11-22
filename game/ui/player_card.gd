class_name PlayerCard
extends Control
## The player card (docs/05 section 5: the same everywhere, docs/13 S9-4; laid out after the
## reference's player detail): the man himself in his uniform on the left; who he is, his
## overall and grade along the top; his shape as a radar chart and the positions he plays on
## a small field; every rating as a bar in its group; his numbers this season. Opened over
## the league and career screens; Esc, the button or a click outside closes it.

var _season: Season
var _player: Player


## Opens a card for a player over a screen.
static func open_for(parent: Node, p: Player, season: Season) -> PlayerCard:
	var card := PlayerCard.new()
	parent.add_child(card)
	card.show_player(p, season)
	return card


func _ready() -> void:
	theme = UiTheme.theme()
	# Over the whole of the screen it opens on (offsets too: anchors alone would leave it the
	# size it had, nothing, at the corner).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _team_of(p: Player) -> Team:
	if _season == null:
		return null
	for id: String in _season.teams:
		var t: Team = _season.teams[id]
		if t.player(p.id) != null:
			return t
	return null


func show_player(p: Player, season: Season) -> void:
	for child: Node in get_children():
		child.queue_free()
	_season = season
	_player = p
	var team := _team_of(p)
	var veil := ColorRect.new()
	veil.color = Color(0.0, 0.01, 0.03, 0.72)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed:
			queue_free())
	add_child(veil)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var accent := team.primary.lightened(0.3) if team != null else UiTheme.ACCENT
	var panel := GlassPanel.make("선수 카드", "identification-card", 1560.0, accent, "PLAYER CARD")
	panel.custom_minimum_size = Vector2(1560.0, 860.0)
	centre.add_child(panel)
	var close := UiKit.button("닫기", queue_free, "x")
	close.tooltip_text = "Esc"
	panel.head.add_child(close)

	var ovr := ClubRules.player_ovr(p, season.ovr, season.catalog) if season != null else 50.0
	var grade := ClubIO.load_default().grade_of(ovr).name
	var columns := UiKit.hbox(26)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.body.add_child(columns)

	# Left: the man.
	var left := UiKit.vbox(6)
	left.custom_minimum_size.x = 380.0
	columns.add_child(left)
	var stage := PlayerStage.make(380.0, 560.0)
	stage.show_player(p, team)
	left.add_child(stage)
	var name_row := UiKit.hbox(12)
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	if team != null:
		name_row.add_child(UiKit.club_mark(team, 46.0))
	name_row.add_child(UiKit.label(p.name, 34, UiTheme.INK, 700))
	name_row.add_child(UiKit.label("#%d" % p.number, 26, accent, 700))
	left.add_child(name_row)
	var tags := UiKit.hbox(6)
	tags.alignment = BoxContainer.ALIGNMENT_CENTER
	var role := ("선발" if p.role() == &"SP" else "구원") if p.is_pitcher() else Position.name_of(p.primary_position())
	tags.add_child(UiKit.badge(role, UiTheme.ACCENT))
	var hands := "%s투%s타" % ["좌" if p.throws == &"L" else "우", {"R": "우", "L": "좌", "S": "양"}[String(p.bats)]]
	tags.add_child(UiKit.badge(hands, Color(1.0, 1.0, 1.0, 0.16), false))
	if p.origin == &"foreign":
		tags.add_child(UiKit.badge("외국인", UiTheme.CYAN))
	elif p.origin == &"asia":
		tags.add_child(UiKit.badge("아시아쿼터", UiTheme.CYAN))
	left.add_child(tags)
	var age := (season.season_year if season != null else 2026) - p.born
	var facts := UiKit.label("%d세 · %dcm %dkg%s" % [age, roundi(p.height_cm), roundi(p.weight_kg), " · 컨디션 %s" % season.condition_name(p.id) if season != null else ""], 17, UiTheme.DIM, 500)
	facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(facts)

	# Middle: overall, the radar, the positions.
	var middle := UiKit.vbox(10)
	middle.custom_minimum_size.x = 400.0
	columns.add_child(middle)
	var top := UiKit.hbox(30)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(UiKit.figure(UiTheme.shown_text(ovr), "종합", UiTheme.rating_color(ovr), 64))
	top.add_child(UiKit.figure(grade, "등급", UiTheme.ACCENT, 64))
	middle.add_child(top)
	var radar: RadarChart
	if p.is_pitcher():
		var catalog := season.catalog if season != null else PitchCatalogIO.load_default()
		radar = RadarChart.make(PackedStringArray(["구위", "제구", "체력", "위기관리", "변화구"]),
			PackedFloat32Array([p.pitching.stuff(catalog), p.pitching.control, p.pitching.stamina, p.pitching.composure, p.pitching.breaking(catalog)]), 330.0)
	else:
		radar = RadarChart.make(PackedStringArray(["컨택트", "파워", "선구안", "주력", "수비"]),
			PackedFloat32Array([p.batting.contact(), p.batting.power(), p.batting.eye, (p.batting.speed + p.batting.baserunning) * 0.5, p.fielding.overall()]), 330.0)
	radar.colour = accent
	radar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	middle.add_child(radar)
	middle.add_child(UiKit.caption("포지션 숙련도"))
	var field := FieldDiagram.new()
	field.custom_minimum_size = Vector2(380.0, 270.0)
	for kind: Position.Kind in Position.FIELD:
		var fit := p.aptitude(kind)
		if fit >= 0.5 and (kind != Position.Kind.P or p.is_pitcher()):
			field.marks[kind] = "%d" % roundi(fit * 100.0)
			field.strong[kind] = kind == p.primary_position() or (p.is_pitcher() and kind == Position.Kind.P)
	middle.add_child(field)

	# Right: every rating, and the season.
	var right := UiKit.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	if p.is_pitcher():
		_group(right, "투구 능력", "person-simple-throw")
		right.add_child(StatBar.make("제구", p.pitching.control))
		right.add_child(StatBar.make("체력", p.pitching.stamina))
		right.add_child(StatBar.make("위기관리", p.pitching.composure))
		right.add_child(StatBar.make("견제", p.pitching.hold))
		_group(right, "구종", "baseball")
		for a: ArsenalPitch in p.pitching.arsenal:
			var t: PitchType = season.catalog.get(a.type) if season != null else null
			right.add_child(StatBar.make("%s %dkm/h" % [t.label if t != null else String(a.type), roundi(a.velo_avg)], (a.movement + a.command) * 0.5, -1.0, 210.0))
	else:
		_group(right, "타격 능력 (우투 상대 / 좌투 상대)", "baseball-helmet")
		right.add_child(StatBar.make("컨택트", p.batting.contact_r, p.batting.contact_l))
		right.add_child(StatBar.make("파워", p.batting.power_r, p.batting.power_l))
		right.add_child(StatBar.make("선구안", p.batting.eye))
		right.add_child(StatBar.make("번트", p.batting.bunt))
		right.add_child(StatBar.make("득점권", p.batting.clutch))
		_group(right, "주루 능력", "sneaker-move")
		# One running rating: speed with base-running sense (as the person raises it).
		right.add_child(StatBar.make("주력", (p.batting.speed + p.batting.baserunning) * 0.5))
		_group(right, "수비 능력", "shield")
		right.add_child(StatBar.make("수비 범위", p.fielding.range))
		right.add_child(StatBar.make("포구", p.fielding.hands))
		right.add_child(StatBar.make("송구 파워", p.fielding.arm))
		right.add_child(StatBar.make("송구 정확도", p.fielding.accuracy))
	if season != null:
		_group(right, "%d 시즌" % season.season_year, "chart-bar")
		var b: BattingLine = season.book.batting.get(p.id)
		if b != null and b.pa > 0:
			var r := UiKit.hbox(26)
			for pair: Array in [[BattingLine.rate_text(b.average()), "타율"], ["%d" % b.games, "경기"], ["%d" % b.home_runs, "홈런"], ["%d" % b.rbi, "타점"], [BattingLine.rate_text(b.ops()), "OPS"]]:
				r.add_child(UiKit.figure(str(pair[0]), str(pair[1]), UiTheme.INK, 28))
			right.add_child(r)
		var l: PitchingLine = season.book.pitching.get(p.id)
		if l != null and l.outs > 0:
			var r := UiKit.hbox(26)
			for pair: Array in [["%.2f" % l.era(), "평균자책점"], ["%d" % l.games, "경기"], [l.innings_text(), "이닝"], ["%d-%d" % [l.wins, l.losses], "승-패"], ["%d" % l.saves, "세이브"], ["%d" % l.strikeouts, "탈삼진"]]:
				r.add_child(UiKit.figure(str(pair[0]), str(pair[1]), UiTheme.INK, 28))
			right.add_child(r)
		if (b == null or b.pa == 0) and (l == null or l.outs == 0):
			right.add_child(UiKit.label("아직 기록이 없습니다.", 17, UiTheme.DIM, 500))


func _group(parent: Control, title: String, icon_name: String) -> void:
	parent.add_child(UiKit.spacer(0.0, 4.0))
	var r := UiKit.hbox(8)
	r.add_child(UiKit.icon(icon_name, 20.0, UiTheme.ACCENT))
	r.add_child(UiKit.label(title, 17, UiTheme.ACCENT, 700))
	parent.add_child(r)
	parent.add_child(UiKit.rule())


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
