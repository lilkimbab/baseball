class_name PlateFace
extends Control
## The drawn shape behind a button, a tile or an orb (ui/kit/plate.gdshader): put behind its
## owner, it fills it. Styles are named in UiTheme.PLATES; a state on top of the style lights
## it (hover), presses it or marks it chosen.

const PAD := 16.0
const SHADER := preload("res://ui/kit/plate.gdshader")

var style := "button"
var overrides: Dictionary = {}
var _material: ShaderMaterial


static func behind(owner_control: Control, style_name: String, more: Dictionary = {}) -> PlateFace:
	var face := PlateFace.new()
	face.style = style_name
	face.overrides = more
	face.show_behind_parent = true
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	owner_control.add_child(face)
	return face


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material = _material
	resized.connect(_apply)


func _ready() -> void:
	_apply()


## Changes what the face looks like (another style, or values over it).
func set_look(style_name: String, more: Dictionary = {}) -> void:
	style = style_name
	overrides = more
	_apply()


## One value of the look (glow as the pointer comes over, say).
func set_value(name: StringName, value: Variant) -> void:
	_material.set_shader_parameter(name, value)


func _apply() -> void:
	# Everything a look may leave out goes back to nothing first (a hover's glow must not stay).
	var look := {"radius": 3.0, "cut": 0.0, "skew": 0.0, "head": 0.0, "gloss": 0.0, "hatch": 0.0, "glow": 0.0, "shadow": 0.0,
		"bar_height": 0.0, "border_width": 1.0, "inner": Color(0, 0, 0, 0), "border": Color(1, 1, 1, 0.14)}
	look.merge(UiTheme.PLATES.get(style, {}) as Dictionary, true)
	look.merge(overrides, true)
	for key: String in look:
		_material.set_shader_parameter(key, look[key])
	_material.set_shader_parameter(&"size", size)
	_material.set_shader_parameter(&"pad", PAD)
	if look.has("round"):
		_material.set_shader_parameter(&"radius", minf(size.x, size.y) * 0.5)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-PAD, -PAD, size.x + PAD * 2.0, size.y + PAD * 2.0), Color.WHITE)
