class_name CreationScreen
extends Control
## Making the career player (docs/02 section 6.1, docs/13 S8-1): name and number, batting and
## throwing hands, body and looks, position and type, then the club and the season length.
##
##   ./dev play res://career/creation_screen.tscn

var spec := PlayerCreator.Spec.new()
var team_id := ""
var games := 36
var rules: CareerRules
var _content: VBoxContainer
var _clubs: Array[Team] = []


func _ready() -> void:
	theme = UiTheme.theme()
	rules = CareerIO.load_default()
	_clubs = RosterIO.load_pack(LeagueSession.PACK)
	spec.type_id = rules.batter_types[0].id
	spec.body_id = rules.bodies[1].id
	spec.skin = rules.skins[1]
	spec.hair = rules.hairs[0]
	spec.beard = rules.beards[0]
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_content = VBoxContainer.new()
	_content.position = Vector2(48.0, 32.0)
	_content.add_theme_constant_override("separation", 8)
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
	_label("커리어 · 선수 만들기", 30, UiTheme.GOLD)
	var name_row := HBoxContainer.new()
	_content.add_child(name_row)
	var name_edit := LineEdit.new()
	name_edit.text = spec.name
	name_edit.custom_minimum_size = Vector2(260.0, 0.0)
	name_edit.text_changed.connect(func(t: String) -> void: spec.name = t)
	name_row.add_child(_small("이름"))
	name_row.add_child(name_edit)
	var number := SpinBox.new()
	number.min_value = 0
	number.max_value = 99
	number.value = spec.number
	number.value_changed.connect(func(v: float) -> void: spec.number = int(v))
	name_row.add_child(_small("  등번호"))
	name_row.add_child(number)
	_choices("타격", ["R", "L", "S"], ["우타", "좌타", "양타"], String(spec.bats), func(v: String) -> void: spec.bats = StringName(v))
	_choices("투구", ["R", "L"], ["우투", "좌투"], String(spec.throws), func(v: String) -> void: spec.throws = StringName(v))
	var body_ids: Array[String] = []
	var body_names: Array[String] = []
	for b: CareerRules.Body in rules.bodies:
		body_ids.append(b.id)
		body_names.append("%s (%dcm·%dkg)" % [b.name, roundi(b.height), roundi(b.weight)])
	_choices("체형", body_ids, body_names, spec.body_id, func(v: String) -> void: spec.body_id = v)
	_choices("피부", Array(rules.skins), Array(rules.skins), spec.skin, func(v: String) -> void: spec.skin = v)
	_choices("머리", Array(rules.hairs), Array(rules.hairs), spec.hair, func(v: String) -> void: spec.hair = v)
	_choices("수염", Array(rules.beards), Array(rules.beards), spec.beard, func(v: String) -> void: spec.beard = v)
	var names: Array[String] = []
	for p: String in rules.positions:
		names.append(rules.position_names.get(p, p))
	_choices("포지션", Array(rules.positions), names, spec.position, func(v: String) -> void:
		var was_pitcher := CareerRules.is_pitching_position(spec.position)
		spec.position = v
		if was_pitcher != CareerRules.is_pitching_position(v):
			spec.type_id = rules.types_for(v)[0].id)
	var type_ids: Array[String] = []
	var type_names: Array[String] = []
	for t: CareerRules.PlayerType in rules.types_for(spec.position):
		type_ids.append(t.id)
		var strong := ", ".join(Array(t.strengths).map(func(k: String) -> String: return _rating_name(k)))
		type_names.append("%s%s" % [t.name, " (%s)" % strong if strong != "" else ""])
	_choices("유형", type_ids, type_names, spec.type_id, func(v: String) -> void: spec.type_id = v)
	var club_ids: Array[String] = []
	var club_names: Array[String] = []
	for i: int in _clubs.size():
		club_ids.append(_clubs[i].id)
		club_names.append("%d부 %s" % [i / 10 + 1, _clubs[i].short_name])
	_label("구단", 20, UiTheme.GOLD)
	var grid := GridContainer.new()
	grid.columns = 6
	_content.add_child(grid)
	for i: int in club_ids.size():
		var b := Button.new()
		b.text = ("● " if team_id == club_ids[i] else "") + club_names[i]
		b.add_theme_font_size_override("font_size", 16)
		var id := club_ids[i]
		b.pressed.connect(func() -> void:
			team_id = id
			refresh())
		grid.add_child(b)
	_choices("시즌", ["36", "72", "144"], ["36경기", "72경기", "144경기"], str(games), func(v: String) -> void: games = int(v))
	var preview := PlayerCreator.create(spec, rules, PitchCatalogIO.load_default())
	_label(_preview_text(preview), 17, UiTheme.DIM)
	var start := Button.new()
	start.text = "커리어 시작 (2군에서 출발)"
	start.disabled = team_id == "" or spec.name.strip_edges() == ""
	start.pressed.connect(begin)
	_content.add_child(start)


## Starts the career with the choices made (also used by tests).
func begin() -> void:
	var c := PlayerCreator.create(spec, rules, PitchCatalogIO.load_default())
	CareerSession.start(c, team_id, games, int(Time.get_unix_time_from_system()) % 100000)
	if is_inside_tree() and not Engine.is_editor_hint():
		get_tree().change_scene_to_file(CareerSession.HUB)


func _preview_text(c: CareerPlayer) -> String:
	var p := c.player
	if p.is_pitcher():
		var pitches := PackedStringArray()
		for a: ArsenalPitch in p.pitching.arsenal:
			pitches.append("%s %d" % [String(a.type), roundi(a.velo_avg)])
		return "시작 능력치 · 제구 %d · 구위 %d · 체력 %d · %s" % [roundi(p.pitching.control), roundi(p.pitching.arsenal[0].movement), roundi(p.pitching.stamina), ", ".join(pitches)]
	return "시작 능력치 · 컨택 %d · 파워 %d · 선구안 %d · 주력 %d · 수비 %d · 어깨 %d" % [roundi(p.batting.contact()), roundi(p.batting.power()), roundi(p.batting.eye), roundi(p.batting.speed), roundi(p.fielding.range), roundi(p.fielding.arm)]


static func _rating_name(key: String) -> String:
	var names := {"contact": "컨택", "power": "파워", "eye": "선구안", "speed": "주력", "baserunning": "주루", "range": "수비 범위", "hands": "포구", "arm": "송구", "velocity": "구속", "stuff": "구위", "control": "제구", "command": "로케이션", "movement": "변화", "stamina": "체력"}
	return str(names.get(key, key))


func _choices(title: String, ids: Array, labels: Array, current: String, pick: Callable) -> void:
	var row := HBoxContainer.new()
	_content.add_child(row)
	row.add_child(_small(title))
	for i: int in ids.size():
		var b := Button.new()
		b.text = ("● " if str(ids[i]) == current else "") + str(labels[i])
		b.add_theme_font_size_override("font_size", 16)
		var id := str(ids[i])
		b.pressed.connect(func() -> void:
			pick.call(id)
			refresh())
		row.add_child(b)


func _label(line: String, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = line
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	_content.add_child(l)


func _small(line: String) -> Label:
	var l := Label.new()
	l.text = line
	l.custom_minimum_size = Vector2(80.0, 0.0)
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", UiTheme.DIM)
	return l
