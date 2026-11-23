class_name StatBar
extends Control
## A rating as the menus show it (docs/04 section 5): its name, a bar filled to the value in
## the colour of its tier, and the number. With `second` set (a hitter's ratings against
## left-handers), a second thinner bar under the first and both numbers.

var label := ""
var value := 0.0
var second := -1.0
var max_value := 99.0
## Width kept for the name on the left (0: no name, the bar takes the whole width).
var label_width := 150.0
## Change since some earlier time, shown as +n or −n after the number (0: nothing).
var delta := 0.0


static func make(text: String, amount: float, other: float = -1.0, name_width: float = 150.0) -> StatBar:
	var bar := StatBar.new()
	bar.label = text
	bar.value = amount
	bar.second = other
	bar.label_width = name_width
	return bar


func _init() -> void:
	custom_minimum_size = Vector2(300.0, 30.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var font := UiTheme.font(600)
	var bold := UiTheme.font(700)
	var mid := size.y * 0.5
	if label_width > 0.0:
		draw_string(font, Vector2(0.0, mid + 6.0), label, HORIZONTAL_ALIGNMENT_LEFT, label_width - 8.0, 17, UiTheme.DIM)
	var number_width := 46.0 if second < 0.0 else 78.0
	if delta != 0.0:
		number_width += 40.0
	var left := label_width
	var width := maxf(size.x - left - number_width - 10.0, 20.0)
	var height := 10.0 if second < 0.0 else 7.0
	var top := mid - height * 0.5 if second < 0.0 else mid - height - 1.0
	_bar(Rect2(left, top, width, height), value)
	if second >= 0.0:
		_bar(Rect2(left, mid + 1.0, width, height), second)
	var text := UiTheme.shown_text(value)
	var at := Vector2(left + width + 10.0, mid + 7.0)
	var ink := UiTheme.rating_color(value)
	if UiTheme.ink_edge(ink).a > 0.0:
		draw_string_outline(bold, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, 3, UiTheme.ink_edge(ink))
	draw_string(bold, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, ink)
	var used := bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20).x
	if second >= 0.0:
		draw_string(font, at + Vector2(used + 4.0, 0.0), "/" + UiTheme.shown_text(second), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, UiTheme.rating_color(second))
		used += font.get_string_size("/" + UiTheme.shown_text(second), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16).x + 4.0
	if delta != 0.0:
		var word := ("+%d" if delta > 0.0 else "%d") % roundi(delta)
		draw_string(font, at + Vector2(used + 6.0, 0.0), word, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, UiTheme.GREEN if delta > 0.0 else UiTheme.RED)


func _bar(rect: Rect2, amount: float) -> void:
	var radius := rect.size.y * 0.5
	_round_rect(rect, Color(1.0, 1.0, 1.0, 0.09), radius)
	var fill := rect
	fill.size.x = maxf(rect.size.x * clampf(UiTheme.shown(amount) / max_value, 0.0, 1.0), rect.size.y)
	var colour := UiTheme.rating_color(amount)
	_round_rect(fill, colour.darkened(0.25), radius)
	# A lighter band along the top half: the bar reads as lit from above.
	var shine := fill
	shine.size.y *= 0.5
	_round_rect(shine, colour, radius * 0.5)
	# (A black bar is outlined, or it would be lost in its track.)
	if UiTheme.ink_edge(colour).a > 0.0:
		draw_rect(fill, Color(1.0, 1.0, 1.0, 0.35), false, 1.0)


func _round_rect(rect: Rect2, colour: Color, radius: float) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(roundi(radius))
	box.anti_aliasing = true
	draw_style_box(box, rect)
