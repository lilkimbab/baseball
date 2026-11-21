class_name FieldDiagram
extends Control
## A small ballpark seen from above with a number at each position (docs/05 section 5): how
## well a player plays each one (the player card), or who stands there (a line-up).

## Position.Kind -> text shown there; `strong` positions are drawn in the accent.
var marks: Dictionary[int, String] = {}
var strong: Dictionary[int, bool] = {}

## Where each position stands, as fractions of the diagram (x across, y down; home at bottom).
const SPOTS := {
	Position.Kind.P: Vector2(0.5, 0.62), Position.Kind.C: Vector2(0.5, 0.9),
	Position.Kind.B1: Vector2(0.69, 0.6), Position.Kind.B2: Vector2(0.6, 0.47),
	Position.Kind.B3: Vector2(0.31, 0.6), Position.Kind.SS: Vector2(0.4, 0.47),
	Position.Kind.LF: Vector2(0.2, 0.3), Position.Kind.CF: Vector2(0.5, 0.17), Position.Kind.RF: Vector2(0.8, 0.3),
}


func _init() -> void:
	custom_minimum_size = Vector2(300.0, 250.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var home := Vector2(size.x * 0.5, size.y * 0.93)
	var reach := minf(size.x * 0.7, size.y * 0.9)
	# The outfield: a quarter circle of grass from foul line to foul line.
	var grass := PackedVector2Array([home])
	for i: int in 25:
		var a := deg_to_rad(-135.0 + 90.0 * i / 24.0)
		grass.append(home + Vector2(cos(a), sin(a)) * reach)
	draw_colored_polygon(grass, Color(0.16, 0.42, 0.2, 0.95))
	var warning := PackedVector2Array()
	for i: int in 25:
		var a := deg_to_rad(-135.0 + 90.0 * i / 24.0)
		warning.append(home + Vector2(cos(a), sin(a)) * reach)
	draw_polyline(warning, Color(0.62, 0.42, 0.26), 5.0, true)
	# The infield dirt and the grass diamond inside it.
	var dirt := PackedVector2Array([home])
	for i: int in 17:
		var a := deg_to_rad(-135.0 + 90.0 * i / 16.0)
		dirt.append(home + Vector2(cos(a), sin(a)) * reach * 0.52)
	draw_colored_polygon(dirt, Color(0.6, 0.41, 0.25))
	var base := reach * 0.36
	var first := home + Vector2(cos(deg_to_rad(-45.0)), sin(deg_to_rad(-45.0))) * base
	var third := home + Vector2(cos(deg_to_rad(-135.0)), sin(deg_to_rad(-135.0))) * base
	var second := home + Vector2(0.0, -base * sqrt(2.0))
	var inset := 0.14
	var centre := (home + second) * 0.5
	var inner := PackedVector2Array()
	for corner: Vector2 in [home, first, second, third]:
		inner.append(corner.lerp(centre, inset * 2.0))
	draw_colored_polygon(inner, Color(0.18, 0.46, 0.22))
	draw_line(home, home + (first - home) * 2.75, Color(1.0, 1.0, 1.0, 0.7), 1.5, true)
	draw_line(home, home + (third - home) * 2.75, Color(1.0, 1.0, 1.0, 0.7), 1.5, true)
	for bag: Vector2 in [first, second, third]:
		draw_rect(Rect2(bag - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), Color.WHITE)
	draw_circle(home.lerp(second, 0.5), 7.0, Color(0.6, 0.41, 0.25))
	var font := UiTheme.font(700)
	for kind: int in marks:
		if not SPOTS.has(kind):
			continue
		var at := Vector2(SPOTS[kind]) * size
		var text := marks[kind]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17).x
		var box := Rect2(at - Vector2(w * 0.5 + 8.0, 14.0), Vector2(w + 16.0, 26.0))
		var on := bool(strong.get(kind, false))
		var plate := StyleBoxFlat.new()
		plate.bg_color = Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.95) if on else Color(0.02, 0.04, 0.08, 0.78)
		plate.set_corner_radius_all(5)
		plate.anti_aliasing = true
		draw_style_box(plate, box)
		draw_string(font, Vector2(at.x - w * 0.5, at.y + 5.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, Color(0.08, 0.06, 0.02) if on else UiTheme.INK)
