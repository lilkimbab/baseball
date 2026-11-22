class_name RadarChart
extends Control
## A player's shape at a glance (docs/05 section 5): one spoke a rating group (contact, power,
## eye, running, fielding for a hitter), the filled polygon how far along each he is; a second
## outline for the man he is compared with.

var axes := PackedStringArray()
var values := PackedFloat32Array()
var compare := PackedFloat32Array()
var colour := UiTheme.ACCENT
var compare_colour := UiTheme.CYAN
var max_value := 99.0
var show_numbers := true


static func make(names: PackedStringArray, amounts: PackedFloat32Array, side: float = 260.0) -> RadarChart:
	var chart := RadarChart.new()
	chart.axes = names
	chart.values = amounts
	chart.custom_minimum_size = Vector2(side, side)
	return chart


func _init() -> void:
	custom_minimum_size = Vector2(260.0, 260.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _point(centre: Vector2, radius: float, index: int, amount: float) -> Vector2:
	var angle := -PI * 0.5 + TAU * index / maxi(axes.size(), 1)
	return centre + Vector2(cos(angle), sin(angle)) * radius * clampf(amount / max_value, 0.0, 1.0)


func _draw() -> void:
	var n := axes.size()
	if n < 3:
		return
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 38.0
	# Rings at 25, 50, 75 and 100, and the spokes.
	for ring: int in 4:
		var points := PackedVector2Array()
		for i: int in n + 1:
			points.append(_point(centre, radius, i % n, max_value * (ring + 1) / 4.0))
		draw_polyline(points, Color(1.0, 1.0, 1.0, 0.1 if ring < 3 else 0.22), 1.0, true)
	for i: int in n:
		draw_line(centre, _point(centre, radius, i, max_value), Color(1.0, 1.0, 1.0, 0.1), 1.0, true)
	_shape(centre, radius, values, colour, 0.34)
	if compare.size() == n:
		_shape(centre, radius, compare, compare_colour, 0.16)
	var font := UiTheme.font(600)
	var bold := UiTheme.font(700)
	for i: int in n:
		var out := _point(centre, radius + 20.0, i, max_value)
		var text := axes[i]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15).x
		var number := UiTheme.shown_text(values[i]) if show_numbers and i < values.size() else ""
		var nw := bold.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17).x
		var total := w + (nw + 5.0 if number != "" else 0.0)
		var at := Vector2(out.x - total * 0.5, out.y + 6.0)
		at.x = clampf(at.x, 0.0, maxf(size.x - total, 0.0))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, UiTheme.DIM)
		if number != "":
			draw_string(bold, at + Vector2(w + 5.0, 1.0), number, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, UiTheme.rating_color(values[i]))


func _shape(centre: Vector2, radius: float, amounts: PackedFloat32Array, tint: Color, fill: float) -> void:
	var n := axes.size()
	if amounts.size() != n:
		return
	var points := PackedVector2Array()
	for i: int in n:
		points.append(_point(centre, radius, i, maxf(UiTheme.shown(amounts[i]), 4.0)))
	draw_colored_polygon(points, Color(tint.r, tint.g, tint.b, fill))
	points.append(points[0])
	draw_polyline(points, tint, 2.0, true)
	for i: int in n:
		draw_circle(points[i], 3.5, tint)
