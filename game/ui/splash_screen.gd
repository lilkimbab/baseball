class_name SplashScreen
extends Control
## The game's own opening (queue stage 6.5, 2026-11-23: "not straight to the title when the
## program starts: our own loading screen first, as other companies' games have, that loads the
## real game"): the game's mark on black, then its name over a ball's seams turning, a bar and a
## tip while the heavy things load in the background (the four player models, the park's and
## the crowd's textures, the match and its screens), then a fade into the title. What it loaded
## is kept (WARM), so the first game starts at once. A key or a click after loading skips the
## wait; nothing can skip the loading itself.

const TITLE := "res://ui/title_screen.tscn"
## Loaded in the background while the splash shows (the heaviest first).
const WARM: Array[String] = [
	"res://assets/characters/player_base.glb", "res://assets/characters/player_lean.glb",
	"res://assets/characters/player_solid.glb", "res://assets/characters/player_heavy.glb",
	"res://assets/crowd/crowd_atlas.png", "res://match/match.tscn", "res://league/league_screen.tscn",
	"res://career/career_screen.tscn", "res://ui/hub_screen.tscn",
]
## Seconds: the mark alone, the least the whole opening takes, the fade out.
const MARK := 1.4
const AT_LEAST := 3.2
const FADE := 0.45

## What was loaded, held so it stays in memory.
static var kept: Array[Resource] = []

var _t := 0.0
var _done := 0
var _leaving := -1.0
var _tip := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Settings.ensure_loaded()
	Settings.apply(get_tree())
	_tip = Loading.TIPS[randi() % Loading.TIPS.size()]
	for path: String in WARM:
		if ResourceLoader.exists(path):
			ResourceLoader.load_threaded_request(path, "", true)


func _process(delta: float) -> void:
	_t += delta
	_done = 0
	for path: String in WARM:
		if not ResourceLoader.exists(path):
			_done += 1
			continue
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_done += 1
	if _leaving < 0.0 and _done == WARM.size() and _t >= AT_LEAST:
		_leave()
	if _leaving >= 0.0:
		_leaving += delta
		if _leaving >= FADE:
			set_process(false)
			get_tree().change_scene_to_file(TITLE)
			return
	queue_redraw()


func _leave() -> void:
	for path: String in WARM:
		if ResourceLoader.exists(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			kept.append(ResourceLoader.load_threaded_get(path))
	_leaving = 0.0


func _gui_input(event: InputEvent) -> void:
	if _done == WARM.size() and _leaving < 0.0 and (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		_leave()


func _unhandled_input(event: InputEvent) -> void:
	if _done == WARM.size() and _leaving < 0.0 and event is InputEventKey and (event as InputEventKey).pressed:
		_leave()


func _draw() -> void:
	var view := size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.02, 0.025, 0.035))
	var fade := 1.0 - clampf(_leaving / FADE, 0.0, 1.0) if _leaving >= 0.0 else 1.0
	var k := view.y / 1080.0
	var mid := view * 0.5
	if _t < MARK:
		# The mark: a ball's seams drawn in, the game's initial on it.
		var a := clampf(_t / 0.4, 0.0, 1.0) * clampf((MARK - _t) / 0.3, 0.0, 1.0)
		_ball(mid, 90.0 * k, _t * 0.6, a, 1.0)
		var font := UiTheme.display(800)
		var size_px := roundi(30 * k)
		var word := "MONEYBALL BASEBALL"
		var w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		draw_string(font, Vector2(mid.x - w * 0.5, mid.y + 150.0 * k), word, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(1, 1, 1, 0.85 * a))
		return
	var a := clampf((_t - MARK) / 0.5, 0.0, 1.0) * fade
	# The name over a ball turning slowly behind it.
	_ball(mid + Vector2(0.0, -60.0 * k), 230.0 * k, _t * 0.25, 0.16 * a, 2.0)
	var title := UiTheme.display(900)
	var big := roundi(150 * k)
	var name := "MONEYBALL"
	var tw := title.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	draw_string(title, Vector2(mid.x - tw * 0.5, mid.y - 10.0 * k), name, HORIZONTAL_ALIGNMENT_LEFT, -1, big, Color(1, 1, 1, a))
	var sub := UiTheme.font(600)
	var line := "머니볼 · 야구"
	var sw := sub.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(28 * k)).x
	draw_string(sub, Vector2(mid.x - sw * 0.5, mid.y + 48.0 * k), line, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(28 * k), Color(UiTheme.ACCENT, a))
	# The bar, and a tip under it.
	var bar := Rect2(Vector2(mid.x - 360.0 * k, view.y - 170.0 * k), Vector2(720.0 * k, 6.0 * k))
	draw_rect(bar, Color(1, 1, 1, 0.12 * a))
	var share := float(_done) / WARM.size()
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), Color(UiTheme.BRAND, a))
	var status := "불러오는 중..." if _done < WARM.size() else "아무 키나 누르세요"
	var stw := sub.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(20 * k)).x
	draw_string(sub, Vector2(mid.x - stw * 0.5, bar.position.y - 16.0 * k), status, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(20 * k), Color(1, 1, 1, 0.75 * a))
	var tip := "TIP  " + _tip
	var tpw := sub.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(20 * k)).x
	draw_string(sub, Vector2(mid.x - tpw * 0.5, bar.end.y + 46.0 * k), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(20 * k), Color(1, 1, 1, 0.55 * a))
	var engine := "Made with Godot Engine"
	var ew := sub.get_string_size(engine, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(15 * k)).x
	draw_string(sub, Vector2(view.x - ew - 30.0 * k, view.y - 26.0 * k), engine, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(15 * k), Color(1, 1, 1, 0.3 * a))


## A ball: a white disc and its two red seams, turning by `turn`.
func _ball(at: Vector2, r: float, turn: float, a: float, width: float) -> void:
	draw_circle(at, r, Color(0.95, 0.94, 0.9, a))
	draw_arc(at, r, 0.0, TAU, 64, Color(0.6, 0.58, 0.55, a), 1.5 * width, true)
	for side: float in [-1.0, 1.0] as Array[float]:
		var points := PackedVector2Array()
		for i: int in 33:
			var u := float(i) / 32.0
			var ang := lerpf(-1.25, 1.25, u)
			var p := Vector2(side * r * (0.62 - 0.22 * cos(ang * 2.0)), r * 0.82 * sin(ang))
			points.append(at + p.rotated(turn))
		draw_polyline(points, Color(0.82, 0.12, 0.14, a), 3.0 * width, true)
		for i: int in range(2, 31, 3):
			var p0 := points[i]
			var dir := (points[i + 1] - points[i - 1]).normalized().orthogonal()
			draw_line(p0 - dir * 5.0 * width, p0 + dir * 5.0 * width, Color(0.82, 0.12, 0.14, a), 1.6 * width, true)
