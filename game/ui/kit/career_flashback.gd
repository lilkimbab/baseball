class_name CareerFlashback
extends CanvasLayer
## The look back before a farewell (the user, 2026-11-23: "a flashback, the ceremony, the
## settling up"; "every photo is the same"; "too plain — make it livelier, and skippable").
## His career's moments (CareerLegacy.flashback), each as a photograph of the moment itself,
## taken on the ceremony's stage (Ceremony.make_still): the jersey held up at the draft and at a
## signing, the ball at a milestone, the trophy at the awards, the cup over his head at a
## championship, a wave in the all-star team's uniform; in the uniform of his club that year and
## at his age then, so that he grows older down the years, the older photographs faded to sepia.
##
## Laid out as a memory montage: the photograph drops in large with a stamp of what it was
## (DRAFT, CHAMPIONS ...), then is tossed onto the table behind, where the career's photographs
## pile up into a collage; the room takes the colours of his club that year, lights sweeping
## over it; the year rolls on to the next; a championship or a title brings gold and confetti,
## an all-star selection stars, a signing its deal in a headline, a milestone its number counted
## up. At the end the collage is lit, and his name. Space skips it, as a game's cutscenes are
## skipped (Esc, Enter or the button too); a click goes on to the next photograph.

const SLIDE := 2.8
const FADE := 0.45
const PHOTO := Vector2(500.0, 600.0)
const PILE_SCALE := 0.42
## Each kind's moment on the stage (the ceremony it is, how long after its thing goes up the
## photograph is taken) and the stamp it gets.
const SHOTS := {"draft": [Ceremony.Kind.DRAFT, 0.8, "DRAFT"], "debut": [Ceremony.Kind.CALL_UP, 0.6, "DEBUT"], "milestone": [Ceremony.Kind.MILESTONE, 3.2, "MILESTONE"],
	"title": [Ceremony.Kind.AWARD, 0.9, "AWARD"], "champion": [Ceremony.Kind.CHAMPION, 0.5, "CHAMPIONS"], "all_star": [Ceremony.Kind.CALL_UP, 2.4, "ALL-STAR"],
	"deal": [Ceremony.Kind.CONTRACT, 0.8, "SIGNED"], "trade": [Ceremony.Kind.TRADE, 0.8, "TRADED"], "tour": [Ceremony.Kind.RETIREMENT, 4.2, "FAREWELL"]}
const GOLD := Color(1.0, 0.8, 0.32)

var player: Player
var season: Season
var moments: Array = []
var name_line := ""
var done: Callable
var time := 0.0

var _canvas: Control
## The photographs: slide index → [its still (Ceremony), frames rendered] while it renders, then
## its picture kept.
var _stills: Dictionary = {}
var _snaps: Dictionary = {}
## Where each photograph lies on the table: [centre (share of the view), turn].
var _spots: Array = []
var _finished := false


static func play(holder: Node, p: Player, s: Season, list: Array, farewell: String, on_done: Callable = Callable()) -> CareerFlashback:
	var f := CareerFlashback.new()
	f.player = p
	f.season = s
	f.moments = list
	f.name_line = farewell
	f.done = on_done
	Ceremony.showing = true
	holder.get_tree().root.add_child(f)
	return f


func _ready() -> void:
	layer = 91
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_all)
	_canvas.gui_input.connect(func(e: InputEvent) -> void:
		var click := e as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			if _skip_rect().has_point(click.position / _k()):
				_finish()
			else:
				_next())
	add_child(_canvas)
	# The table: a spot for each photograph spread over the room, the same each time for the same
	# career.
	var rng := Rng.new(hash(player.id if player != null else "flashback"))
	for i: int in moments.size():
		_spots.append([Vector2(rng.next_range(0.08, 0.92), rng.next_range(0.14, 0.78)), rng.next_range(-0.32, 0.32)])
	_shoot(0)
	_shoot(1)


func _k() -> float:
	return _canvas.size.y / 1080.0


func _skip_rect() -> Rect2:
	var view := _canvas.size / _k()
	return Rect2(Vector2(view.x - 250.0, 34.0), Vector2(210.0, 50.0))


## The photograph of slide `i` (made a slide ahead; kept as a picture once it has rendered).
func _shoot(i: int) -> void:
	if i < 0 or i >= moments.size() or _stills.has(i) or _snaps.has(i) or player == null:
		return
	var m: Array = moments[i]
	var shot: Array = SHOTS.get(str(m[1]), SHOTS["debut"])
	var still := Ceremony.make_still(player, _club_of(m), shot[0], 0.0, maxi(int(m[0]) - player.born, 18), Vector2i(PHOTO))
	add_child(still)
	still.time = still.raised_at() + float(shot[1])
	_stills[i] = [still, 0]


func _keep_pictures() -> void:
	for i: Variant in _stills.keys():
		var entry: Array = _stills[i]
		entry[1] = int(entry[1]) + 1
		# (A few frames to render, then its picture kept and the stage let go.)
		if int(entry[1]) >= 4:
			var still: Ceremony = entry[0]
			var picture := still.picture()
			var image := picture.get_image() if picture != null else null
			if image != null:
				_snaps[i] = ImageTexture.create_from_image(image)
			still.queue_free()
			_stills.erase(i)


func _picture(i: int) -> Texture2D:
	if _snaps.has(i):
		return _snaps[i]
	if _stills.has(i):
		return ((_stills[i] as Array)[0] as Ceremony).picture()
	return null


## The club of a moment (the all-star game's team in its own colours).
func _club_of(m: Array) -> Team:
	if str(m[1]) == "all_star":
		var t := Team.new()
		t.id = "all_star_0"
		t.name = AllStar.TEAM_NAMES[0]
		t.short_name = AllStar.TEAM_NAMES[0].substr(0, 2)
		t.primary = AllStar.TEAM_COLOURS[0][0]
		t.secondary = AllStar.TEAM_COLOURS[0][1]
		t.accent = AllStar.TEAM_COLOURS[0][2]
		return t
	return season.teams.get(str(m[4])) if season != null else null


func length() -> float:
	return SLIDE * (moments.size() + 1.4)


func _process(delta: float) -> void:
	time += delta
	if time >= length():
		_finish()
		return
	var index := int(time / SLIDE)
	_shoot(index)
	_shoot(index + 1)
	_keep_pictures()
	_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode in [KEY_SPACE, KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_finish()


func _next() -> void:
	time = (floorf(time / SLIDE) + 1.0) * SLIDE
	if time >= length():
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


# --- Drawing (1920 x 1080 units) ---


func _draw_all() -> void:
	var c := _canvas
	var k := _k()
	var view := c.size / k
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	var index := mini(int(time / SLIDE), moments.size())
	var u := fmod(time, SLIDE) if index < moments.size() else time - SLIDE * moments.size()
	var ending := index >= moments.size()
	_room(c, view, index, u)
	# The table: the photographs gone by, small, where they were tossed (lit at the end).
	for i: int in mini(index, moments.size()):
		var travel := 1.0 if i < index - 1 else clampf(u / 0.6, 0.0, 1.0)
		_pile_photo(c, view, i, travel, ending)
	if not ending:
		c.draw_rect(Rect2(Vector2.ZERO, view), Color(0.0, 0.0, 0.0, 0.42))
		_slide(c, view, index, u)
	else:
		_last(c, view, u)
	_strip(c, view, index)
	_skip_button(c)


## The room: dark, in the colours of his club that year (fading from the last), lights sweeping.
func _room(c: Control, view: Vector2, index: int, u: float) -> void:
	var tint := Color(0.2, 0.22, 0.3)
	if not moments.is_empty():
		var now := _club_of(moments[mini(index, moments.size() - 1)])
		var before := _club_of(moments[clampi(index - 1, 0, moments.size() - 1)])
		var tint_now := now.primary if now != null else tint
		var tint_before := before.primary if before != null else tint_now
		tint = tint_before.lerp(tint_now, clampf(u / 0.8, 0.0, 1.0))
	var top := tint.darkened(0.55)
	var foot := Color(0.03, 0.03, 0.035)
	c.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(view.x, 0.0), view, Vector2(0.0, view.y)]), PackedColorArray([top, top, foot, foot]))
	for i: int in 6:
		var x := view.x * (0.08 + 0.17 * i) + 120.0 * sin(time * 0.45 + i * 1.7)
		var foot_x := view.x * 0.5 + (x - view.x * 0.5) * 0.35
		c.draw_colored_polygon(PackedVector2Array([Vector2(x - 22.0, -10.0), Vector2(x + 22.0, -10.0), Vector2(foot_x + 170.0, view.y), Vector2(foot_x - 170.0, view.y)]), Color(1.0, 0.95, 0.85, 0.035))


## A photograph on the table: from where it was shown large to its spot, small and turned.
func _pile_photo(c: Control, view: Vector2, i: int, travel: float, lit: bool) -> void:
	var spot: Array = _spots[i]
	var to := Vector2((spot[0] as Vector2).x * view.x, (spot[0] as Vector2).y * view.y)
	var from := Vector2(view.x * 0.33, view.y * 0.46)
	var e := 1.0 - pow(1.0 - travel, 3.0)
	var at := from.lerp(to, e)
	var scale := lerpf(1.0, PILE_SCALE * (1.2 if lit else 1.0), e)
	var turn := lerpf(_turn_of(i), float(spot[1]), e)
	_photo(c, i, at, turn, scale, 0.95 if lit else 0.75)


func _turn_of(i: int) -> float:
	return deg_to_rad(-3.0 if i % 2 == 0 else 2.5)


## A photograph in its white frame at `at`, turned, scaled: the picture over his club's colours,
## faded with its years, the year and the club under it, and its stamp.
func _photo(c: Control, i: int, at: Vector2, turn: float, scale: float, alpha: float) -> void:
	var m: Array = moments[i]
	var club := _club_of(m)
	var k := _k()
	c.draw_set_transform(at * k, turn, Vector2.ONE * k * scale)
	var frame := Rect2(-PHOTO * 0.5 - Vector2(16.0, 16.0), PHOTO + Vector2(32.0, 84.0))
	c.draw_rect(Rect2(frame.position + Vector2(12.0, 16.0), frame.size), Color(0.0, 0.0, 0.0, 0.5 * alpha))
	c.draw_rect(frame, Color(0.95, 0.93, 0.88, alpha))
	var photo := Rect2(-PHOTO * 0.5, PHOTO)
	var top := club.primary.darkened(0.25) if club != null else Color(0.2, 0.22, 0.26)
	var foot := club.primary.darkened(0.7) if club != null else Color(0.08, 0.08, 0.1)
	c.draw_polygon(PackedVector2Array([photo.position, Vector2(photo.end.x, photo.position.y), photo.end, Vector2(photo.position.x, photo.end.y)]), PackedColorArray([Color(top, alpha), Color(top, alpha), Color(foot, alpha), Color(foot, alpha)]))
	c.draw_circle(Vector2(0.0, photo.position.y + PHOTO.y * 0.42), PHOTO.x * 0.45, Color(1.0, 0.9, 0.75, 0.1 * alpha))
	var picture := _picture(i)
	if picture != null:
		c.draw_texture_rect(picture, photo, false, Color(1, 1, 1, alpha))
	# Its years: the older, the more sepia (none for his last season).
	var last_year := int((moments[-1] as Array)[0])
	var aged := clampf(float(last_year - int(m[0])) / 12.0, 0.0, 1.0)
	c.draw_rect(photo, Color(0.62, 0.44, 0.24, (0.06 + 0.32 * aged) * alpha))
	c.draw_rect(photo, Color(0.96, 0.9, 0.78, 0.12 * aged * alpha))
	c.draw_string(UiTheme.font(600), Vector2(frame.position.x, frame.end.y - 24.0), "%d · %s" % [int(m[0]), club.name if club != null else ""], HORIZONTAL_ALIGNMENT_CENTER, frame.size.x, 22, Color(0.25, 0.22, 0.2, alpha))
	# The stamp, at a slant across the top corner.
	var stamp := str((SHOTS.get(str(m[1]), SHOTS["debut"]) as Array)[2])
	var ink := GOLD if str(m[1]) in ["champion", "title"] else (club.primary.lightened(0.2) if club != null else UiTheme.BRAND)
	c.draw_set_transform((at + Vector2(PHOTO.x * 0.24, -PHOTO.y * 0.38).rotated(turn) * scale) * k, turn + 0.22, Vector2.ONE * k * scale)
	var face := UiTheme.numeric(true, true)
	var w := face.get_string_size(stamp, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 34).x + 26.0
	var box := Rect2(Vector2(-w * 0.5, -24.0), Vector2(w, 46.0))
	c.draw_rect(box, Color(0.0, 0.0, 0.0, 0.25 * alpha))
	c.draw_rect(box, Color(ink, 0.95 * alpha), false, 3.0)
	c.draw_string(face, Vector2(box.position.x, 12.0), stamp, HORIZONTAL_ALIGNMENT_CENTER, w, 34, Color(ink, 0.98 * alpha))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))


## A moment shown large: the photograph drops in, the year rolls on, the words come in; gold,
## stars or a number by what it was.
func _slide(c: Control, view: Vector2, index: int, u: float) -> void:
	var m: Array = moments[index]
	var kind := str(m[1])
	var club := _club_of(m)
	var a := clampf(u / FADE, 0.0, 1.0)
	var out := clampf((SLIDE - u) / 0.25, 0.0, 1.0)
	# Gold and confetti for a title or a championship, stars for the all-star game.
	if kind in ["champion", "title"]:
		c.draw_circle(Vector2(view.x * 0.33, view.y * 0.46), 430.0, Color(GOLD, 0.1 * a))
		_confetti(c, view, u, [GOLD, Color.WHITE, club.primary.lightened(0.2) if club != null else GOLD], 70 if kind == "champion" else 30)
	elif kind == "all_star":
		_stars(c, view, u)
	# The photograph: dropped in from above, settling with a little bounce.
	var drop := 1.0 - pow(1.0 - clampf(u / 0.5, 0.0, 1.0), 3.0)
	var settle := sin(clampf((u - 0.5) / 0.35, 0.0, 1.0) * PI) * 0.03
	var at := Vector2(view.x * 0.33, view.y * 0.46 - (1.0 - drop) * 220.0)
	_photo(c, index, at, _turn_of(index), (1.12 - 0.12 * drop + settle) * (1.0 + 0.03 * u / SLIDE), a * out)
	# The year, rolling on from the last one.
	var x := view.x * 0.6
	var slide := (1.0 - a) * 40.0
	var last_year := int((moments[index - 1] as Array)[0]) if index > 0 else int(m[0])
	var year := roundi(lerpf(last_year, int(m[0]), 1.0 - pow(1.0 - clampf(u / 0.7, 0.0, 1.0), 3.0)))
	c.draw_string(UiTheme.numeric(true, true), Vector2(x + slide, view.y * 0.34), str(year), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 150, Color(1.0, 0.93, 0.8, 0.92 * a * out))
	var name := str(CareerLegacy.KIND_NAMES.get(kind, ""))
	var line_a := clampf((u - 0.25) / FADE, 0.0, 1.0) * out
	var golden := kind in ["champion", "title"]
	if name != "":
		var font := UiTheme.font(700)
		var chip := Rect2(Vector2(x + slide, view.y * 0.34 + 28.0), Vector2(font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20).x + 28.0, 34.0))
		c.draw_rect(chip, Color(GOLD if golden else (club.primary.lightened(0.1) if club != null else UiTheme.BRAND), 0.92 * line_a))
		c.draw_string(font, chip.position + Vector2(0.0, 24.0), name, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 20, Color(0.08, 0.06, 0.02, line_a) if golden else Color(1, 1, 1, line_a))
	var big_face := UiTheme.face(&"impact") if golden else UiTheme.display(800)
	c.draw_string(big_face, Vector2(x + slide * 1.5, view.y * 0.34 + 124.0), str(m[2]), HORIZONTAL_ALIGNMENT_LEFT, view.x * 0.37, 56, Color(1, 1, 1, line_a))
	var detail_a := clampf((u - 0.5) / FADE, 0.0, 1.0) * out
	if kind == "deal":
		# A signing's deal as the papers headline it.
		c.draw_string(UiTheme.display(800), Vector2(x, view.y * 0.34 + 186.0), str(m[3]).get_slice(" (", 0), HORIZONTAL_ALIGNMENT_LEFT, view.x * 0.37, 40, Color(GOLD, detail_a))
		if str(m[3]).contains(" ("):
			c.draw_string(UiTheme.font(500), Vector2(x, view.y * 0.34 + 228.0), "(" + str(m[3]).get_slice(" (", 1), HORIZONTAL_ALIGNMENT_LEFT, view.x * 0.37, 22, Color(1, 1, 1, 0.7 * detail_a))
	else:
		c.draw_string(UiTheme.font(500), Vector2(x, view.y * 0.34 + 176.0), str(m[3]), HORIZONTAL_ALIGNMENT_LEFT, view.x * 0.37, 26, Color(1, 1, 1, 0.72 * detail_a))
	# A milestone's number, counted up.
	if kind == "milestone":
		var digits := ""
		for ch: String in str(m[2]):
			if ch >= "0" and ch <= "9":
				digits += ch
		if digits.length() >= 2:
			var n := roundi(int(digits) * (1.0 - pow(1.0 - clampf((u - 0.3) / 1.2, 0.0, 1.0), 3.0)))
			c.draw_string(UiTheme.numeric(true, true), Vector2(x, view.y * 0.34 + 300.0), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 110, Color(GOLD, detail_a))


## The end: the collage lit, his name over it.
func _last(c: Control, view: Vector2, u: float) -> void:
	var a := clampf(u / 0.8, 0.0, 1.0)
	c.draw_rect(Rect2(Vector2(0.0, view.y * 0.36), Vector2(view.x, 230.0)), Color(0.0, 0.0, 0.0, 0.62 * a))
	var head := UiTheme.display(900)
	var w := head.get_string_size(name_line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 76).x
	c.draw_string(UiTheme.font(600), Vector2(0.0, view.y * 0.36 + 70.0), "그리고 오늘,", HORIZONTAL_ALIGNMENT_CENTER, view.x, 30, Color(1.0, 0.93, 0.8, 0.9 * a))
	c.draw_string(head, Vector2((view.x - w) * 0.5, view.y * 0.36 + 170.0), name_line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 76, Color(1, 1, 1, a))


func _confetti(c: Control, view: Vector2, u: float, colours: Array, count: int) -> void:
	for i: int in count:
		var r1 := fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		var r2 := fposmod(sin(float(i) * 78.233) * 12543.123, 1.0)
		var y := fposmod((r2 - 0.6) * view.y + u * (140.0 + 120.0 * r2), view.y + 40.0) - 20.0
		var x := r1 * view.x + sin(u * 2.0 + i) * 30.0
		var turn := u * (2.0 + 3.0 * r2) + i
		var along := Vector2(cos(turn), sin(turn)) * 7.0
		var across := along.orthogonal().normalized() * 3.0 * absf(cos(u * 4.0 + i))
		var at := Vector2(x, y)
		c.draw_colored_polygon(PackedVector2Array([at - along - across, at + along - across, at + along + across, at - along + across]), Color(colours[i % colours.size()], 0.9))


func _stars(c: Control, view: Vector2, u: float) -> void:
	for i: int in 40:
		var r1 := fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		var r2 := fposmod(sin(float(i) * 78.233) * 12543.123, 1.0)
		var at := Vector2(r1 * view.x, r2 * view.y * 0.85)
		var twinkle := 0.5 + 0.5 * sin(u * 5.0 + i * 1.3)
		var s := 3.0 + 6.0 * twinkle
		var colour := Color(0.75, 0.88, 1.0, 0.75 * twinkle)
		c.draw_colored_polygon(PackedVector2Array([at + Vector2(0.0, -s * 2.0), at + Vector2(s * 0.5, 0.0), at + Vector2(0.0, s * 2.0), at + Vector2(-s * 0.5, 0.0)]), colour)
		c.draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 2.0, 0.0), at + Vector2(0.0, s * 0.5), at + Vector2(s * 2.0, 0.0), at + Vector2(0.0, -s * 0.5)]), colour)


## The years along the foot as a film strip, the one shown lit.
func _strip(c: Control, view: Vector2, index: int) -> void:
	var y := view.y - 70.0
	c.draw_rect(Rect2(Vector2(0.0, y - 26.0), Vector2(view.x, 52.0)), Color(0.0, 0.0, 0.0, 0.6))
	for i: int in 48:
		var x := 20.0 + i * 40.0
		c.draw_rect(Rect2(Vector2(x, y - 22.0), Vector2(14.0, 8.0)), Color(1, 1, 1, 0.12))
		c.draw_rect(Rect2(Vector2(x, y + 14.0), Vector2(14.0, 8.0)), Color(1, 1, 1, 0.12))
	var n := moments.size()
	if n == 0:
		return
	var span := minf(view.x - 240.0, n * 150.0)
	var left := (view.x - span) * 0.5
	var font := UiTheme.numeric(false, true)
	for i: int in n:
		var x := left + span * (i + 0.5) / n
		var on := i == index
		c.draw_circle(Vector2(x, y), 7.0 if on else 4.0, GOLD if on else Color(1, 1, 1, 0.35 if i > index else 0.7))
		c.draw_string(font, Vector2(x - 40.0, y - 12.0), str(int((moments[i] as Array)[0])), HORIZONTAL_ALIGNMENT_CENTER, 80.0, 16, Color(1, 1, 1, 0.85 if on else 0.35))


## "건너뛰기" at the top right, a button to press (Esc too); Space goes on to the next.
func _skip_button(c: Control) -> void:
	var r := _skip_rect()
	c.draw_rect(r, Color(0.0, 0.0, 0.0, 0.55))
	c.draw_rect(r, Color(1, 1, 1, 0.35), false, 1.5)
	c.draw_string(UiTheme.font(700), Vector2(r.position.x, r.position.y + 33.0), "건너뛰기  Space", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, Color.WHITE)
	c.draw_string(UiTheme.font(500), Vector2(r.position.x, r.end.y + 24.0), "Space 건너뛰기 · 클릭 다음 사진", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, Color(1, 1, 1, 0.5))
