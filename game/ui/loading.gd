class_name Loading
extends CanvasLayer
## What is on screen while one part of the game gives way to another (docs/05 section 5).
## Into and out of a game (the park and the players take a moment to build): a full screen —
## the two clubs with their emblems for a game, or where it is going — with a tip and a bar.
## Between menus: a quick slanted wipe in the menus' colours.
##
##   Loading.go(get_tree(), "res://match/match.tscn", {"away": team_a, "home": team_b, "line": "등대 파크 · 야간"})
##
## Without a display (tests) the scene just changes.

const TIPS: Array[String] = [
	"배트 커서의 안쪽 원에 공을 맞히면 정타가 됩니다.",
	"던지기 전에 보이는 궤적의 화살표가 변화구의 꺾임입니다.",
	"우클릭은 파워 스윙: 장타가 늘지만 헛스윙도 늘어납니다.",
	"불리한 볼카운트에서는 스트라이크 존을 넓게 보세요.",
	"투심과 체인지업은 회전이 아니라 실밥이 공을 밀어냅니다.",
	"투수의 구종 숙련도가 높을수록 제구 원이 작아집니다.",
	"주자가 있을 때 Shift로 도루를 지시할 수 있습니다.",
	"리그 모드에서 컨디션이 나쁜 선수는 쉬게 하는 편이 좋습니다.",
	"좌타자는 우투수에게, 우타자는 좌투수에게 강합니다.",
	"경기를 마치면 포인트와 경험치를 받습니다.",
]
const MIN_SECONDS := 1.1

static var _instance: Loading

var _target := ""
var _info: Dictionary = {}
var _veil: Control
var _stage := 0
var _clock := 0.0
var _frames := 0
var _progress := 0.0
var _wipe := false
var _tip := ""


## Changes scene behind a loading screen (a game) or a wipe (a menu).
static func go(tree: SceneTree, path: String, info: Dictionary = {}) -> void:
	if path == "" or tree == null:
		return
	if DisplayServer.get_name() == "headless":
		tree.change_scene_to_file(path)
		return
	if _instance != null and is_instance_valid(_instance):
		return
	_instance = Loading.new()
	_instance._target = path
	_instance._info = info
	_instance._wipe = is_menu(path) and not info.has("full") and tree.current_scene != null and tree.current_scene.is_in_group(&"menu")
	tree.root.add_child(_instance)


## Menus change with a wipe; anything else (a game) behind the full screen.
static func is_menu(path: String) -> bool:
	return path.begins_with("res://ui/") or path.ends_with("league_screen.tscn") or path.ends_with("career_screen.tscn") or path.ends_with("creation_screen.tscn")


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tip = TIPS[randi() % TIPS.size()]
	_veil = Control.new()
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_veil.draw.connect(_draw_wipe if _wipe else _draw_full)
	add_child(_veil)


func _process(delta: float) -> void:
	_clock += delta
	_frames += 1
	var cover := 0.16 if _wipe else 0.25
	match _stage:
		0:
			# Coming over the old scene.
			_progress = minf(_clock / cover, 1.0)
			if _progress >= 1.0 and _frames > 3:
				_stage = 1
				_frames = 0
		1:
			# Covered, and drawn at least once: change now (this is where it stops a moment).
			if _frames >= 2:
				get_tree().paused = false
				get_tree().change_scene_to_file(_target)
				_stage = 2
				_clock = 0.0
				_frames = 0
		2:
			# The new scene is in; hold a moment (so the screen can be read), then leave.
			var held := 0.05 if _wipe else MIN_SECONDS
			if _frames > 4 and _clock >= held:
				_stage = 3
				_clock = 0.0
		3:
			_progress = 1.0 - minf(_clock / (cover * 1.3), 1.0)
			if _progress <= 0.0:
				_instance = null
				queue_free()
				return
	_veil.queue_redraw()


func _k() -> float:
	return UiTheme.scale_for(_veil.size.y)


## Two slanted bands sweeping across: blue, then the accent at its leading edge.
func _draw_wipe() -> void:
	var s := _veil.size
	var lean := s.y * 0.25
	var t := ease(_progress, -1.8)
	var cover := (s.x + lean * 2.0) * t
	var left := -lean if _stage < 3 else (s.x + lean) - cover
	var right := left + cover
	_veil.draw_colored_polygon(PackedVector2Array([Vector2(left + lean, 0.0), Vector2(right + lean, 0.0), Vector2(right - lean, s.y), Vector2(left - lean, s.y)]), Color(0.05, 0.055, 0.07))
	var edge := right if _stage < 3 else left
	_veil.draw_colored_polygon(PackedVector2Array([Vector2(edge + lean - 26.0, 0.0), Vector2(edge + lean + 26.0, 0.0), Vector2(edge - lean + 26.0, s.y), Vector2(edge - lean - 26.0, s.y)]), UiTheme.BRAND)


func _draw_full() -> void:
	var s := _veil.size
	var k := _k()
	var a := _progress
	var away: Team = _info.get("away")
	var home: Team = _info.get("home")
	_veil.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.033, 0.042, a))
	if a < 0.02:
		return
	# Two fields of colour meeting on a slant: the clubs' own for a game, the menus' blue otherwise.
	var left_colour := (away.primary.darkened(0.35) if away != null else Color(0.1, 0.105, 0.125))
	var right_colour := (home.primary.darkened(0.35) if home != null else Color(0.055, 0.06, 0.075))
	var mid := s.x * 0.5
	var lean := s.y * 0.18
	_veil.draw_colored_polygon(PackedVector2Array([Vector2(0.0, 0.0), Vector2(mid + lean, 0.0), Vector2(mid - lean, s.y), Vector2(0.0, s.y)]), Color(left_colour.r, left_colour.g, left_colour.b, a))
	_veil.draw_colored_polygon(PackedVector2Array([Vector2(mid + lean, 0.0), Vector2(s.x, 0.0), Vector2(s.x, s.y), Vector2(mid - lean, s.y)]), Color(right_colour.r, right_colour.g, right_colour.b, a))
	# Fine slanted stripes over both, and a dark band top and bottom.
	var x := -s.y
	while x < s.x:
		_veil.draw_line(Vector2(x, s.y), Vector2(x + s.y * 0.6, 0.0), Color(1.0, 1.0, 1.0, 0.025 * a), 14.0 * k)
		x += 58.0 * k
	_veil.draw_rect(Rect2(0.0, 0.0, s.x, 110.0 * k), Color(0.0, 0.0, 0.0, 0.6 * a))
	_veil.draw_rect(Rect2(0.0, s.y - 190.0 * k, s.x, 190.0 * k), Color(0.0, 0.0, 0.0, 0.72 * a))
	_veil.draw_colored_polygon(PackedVector2Array([Vector2(mid + lean - 5.0 * k, 0.0), Vector2(mid + lean + 5.0 * k, 0.0), Vector2(mid - lean + 5.0 * k, s.y), Vector2(mid - lean - 5.0 * k, s.y)]), Color(1.0, 1.0, 1.0, 0.85 * a))
	var bold := UiTheme.display(700)
	var num := UiTheme.numeric(true)
	var white := Color(1.0, 1.0, 1.0, a)
	var heading := str(_info.get("title", "경기 준비 중" if away != null else "불러오는 중"))
	_text(bold, Vector2(60.0 * k, 72.0 * k), heading, 38.0 * k, white)
	if _info.has("line"):
		var line := str(_info["line"])
		var w := bold.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(24.0 * k)).x
		_text(bold, Vector2(s.x - w - 60.0 * k, 68.0 * k), line, 24.0 * k, Color(0.85, 0.92, 1.0, a))
	if away != null and home != null:
		var side := 300.0 * k
		var cy := s.y * 0.44
		for pair: Array in [[away, s.x * 0.25, "AWAY"], [home, s.x * 0.75, "HOME"]]:
			var team: Team = pair[0]
			var cx := float(pair[1])
			Emblem.draw_emblem(_veil, team, Rect2(cx - side * 0.5, cy - side * 0.5, side, side))
			var w := bold.get_string_size(team.name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(52.0 * k)).x
			_text(bold, Vector2(cx - w * 0.5, cy + side * 0.5 + 76.0 * k), team.name, 52.0 * k, white)
			var tag := str(pair[2])
			var tw := num.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(30.0 * k)).x
			_veil.draw_string(num, Vector2(cx - tw * 0.5, cy - side * 0.5 - 26.0 * k), tag, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(30.0 * k), Color(1.0, 0.85, 0.4, a))
		var vs := "VS"
		var vw := num.get_string_size(vs, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(150.0 * k)).x
		_veil.draw_string_outline(num, Vector2(mid - vw * 0.5, cy + 52.0 * k), vs, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(150.0 * k), int(16.0 * k), Color(0.0, 0.03, 0.12, a))
		_veil.draw_string(num, Vector2(mid - vw * 0.5, cy + 52.0 * k), vs, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(150.0 * k), Color(1.0, 1.0, 1.0, a))
	else:
		var ball := UiTheme.icon("baseball")
		if ball != null:
			var side := 240.0 * k
			_veil.draw_set_transform(Vector2(mid, s.y * 0.44), _clock * 1.2, Vector2.ONE)
			_veil.draw_texture_rect(ball, Rect2(-side * 0.5, -side * 0.5, side, side), false, Color(1.0, 1.0, 1.0, 0.9 * a))
			_veil.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The tip, and the bar.
	var y := s.y - 130.0 * k
	var tag_points := PackedVector2Array([Vector2(60.0 * k, y - 30.0 * k), Vector2(146.0 * k, y - 30.0 * k), Vector2(136.0 * k, y + 8.0 * k), Vector2(50.0 * k, y + 8.0 * k)])
	_veil.draw_colored_polygon(tag_points, Color(UiTheme.BRAND.r, UiTheme.BRAND.g, UiTheme.BRAND.b, a))
	_veil.draw_string(num, Vector2(74.0 * k, y), "TIP", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(30.0 * k), Color(1.0, 1.0, 1.0, a))
	_veil.draw_string(UiTheme.font(600), Vector2(166.0 * k, y - 2.0 * k), _tip, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(26.0 * k), white)
	var bar := Rect2(60.0 * k, s.y - 78.0 * k, s.x - 120.0 * k, 12.0 * k)
	_veil.draw_rect(bar, Color(1.0, 1.0, 1.0, 0.14 * a))
	var filled := [0.3, 0.42, 0.42 + 0.58 * minf(_clock / MIN_SECONDS, 1.0), 1.0][_stage] as float
	_veil.draw_rect(Rect2(bar.position, Vector2(bar.size.x * filled, bar.size.y)), Color(UiTheme.BRAND.r, UiTheme.BRAND.g, UiTheme.BRAND.b, a))
	var word := "LOADING" + ".".repeat(1 + int(_clock * 3.0) % 3) if _stage < 3 else "READY"
	_veil.draw_string(num, Vector2(60.0 * k, s.y - 34.0 * k), word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(26.0 * k), Color(0.85, 0.92, 1.0, a))


func _text(font: Font, at: Vector2, text: String, px: float, colour: Color) -> void:
	_veil.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(px), maxi(int(px / 6.0), 2), Color(0.0, 0.03, 0.12, colour.a * 0.8))
	_veil.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(px), colour)
