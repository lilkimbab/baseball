class_name HudCanvas
extends Control
## Base for the HUD layers: everything is drawn in units of a 1920 x 1080 screen and scaled
## to the window, so 720p and 1080p show the same layout (docs/13 S6). Positions projected
## from the 3D scene come in screen pixels; `from_screen` turns them into HUD units.

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
	draw_string_outline(f, at, line, align, width, font_size, 4, Color(UiTheme.SHADOW, UiTheme.SHADOW.a * color.a))
	draw_string(f, at, line, align, width, font_size, color)


func text_width(line: String, font_size: int, weight: int = 600) -> float:
	return UiTheme.face(&"broadcast", weight).get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## A figure or Latin capitals (a speed, a count, a score): the condensed face.
func figure(at: Vector2, line: String, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, slanted: bool = false) -> void:
	var f := UiTheme.numeric(slanted, true)
	draw_string_outline(f, at, line, align, width, font_size, 4, Color(UiTheme.SHADOW, UiTheme.SHADOW.a * color.a))
	draw_string(f, at, line, align, width, font_size, color)


## What is shouted (an umpire's call, a judgment): the heavy face, with a dark edge.
func shout(at: Vector2, line: String, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var f := UiTheme.face(&"impact")
	draw_string_outline(f, at, line, align, width, font_size, maxi(font_size / 6, 4), Color(0.03, 0.03, 0.05, 0.9 * color.a))
	draw_string(f, at, line, align, width, font_size, color)


func panel(rect: Rect2, color: Color = UiTheme.PANEL) -> void:
	draw_rect(rect, color)


## A horizontal bar filled to `fraction`.
func bar(rect: Rect2, fraction: float, color: Color) -> void:
	draw_rect(rect, Color(1, 1, 1, 0.12))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(fraction, 0.0, 1.0), rect.size.y)), color)
