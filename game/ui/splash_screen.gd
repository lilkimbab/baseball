class_name SplashScreen
extends Control
## The game's own opening, as a released game opens (the user, 2026-11-23: "not straight to the
## title: our own loading first, as other companies' games have"; "make it look made by a game
## company"), while the heavy things load in the background (the four player models, the
## crowd's pictures, the match and its screens — kept in WARM, so the first game starts at once):
##
## 1. The game's ident: a ball rolls in spinning, a red slash sweeps across and leaves the name
##    behind it, "PRO BASEBALL" above, a line drawn under.
## 2. The engine's credit.
## 3. A notice: the game saves by itself; sound is best with headphones.
##
## A key or a click skips to the next; the title comes when the last is over and everything is
## loaded (a turning ball at the bottom right says it is still loading).

const TITLE := "res://ui/title_screen.tscn"
## Loaded in the background while the splash shows (the heaviest first).
const WARM: Array[String] = [
	"res://assets/characters/player_base.glb", "res://assets/characters/player_lean.glb",
	"res://assets/characters/player_solid.glb", "res://assets/characters/player_heavy.glb",
	"res://assets/crowd/crowd_atlas.png", "res://match/match.tscn", "res://league/league_screen.tscn",
	"res://career/career_screen.tscn", "res://ui/hub_screen.tscn",
]
## How long each part shows (s), and the fade into the title.
const PARTS: Array[float] = [2.9, 1.7, 2.9]
const FADE := 0.5

## What was loaded, held so it stays in memory.
static var kept: Array[Resource] = []

var _t := 0.0
var _part := 0
var _part_t := 0.0
var _done := 0
var _leaving := -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Settings.ensure_loaded()
	Settings.apply(get_tree())
	for path: String in WARM:
		if ResourceLoader.exists(path):
			ResourceLoader.load_threaded_request(path, "", true)


func _process(delta: float) -> void:
	_t += delta
	_part_t += delta
	_done = 0
	for path: String in WARM:
		if not ResourceLoader.exists(path):
			_done += 1
			continue
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_done += 1
	if _part < PARTS.size() and _part_t >= PARTS[_part]:
		_next()
	if _leaving < 0.0 and _part >= PARTS.size() and _done == WARM.size():
		_leave()
	if _leaving >= 0.0:
		_leaving += delta
		if _leaving >= FADE:
			set_process(false)
			get_tree().change_scene_to_file(TITLE)
			return
	queue_redraw()


func _next() -> void:
	_part = mini(_part + 1, PARTS.size())
	_part_t = 0.0


func _leave() -> void:
	for path: String in WARM:
		if ResourceLoader.exists(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			kept.append(ResourceLoader.load_threaded_get(path))
	_leaving = 0.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_next()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		_next()


func _draw() -> void:
	var view := size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.012, 0.014, 0.02))
	var k := view.y / 1080.0
	var out := 1.0 - clampf(_leaving / FADE, 0.0, 1.0) if _leaving >= 0.0 else 1.0
	if _part < PARTS.size():
		# Each part fades in and out.
		var length := PARTS[_part]
		var a := clampf(_part_t / 0.35, 0.0, 1.0) * clampf((length - _part_t) / 0.35, 0.0, 1.0)
		match _part:
			0:
				_ident(view, k, _part_t, a)
			1:
				_engine(view, k, a)
			2:
				_notice(view, k, a)
	if _done < WARM.size() or _part >= PARTS.size():
		# Still loading: the turning ball and the word at the bottom right.
		var sub := UiTheme.numeric(true)
		var word := "LOADING" if _done < WARM.size() else ""
		if word != "":
			var w := sub.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(24 * k)).x
			draw_string(sub, Vector2(view.x - 60.0 * k - w, view.y - 54.0 * k), word, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(24 * k), Color(1, 1, 1, 0.6 * out))
			Loading.ball(self, Vector2(view.x - 84.0 * k - w, view.y - 62.0 * k), 15.0 * k, _t * 5.0, 0.85 * out)


## The game's ident: the ball rolls in, the slash sweeps the name into view.
func _ident(view: Vector2, k: float, t: float, a: float) -> void:
	var mid := view * 0.5
	var font := UiTheme.numeric(true, true)
	var px := roundi(176 * k)
	var name := "MONEYBALL"
	var width := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var left := mid.x - width * 0.5 + 70.0 * k
	var base := mid.y + 58.0 * k
	# The ball: rolls in from the left, spinning, and comes to rest before the name.
	var rest := Vector2(left - 120.0 * k, mid.y - 4.0 * k)
	var roll := ease(clampf(t / 0.75, 0.0, 1.0), 0.35)
	var at := Vector2(lerpf(-140.0 * k, rest.x, roll), rest.y)
	var r := 74.0 * k
	Loading.ball(self, at, r, (at.x - rest.x) / r + t * 0.4, a)
	# The slash: from the ball across the name and away, the letters left lit behind it.
	var sweep := clampf((t - 0.55) / 0.6, 0.0, 1.0)
	var edge := lerpf(left - 60.0 * k, left + width + 140.0 * k, ease(sweep, -1.6))
	var drawn := ""
	for i: int in name.length():
		var x := left + font.get_string_size(drawn, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var lit := clampf((edge - x) / (60.0 * k), 0.0, 1.0)
		draw_string(font, Vector2(x, base), name[i], HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(1, 1, 1, a * lit))
		drawn += name[i]
	if sweep > 0.0 and sweep < 1.0:
		var h := 210.0 * k
		var lean := 46.0 * k
		var w := 26.0 * k
		draw_colored_polygon(PackedVector2Array([Vector2(edge + lean, mid.y - h * 0.5), Vector2(edge + lean + w, mid.y - h * 0.5), Vector2(edge - lean + w, mid.y + h * 0.5), Vector2(edge - lean, mid.y + h * 0.5)]), Color(UiTheme.BRAND, a * (1.0 - sweep * 0.6)))
	# Above: "PRO BASEBALL", spaced; below: a red line drawn out from the ball.
	var kicker_a := clampf((t - 1.05) / 0.35, 0.0, 1.0) * a
	var small := UiTheme.numeric(true, false)
	var kicker := "P R O    B A S E B A L L"
	draw_string(small, Vector2(left + 6.0 * k, mid.y - 118.0 * k), kicker, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(30 * k), Color(1.0, 0.84, 0.36, kicker_a))
	var line := clampf((t - 0.9) / 0.6, 0.0, 1.0)
	draw_rect(Rect2(left + 4.0 * k, base + 26.0 * k, width * ease(line, -2.0), 5.0 * k), Color(UiTheme.BRAND, a))
	var sub := UiTheme.font(600)
	draw_string(sub, Vector2(left + 6.0 * k, base + 78.0 * k), "머니볼 · 프로야구", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(26 * k), Color(1, 1, 1, 0.7 * kicker_a))


## The engine's credit.
func _engine(view: Vector2, k: float, a: float) -> void:
	var mid := view * 0.5
	var small := UiTheme.numeric(false, false)
	var big := UiTheme.numeric(false, true)
	var top := "POWERED BY"
	var name := "GODOT ENGINE"
	var tw := small.get_string_size(top, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(24 * k)).x
	var nw := big.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(72 * k)).x
	draw_string(small, Vector2(mid.x - tw * 0.5, mid.y - 34.0 * k), top, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(24 * k), Color(1, 1, 1, 0.55 * a))
	draw_string(big, Vector2(mid.x - nw * 0.5, mid.y + 40.0 * k), name, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(72 * k), Color(0.36, 0.62, 0.86, a))


## The notice: the game saves by itself; headphones. Centred as one block.
func _notice(view: Vector2, k: float, a: float) -> void:
	var mid := view * 0.5
	var heading := UiTheme.display(800)
	var body := UiTheme.font(600)
	var rows: Array = [["floppy-disk", "자동 저장", "리그와 전설의 시작의 진행 상황은 자동으로 저장됩니다. 저장 중에는 게임을 끄지 마세요."],
		["speaker-high", "소리", "헤드폰을 쓰면 관중의 함성과 중계를 더 생생하게 들을 수 있습니다."]]
	var widest := 0.0
	for row: Array in rows:
		widest = maxf(widest, body.get_string_size(str(row[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(28 * k)).x)
	var x := mid.x - (widest + 120.0 * k) * 0.5
	var y := mid.y - 70.0 * k
	for row: Array in rows:
		var icon := UiTheme.icon(str(row[0]))
		draw_circle(Vector2(x + 40.0 * k, y - 10.0 * k), 40.0 * k, Color(UiTheme.BRAND, 0.9 * a))
		if icon != null:
			draw_texture_rect(icon, Rect2(x + 16.0 * k, y - 34.0 * k, 48.0 * k, 48.0 * k), false, Color(1, 1, 1, a))
		draw_string(heading, Vector2(x + 120.0 * k, y - 16.0 * k), str(row[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(38 * k), Color(1, 1, 1, a))
		draw_string(body, Vector2(x + 120.0 * k, y + 30.0 * k), str(row[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(28 * k), Color(1, 1, 1, 0.72 * a))
		y += 160.0 * k
