class_name CreationScreen
extends Screen
## Making the career's player (docs/02 section 6.1, docs/13 S8-1): the player stands on the
## left as he is being made, with his starting ratings as a chart; in the middle who he is
## (name, number, hands, build, looks) and what he plays (position, type); on the right where
## he starts (docs/08 R8-3): a third-year student at a high school of his choice (its weekend
## league, then the draft decides his club), or at once in a club's second team; and the length
## of his pro seasons.

var spec := PlayerCreator.Spec.new()
var team_id := ""
## "school" (high school, then the draft) or "pro" (a club's second team at once).
var start_kind := "school"
var school_id := ""
var region := ""
var games := 36
var rules: CareerRules
var _clubs: Array[Team] = []
var _start: GameButton


func setup() -> void:
	heading = "선수 생성"
	heading_latin = "CREATE PLAYER"
	vantage = &"field"
	dock_id = "career"


func _ready() -> void:
	rules = CareerIO.load_default()
	_clubs = LeagueSession.league_clubs()
	var all := SchoolLeague.schools()
	if not all.is_empty():
		region = str((all[0] as Dictionary)["league"])
	spec.type_id = rules.batter_types[0].id
	spec.body_id = rules.bodies[1].id
	spec.skin = rules.skins[1]
	spec.hair = rules.hairs[0]
	spec.beard = rules.beards[0]
	super._ready()


func build() -> void:
	var preview := PlayerCreator.create(spec, rules, PitchCatalogIO.load_default())
	var team: Team = null
	for t: Team in _clubs:
		if t.id == team_id:
			team = t
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	# The player as he is being made.
	var left := UiKit.vbox(4)
	left.custom_minimum_size.x = 420.0
	columns.add_child(left)
	var stage := PlayerStage.make(420.0, 430.0)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.show_player(preview.player, team)
	left.add_child(stage)
	var p := preview.player
	var radar: RadarChart
	if p.is_pitcher():
		var catalog := PitchCatalogIO.load_default()
		radar = RadarChart.make(PackedStringArray(["구위", "제구", "체력", "위기관리", "변화구"]), PackedFloat32Array([p.pitching.stuff(catalog), p.pitching.control, p.pitching.stamina, p.pitching.composure, p.pitching.breaking(catalog)]), 300.0)
	else:
		radar = RadarChart.make(PackedStringArray(["컨택트", "파워", "선구안", "주력", "수비"]), PackedFloat32Array([p.batting.contact(), p.batting.power(), p.batting.eye, (p.batting.speed + p.batting.baserunning) * 0.5, p.fielding.overall()]), 300.0)
	radar.colour = tint
	radar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(radar)

	var who := panel("기본 정보", "identification-card", columns, 0.0, "PROFILE")
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_row := UiKit.hbox(12)
	who.body.add_child(name_row)
	var name_label := UiKit.label("이름", 18, UiTheme.DIM, 600)
	name_label.custom_minimum_size.x = 200.0
	name_row.add_child(name_label)
	var name_edit := LineEdit.new()
	name_edit.text = spec.name
	name_edit.placeholder_text = "선수 이름"
	name_edit.custom_minimum_size = Vector2(260.0, 0.0)
	name_edit.text_changed.connect(func(t: String) -> void:
		spec.name = t
		_update_start())
	name_row.add_child(name_edit)
	var number_label := UiKit.label("등번호", 18, UiTheme.DIM, 600)
	name_row.add_child(number_label)
	var number := SpinBox.new()
	number.min_value = 0
	number.max_value = 99
	number.value = spec.number
	number.value_changed.connect(func(v: float) -> void: spec.number = int(v))
	name_row.add_child(number)
	choices("타석", ["R", "L", "S"], ["우타", "좌타", "양타"], String(spec.bats), func(v: String) -> void: spec.bats = StringName(v), who.body)
	choices("투구", ["R", "L"], ["우투", "좌투"], String(spec.throws), func(v: String) -> void: spec.throws = StringName(v), who.body)
	var body_ids: Array = []
	var body_names: Array = []
	for b: CareerRules.Body in rules.bodies:
		body_ids.append(b.id)
		body_names.append("%s %dcm·%dkg" % [b.name, roundi(b.height), roundi(b.weight)])
	choices("체형", body_ids, body_names, spec.body_id, func(v: String) -> void: spec.body_id = v, who.body)
	choices("피부", Array(rules.skins), Array(rules.skins), spec.skin, func(v: String) -> void: spec.skin = v, who.body)
	choices("헤어", Array(rules.hairs), Array(rules.hairs), spec.hair, func(v: String) -> void: spec.hair = v, who.body)
	choices("수염", Array(rules.beards), Array(rules.beards), spec.beard, func(v: String) -> void: spec.beard = v, who.body)
	who.body.add_child(UiKit.rule())
	var names: Array = []
	for position: String in rules.positions:
		names.append(rules.position_names.get(position, position))
	choices("포지션", Array(rules.positions), names, spec.position, func(v: String) -> void:
		var was_pitcher := CareerRules.is_pitching_position(spec.position)
		spec.position = v
		if was_pitcher != CareerRules.is_pitching_position(v):
			spec.type_id = rules.types_for(v)[0].id, who.body)
	var type_ids: Array = []
	var type_names: Array = []
	var strengths := ""
	for t: CareerRules.PlayerType in rules.types_for(spec.position):
		type_ids.append(t.id)
		type_names.append(t.name)
		if t.id == spec.type_id:
			strengths = ", ".join(Array(t.strengths).map(func(k: String) -> String: return _rating_name(k)))
	choices("유형", type_ids, type_names, spec.type_id, func(v: String) -> void: spec.type_id = v, who.body)
	if strengths != "":
		who.body.add_child(UiKit.label("강점: %s (성장 비용 20%% 할인)" % strengths, 16, UiTheme.DIM, 500))

	var where := panel("출발", "graduation-cap", columns, 540.0, "START")
	choices("시작", ["school", "pro"], ["고교 3학년", "바로 프로 입단"], start_kind, func(v: String) -> void: start_kind = v, where.body)
	if start_kind == "school":
		where.body.add_child(UiKit.label("고교리그(주말리그와 왕중왕전)를 뛰고 신인 드래프트에서 지명한 구단에 입단합니다. 구단은 고를 수 없습니다.", 15, UiTheme.DIM, 500))
		var regions: Array = SchoolLeague.data().get("leagues", [])
		choices("권역", regions, regions, region, func(v: String) -> void:
			region = v
			school_id = "", where.body)
		var schools := DataTable.new()
		schools.row_height = 34.0
		schools.set_columns([["학교", 300.0, 0], ["권역", 160.0, 1]])
		for e: Dictionary in SchoolLeague.schools():
			if str(e["league"]) != region:
				continue
			var at := schools.add_row([str(e["name"]), str(e["league"])], str(e["id"]))
			if str(e["id"]) == school_id:
				schools.selected = at
		schools.row_pressed.connect(func(_row: int, tag: Variant) -> void:
			school_id = str(tag)
			refresh())
		where.body.add_child(schools)
	else:
		where.body.add_child(UiKit.label("드래프트 없이 고른 구단의 2군(퓨처스리그)에서 시작합니다.", 15, UiTheme.DIM, 500))
		var table := DataTable.new()
		table.row_height = 36.0
		table.set_columns([["구단", 380.0, 0]])
		for i: int in _clubs.size():
			var at := table.add_row([_clubs[i].name], _clubs[i].id)
			if _clubs[i].id == team_id:
				table.selected = at
		table.row_pressed.connect(func(_row: int, tag: Variant) -> void:
			team_id = str(tag)
			refresh())
		where.body.add_child(table)
	choices("프로 시즌 길이", ["36", "72", "144"], ["36경기", "72경기", "144경기"], str(games), func(v: String) -> void: games = int(v), where.body)
	_start = UiKit.button("커리어 시작", begin, "play", "primary")
	_start.add_theme_font_size_override("font_size", 26)
	where.body.add_child(_start)
	_update_start()


func _update_start() -> void:
	if _start != null and is_instance_valid(_start):
		var where := school_id if start_kind == "school" else team_id
		_start.disabled = where == "" or spec.name.strip_edges() == ""
		_start.tooltip_text = ("이름을 입력하고 학교를 선택하세요" if start_kind == "school" else "이름을 입력하고 구단을 선택하세요") if _start.disabled else ""


## Starts the career with the choices made (also used by tests).
func begin() -> void:
	var c := PlayerCreator.create(spec, rules, PitchCatalogIO.load_default())
	var seed_value := int(Time.get_unix_time_from_system()) % 100000
	if start_kind == "school":
		CareerSession.start_school(c, school_id, games, seed_value)
	else:
		CareerSession.start(c, team_id, games, seed_value)
		CareerSession.career_season.pro_games = games
	if is_inside_tree() and not Engine.is_editor_hint():
		go(CareerSession.HUB)


static func _rating_name(key: String) -> String:
	var names := {"contact": "컨택트", "power": "파워", "eye": "선구안", "speed": "주력", "baserunning": "주력", "range": "수비 범위", "hands": "포구", "arm": "송구 파워", "velocity": "구속", "stuff": "구위", "control": "제구", "command": "제구", "movement": "구위", "stamina": "체력"}
	return str(names.get(key, key))
