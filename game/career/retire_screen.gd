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
	return [sum[0], sum[1], met, 0]


func build() -> void:
	var c := CareerSession.career
	var cs := CareerSession.career_season
	if c == null or cs == null or _result.is_empty():
		var p := panel("은퇴식", "user-circle", null, 0.0, "RETIREMENT")
		p.body.add_child(UiKit.label("은퇴할 수 있는 커리어가 없습니다(시즌이 끝난 겨울에 할 수 있습니다).", 20, UiTheme.DIM, 500))
		return
	var team: Team = cs.season.teams[c.team_id]
	set_heading("%s 은퇴식" % c.player.name, "프로 %d시즌 · %s" % [c.pro_years, team.name])
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var stage := PlayerStage.make(420.0, 560.0)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.show_player(c.player, team)
	columns.add_child(stage)
	var bat: BattingLine = _result[0]
	var pitch: PitchingLine = _result[1]
	var met: PackedStringArray = _result[2]
	var career := panel("통산 기록", "chart-bar", columns, 0.0, "CAREER")
	career.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tiles := UiKit.hbox(8)
	career.body.add_child(tiles)
	var figures: Array = [["%d" % pitch.wins, "승"], ["%d" % pitch.losses, "패"], ["%d" % pitch.saves, "세이브"], ["%.2f" % pitch.era() if pitch.outs > 0 else "-", "평균자책점"], ["%d" % pitch.strikeouts, "탈삼진"]] if c.is_pitcher() else \
		[["%d" % bat.games, "경기"], ["%d" % bat.hits, "안타"], ["%d" % bat.home_runs, "홈런"], ["%d" % bat.rbi, "타점"], [BattingLine.rate_text(bat.average()), "타율"], [BattingLine.rate_text(bat.ops()), "OPS"]]
	for f: Array in figures:
		var t := UiKit.tile(str(f[0]), str(f[1]), 0.0, 30)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tiles.add_child(t)
	career.body.add_child(UiKit.caption("시즌별"))
	for row: Variant in c.seasons:
		var r: Array = row
		career.body.add_child(UiKit.label("%d · %s · %s" % [int(r[0]), str(r[1]), str(r[3])], 16, UiTheme.INK, 500))
	var hall := panel("명예의 전당", "trophy", columns, 460.0, "HALL OF FAME")
	if met.is_empty():
		hall.body.add_child(UiKit.heading("헌액 기준에 미치지 못했습니다", 22, UiTheme.DIM))
	else:
		hall.body.add_child(UiKit.heading("명예의 전당 헌액!", 30, UiTheme.ACCENT))
		for m: String in met:
			hall.body.add_child(UiKit.label("· %s" % m, 18, UiTheme.INK, 600))
	hall.body.add_child(UiKit.rule())
	hall.body.add_child(UiKit.caption("헌액 기준"))
	hall.body.add_child(UiKit.label(HallOfFame.MARKS_TEXT, 15, UiTheme.DIM, 500))
	hall.body.add_child(UiKit.spacer(0.0, 0.0, true))
	hall.body.add_child(UiKit.button("커리어 마치기", func() -> void: go(CareerSession.HUB), "check", "primary", 320.0))
