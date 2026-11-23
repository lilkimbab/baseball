class_name Loading
extends CanvasLayer
## What is on screen while one part of the game gives way to another (docs/04 section 5), as a
## released sports game has it (the user, 2026-11-23: "loading and title screens that look made
## by a game company"):
##
## - Into a game: the match-up card of a broadcast — the two clubs' colours meeting on a slant,
##   their emblems large and faint behind, each club's emblem, name and record, "VS", the park
##   and the hour at the top. It stays until the line-ups' faces are drawn (PortraitStudio), so
##   the pre-game introduction that follows runs without a stop; the game holds its show
##   meanwhile (`covering`).
## - Anywhere else (the league, the career, the lobby): the place's own picture under a dark
##   wash, where it is going in large letters.
## - Both: a tip, a turning ball and "LOADING" with its share, a thin bar along the foot.
## - Between menus: a quick slanted wipe in the menus' colours.
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
	"바람이 외야로 불면 뜬공이 더 멀리 날아갑니다.",
	"몸을 덜 푼 구원 투수는 처음 몇 구의 제구가 흔들립니다.",
	"경기 전 라인업 소개는 Space로 건너뛸 수 있습니다.",
	"Tab을 누르고 있으면 타자와 투수의 능력치를 볼 수 있습니다.",
]
## The least a full loading screen stays (s), and the most it waits for the faces.
const MIN_SECONDS := 1.4
const MAX_WAIT := 10.0
## The picture behind each place that is not a game.
const ART := {"league_screen": "res://ui/art/league.jpg", "career_screen": "res://ui/art/career.jpg", "creation_screen": "res://ui/art/career.jpg",
	"practice": "res://ui/art/practice.jpg", "shop": "res://ui/art/shop.jpg", "quick": "res://ui/art/exhibition.jpg"}
const ART_DEFAULT := "res://ui/art/park.jpg"

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
var _art: Texture2D
## Faces the game asked for when it came in, and the most there were to wait for.
var _faces_most := 0
var _share := 0.0


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


## A full loading screen is up over the new scene (a game holds its pre-game show till it goes).
static func covering() -> bool:
	return _instance != null and is_instance_valid(_instance) and not _instance._wipe and _instance._stage < 3


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tip = TIPS[randi() % TIPS.size()]
	if not _wipe and not _info.has("away"):
		var path := ART_DEFAULT
		for key: String in ART:
			if _target.contains(key):
				path = ART[key]
		if ResourceLoader.exists(path):
			_art = load(path) as Texture2D
	_veil = Control.new()
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_veil.draw.connect(_draw_wipe if _wipe else _draw_full)
	add_child(_veil)


func _process(delta: float) -> void:
	_clock += delta
	_frames += 1
	var cover := 0.16 if _wipe else 0.28
	match _stage:
		0:
			# Coming over the old scene.
			_progress = minf(_clock / cover, 1.0)
			_share = 0.12 * _progress
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
				_share = 0.3
		2:
			# The new scene is in. A menu: away at once. A game: the faces of its line-ups are
			# drawn behind this screen first (not more than MAX_WAIT), the screen read meanwhile.
			var left := 0 if _wipe else PortraitStudio.pending()
			_faces_most = maxi(_faces_most, left)
			var faces_done := 1.0 if _faces_most == 0 else 1.0 - float(left) / _faces_most
			_share = 0.3 + 0.7 * minf(minf(_clock / MIN_SECONDS, 1.0), faces_done)
			var held := 0.05 if _wipe else MIN_SECONDS
			if _frames > 4 and _clock >= held and (left == 0 or _clock >= MAX_WAIT):
				_stage = 3
				_clock = 0.0
				_share = 1.0
		3:
			_progress = 1.0 - minf(_clock / (cover * 1.4), 1.0)
			if _progress <= 0.0:
				_instance = null
				queue_free()
				return
	_veil.queue_redraw()


func _k() -> float:
	return UiTheme.scale_for(_veil.size.y)


## Two slanted bands sweeping across: graphite, then the brand red at its leading edge.
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
	var a := ease(_progress, 0.6)
	_veil.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.024, 0.032, a))
	if a < 0.02:
		return
	var away: Team = _info.get("away")
	var home: Team = _info.get("home")
	if away != null and home != null:
		_draw_match(s, k, a, away, home)
	else:
		_draw_place(s, k, a)
	_draw_foot(s, k, a)


## The broadcast's match-up card.
func _draw_match(s: Vector2, k: float, a: float, away: Team, home: Team) -> void:
	var mid := s.x * 0.5
	var lean := s.y * 0.16
	# Each side in its club's colour, bright at the outer edge and deep toward the middle.
	for side: int in 2:
		var team := away if side == 0 else home
		var base := HudCanvas.club_colour(team)
		var outer := Color(base.darkened(0.25), a)
		var inner := Color(base.darkened(0.72), a)
		var shape := PackedVector2Array([Vector2(0.0, 0.0), Vector2(mid + lean, 0.0), Vector2(mid - lean, s.y), Vector2(0.0, s.y)]) if side == 0 \
			else PackedVector2Array([Vector2(mid + lean, 0.0), Vector2(s.x, 0.0), Vector2(s.x, s.y), Vector2(mid - lean, s.y)])
		var colours := PackedColorArray([outer, inner, inner, outer]) if side == 0 else PackedColorArray([inner, outer, outer, inner])
		_veil.draw_polygon(shape, colours)
		# Its emblem huge and faint, running off the edge.
		var big := 980.0 * k
		var at := Vector2(-big * 0.34, s.y * 0.5 - big * 0.5) if side == 0 else Vector2(s.x - big * 0.66, s.y * 0.5 - big * 0.5)
		Emblem.draw_emblem(_veil, team, Rect2(at, Vector2(big, big)))
		_veil.draw_colored_polygon(shape, Color(inner.r, inner.g, inner.b, 0.86 * a))
	# Light through the stands: fine slanted stripes, a vignette top and foot.
	var x := -s.y
	while x < s.x:
		_veil.draw_line(Vector2(x, s.y), Vector2(x + s.y * 0.5, 0.0), Color(1.0, 1.0, 1.0, 0.022 * a), 10.0 * k)
		x += 46.0 * k
	_gradient_band(Rect2(0.0, 0.0, s.x, 220.0 * k), Color(0.0, 0.0, 0.0, 0.7 * a), Color(0.0, 0.0, 0.0, 0.0))
	# The seam between the clubs: a white line with a red glow.
	for w: float in [26.0, 12.0]:
		_veil.draw_colored_polygon(PackedVector2Array([Vector2(mid + lean - w * k, 0.0), Vector2(mid + lean + w * k, 0.0), Vector2(mid - lean + w * k, s.y), Vector2(mid - lean - w * k, s.y)]), Color(UiTheme.BRAND, (0.25 if w > 20.0 else 0.6) * a))
	_veil.draw_colored_polygon(PackedVector2Array([Vector2(mid + lean - 3.0 * k, 0.0), Vector2(mid + lean + 3.0 * k, 0.0), Vector2(mid - lean + 3.0 * k, s.y), Vector2(mid - lean - 3.0 * k, s.y)]), Color(1.0, 1.0, 1.0, 0.92 * a))
	_head(s, k, a, str(_info.get("title", "경기 준비 중")))
	# The clubs.
	var bold := UiTheme.display(800)
	var num := UiTheme.numeric(true)
	var cy := s.y * 0.43
	for side: int in 2:
		var team := away if side == 0 else home
		var cx := s.x * (0.25 if side == 0 else 0.75)
		var emblem := 290.0 * k
		# A soft dark disc under the emblem, so any colour reads.
		_veil.draw_circle(Vector2(cx, cy), emblem * 0.62, Color(0.0, 0.0, 0.0, 0.25 * a))
		Emblem.draw_emblem(_veil, team, Rect2(cx - emblem * 0.5, cy - emblem * 0.5, emblem, emblem))
		var tag := "AWAY" if side == 0 else "HOME"
		_centred(num, Vector2(cx, cy - emblem * 0.5 - 34.0 * k), tag, 30.0 * k, Color(1.0, 0.84, 0.36, a))
		_centred(bold, Vector2(cx, cy + emblem * 0.5 + 84.0 * k), team.name, 58.0 * k, Color(1.0, 1.0, 1.0, a), true)
		var record := str(_info.get("record%d" % side, ""))
		if record != "":
			_centred(UiTheme.font(600), Vector2(cx, cy + emblem * 0.5 + 128.0 * k), record, 26.0 * k, Color(1.0, 1.0, 1.0, 0.75 * a))
	# "VS" in the shouting face, on a dark disc with a red ring.
	var vs_at := Vector2(mid, cy + 6.0 * k)
	_veil.draw_circle(vs_at, 104.0 * k, Color(0.03, 0.03, 0.05, 0.9 * a))
	_veil.draw_arc(vs_at, 104.0 * k, 0.0, TAU, 64, Color(UiTheme.BRAND, a), 6.0 * k, true)
	_veil.draw_arc(vs_at, 116.0 * k, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.25 * a), 2.0 * k, true)
	_centred(UiTheme.face(&"impact"), vs_at + Vector2(0.0, 40.0 * k), "VS", 118.0 * k, Color(1.0, 1.0, 1.0, a), true)


## Somewhere that is not a game: its picture, darkened, and where it is going.
func _draw_place(s: Vector2, k: float, a: float) -> void:
	if _art != null:
		# Cover the screen, keeping its shape, drifting slowly.
		var tex := _art.get_size()
		var scale := maxf(s.x / tex.x, s.y / tex.y) * (1.06 + 0.02 * minf(_clock / 4.0, 1.0))
		var size := tex * scale
		_veil.draw_texture_rect(_art, Rect2((s - size) * 0.5, size), false, Color(1.0, 1.0, 1.0, a))
	# A dark wash from the left (the words) and over the foot.
	_gradient_band(Rect2(0.0, 0.0, s.x * 0.75, s.y), Color(0.02, 0.025, 0.035, 0.92 * a), Color(0.02, 0.025, 0.035, 0.25 * a), true)
	_gradient_band(Rect2(0.0, s.y * 0.55, s.x, s.y * 0.45), Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.85 * a))
	_head(s, k, a, "")
	var title := str(_info.get("title", "불러오는 중"))
	var kicker := "LEAGUE" if _target.contains("league") else ("CAREER" if _target.contains("career") or _target.contains("creation") else ("LOBBY" if _target.contains("hub") else "MONEYBALL"))
	var x := 110.0 * k
	var y := s.y * 0.5
	_veil.draw_colored_polygon(PackedVector2Array([Vector2(x, y - 96.0 * k), Vector2(x + 14.0 * k, y - 96.0 * k), Vector2(x + 2.0 * k, y + 30.0 * k), Vector2(x - 12.0 * k, y + 30.0 * k)]), Color(UiTheme.BRAND, a))
	_veil.draw_string(UiTheme.numeric(true), Vector2(x + 34.0 * k, y - 58.0 * k), kicker, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(34.0 * k), Color(1.0, 0.84, 0.36, a))
	_text(UiTheme.display(800), Vector2(x + 30.0 * k, y + 22.0 * k), title, 76.0 * k, Color(1.0, 1.0, 1.0, a))


## The top line: the game's mark at the left, the place and the hour at the right.
func _head(s: Vector2, k: float, a: float, heading: String) -> void:
	var x := 64.0 * k
	var y := 74.0 * k
	_veil.draw_colored_polygon(PackedVector2Array([Vector2(x + 8.0 * k, y - 34.0 * k), Vector2(x + 18.0 * k, y - 34.0 * k), Vector2(x + 10.0 * k, y + 2.0 * k), Vector2(x, y + 2.0 * k)]), Color(UiTheme.BRAND, a))
	var num := UiTheme.numeric(true)
	_veil.draw_string(num, Vector2(x + 30.0 * k, y), "MONEYBALL", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(36.0 * k), Color(1.0, 1.0, 1.0, a))
	if heading != "":
		var w := num.get_string_size("MONEYBALL", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(36.0 * k)).x
		_veil.draw_line(Vector2(x + 48.0 * k + w, y - 28.0 * k), Vector2(x + 48.0 * k + w, y - 2.0 * k), Color(1.0, 1.0, 1.0, 0.35 * a), 2.0 * k)
		_veil.draw_string(UiTheme.display(700), Vector2(x + 66.0 * k + w, y - 2.0 * k), heading, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(28.0 * k), Color(1.0, 1.0, 1.0, 0.9 * a))
	if _info.has("line"):
		var line := str(_info["line"])
		var font := UiTheme.display(700)
		var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(24.0 * k)).x
		var plate := Rect2(s.x - w - 104.0 * k, y - 38.0 * k, w + 44.0 * k, 48.0 * k)
		_veil.draw_colored_polygon(HudCanvas.plate_shape(plate, 10.0 * k), Color(0.0, 0.0, 0.0, 0.45 * a))
		_veil.draw_rect(Rect2(plate.position, Vector2(4.0 * k, plate.size.y)), Color(UiTheme.BRAND, a))
		_veil.draw_string(font, Vector2(plate.position.x + 24.0 * k, y - 5.0 * k), line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(24.0 * k), Color(0.9, 0.94, 1.0, a))


## The foot: a tip at the left, the turning ball, "LOADING" and its share at the right, a thin
## bar along the bottom edge.
func _draw_foot(s: Vector2, k: float, a: float) -> void:
	_gradient_band(Rect2(0.0, s.y - 200.0 * k, s.x, 200.0 * k), Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.78 * a))
	var y := s.y - 70.0 * k
	var chip := Rect2(64.0 * k, y - 34.0 * k, 78.0 * k, 44.0 * k)
	_veil.draw_colored_polygon(HudCanvas.plate_shape(chip, 8.0 * k), Color(UiTheme.BRAND, a))
	_veil.draw_string(UiTheme.numeric(true), Vector2(chip.position.x + 16.0 * k, y - 1.0 * k), "TIP", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(30.0 * k), Color(1.0, 1.0, 1.0, a))
	_veil.draw_string(UiTheme.font(600), Vector2(chip.end.x + 22.0 * k, y - 4.0 * k), _tip, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(26.0 * k), Color(1.0, 1.0, 1.0, 0.92 * a))
	# The ball and the word.
	var num := UiTheme.numeric(true)
	var ready := _stage >= 3
	var word := "READY" if ready else "LOADING"
	var pct := "%d%%" % roundi(_share * 100.0)
	var pw := num.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(30.0 * k)).x
	var ww := num.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(30.0 * k)).x
	var right := s.x - 64.0 * k
	_veil.draw_string(num, Vector2(right - pw, y - 1.0 * k), pct, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(30.0 * k), Color(1.0, 0.84, 0.36, a))
	_veil.draw_string(num, Vector2(right - pw - 18.0 * k - ww, y - 1.0 * k), word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(30.0 * k), Color(1.0, 1.0, 1.0, a))
	ball(_veil, Vector2(right - pw - ww - 62.0 * k, y - 12.0 * k), 21.0 * k, _clock * 5.0, a)
	# The bar.
	var bar := Rect2(0.0, s.y - 6.0 * k, s.x, 6.0 * k)
	_veil.draw_rect(bar, Color(1.0, 1.0, 1.0, 0.1 * a))
	_veil.draw_rect(Rect2(bar.position, Vector2(bar.size.x * _share, bar.size.y)), Color(UiTheme.BRAND, a))
	_veil.draw_rect(Rect2(bar.position, Vector2(bar.size.x * _share, bar.size.y * 0.4)), Color(1.0, 1.0, 1.0, 0.25 * a))


## A baseball: a white disc, its two red seams with their stitches, turning by `turn`.
static func ball(on: CanvasItem, at: Vector2, r: float, turn: float, a: float) -> void:
	on.draw_circle(at, r, Color(0.96, 0.95, 0.91, a))
	on.draw_arc(at, r, 0.0, TAU, 48, Color(0.55, 0.53, 0.5, a), maxf(r * 0.05, 1.0), true)
	var width := maxf(r / 45.0, 1.0)
	for side: float in [-1.0, 1.0] as Array[float]:
		var points := PackedVector2Array()
		for i: int in 25:
			var ang := lerpf(-1.25, 1.25, float(i) / 24.0)
			points.append(at + Vector2(side * r * (0.62 - 0.22 * cos(ang * 2.0)), r * 0.82 * sin(ang)).rotated(turn))
		on.draw_polyline(points, Color(0.82, 0.12, 0.14, a), 2.4 * width, true)
		for i: int in range(2, 23, 3):
			var dir := (points[i + 1] - points[i - 1]).normalized().orthogonal()
			on.draw_line(points[i] - dir * 4.0 * width, points[i] + dir * 4.0 * width, Color(0.82, 0.12, 0.14, a), 1.3 * width, true)


## A rectangle shaded from one colour to another, top to bottom (or left to right).
func _gradient_band(rect: Rect2, from: Color, to: Color, across: bool = false) -> void:
	var p := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var c := PackedColorArray([from, to, to, from]) if across else PackedColorArray([from, from, to, to])
	_veil.draw_polygon(p, c)


func _centred(font: Font, at: Vector2, text: String, px: float, colour: Color, outline: bool = false) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(px)).x
	if outline:
		_text(font, Vector2(at.x - w * 0.5, at.y), text, px, colour)
	else:
		_veil.draw_string(font, Vector2(at.x - w * 0.5, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(px), colour)


func _text(font: Font, at: Vector2, text: String, px: float, colour: Color) -> void:
	_veil.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(px), maxi(int(px / 7.0), 2), Color(0.0, 0.02, 0.08, colour.a * 0.7))
	_veil.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(px), colour)
