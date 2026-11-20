class_name UniformArt
extends Control
## Paints one garment's texture: base colour, pinstripes, trim and lettering. The garment's
## UVs put the front on the left half and the back on the right half, with the top of the
## texture at the top of the garment, so everything is laid out in metres from the top-left
## of each half.

enum Garment { JERSEY, PANTS }

var garment: Garment = Garment.JERSEY
var style: UniformStyle
## Size of one half (front or back) in metres.
var half_size := Vector2(0.72, 0.48)
var font: Font

var _scale := 1.0


func _draw() -> void:
	if style == null:
		return
	var half_px := size.x * 0.5
	_scale = half_px / half_size.x
	if garment == Garment.JERSEY:
		_draw_jersey(half_px)
	else:
		_draw_pants(half_px)


func _m(metres: float) -> float:
	return metres * _scale


func _stripes(colour: Color) -> void:
	var gap := _m(0.022)
	var x := gap * 0.5
	while x < size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), colour, maxf(_m(0.0022), 1.0))
		x += gap


func _centred(text: String, centre: Vector2, height_m: float, colour: Color, outline: Color = Color(0, 0, 0, 0), slant: float = 0.0) -> void:
	var px := roundi(_m(height_m))
	var width := _m(0.6)
	draw_set_transform(centre, slant, Vector2.ONE)
	var at := Vector2(-width * 0.5, px * 0.36)
	if outline.a > 0.0:
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, px, maxi(roundi(px * 0.14), 2), outline)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, px, colour)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_jersey(half_px: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), style.jersey)
	if style.jersey_pinstripes:
		_stripes(style.pinstripe)
	var band := _m(0.03)
	for half: int in 2:
		var x0 := half_px * half
		# Sleeve bands at the outer ends of each half, and a band round the neck.
		draw_rect(Rect2(x0, 0.0, band, size.y), style.trim)
		draw_rect(Rect2(x0 + half_px - band, 0.0, band, size.y), style.trim)
		draw_arc(Vector2(x0 + half_px * 0.5, -_m(0.02)), _m(0.105), 0.0, PI, 32, style.trim, _m(0.022), true)
	# Front: placket piping, buttons, the team word and a small number.
	var front := half_px * 0.5
	for dx: float in [-0.012, 0.012] as Array[float]:
		draw_line(Vector2(front + _m(dx), _m(0.07)), Vector2(front + _m(dx), size.y), style.trim, maxf(_m(0.004), 1.0))
	for i: int in 4:
		draw_circle(Vector2(front, _m(0.12 + 0.09 * i)), _m(0.006), style.trim.lerp(Color.WHITE, 0.5))
	if style.wordmark != "":
		_centred(style.wordmark, Vector2(front, _m(0.2)), 0.075, style.ink, style.trim.lerp(style.jersey, 0.15), -0.07)
	if style.number > 0:
		_centred(str(style.number), Vector2(front + _m(0.085), _m(0.31)), 0.07, style.ink)
	# Back: name above a large number.
	var back := half_px * 1.5
	if style.player_name != "":
		_centred(style.player_name, Vector2(back, _m(0.15)), 0.055, style.ink)
	if style.number > 0:
		_centred(str(style.number), Vector2(back, _m(0.31)), 0.19, style.ink)


func _draw_pants(_half_px: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), style.pants)
	if style.pants_pinstripes:
		_stripes(style.pinstripe)
