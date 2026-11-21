class_name UniformArt
extends Control
## Paints one garment's texture (docs/13 S11-9): cloth colour, pinstripes, trim, lettering and
## patches, laid out at the sizes of a real uniform. The garment's UVs put the front on the
## left half and the back on the right half (mirrored, so lettering reads from behind), with
## the top of the texture at the top of the garment, so everything is placed in metres from the
## top-left of each half.
##
## Sizes (KBO and MLB uniforms; the numbers are regulation, the rest measured from photographs):
##   number on the back 20 cm (8 in) tall, on the front 10 cm (4 in);
##   name on the back 6.5 cm tall, above the number;
##   word across the chest 8 to 9 cm tall (its capitals), 30 cm or so wide;
##   outline round letters and numbers 4 mm; piping 5 mm; buttons 11 mm, 9 cm apart.

enum Garment { JERSEY, PANTS }

const BACK_NUMBER := 0.203
const FRONT_NUMBER := 0.102
const NAME_HEIGHT := 0.065
const WORD_HEIGHT := 0.085
const OUTLINE := 0.0042
const PIPING := 0.005

var garment: Garment = Garment.JERSEY
var style: UniformStyle
## Size of one half (front or back) in metres.
var half_size := Vector2(0.72, 0.48)
## Places on the jersey, in metres down from its top: the point of the V of the neck, the line
## of the chest, the belt.
var neck_point := 0.13
var chest := 0.25
## The sleeves, in the front half's metres: for each arm {"shoulder": Vector2, "along": Vector2
## (unit, toward the elbow), "hem": float (m from the shoulder to the sleeve's end)}.
var sleeves: Array[Dictionary] = []
## The pinstripes are laid on along the garment's second UV map instead (SkinnedPuppet, when
## the model has it), evenly round the legs and sleeves.
var stripes_on_wrap := false

var _scale := 1.0
static var _cap_ratio: Dictionary[int, float] = {}


## The face of the letter on a cap or helmet for a uniform.
static func cap_font(s: UniformStyle) -> Font:
	return UniformFonts.face(&"tuscan" if s != null and s.lettering == &"tuscan" else &"block")


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


## How tall a face's capitals are, as a share of its size.
static func cap_ratio(face: Font) -> float:
	var key := face.get_instance_id()
	if _cap_ratio.has(key):
		return _cap_ratio[key]
	var ratio := 0.7
	var rids := face.get_rids()
	if not rids.is_empty():
		var server := TextServerManager.get_primary_interface()
		var glyph := server.font_get_glyph_index(rids[0], 200, "H".unicode_at(0), 0)
		server.font_render_glyph(rids[0], Vector2i(200, 0), glyph)
		var drawn := server.font_get_glyph_size(rids[0], Vector2i(200, 0), glyph)
		if drawn.y > 20.0:
			ratio = drawn.y / 200.0
	_cap_ratio[key] = ratio
	return ratio


func _stripes(colour: Color) -> void:
	var gap := _m(0.025)
	var x := gap * 0.5
	while x < size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), colour, maxf(_m(0.0018), 1.0))
		x += gap


## A word or number with its capitals `height_m` tall, centred on `centre` (px), turned by
## `slant`; edged in the style's second colour when it has one. Returns its width (px).
func _lettered(face: Font, text: String, centre: Vector2, height_m: float, colour: Color, slant: float = 0.0, edge: Color = Color(0, 0, 0, 0)) -> float:
	var ratio := cap_ratio(face)
	var px := maxi(roundi(_m(height_m) / ratio), 4)
	var width := face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	draw_set_transform(centre, slant, Vector2.ONE)
	var at := Vector2(-width * 0.5, _m(height_m) * 0.5)
	if edge.a > 0.0:
		draw_string_outline(face, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, maxi(roundi(_m(OUTLINE) * 2.0), 2), edge)
	draw_string(face, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, colour)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return width


## A word set on an arc that rises in the middle (`radius_m` to the feet of its letters).
func _arched(face: Font, text: String, centre: Vector2, height_m: float, radius_m: float, colour: Color, edge: Color = Color(0, 0, 0, 0)) -> void:
	var ratio := cap_ratio(face)
	var px := maxi(roundi(_m(height_m) / ratio), 4)
	var widths: Array[float] = []
	var total := 0.0
	for i: int in text.length():
		var w := face.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
		widths.append(w)
		total += w
	var radius := _m(radius_m)
	var pivot := centre + Vector2(0.0, radius + _m(height_m) * 0.5)
	for pass_index: int in 2:
		if pass_index == 0 and edge.a <= 0.0:
			continue
		var run := -total * 0.5
		for i: int in text.length():
			var angle := (run + widths[i] * 0.5) / radius
			draw_set_transform(pivot + Vector2(sin(angle), -cos(angle)) * radius, angle, Vector2.ONE)
			var at := Vector2(-widths[i] * 0.5, 0.0)
			if pass_index == 0:
				draw_string_outline(face, at, text[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, maxi(roundi(_m(OUTLINE) * 2.0), 2), edge)
			else:
				draw_string(face, at, text[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, colour)
			run += widths[i]
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The tail under a script word: from under its last letter back under its first, tapering.
func _tail(centre: Vector2, width: float, slant: float, colour: Color, edge: Color) -> void:
	var from := width * 0.5 - _m(0.012)
	var to := -width * 0.5 + _m(0.03)
	var drop := _m(WORD_HEIGHT) * 0.5 + _m(0.014)
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	for i: int in 25:
		var f := i / 24.0
		var x := lerpf(to, from, f)
		# Bowed a little, thick under the end of the word and thinning to a point.
		var y := drop + _m(0.012) * sin(f * PI) * 0.6 - _m(0.004) * f
		var thick := _m(0.003 + 0.016 * pow(f, 0.75))
		upper.append(Vector2(x, y))
		lower.append(Vector2(x, y + thick))
	lower.reverse()
	var shape := upper + lower
	draw_set_transform(centre, slant, Vector2.ONE)
	if edge.a > 0.0:
		var closed := shape.duplicate()
		closed.append(shape[0])
		draw_polyline(closed, edge, _m(OUTLINE) * 2.0, true)
	draw_colored_polygon(shape, colour)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _rounded(rect: Rect2, radius: float, colour: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(roundi(radius))
	box.anti_aliasing = true
	draw_style_box(box, rect)


func _draw_jersey(half_px: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), style.jersey)
	if style.official:
		_draw_polo(half_px)
		return
	if style.jersey_pinstripes and not stripes_on_wrap:
		_stripes(style.pinstripe)
	var block := UniformFonts.face(&"tuscan" if style.lettering == &"tuscan" else &"block")
	var front := half_px * 0.5
	var back := half_px * 1.5
	_sleeve_trim(half_px)

	# The front: the button strip from the point of the V down, its two seams, the piping
	# either side of it, the buttons.
	var strip := _m(0.016)
	var top := _m(neck_point - 0.01)
	var seam := style.jersey.darkened(0.1)
	for side: float in [-1.0, 1.0] as Array[float]:
		draw_line(Vector2(front + side * strip, top), Vector2(front + side * strip, size.y), seam, maxf(_m(0.0012), 1.0))
		if style.piping:
			var x := front + side * (strip + _m(0.006))
			draw_line(Vector2(x, top - _m(0.02)), Vector2(x, size.y), style.trim, _m(PIPING))
	var button := style.jersey.lerp(Color(0.86, 0.86, 0.84), 0.6) if style.jersey.get_luminance() > 0.5 else style.jersey.lightened(0.25)
	var y := neck_point + 0.03
	while _m(y) < size.y - _m(0.03):
		draw_circle(Vector2(front, _m(y)), _m(0.0055), button.darkened(0.25))
		draw_circle(Vector2(front, _m(y)), _m(0.0045), button)
		y += 0.09

	# The word across the chest, and the small number under it on the wearer's left.
	var word_at := Vector2(front, _m(chest - 0.05))
	if style.wordmark != "":
		if style.lettering == &"script":
			var face := UniformFonts.face(&"script")
			var slant := -0.1
			var width := _lettered(face, style.wordmark, word_at, WORD_HEIGHT, style.ink, slant, style.outline)
			if style.tail:
				_tail(word_at, width, slant, style.ink, style.outline)
		elif style.arch:
			_arched(block, style.wordmark, word_at, WORD_HEIGHT * 0.82, 0.42, style.ink, style.outline)
		else:
			_lettered(block, style.wordmark, word_at, WORD_HEIGHT * 0.82, style.ink, 0.0, style.outline)
	if style.number > 0 and style.front_number:
		_lettered(block, str(style.number), Vector2(front + _m(0.085), _m(chest + 0.085)), FRONT_NUMBER, style.ink, 0.0, style.outline)
	# A sponsor's small patch high on the wearer's right chest.
	if not style.chest_sponsor.is_empty():
		_sponsor(style.chest_sponsor, Vector2(front - _m(0.1), _m(neck_point - 0.005)), 0.0, 0.062, 0.02)

	# The back: the name over a large number.
	if style.player_name != "":
		var name_face := UniformFonts.face(style.name_face)
		var name_at := Vector2(back, _m(0.125))
		var height := NAME_HEIGHT * (0.8 if style.player_name.length() > 4 else 1.0)
		if style.name_arch:
			_arched(name_face, style.player_name, name_at, height, 0.5, style.ink, style.outline)
		else:
			_lettered(name_face, style.player_name, name_at, height, style.ink, 0.0, style.outline)
	if style.number > 0:
		_lettered(block, str(style.number), Vector2(back, _m(0.285)), BACK_NUMBER, style.ink, 0.0, style.outline)


## An umpire's polo shirt: a short buttoned opening under the collar, a pocket on the wearer's
## left chest with the league's badge over it, the badge on one sleeve and his number on the
## other, each sleeve finished with a ribbed cuff.
func _draw_polo(half_px: float) -> void:
	var front := half_px * 0.5
	var seam := style.jersey.lightened(0.09)
	var thin := maxf(_m(0.0014), 1.0)
	# The opening: a strip from the collar to a hand below the point of the V, two buttons.
	var strip := _m(0.017)
	var top := _m(neck_point - 0.03)
	var foot := _m(neck_point + 0.085)
	draw_rect(Rect2(front - strip, top, strip * 2.0, foot - top), style.jersey.lightened(0.03))
	for x: float in [front - strip, front + strip] as Array[float]:
		draw_line(Vector2(x, top), Vector2(x, foot), seam, thin)
	draw_line(Vector2(front - strip, foot), Vector2(front + strip, foot), seam, thin)
	for y: float in [neck_point + 0.012, neck_point + 0.058] as Array[float]:
		draw_circle(Vector2(front, _m(y)), _m(0.0055), Color(0.2, 0.2, 0.22))
		draw_circle(Vector2(front, _m(y)), _m(0.0042), Color(0.1, 0.1, 0.12))
	# The pocket (a stitched outline, its foot coming to a shallow point) and the badge.
	var pocket := Rect2(front + _m(0.05), _m(chest - 0.035), _m(0.1), _m(0.105))
	var outline := PackedVector2Array([pocket.position, Vector2(pocket.end.x, pocket.position.y), pocket.end - Vector2(0.0, _m(0.012)),
		Vector2(pocket.get_center().x, pocket.end.y), Vector2(pocket.position.x, pocket.end.y - _m(0.012)), pocket.position])
	draw_polyline(outline, seam, thin * 1.4, true)
	_badge(Vector2(pocket.get_center().x, pocket.position.y - _m(0.03)), 0.036, 0.0)
	# Sleeves: a ribbed cuff, the league's badge on the wearer's left, his number on his right.
	for i: int in sleeves.size():
		var sleeve := sleeves[i]
		var along: Vector2 = sleeve["along"]
		for half: int in 2:
			var flip := 1.0 if half == 0 else -1.0
			var origin := Vector2(half_px * half, 0.0) if half == 0 else Vector2(half_px * 2.0, 0.0)
			var shoulder := origin + Vector2(_m(float(sleeve["shoulder"].x)) * flip, _m(float(sleeve["shoulder"].y)))
			var dir := Vector2(along.x * flip, along.y)
			var side := Vector2(-dir.y, dir.x)
			var hem := shoulder + dir * _m(float(sleeve["hem"]))
			var reach := side * _m(0.085)
			draw_colored_polygon(PackedVector2Array([hem - reach, hem + reach, hem - dir * _m(0.022) + reach, hem - dir * _m(0.022) - reach]), style.jersey.lightened(0.05))
			if half != 0:
				continue
			var spot := shoulder + dir * _m(float(sleeve["hem"]) * 0.52) + Vector2(-along.y, along.x) * _m(0.02) * (-1.0 if i == 0 else 1.0)
			var turn := dir.angle() - PI * 0.5
			if i == 0:
				_badge(spot, 0.04, turn)
			elif style.number > 0:
				_lettered(UniformFonts.face(&"block"), str(style.number), spot, 0.052, style.ink, turn)


## The league's badge: a shield with its initials.
func _badge(centre: Vector2, height_m: float, turn: float) -> void:
	var h := _m(height_m)
	var w := h * 0.82
	draw_set_transform(centre, turn, Vector2.ONE)
	var shield := PackedVector2Array([Vector2(-w * 0.5, -h * 0.5), Vector2(w * 0.5, -h * 0.5), Vector2(w * 0.5, h * 0.12), Vector2(0.0, h * 0.5), Vector2(-w * 0.5, h * 0.12)])
	draw_colored_polygon(shield, Color(0.93, 0.93, 0.94))
	var inner := PackedVector2Array()
	for p: Vector2 in shield:
		inner.append(p * 0.84)
	draw_colored_polygon(inner, Color(0.1, 0.16, 0.38))
	draw_rect(Rect2(-w * 0.42, -h * 0.42, w * 0.84, h * 0.16), Color(0.75, 0.12, 0.14))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_lettered(UiTheme.numeric(false, true), UniformStyle.LEAGUE, centre + Vector2(0.0, h * 0.02).rotated(turn), height_m * 0.26, Color(0.96, 0.96, 0.96), turn)


## Bands or piping at the ends of the sleeves, the club's patch on the wearer's left sleeve and
## a sponsor's on his right (on the front of each, which is what the texture's front half covers).
func _sleeve_trim(half_px: float) -> void:
	for i: int in sleeves.size():
		var sleeve := sleeves[i]
		var along: Vector2 = sleeve["along"]
		var across := Vector2(-along.y, along.x)
		for half: int in 2:
			# The back half is the front's mirror image.
			var flip := 1.0 if half == 0 else -1.0
			var origin := Vector2(half_px * half, 0.0) if half == 0 else Vector2(half_px * 2.0, 0.0)
			var shoulder := origin + Vector2(_m(float(sleeve["shoulder"].x)) * flip, _m(float(sleeve["shoulder"].y)))
			var dir := Vector2(along.x * flip, along.y)
			var side := Vector2(across.x * flip, across.y)
			var hem := shoulder + dir * _m(float(sleeve["hem"]))
			var bands: Array[Vector2] = []
			if style.sleeve_bands == 1:
				bands.append(Vector2(0.004, 0.03))
			elif style.sleeve_bands == 2:
				bands.append(Vector2(0.004, 0.012))
				bands.append(Vector2(0.022, 0.012))
			elif style.piping:
				bands.append(Vector2(0.0, PIPING * 1.6))
			for band: Vector2 in bands:
				var a := hem - dir * _m(band.x)
				var b := hem - dir * _m(band.x + band.y)
				# Across the sleeve and no further (the ribs are a hand's breadth beyond it).
				var reach := side * _m(0.085)
				draw_colored_polygon(PackedVector2Array([a - reach, a + reach, b + reach, b - reach]), style.trim)
			if half != 0:
				continue
			# Half way down the sleeve, toward the outside of the arm.
			var spot := shoulder + dir * _m(float(sleeve["hem"]) * 0.55) + side * _m(0.022) * (-1.0 if i == 0 else 1.0)
			var turn := dir.angle() - PI * 0.5
			# Wearer's left arm (the first): the club's round patch. His right: a sponsor's.
			if i == 0 and style.patch != "":
				draw_circle(spot, _m(0.034), style.trim)
				draw_circle(spot, _m(0.029), style.jersey.lerp(Color.WHITE, 0.3) if style.trim.get_luminance() < 0.5 else style.jersey.darkened(0.6))
				_lettered(cap_font(style), style.patch, spot, 0.03, style.trim, turn)
			elif i == 1 and not style.sleeve_sponsor.is_empty():
				_sponsor(style.sleeve_sponsor, spot, turn, 0.07, 0.034)


## A sponsor's patch: its name on its colour.
func _sponsor(sponsor: Dictionary, centre: Vector2, turn: float, width_m: float, height_m: float) -> void:
	var bg := Color(str(sponsor.get("bg", "#222222")))
	var fg := Color(str(sponsor.get("fg", "#ffffff")))
	draw_set_transform(centre, turn, Vector2.ONE)
	var box := Rect2(Vector2(-_m(width_m), -_m(height_m)) * 0.5, Vector2(_m(width_m), _m(height_m)))
	_rounded(box, _m(0.004), bg)
	var face := UiTheme.numeric(false, true)
	var words := str(sponsor.get("latin", sponsor.get("name", "")))
	var px := maxi(roundi(_m(height_m) * 0.62), 4)
	var width := face.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	if width > box.size.x * 0.88:
		px = maxi(roundi(px * box.size.x * 0.88 / width), 4)
		width = face.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	draw_string(face, Vector2(-width * 0.5, px * 0.36), words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, fg)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_pants(half_px: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), style.pants)
	if style.pants_pinstripes and not stripes_on_wrap:
		_stripes(style.pinstripe)
	# (The piping down the sides is a strip of its own on the model, "PantsStripe": painted
	# here, at the edges of the front and back views, it landed on whatever stood furthest out.)
	var seam := style.pants.darkened(0.14)
	for half: int in 2:
		var x0 := half_px * half
		# Belt loops round the waistband.
		for f: float in [0.18, 0.38, 0.62, 0.82] as Array[float]:
			draw_rect(Rect2(x0 + half_px * f - _m(0.006), 0.0, _m(0.012), _m(0.042)), style.pants.darkened(0.1))
	# The fly in front, the two hip pockets behind (a welt and a button each).
	var front := half_px * 0.5
	draw_line(Vector2(front + _m(0.014), _m(0.045)), Vector2(front + _m(0.014), _m(0.17)), seam, maxf(_m(0.0015), 1.0))
	var back := half_px * 1.5
	for side: float in [-1.0, 1.0] as Array[float]:
		var pocket := Rect2(back + side * _m(0.085) - _m(0.062), _m(0.105), _m(0.124), _m(0.008))
		draw_rect(pocket, seam)
		draw_circle(Vector2(pocket.get_center().x, pocket.end.y + _m(0.012)), _m(0.0045), style.pants.darkened(0.2))
