class_name PlayerCompare
extends Control
## Two players side by side (docs/08 R5; the reference's line-up screen compares the man in
## the line-up with the one picked on a radar): each man in his uniform at a side with his
## overall, their shapes laid over each other on one radar in the middle, and under it every
## rating and this season's numbers in three columns — his, the name, the other's — the better
## of each pair lit. Batters with batters, pitchers with pitchers. Esc, the button or a click
## outside closes it.

## The two sides' colours: the first man (the one pinned) and the one he is compared with.
const FIRST := Color(1.0, 0.76, 0.24)
const SECOND := Color(0.45, 0.82, 1.0)

var _season: Season


static func open_for(parent: Node, a: Player, b: Player, season: Season) -> PlayerCompare:
	var view := PlayerCompare.new()
	parent.add_child(view)
	view.show_players(a, b, season)
	return view


## Whether two players can be compared (both pitchers or both batters).
static func comparable(a: Player, b: Player) -> bool:
	return a != null and b != null and a.id != b.id and a.is_pitcher() == b.is_pitcher()


## The radar's spokes for a player: names and values.
static func shape(p: Player, catalog: Dictionary) -> Array:
	if p.is_pitcher():
		return [PackedStringArray(["구위", "제구", "체력", "평정", "변화구"]),
			PackedFloat32Array([p.pitching.stuff(catalog), p.pitching.control, p.pitching.stamina, p.pitching.composure, p.pitching.breaking(catalog)])]
	return [PackedStringArray(["컨택트", "파워", "선구안", "주루", "수비"]),
		PackedFloat32Array([p.batting.contact(), p.batting.power(), p.batting.eye, (p.batting.speed + p.batting.baserunning) * 0.5, p.fielding.overall()])]


## Every rating the two are compared on: [name, his, the other's].
static func ratings(a: Player, b: Player, catalog: Dictionary) -> Array:
	var rows: Array = []
	if a.is_pitcher():
		for pair: Array in [["구위", func(p: Player) -> float: return p.pitching.stuff(catalog)],
				["제구", func(p: Player) -> float: return p.pitching.control],
				["체력", func(p: Player) -> float: return p.pitching.stamina],
				["평정", func(p: Player) -> float: return p.pitching.composure],
				["변화구", func(p: Player) -> float: return p.pitching.breaking(catalog)],
				["견제", func(p: Player) -> float: return p.pitching.hold]]:
			rows.append([pair[0], (pair[1] as Callable).call(a), (pair[1] as Callable).call(b)])
		return rows
	for pair: Array in [["컨택트 (우투)", func(p: Player) -> float: return p.batting.contact_r],
			["컨택트 (좌투)", func(p: Player) -> float: return p.batting.contact_l],
			["파워 (우투)", func(p: Player) -> float: return p.batting.power_r],
			["파워 (좌투)", func(p: Player) -> float: return p.batting.power_l],
			["선구안", func(p: Player) -> float: return p.batting.eye],
			["주력", func(p: Player) -> float: return p.batting.speed],
			["주루", func(p: Player) -> float: return p.batting.baserunning],
			["수비", func(p: Player) -> float: return p.fielding.overall()],
			["송구", func(p: Player) -> float: return p.fielding.arm]]:
		rows.append([pair[0], (pair[1] as Callable).call(a), (pair[1] as Callable).call(b)])
	return rows


## This season's numbers: [name, his text, the other's text, which is better (-1 his, 1 the
## other's, 0 even or none)].
static func season_rows(a: Player, b: Player, season: Season) -> Array:
	var rows: Array = []
	if season == null:
		return rows
	if a.is_pitcher():
		var la: PitchingLine = season.book.pitching.get(a.id, PitchingLine.new())
		var lb: PitchingLine = season.book.pitching.get(b.id, PitchingLine.new())
		var some := la.outs > 0 and lb.outs > 0
		rows.append(["평균자책점", "%.2f" % la.era() if la.outs > 0 else "-", "%.2f" % lb.era() if lb.outs > 0 else "-", _better(lb.era(), la.era()) if some else 0])
		rows.append(["이닝", la.innings_text(), lb.innings_text(), _better(la.outs, lb.outs)])
		rows.append(["승-패", "%d-%d" % [la.wins, la.losses], "%d-%d" % [lb.wins, lb.losses], _better(la.wins, lb.wins)])
		rows.append(["세이브", str(la.saves), str(lb.saves), _better(la.saves, lb.saves)])
		rows.append(["탈삼진", str(la.strikeouts), str(lb.strikeouts), _better(la.strikeouts, lb.strikeouts)])
		return rows
	var ba: BattingLine = season.book.batting.get(a.id, BattingLine.new())
	var bb: BattingLine = season.book.batting.get(b.id, BattingLine.new())
	var both := ba.ab > 0 and bb.ab > 0
	rows.append(["타율", BattingLine.rate_text(ba.average()) if ba.ab > 0 else "-", BattingLine.rate_text(bb.average()) if bb.ab > 0 else "-", _better(ba.average(), bb.average()) if both else 0])
	rows.append(["홈런", str(ba.home_runs), str(bb.home_runs), _better(ba.home_runs, bb.home_runs)])
	rows.append(["타점", str(ba.rbi), str(bb.rbi), _better(ba.rbi, bb.rbi)])
	rows.append(["OPS", BattingLine.rate_text(ba.ops()) if ba.pa > 0 else "-", BattingLine.rate_text(bb.ops()) if bb.pa > 0 else "-", _better(ba.ops(), bb.ops()) if ba.pa > 0 and bb.pa > 0 else 0])
	rows.append(["도루", str(ba.stolen_bases), str(bb.stolen_bases), _better(ba.stolen_bases, bb.stolen_bases)])
	return rows


## -1 when the first is larger, 1 when the second is, 0 when even.
static func _better(first: float, second: float) -> int:
	if is_equal_approx(first, second):
		return 0
	return -1 if first > second else 1


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_players(a: Player, b: Player, season: Season) -> void:
	for child: Node in get_children():
		child.queue_free()
	_season = season
	var catalog := season.catalog if season != null else PitchCatalogIO.load_default()
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
	var panel := GlassPanel.make("선수 비교", "chart-polar", 1500.0, FIRST, "COMPARE")
	panel.custom_minimum_size = Vector2(1500.0, 840.0)
	centre.add_child(panel)
	var close := UiKit.button("닫기", queue_free, "x")
	close.tooltip_text = "Esc"
	panel.head.add_child(close)
	var columns := UiKit.hbox(24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.body.add_child(columns)
	columns.add_child(_side(a, FIRST, season))
	var middle := UiKit.vbox(8)
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(middle)
	var spokes := shape(a, catalog)
	var radar := RadarChart.make(spokes[0], spokes[1], 300.0)
	radar.compare = shape(b, catalog)[1]
	radar.colour = FIRST
	radar.compare_colour = SECOND
	radar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	middle.add_child(radar)
	# Under the radar, the ratings and the season side by side.
	var lists := UiKit.hbox(20)
	middle.add_child(lists)
	var left := UiKit.vbox(2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_child(left)
	left.add_child(_heading_row("능력치", "sliders-horizontal"))
	for row: Array in ratings(a, b, catalog):
		var va := float(row[1])
		var vb := float(row[2])
		left.add_child(_line(str(roundi(va)), str(row[0]), str(roundi(vb)), _better(roundi(va), roundi(vb))))
	if season != null:
		var right := UiKit.vbox(2)
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lists.add_child(right)
		right.add_child(_heading_row("%d 시즌" % season.season_year, "chart-bar"))
		for row: Array in season_rows(a, b, season):
			right.add_child(_line(str(row[1]), str(row[0]), str(row[2]), int(row[3])))
	columns.add_child(_side(b, SECOND, season))


func _team_of(p: Player) -> Team:
	if _season == null:
		return null
	for id: String in _season.teams:
		var t: Team = _season.teams[id]
		if t.player(p.id) != null:
			return t
	return null


## One man: his picture, his club, his name and number, what he plays, his overall.
func _side(p: Player, colour: Color, season: Season) -> VBoxContainer:
	var team := _team_of(p)
	var side := UiKit.vbox(6)
	side.custom_minimum_size.x = 360.0
	var stage := PlayerStage.make(360.0, 480.0)
	stage.show_player(p, team)
	side.add_child(stage)
	var name_row := UiKit.hbox(10)
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	if team != null:
		name_row.add_child(UiKit.club_mark(team, 40.0))
	name_row.add_child(UiKit.label(p.name, 30, UiTheme.INK, 700))
	name_row.add_child(UiKit.label("#%d" % p.number, 22, colour, 700))
	side.add_child(name_row)
	var role := ("선발 투수" if p.role() == &"SP" else "구원 투수") if p.is_pitcher() else Position.name_of(p.primary_position())
	var facts := UiKit.label("%s · %d세" % [role, (season.season_year if season != null else 2026) - p.born], 17, UiTheme.DIM, 500)
	facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(facts)
	if season != null:
		var ovr := ClubRules.player_ovr(p, season.ovr, season.catalog)
		var figures := UiKit.hbox(20)
		figures.alignment = BoxContainer.ALIGNMENT_CENTER
		figures.add_child(UiKit.figure("%d" % roundi(ovr), "OVR", colour, 48))
		figures.add_child(UiKit.figure(season.club_rules.grade_of(ovr).name, "등급", UiTheme.INK, 48))
		side.add_child(figures)
	# A line in his colour under him, as on the radar.
	var mark := ColorRect.new()
	mark.color = colour
	mark.custom_minimum_size = Vector2(0.0, 4.0)
	side.add_child(mark)
	return side


func _heading_row(title: String, icon_name: String) -> HBoxContainer:
	var r := UiKit.hbox(8)
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_child(UiKit.icon(icon_name, 20.0, UiTheme.ACCENT))
	r.add_child(UiKit.label(title, 17, UiTheme.ACCENT, 700))
	return r


## His figure, the name, the other's: the better one in his colour and heavier.
func _line(left: String, name: String, right: String, better: int) -> HBoxContainer:
	var row := UiKit.hbox(0)
	var a := UiKit.latin(left, 22, FIRST if better < 0 else UiTheme.INK, false)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	a.custom_minimum_size.x = 70.0
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(a)
	var n := UiKit.label(name, 15, UiTheme.DIM, 500)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.custom_minimum_size.x = 130.0
	row.add_child(n)
	var b := UiKit.latin(right, 22, SECOND if better > 0 else UiTheme.INK, false)
	b.custom_minimum_size.x = 70.0
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(b)
	return row


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
