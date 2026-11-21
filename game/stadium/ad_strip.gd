class_name AdStrip
extends Control
## A strip of sponsors' boards (docs/06 6.2-8), drawn once into a viewport that the ad bands
## round the park show: each a coloured board with the sponsor's mark and name.

const SPONSORS := "res://data/sponsors.ko.json"

var sponsors: Array[Dictionary] = []
var slots := 8


static func load_sponsors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(SPONSORS):
		return out
	for s: Dictionary in JsonIO.read_object(SPONSORS).get("sponsors", []):
		out.append(s)
	return out


func _draw() -> void:
	var w := size.x / slots
	for i: int in slots:
		var s: Dictionary = sponsors[i % sponsors.size()] if not sponsors.is_empty() else {"name": "", "bg": "#202020", "fg": "#ffffff"}
		board(self, Rect2(Vector2(w * i, 0.0), Vector2(w, size.y)), s)


## One sponsor's board on a canvas: its colour, its mark, its name large in Latin letters with
## the Korean name small under it (as real boards carry them), a dark seam at its edge.
static func board(on: CanvasItem, rect: Rect2, s: Dictionary) -> void:
	var bg := Color(str(s.get("bg", "#202020")))
	var fg := Color(str(s.get("fg", "#ffffff")))
	on.draw_rect(rect, bg)
	on.draw_rect(Rect2(rect.position, Vector2(2.0, rect.size.y)), Color(0, 0, 0, 0.35))
	var latin := str(s.get("latin", ""))
	var korean := str(s.get("name", ""))
	var h := rect.size.y
	# Each brand in its own lettering (a row of boards all in one face looks like a list).
	var kind := str(s.get("face", "plain"))
	var big: Font = UiTheme.numeric(true, true) if kind == "plain" else UiTheme.face(StringName("ad_" + kind), 800)
	var small: Font = UiTheme.font(700) if kind == "plain" or kind == "script" or kind == "slab" else UiTheme.face(StringName("ad_" + kind), 600)
	var big_px := roundi(h * (0.5 if latin != "" else 0.0))
	var small_px := roundi(h * (0.22 if latin != "" else 0.5))
	var big_w := big.get_string_size(latin, HORIZONTAL_ALIGNMENT_LEFT, -1, big_px).x if latin != "" else 0.0
	var small_w := small.get_string_size(korean, HORIZONTAL_ALIGNMENT_LEFT, -1, small_px).x
	var mark_w := h * 0.62
	var words_w := maxf(big_w, small_w)
	# Too long a name is set smaller, not cut.
	var room := rect.size.x - mark_w - h * 0.5
	if words_w > room and words_w > 0.0:
		var shrink := room / words_w
		big_px = roundi(big_px * shrink)
		small_px = maxi(roundi(small_px * shrink), 8)
		big_w *= shrink
		small_w *= shrink
		words_w = room
	var x := rect.position.x + (rect.size.x - mark_w - h * 0.18 - words_w) * 0.5
	_mark(on, str(s.get("mark", "ring")), Vector2(x + mark_w * 0.5, rect.position.y + h * 0.5), mark_w * 0.42, fg, bg)
	x += mark_w + h * 0.18
	if latin != "":
		on.draw_string(big, Vector2(x, rect.position.y + h * 0.56), latin, HORIZONTAL_ALIGNMENT_LEFT, -1, big_px, fg)
		on.draw_string(small, Vector2(x, rect.position.y + h * 0.88), korean, HORIZONTAL_ALIGNMENT_LEFT, -1, small_px, Color(fg.r, fg.g, fg.b, 0.85))
	else:
		on.draw_string(small, Vector2(x, rect.position.y + h * 0.5 + small_px * 0.36), korean, HORIZONTAL_ALIGNMENT_LEFT, -1, small_px, fg)


## A sponsor's mark: a plain shape in its colour, a different kind for each.
static func _mark(on: CanvasItem, kind: String, at: Vector2, r: float, fg: Color, bg: Color) -> void:
	match kind:
		"bars":
			for k: int in 3:
				var top := at + Vector2(-r + k * r * 0.72, r * (0.5 - 0.5 * k))
				on.draw_rect(Rect2(top, Vector2(r * 0.5, at.y + r - top.y)), fg)
		"diamond":
			on.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]), fg)
			on.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r * 0.45), at + Vector2(r * 0.45, 0), at + Vector2(0, r * 0.45), at + Vector2(-r * 0.45, 0)]), bg)
		"wave":
			for k: int in 3:
				var points := PackedVector2Array()
				for j: int in 17:
					var f := j / 16.0
					points.append(at + Vector2(-r + 2.0 * r * f, (k - 1) * r * 0.55 + sin(f * TAU) * r * 0.2))
				on.draw_polyline(points, fg, r * 0.22, true)
		"dot":
			on.draw_circle(at, r, fg)
			on.draw_circle(at + Vector2(r * 0.3, -r * 0.3), r * 0.42, bg)
		"slash":
			for k: int in 2:
				var x0 := at.x - r + k * r * 0.9
				on.draw_colored_polygon(PackedVector2Array([Vector2(x0 + r * 0.5, at.y - r), Vector2(x0 + r * 1.1, at.y - r), Vector2(x0 + r * 0.6, at.y + r), Vector2(x0, at.y + r)]), fg)
		_:
			on.draw_arc(at, r * 0.8, 0.0, TAU, 40, fg, r * 0.32, true)
