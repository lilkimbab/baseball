class_name HudCanvas
extends Control
## Base for the HUD layers: everything is drawn in units of a 1920 x 1080 screen and scaled
## to the window, so 720p and 1080p show the same layout. Positions projected
## from the 3D scene come in screen pixels; `from_screen` turns them into HUD units.

## The broadcast's own plates (the inning and the count, the play-by-play, its tags): their
## colours. The user, 2026-11-23: "the red that shows everywhere looks odd — are these the
## right colours for a game?"). Graphite with a gold line by default: neutral, as broadcasts
## keep their own graphics, so that the clubs' colours (red ones too) stand on it; red and
## navy kept for comparison (`--hud-style` in the capture tools). Each: the top, the foot, a
## line along the top (none when clear), the ink on a white tab.
const STYLES := {
	&"red": [Color(0.86, 0.16, 0.2), Color(0.42, 0.04, 0.09), Color(1.0, 1.0, 1.0, 0.0), Color(0.55, 0.05, 0.09)],
	&"graphite": [Color(0.2, 0.21, 0.24), Color(0.055, 0.06, 0.075), Color(0.98, 0.78, 0.3), Color(0.1, 0.11, 0.13)],
	&"navy": [Color(0.11, 0.2, 0.38), Color(0.03, 0.065, 0.15), Color(0.98, 0.78, 0.3), Color(0.06, 0.12, 0.26)],
}
static var style := &"graphite"


static func style_colour(i: int) -> Color:
	return (STYLES.get(style, STYLES[&"red"]) as Array)[i]


## Screen pixels per HUD unit, and the window's size in HUD units.
var k := 1.0
var view := Vector2(1920.0, 1080.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Call first in _draw().
func begin() -> void:
	k = UiTheme.scale_for(size.y)
	view = size / k
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))


func from_screen(p: Vector2) -> Vector2:
	return p / k


## Text of the broadcast graphics (the score bug, the bars, the panels): the television face.
func text(at: Vector2, line: String, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, weight: int = 600) -> void:
	var f := UiTheme.face(&"broadcast", weight)
	var edge := UiTheme.ink_edge(color)
	draw_string_outline(f, at, line, align, width, font_size, 4, edge if edge.a > 0.0 else Color(UiTheme.SHADOW, UiTheme.SHADOW.a * color.a))
	draw_string(f, at, line, align, width, font_size, color)


func text_width(line: String, font_size: int, weight: int = 600) -> float:
	return UiTheme.face(&"broadcast", weight).get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## A figure or Latin capitals (a speed, a count, a score): the condensed face.
func figure(at: Vector2, line: String, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, slanted: bool = false) -> void:
	var f := UiTheme.numeric(slanted, true)
	var edge := UiTheme.ink_edge(color)
	draw_string_outline(f, at, line, align, width, font_size, 4, edge if edge.a > 0.0 else Color(UiTheme.SHADOW, UiTheme.SHADOW.a * color.a))
	draw_string(f, at, line, align, width, font_size, color)


## What is shouted (an umpire's call, a judgment): the heavy face, with a dark edge.
func shout(at: Vector2, line: String, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var f := UiTheme.face(&"impact")
	draw_string_outline(f, at, line, align, width, font_size, maxi(font_size / 6, 4), Color(0.03, 0.03, 0.05, 0.9 * color.a))
	draw_string(f, at, line, align, width, font_size, color)


## A plate of the menus (docs/04 section 5) drawn with plain draw calls (no shader, so a dozen
## on screen cost nothing): graphite, lighter at the top, the top-left and bottom-right
## corners cut on the slant, a hairline edge with a light line along the top, a soft shadow.
func panel(rect: Rect2, color: Color = UiTheme.PANEL, cut: float = 10.0) -> void:
	var shape := plate_shape(rect, cut)
	var shadow := PackedVector2Array()
	for p: Vector2 in shape:
		shadow.append(p + Vector2(0.0, 5.0))
	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.3 * color.a))
	var top := Color(color.lightened(0.07), color.a)
	var foot := Color(color.darkened(0.3), minf(color.a + 0.04, 1.0))
	var shades := PackedColorArray()
	for p: Vector2 in shape:
		shades.append(top.lerp(foot, (p.y - rect.position.y) / maxf(rect.size.y, 1.0)))
	draw_polygon(shape, shades)
	var edge := shape.duplicate()
	edge.append(shape[0])
	draw_polyline(edge, Color(1.0, 1.0, 1.0, 0.12 * color.a), 1.2, true)
	draw_line(shape[0] + Vector2(0.0, 1.5), Vector2(rect.end.x - 1.0, rect.position.y + 1.5), Color(1.0, 1.0, 1.0, 0.08 * color.a), 1.0)


## The outline of a plate: a rectangle with its top-left and bottom-right corners cut off.
static func plate_shape(rect: Rect2, cut: float) -> PackedVector2Array:
	var c := minf(cut, minf(rect.size.x, rect.size.y) * 0.4)
	var a := rect.position
	var b := rect.end
	return PackedVector2Array([Vector2(a.x + c, a.y), Vector2(b.x, a.y), Vector2(b.x, b.y - c), Vector2(b.x - c, b.y), Vector2(a.x, b.y), Vector2(a.x, a.y + c)])


## A club's colour as the HUD shows it on graphite: its main colour, lifted when it is so
## dark (a navy, a black) that it would vanish into the plate.
static func club_colour(club: Team) -> Color:
	if club == null:
		return Color(0.4, 0.42, 0.48)
	var c := club.primary
	var light := c.get_luminance()
	if light < 0.2:
		c = c.lerp(Color.WHITE, clampf((0.2 - light) * 2.2, 0.0, 0.45))
	return c


## A plate in a club's colours (the user, 2026-11-23: "less black, more colour — as a KBO
## broadcast, 2K14 and The Show have it"): the club's colour from bright at the left to deep at
## the right, a gloss along the top, a slanted stripe of its second colour, its emblem large and
## faint behind, the plate's cut corners and shadow. Text on it stays white.
func team_plate(rect: Rect2, club: Team, cut: float = 12.0, alpha: float = 0.96) -> void:
	var base := HudCanvas.club_colour(club)
	var accent := club.accent if club != null else UiTheme.ACCENT
	if absf(accent.get_luminance() - base.get_luminance()) < 0.12:
		accent = club.secondary if club != null else Color.WHITE
	var shape := plate_shape(rect, cut)
	var shadow := PackedVector2Array()
	for p: Vector2 in shape:
		shadow.append(p + Vector2(0.0, 5.0))
	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.35 * alpha))
	var bright := Color(base.lightened(0.08), alpha)
	var deep := Color(base.darkened(0.62), alpha)
	var shades := PackedColorArray()
	for p: Vector2 in shape:
		var u := (p.x - rect.position.x) / maxf(rect.size.x, 1.0)
		var v := (p.y - rect.position.y) / maxf(rect.size.y, 1.0)
		shades.append(bright.lerp(deep, clampf(u * 0.85 + v * 0.25, 0.0, 1.0)))
	draw_polygon(shape, shades)
	if club != null and rect.size.y >= 70.0:
		# (Inside the plate, behind its right end.)
		var side := rect.size.y - 10.0
		var mark := Rect2(Vector2(rect.end.x - side - rect.size.x * 0.2, rect.position.y + 5.0), Vector2(side, side))
		Emblem.draw_emblem(self, club, mark)
		# (Pushed back into the plate: a wash of its deep colour over the emblem.)
		var wash := PackedVector2Array([mark.position, Vector2(mark.end.x, mark.position.y), mark.end, Vector2(mark.position.x, mark.end.y)])
		draw_colored_polygon(wash, Color(deep.lerp(bright, 0.25), 0.78))
	# The slanted stripe of the second colour, and a gloss along the top.
	var x := rect.position.x + rect.size.x * 0.62
	draw_colored_polygon(PackedVector2Array([Vector2(x, rect.position.y), Vector2(x + 16.0, rect.position.y), Vector2(x + 16.0 - rect.size.y * 0.35, rect.end.y), Vector2(x - rect.size.y * 0.35, rect.end.y)]), Color(accent, 0.22 * alpha))
	draw_rect(Rect2(rect.position + Vector2(cut, 1.0), Vector2(rect.size.x - cut, rect.size.y * 0.42)), Color(1.0, 1.0, 1.0, 0.07 * alpha))
	draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - 4.0), Vector2(rect.size.x - cut, 4.0)), Color(accent, 0.9 * alpha))
	var edge := shape.duplicate()
	edge.append(shape[0])
	draw_polyline(edge, Color(1.0, 1.0, 1.0, 0.18 * alpha), 1.2, true)


## The broadcast's own colour block (the inning, the bases, the count; a line of play-by-play):
## a deep red running to a darker one, glossed.
func brand_plate(rect: Rect2, cut: float = 10.0, alpha: float = 0.96) -> void:
	var shape := plate_shape(rect, cut)
	var shadow := PackedVector2Array()
	for p: Vector2 in shape:
		shadow.append(p + Vector2(0.0, 5.0))
	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.35 * alpha))
	var top := Color(style_colour(0), alpha)
	var foot := Color(style_colour(1), alpha)
	var shades := PackedColorArray()
	for p: Vector2 in shape:
		shades.append(top.lerp(foot, clampf((p.y - rect.position.y) / maxf(rect.size.y, 1.0) * 0.8 + (p.x - rect.position.x) / maxf(rect.size.x, 1.0) * 0.3, 0.0, 1.0)))
	draw_polygon(shape, shades)
	draw_rect(Rect2(rect.position + Vector2(cut, 1.0), Vector2(rect.size.x - cut, rect.size.y * 0.4)), Color(1.0, 1.0, 1.0, 0.08 * alpha))
	var edge := shape.duplicate()
	edge.append(shape[0])
	draw_polyline(edge, Color(1.0, 1.0, 1.0, 0.2 * alpha), 1.2, true)
	var line := style_colour(2)
	if line.a > 0.0:
		draw_rect(Rect2(rect.position + Vector2(cut, 0.0), Vector2(rect.size.x - cut, 3.0)), Color(line, line.a * alpha))


## A band of a club's colour down the left edge of a plate; with `cut`, its top follows the
## plate's cut corner.
func club_band(rect: Rect2, colour: Color, cut: float = 0.0) -> void:
	if cut <= rect.size.x:
		draw_rect(rect, colour)
		return
	var a := rect.position
	var w := rect.size.x
	draw_colored_polygon(PackedVector2Array([Vector2(a.x, a.y + cut), Vector2(a.x + w, a.y + cut - w), Vector2(a.x + w, rect.end.y), Vector2(a.x, rect.end.y)]), colour)


## A key as the menus' bottom bar shows it: a small light cap with the key's name, the action
## after it in grey. Returns the width it took (with the gap before the next).
func keycap(at: Vector2, key: String, label: String, font_size: int = 15) -> float:
	var f := UiTheme.numeric(false, true)
	var key_size := font_size + 1
	var kw := maxf(f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, key_size).x + 16.0, 26.0)
	var cap := Rect2(at + Vector2(0.0, -font_size - 1.0), Vector2(kw, font_size + 8.0))
	draw_rect(cap, Color(1.0, 1.0, 1.0, 0.13))
	draw_rect(cap, Color(1.0, 1.0, 1.0, 0.42), false, 1.0)
	draw_string(f, Vector2(cap.position.x, at.y + 1.0), key, HORIZONTAL_ALIGNMENT_CENTER, kw, key_size, Color.WHITE)
	text(at + Vector2(kw + 8.0, 0.0), label, font_size, UiTheme.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500)
	return kw + 8.0 + text_width(label, font_size, 500) + 22.0


## A line of key hints ("Space 번트   F 작전·교체 …", items two or more spaces apart, the key
## first) drawn as caps, centred in `width` from `at` (the baseline's left end); a smaller
## size when the line would not fit.
func keycaps(at: Vector2, line: String, width: float, font_size: int = 15) -> void:
	var items := key_items(line)
	var size := font_size
	var total := _keycaps_width(items, size)
	while total > width and size > 11:
		size -= 1
		total = _keycaps_width(items, size)
	var x := at.x + maxf((width - total + 22.0) * 0.5, 0.0)
	for item: PackedStringArray in items:
		x += keycap(Vector2(x, at.y), item[0], item[1], size)


func _keycaps_width(items: Array[PackedStringArray], font_size: int) -> float:
	var f := UiTheme.numeric(false, true)
	var total := 0.0
	for item: PackedStringArray in items:
		total += maxf(f.get_string_size(item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size + 1).x + 16.0, 26.0) + 8.0 + text_width(item[1], font_size, 500) + 22.0
	return total


## "Space 번트   F 작전·교체" → [["Space", "번트"], ["F", "작전·교체"]].
static func key_items(line: String) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	var gaps := RegEx.create_from_string("\\s{2,}")
	for part: String in gaps.sub(line.strip_edges(), "\n", true).split("\n", false):
		var space := part.find(" ")
		if space < 0:
			out.append(PackedStringArray([part, ""]))
		else:
			out.append(PackedStringArray([part.substr(0, space), part.substr(space + 1).strip_edges()]))
	return out


## A plate's title as the menus write it: a slanted stroke in the accent, the title in white,
## a grey note after it.
func heading(at: Vector2, title: String, note: String = "", accent: Color = UiTheme.ACCENT, font_size: int = 20) -> void:
	var h := font_size * 0.95
	draw_colored_polygon(PackedVector2Array([at + Vector2(5.0, -h), at + Vector2(10.0, -h), at + Vector2(5.0, 2.0), at + Vector2(0.0, 2.0)]), accent)
	text(at + Vector2(18.0, 0.0), title, font_size, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
	if note != "":
		text(at + Vector2(28.0 + text_width(title, font_size, 700), 0.0), note, font_size - 4, UiTheme.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500)


## A horizontal bar filled to `fraction`.
func bar(rect: Rect2, fraction: float, color: Color) -> void:
	draw_rect(rect, Color(1, 1, 1, 0.1))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(fraction, 0.0, 1.0), rect.size.y)), color)
