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
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var modes := UiKit.vbox(16)
	modes.custom_minimum_size.x = 560.0
	columns.add_child(modes)
	for m: Array in [["bat", "타격 연습", "", "baseball-helmet", Color(1.0, 0.45, 0.38), "BATTING", "practice"],
			["pitch", "투구 연습", "", "person-simple-throw", Color(0.4, 0.8, 1.0), "PITCHING", "career"],
			["watch", "관전", "", "eye", Color(0.7, 0.78, 0.9), "WATCH", "park"]]:
		var id := str(m[0])
		var tile := ModeTile.make(str(m[1]), str(m[2]), str(m[3]), func() -> void:
			mode = id
			refresh(), m[4], str(m[5]), str(m[6]))
		tile.custom_minimum_size = Vector2(560.0, 170.0)
		tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if mode == id:
			tile.status = "선택"
		modes.add_child(tile)
	var p := panel("연습 설정", "sliders-horizontal", columns, 0.0, "SETUP")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Settings as selectors (◀ value ▶), as the exhibition screen.
	if mode == "bat":
		p.body.add_child(UiKit.selector("상대 구종", ["all", "fast", "breaking", "offspeed"], ["전체", "패스트볼", "브레이킹볼", "오프스피드"], mix, func(v: String) -> void:
			mix = v
			refresh()))
	p.body.add_child(UiKit.selector("투수", ["0", "1"], ["우투", "좌투"], "1" if pitcher_left else "0", func(v: String) -> void:
		pitcher_left = v == "1"
		refresh()))
	p.body.add_child(UiKit.selector("타자", ["0", "1"], ["우타", "좌타"], "1" if batter_left else "0", func(v: String) -> void:
		batter_left = v == "1"
		refresh()))
	var park_ids: Array = [""]
	var park_names: Array = ["연습 구장"]
	for id: String in StadiumIO.ids():
		park_ids.append(id)
		park_names.append(StadiumIO.load_park(id).name)
	p.body.add_child(UiKit.selector("구장", park_ids, park_names, park, func(v: String) -> void:
		park = v
		refresh()))
	p.body.add_child(UiKit.selector("시간", ["day", "dusk", "night"], ["주간", "석양", "야간"], time, func(v: String) -> void:
		time = v
		refresh()))
	p.body.add_child(UiKit.spacer(0.0, 0.0, true))
	var start_button := UiKit.button("연습 시작", start, "play", "primary")
	start_button.add_theme_font_size_override("font_size", 26)
	p.body.add_child(start_button)


func start() -> void:
	pending = true
	go(FIELD, {"title": "연습 모드", "line": {"bat": "타격 연습", "pitch": "투구 연습", "watch": "관전"}[mode]})


## The pitch types the practice pitcher is limited to (empty: all of them).
static func pitch_pool() -> Array:
	return MIXES.get(mix, [])
