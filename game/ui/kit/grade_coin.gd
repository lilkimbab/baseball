class_name GradeCoin
extends Control
## A player's grade as a coin (after the reference's lists): gold for S and A, silver for B,
## bronze for C, steel below, with a rim, a shine across the top and the letter struck in it.

var grade := "C"

const METALS := {
	"S": [Color(1.0, 0.9, 0.45), Color(0.86, 0.5, 0.06)], "A": [Color(1.0, 0.86, 0.4), Color(0.8, 0.52, 0.1)],
	"B": [Color(0.93, 0.95, 0.99), Color(0.52, 0.58, 0.68)], "C": [Color(0.92, 0.68, 0.46), Color(0.55, 0.3, 0.14)],
}


static func make(letter: String, side: float = 30.0) -> GradeCoin:
	var c := GradeCoin.new()
	c.grade = letter
	c.custom_minimum_size = Vector2(side, side)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_coin(self, grade, Rect2(Vector2.ZERO, size))


static func draw_coin(on: CanvasItem, letter: String, rect: Rect2) -> void:
	var metal: Array = METALS.get(letter.substr(0, 1), [Color(0.7, 0.75, 0.82), Color(0.34, 0.38, 0.46)])
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.5
	on.draw_circle(c + Vector2(0.0, r * 0.08), r, Color(0.0, 0.0, 0.0, 0.4))
	on.draw_circle(c, r, (metal[1] as Color).darkened(0.3))
	on.draw_circle(c, r * 0.9, metal[1])
	on.draw_circle(c - Vector2(0.0, r * 0.12), r * 0.78, metal[0])
	on.draw_circle(c, r * 0.72, (metal[0] as Color).lerp(metal[1], 0.45))
	var font := UiTheme.numeric(false)
	var px := maxi(roundi(r * 1.25), 8)
	var w := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	var at := Vector2(c.x - w * 0.5, c.y + px * 0.35)
	on.draw_string(font, at + Vector2(0.0, 1.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, Color(1.0, 1.0, 1.0, 0.5))
	on.draw_string(font, at, letter, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, (metal[1] as Color).darkened(0.55))
