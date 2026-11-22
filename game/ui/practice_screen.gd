class_name PracticeScreen
extends Screen
## The practice field (docs/02; docs/13 S9): batting practice against a pitcher throwing what
## is asked for, pitching practice with the path of each pitch shown, or watching the two
## computers. The park and the hour are chosen here; the field itself is match/duel.tscn.

const FIELD := "res://match/duel.tscn"
## What the pitcher throws in batting practice: every pitch, or one family.
const MIXES := {
	"all": [],
	"fast": [&"four_seam", &"two_seam", &"cutter"],
	"breaking": [&"slider", &"curve", &"sweeper"],
	"offspeed": [&"changeup", &"splitter"],
}

static var mode := "bat"
static var mix := "all"
static var park := ""
static var time := "day"
static var pitcher_left := false
static var batter_left := false
## Set when the field is opened from here; the field reads the choices once.
static var pending := false


func setup() -> void:
	heading = "연습 모드"
	heading_latin = "PRACTICE"
	heading_icon = "target"
	vantage = &"mound"
	dock_id = "practice"


func build() -> void:
	# The three ways to practise across the top, as the hub's tiles.
	var modes := UiKit.hbox(16)
	modes.custom_minimum_size.y = 240.0
	content.add_child(modes)
	for m: Array in [["bat", "타격 연습", "", "baseball-helmet", Color(1.0, 0.45, 0.38), "BATTING", "practice"],
			["pitch", "투구 연습", "", "person-simple-throw", Color(0.4, 0.8, 1.0), "PITCHING", "career"],
			["watch", "관전", "", "eye", Color(0.7, 0.78, 0.9), "WATCH", "park"]]:
		var id := str(m[0])
		var tile := ModeTile.make(str(m[1]), str(m[2]), str(m[3]), func() -> void:
			mode = id
			refresh(), m[4], str(m[5]), str(m[6]))
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if mode == id:
			tile.status = "선택"
		modes.add_child(tile)
	var columns := UiKit.hbox(16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var p := panel("연습 설정", "sliders-horizontal", columns, 0.0, "SETUP")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Settings as selectors (◀ value ▶), as the exhibition screen, two to a row.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	p.body.add_child(grid)
	var picks: Array[Control] = []
	var levels: Array = []
	for level_id: String in Difficulty.IDS:
		levels.append(level_id)
	picks.append(UiKit.selector("난이도", levels, Difficulty.NAMES, Settings.difficulty, func(v: String) -> void:
		Settings.difficulty = v
		Settings.save_file()
		refresh()))
	if mode == "bat":
		picks.append(UiKit.selector("상대 구종", ["all", "fast", "breaking", "offspeed"], ["전체", "패스트볼", "브레이킹볼", "오프스피드"], mix, func(v: String) -> void:
			mix = v
			refresh()))
	picks.append(UiKit.selector("투수", ["0", "1"], ["우투", "좌투"], "1" if pitcher_left else "0", func(v: String) -> void:
		pitcher_left = v == "1"
		refresh()))
	picks.append(UiKit.selector("타자", ["0", "1"], ["우타", "좌타"], "1" if batter_left else "0", func(v: String) -> void:
		batter_left = v == "1"
		refresh()))
	var park_ids: Array = [""]
	var park_names: Array = ["연습 구장"]
	for id: String in StadiumIO.ids():
		park_ids.append(id)
		park_names.append(StadiumIO.load_park(id).name)
	picks.append(UiKit.selector("구장", park_ids, park_names, park, func(v: String) -> void:
		park = v
		refresh()))
	picks.append(UiKit.selector("시간", ["day", "dusk", "night"], ["주간", "석양", "야간"], time, func(v: String) -> void:
		time = v
		refresh()))
	for pick: Control in picks:
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(pick)
	p.body.add_child(UiKit.spacer(0.0, 0.0, true))
	var start_button := UiKit.button("연습 시작", start, "play", "primary")
	start_button.add_theme_font_size_override("font_size", 26)
	p.body.add_child(start_button)
	_build_record(columns)


## The person's practice record (Profile.practice): his swings and his pitches, and his bests.
func _build_record(parent: Control) -> void:
	var r := Profile.practice
	var p := panel("연습 기록", "chart-bar", parent, 620.0, "RECORD")
	var swings := float(r.get("swings", 0.0))
	var pitches := float(r.get("pitches", 0.0))
	var rows: Array = [
		["타격", [["%d" % roundi(swings), "스윙"], ["%d%%" % roundi(100.0 * float(r.get("perfect", 0.0)) / swings) if swings > 0.0 else "-", "퍼펙트 타이밍"],
			["%d" % roundi(float(r.get("best_exit", 0.0))) if r.has("best_exit") else "-", "최고 타구 속도 km/h"], ["%d" % roundi(float(r.get("longest", 0.0))) if r.has("longest") else "-", "최장 비거리 m"]]],
		["투구", [["%d" % roundi(pitches), "투구"], ["%d%%" % roundi(100.0 * float(r.get("strikes", 0.0)) / pitches) if pitches > 0.0 else "-", "스트라이크"],
			["%.1f" % float(r.get("best_miss", 0.0)) if r.has("best_miss") else "-", "최소 오차 cm"], ["%d" % roundi(float(r.get("home_runs", 0.0))), "연습 홈런"]]],
	]
	for row: Array in rows:
		p.body.add_child(UiKit.caption(str(row[0])))
		var line := UiKit.hbox(8)
		p.body.add_child(line)
		for pair: Array in row[1]:
			var t := UiKit.tile(str(pair[0]), str(pair[1]), 0.0, 30)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(t)


func start() -> void:
	pending = true
	go(FIELD, {"title": "연습 모드", "line": {"bat": "타격 연습", "pitch": "투구 연습", "watch": "관전"}[mode]})


## The pitch types the practice pitcher is limited to (empty: all of them).
static func pitch_pool() -> Array:
	return MIXES.get(mix, [])
