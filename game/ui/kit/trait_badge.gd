class_name TraitBadge
extends Control
## A trait as a badge (the reference games show a player's special abilities as badges whose
## metal tells the tier): a hexagon in bronze, silver or gold for the best stage held, grey
## when none is held, with the trait's mark in the middle.

## Best stage held: -1 none, 0 bronze, 1 silver, 2 gold, 3 platinum (achievements).
var tier := -1
var mark := "sparkle"

const METALS := [
	[Color(0.78, 0.5, 0.3), Color(0.45, 0.25, 0.13)],
	[Color(0.86, 0.88, 0.92), Color(0.46, 0.5, 0.56)],
	[Color(1.0, 0.84, 0.36), Color(0.62, 0.42, 0.08)],
	[Color(0.86, 0.94, 1.0), Color(0.42, 0.52, 0.66)],
]


static func make(stage: int, icon_name: String, side: float = 72.0) -> TraitBadge:
	var b := TraitBadge.new()
	b.tier = stage
	b.mark = icon_name
	b.custom_minimum_size = Vector2(side, side)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.48
	var outer := _hexagon(c, r)
	var inner := _hexagon(c, r * 0.8)
	if tier < 0:
		draw_colored_polygon(outer, Color(1.0, 1.0, 1.0, 0.06))
		draw_polyline(_closed(outer), Color(1.0, 1.0, 1.0, 0.18), 1.5, true)
		draw_polyline(_closed(inner), Color(1.0, 1.0, 1.0, 0.08), 1.0, true)
	else:
		var light: Color = METALS[tier][0]
		var dark: Color = METALS[tier][1]
		# The rim lit from above, the face a shade darker, the mark in the dark of the metal.
		var colours := PackedColorArray()
		for p: Vector2 in outer:
			colours.append(dark.lerp(light, clampf(0.5 - (p.y - c.y) / (r * 2.0), 0.0, 1.0)))
		draw_polygon(outer, colours)
		var face := PackedColorArray()
		for p: Vector2 in inner:
			face.append(dark.lerp(light, clampf(0.25 + (p.y - c.y) / (r * 2.2), 0.0, 1.0)))
		draw_polygon(inner, face)
		draw_polyline(_closed(inner), Color(1.0, 1.0, 1.0, 0.35), 1.0, true)
	var tex := UiTheme.icon(mark)
	if tex != null:
		var side := r * 0.95
		var tint := Color(1.0, 1.0, 1.0, 0.3) if tier < 0 else Color(0.08, 0.06, 0.04, 0.88)
		draw_texture_rect(tex, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false, tint)


static func _hexagon(c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i: int in 6:
		var a := deg_to_rad(60.0 * i - 90.0)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	out.append(points[0])
	return out
