class_name Emblem
extends Control
## A club's emblem (docs/13 S11-9; the clubs are fictional, so are their marks): a shield, a
## roundel or a pennant diamond in the club's colours — which one, and the device on it (a
## star, stitches, a stripe), from the club's id — with the first letter of its name. Drawn,
## not painted: any size, any club.

var team: Team


static func make(club: Team, side: float = 64.0) -> Emblem:
	var e := Emblem.new()
	e.team = club
	e.custom_minimum_size = Vector2(side, side)
	e.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	e.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return e


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_emblem(self, team, Rect2(Vector2.ZERO, size))


## Draws a club's emblem into a rectangle of any canvas item.
static func draw_emblem(on: CanvasItem, club: Team, rect: Rect2) -> void:
	var primary := club.primary if club != null else Color(0.25, 0.3, 0.4)
	var accent := club.accent if club != null else Color(0.9, 0.9, 0.9)
	var id := club.id if club != null else "none"
	var kind := absi(hash(id + ":emblem")) % 3
	var device := absi(hash(id + ":device")) % 3
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.5
	var outline := _outline(kind, c, r)
	# A dark edge, a white edge, the club's colour: three shapes, each a little smaller.
	on.draw_colored_polygon(_scaled(outline, c, 1.0), Color(0.02, 0.04, 0.1, 0.9))
	on.draw_colored_polygon(_scaled(outline, c, 0.93), Color(0.97, 0.97, 0.99))
	on.draw_colored_polygon(_scaled(outline, c, 0.84), primary.darkened(0.25))
	# The upper part lighter: the mark is lit from above.
	var upper := PackedVector2Array()
	for p: Vector2 in _scaled(outline, c, 0.84):
		upper.append(Vector2(p.x, minf(p.y, c.y + r * 0.08)))
	on.draw_colored_polygon(upper, primary.lightened(0.08))
	match device:
		0:
			# A band of the second colour across the foot.
			var band := PackedVector2Array()
			for p: Vector2 in _scaled(outline, c, 0.84):
				band.append(Vector2(p.x, maxf(p.y, c.y + r * 0.42)))
			on.draw_colored_polygon(band, accent)
		1:
			# Two thin stripes of the second colour across the head.
			for k: float in [0.5, 0.36]:
				var stripe := PackedVector2Array()
				for p: Vector2 in _scaled(outline, c, 0.84):
					stripe.append(Vector2(p.x, clampf(p.y, c.y - r * k, c.y - r * (k - 0.07))))
				on.draw_colored_polygon(stripe, accent)
		2:
			# A star over the letter.
			var star := PackedVector2Array()
			for i: int in 10:
				var a := -PI * 0.5 + TAU * i / 10.0
				star.append(c + Vector2(0.0, -r * 0.5) + Vector2(cos(a), sin(a)) * r * (0.16 if i % 2 == 0 else 0.07))
			on.draw_colored_polygon(star, accent)
	var letter := club.short_name.substr(0, 1) if club != null and club.short_name != "" else "?"
	var font := UiTheme.display(700)
	var px := maxi(roundi(r * 0.92), 8)
	var w := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	var ink := Color.WHITE if primary.get_luminance() < 0.62 else Color(0.08, 0.1, 0.16)
	var at := Vector2(c.x - w * 0.5, c.y + px * 0.36 + (r * 0.06 if device == 2 else 0.0))
	on.draw_string_outline(font, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, maxi(roundi(r * 0.12), 2), Color(0.0, 0.0, 0.0, 0.45))
	on.draw_string(font, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, ink)


static func _scaled(points: PackedVector2Array, centre: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(centre + (p - centre) * k)
	return out


static func _outline(kind: int, c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match kind:
		0:
			# A shield: flat top with rounded shoulders, sides curving in to a point.
			for i: int in 9:
				var a := PI + PI * i / 8.0
				pts.append(c + Vector2(cos(a) * r * 0.86, -r * 0.55 + sin(a) * r * 0.36))
			for i: int in 9:
				var t := float(i) / 8.0
				pts.append(c + Vector2(r * 0.86 * (1.0 - t * t), -r * 0.55 + r * 1.5 * t))
			for i: int in range(7, 0, -1):
				var t := float(i) / 8.0
				pts.append(c + Vector2(-r * 0.86 * (1.0 - t * t), -r * 0.55 + r * 1.5 * t))
		1:
			for i: int in 32:
				var a := TAU * i / 32.0
				pts.append(c + Vector2(cos(a), sin(a)) * r * 0.95)
		_:
			# A diamond with its corners cut: a base path seen from above.
			for corner: Array in [[0.0, -1.0], [1.0, 0.0], [0.0, 1.0], [-1.0, 0.0]]:
				var v := Vector2(float(corner[0]), float(corner[1])) * r * 0.98
				var side := Vector2(-v.y, v.x).normalized() * r * 0.13
				pts.append(c + v * 0.87 - side)
				pts.append(c + v * 0.87 + side)
	return pts
