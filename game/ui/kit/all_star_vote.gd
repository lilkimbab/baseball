class_name AllStarVote
extends CanvasLayer
## The fans' all-star vote announced (the user, 2026-11-23: "an animation of the vote picking
## the players would be fun; 청팀 and 백팀, an event game of its own"): each team's best twelve
## (AllStar.board) comes up place by place, 청팀 on the left and 백팀 on the right, the
## ballot's count running up beside each name; the person's own man (the career player, or the
## managed club's men) lit in gold and stamped 선정. A key shows the rest at once, then closes.

const REVEAL_FROM := 1.0
const EVERY := 0.36
const COUNT_UP := 0.8
const ROW := 58.0
const TOP := 238.0
const BLUE := Color("#1f4e9c")
const WHITE := Color(0.93, 0.94, 0.96)

var heading := ""
var footer := ""
## AllStar.board's lines.
var lines := PackedStringArray()
## For the clubs' emblems (null: none drawn).
var season: Season
var done: Callable
var time := 0.0

var _rows: Array = [[], []]
var _canvas: Control
var _finished := false


## Shows it over everything; `on_done` when it is closed.
static func play(holder: Node, title: String, board: PackedStringArray, bottom: String, s: Season, on_done: Callable = Callable()) -> AllStarVote:
	var v := AllStarVote.new()
	v.heading = title
	v.lines = board
	v.footer = bottom
	v.season = s
	v.done = on_done
	Ceremony.showing = true
	holder.get_tree().root.add_child(v)
	return v


func _ready() -> void:
	layer = 90
	for line: String in lines:
		var f := line.split("|")
		if f.size() >= 6:
			(_rows[clampi(int(f[0]), 0, 1)] as Array).append([f[1], f[2], f[3], int(f[4]), f[5] == "1"])
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_all)
	_canvas.gui_input.connect(func(e: InputEvent) -> void:
		var click := e as InputEventMouseButton
		if click != null and click.pressed:
			_advance())
	add_child(_canvas)


## When everything is up.
func revealed_at() -> float:
	return REVEAL_FROM + EVERY * maxf(float(maxi((_rows[0] as Array).size(), (_rows[1] as Array).size())) - 1.0, 0.0) + COUNT_UP + 0.4


func _process(delta: float) -> void:
	time += delta
	_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		get_viewport().set_input_as_handled()
		_advance()


## The first key shows the rest at once; the next one closes it.
func _advance() -> void:
	if time < revealed_at():
		time = revealed_at()
	else:
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	Ceremony.showing = false
	var callback := done
	queue_free()
	if callback.is_valid():
		callback.call()


# --- Drawing (in 1920 x 1080 units, scaled to the window) ---


func _draw_all() -> void:
	var c := _canvas
	var k := c.size.y / 1080.0
	var view := c.size / k
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	_backdrop(c, view)
	var head := UiTheme.display(800)
	var body := UiTheme.font(600)
	var a := clampf(time / 0.4, 0.0, 1.0)
	_centred(c, UiTheme.numeric(true, true), Vector2(view.x * 0.5, 70.0), "ALL-STAR  FAN  VOTE", 26, Color(UiTheme.GOLD, a))
	_centred(c, head, Vector2(view.x * 0.5, 128.0), heading, 50, Color(1.0, 1.0, 1.0, a))
	var col := minf(800.0, (view.x - 160.0) * 0.5)
	var lefts := [view.x * 0.5 - 30.0 - col, view.x * 0.5 + 30.0]
	for side: int in 2:
		var x: float = lefts[side]
		# The team's head: 청팀 on blue, 백팀 on white.
		var plate := Rect2(Vector2(x, TOP - 70.0), Vector2(col, 52.0))
		c.draw_rect(plate, Color(BLUE if side == 0 else WHITE, 0.95 * a))
		c.draw_rect(Rect2(plate.position + Vector2(0.0, plate.size.y - 4.0), Vector2(col, 4.0)), Color(UiTheme.GOLD, 0.9 * a))
		var ink := Color.WHITE if side == 0 else Color(0.1, 0.12, 0.16)
		c.draw_string(head, plate.position + Vector2(22.0, 37.0), "청팀" if side == 0 else "백팀", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, Color(ink, a))
		c.draw_string(body, plate.position + Vector2(0.0, 35.0), "베스트 12", HORIZONTAL_ALIGNMENT_RIGHT, col - 22.0, 20, Color(ink, 0.75 * a))
		var rows: Array = _rows[side]
		for i: int in rows.size():
			_row(c, rows[i], Rect2(Vector2(x, TOP + ROW * i), Vector2(col, ROW - 6.0)), REVEAL_FROM + EVERY * i, side)
	# The end: what it means for the person, and how to go on.
	var end := revealed_at()
	if time >= end - 0.3 and footer != "":
		var fa := clampf((time - end + 0.3) / 0.4, 0.0, 1.0)
		var band := Rect2(Vector2(0.0, view.y - 118.0), Vector2(view.x, 70.0))
		c.draw_rect(band, Color(0.02, 0.02, 0.03, 0.8 * fa))
		c.draw_rect(Rect2(band.position, Vector2(view.x, 3.0)), Color(UiTheme.GOLD, 0.9 * fa))
		_centred(c, head, Vector2(view.x * 0.5, band.position.y + 48.0), footer, 32, Color(1.0, 0.95, 0.8, fa))
	var hint := "Space 계속" if time >= end else "Space 결과 바로 보기"
	c.draw_string(body, Vector2(view.x - 260.0, view.y - 18.0), hint, HORIZONTAL_ALIGNMENT_RIGHT, 230.0, 17, Color(1, 1, 1, 0.55))


func _backdrop(c: Control, view: Vector2) -> void:
	var top := Color(0.025, 0.03, 0.05)
	var foot := Color(0.05, 0.06, 0.09)
	c.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(view.x, 0.0), view, Vector2(0.0, view.y)]), PackedColorArray([top, top, foot, foot]))
	# Each half faintly in its team's colour, split on the slant.
	c.draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(view.x * 0.53, 0.0), Vector2(view.x * 0.47, view.y), Vector2(0.0, view.y)]), Color(BLUE, 0.16))
	c.draw_colored_polygon(PackedVector2Array([Vector2(view.x * 0.53, 0.0), Vector2(view.x, 0.0), view, Vector2(view.x * 0.47, view.y)]), Color(WHITE, 0.05))
	# Beams sweeping from above.
	for i: int in 5:
		var x := view.x * (0.1 + 0.2 * i) + 90.0 * sin(time * 0.5 + i * 1.9)
		c.draw_colored_polygon(PackedVector2Array([Vector2(x - 24.0, 0.0), Vector2(x + 24.0, 0.0), Vector2(view.x * 0.5 + (x - view.x * 0.5) * 0.3 + 160.0, view.y), Vector2(view.x * 0.5 + (x - view.x * 0.5) * 0.3 - 160.0, view.y)]), Color(1.0, 0.97, 0.88, 0.03))


## One place of a team: in from its side at `from`, the count running up, gold if it is his.
func _row(c: Control, r: Array, rect: Rect2, from: float, side: int) -> void:
	var u := time - from
	if u <= 0.0:
		# Still to come: the place's name in a dim empty row.
		c.draw_rect(rect, Color(1.0, 1.0, 1.0, 0.035))
		c.draw_string(UiTheme.font(600), rect.position + Vector2(18.0, 35.0), str(r[0]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Color(1, 1, 1, 0.3))
		return
	var a := clampf(u / 0.25, 0.0, 1.0)
	var slide := (1.0 - a) * 60.0 * (-1.0 if side == 0 else 1.0)
	var box := Rect2(rect.position + Vector2(slide, 0.0), rect.size)
	var mine := bool(r[4])
	c.draw_rect(box, Color(UiTheme.GOLD, 0.16 * a) if mine else Color(0.1, 0.11, 0.14, 0.88 * a))
	c.draw_rect(Rect2(box.position, Vector2(5.0, box.size.y)), Color(UiTheme.GOLD if mine else (BLUE.lightened(0.25) if side == 0 else WHITE), a))
	if mine:
		c.draw_rect(box, Color(UiTheme.GOLD, 0.9 * a), false, 2.0)
	var body := UiTheme.font(600)
	c.draw_string(body, box.position + Vector2(18.0, 35.0), str(r[0]), HORIZONTAL_ALIGNMENT_LEFT, 120.0, 19, Color(1, 1, 1, 0.62 * a))
	var x := box.position.x + 146.0
	var club: Team = season.teams.get(str(r[2])) if season != null else null
	if club != null:
		Emblem.draw_emblem(c, club, Rect2(Vector2(x, box.position.y + 6.0), Vector2(40.0, 40.0)))
	x += 52.0
	var head := UiTheme.display(800)
	c.draw_string(head, Vector2(x, box.position.y + 36.0), str(r[1]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 25, Color(1, 1, 1, a))
	if club != null:
		var w := head.get_string_size(str(r[1]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 25).x
		c.draw_string(body, Vector2(x + w + 12.0, box.position.y + 35.0), club.short_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, Color(1, 1, 1, 0.5 * a))
	# The ballot's count running up.
	var k := clampf(u / COUNT_UP, 0.0, 1.0)
	var shown := roundi(float(r[3]) * (1.0 - pow(1.0 - k, 3.0)))
	var votes := "%s표" % _thousands(shown)
	var right := box.end.x - (110.0 if mine else 18.0)
	c.draw_string(UiTheme.numeric(true, true), Vector2(right - 220.0, box.position.y + 38.0), votes, HORIZONTAL_ALIGNMENT_RIGHT, 220.0, 28, Color(UiTheme.GOLD if mine else Color(1.0, 0.9, 0.62), a))
	# 선정: stamped as the count stops.
	if mine and u >= COUNT_UP:
		var p := clampf((u - COUNT_UP) / 0.22, 0.0, 1.0)
		var s := lerpf(1.8, 1.0, p)
		var centre := Vector2(box.end.x - 52.0, box.position.y + box.size.y * 0.5)
		c.draw_set_transform((centre) * (c.size.y / 1080.0), -0.14, Vector2.ONE * s * (c.size.y / 1080.0))
		var stamp := Rect2(Vector2(-42.0, -20.0), Vector2(84.0, 40.0))
		c.draw_rect(stamp, Color(0.78, 0.1, 0.12, 0.92 * p))
		c.draw_rect(stamp, Color(1.0, 0.85, 0.4, p), false, 2.5)
		c.draw_string(UiTheme.face(&"impact"), Vector2(-42.0, 11.0), "선정", HORIZONTAL_ALIGNMENT_CENTER, 84.0, 26, Color(1, 1, 1, p))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * (c.size.y / 1080.0))


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


static func _centred(c: Control, font: Font, at: Vector2, text: String, px: int, colour: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	c.draw_string(font, Vector2(at.x - w * 0.5, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, colour)
