class_name GameButton
extends Button
## A button of the menus (docs/05 section 5): a drawn shape behind its words (PlateFace).
## "button": quiet glass that turns white under the pointer (dark words on it); "primary": the
## brand red, for a screen's main action; "segment": one of a row of choices, white when
## chosen; "tab": words over a line that lights in `tint` when chosen.

var look := "button"
## The colour of a chosen tab's line (the part of the game it belongs to).
var tint := UiTheme.BRAND
var _face: PlateFace
var _shown := ""

const PADS := {"button": [18.0, 10.0], "primary": [28.0, 13.0], "segment": [16.0, 8.0], "tab": [20.0, 12.0]}


static func make(text_value: String, action: Callable, icon_name: String = "", look_name: String = "button", width: float = 0.0) -> GameButton:
	var b := GameButton.new()
	b.text = text_value
	b.look = look_name
	if icon_name != "":
		b.icon = UiTheme.icon(icon_name)
		b.expand_icon = true
	if width > 0.0:
		b.custom_minimum_size.x = width
	if action.is_valid():
		b.pressed.connect(action)
	return b


func _init() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _ready() -> void:
	_face = PlateFace.behind(self, look)
	var pad: Array = PADS.get(look, PADS["button"])
	var side := float(pad[0]) if text != "" else float(pad[1])
	for state: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, UiTheme.margins(side, float(pad[1]), side, float(pad[1])))
	if look == "segment":
		add_theme_font_size_override("font_size", 18)
	_show_state()


func _state() -> String:
	if disabled:
		return look + "_off"
	if toggle_mode and button_pressed:
		return look + "_on"
	if is_pressed():
		return look + "_down"
	if is_hovered() or has_focus():
		return look + "_hover"
	return look


func _process(_delta: float) -> void:
	_show_state()


func _show_state() -> void:
	var state := _state()
	if state == _shown or _face == null:
		return
	_shown = state
	var style := state if UiTheme.PLATES.has(state) else look
	var more := {}
	if state == "tab_on":
		more = {"bar": tint, "bottom": Color(tint.r, tint.g, tint.b, 0.2), "top": Color(tint.r, tint.g, tint.b, 0.0)}
	_face.set_look(style, more)
	var dark := (UiTheme.PLATES[style] as Dictionary).has("dark")
	var ink := UiTheme.NAVY_TEXT if dark else Color.WHITE
	if look == "tab" and state != "tab_on" and state != "tab_hover":
		ink = Color(1.0, 1.0, 1.0, 0.62)
	if disabled:
		ink = Color(1.0, 1.0, 1.0, 0.35)
	for colour: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color",
			"icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color", "icon_disabled_color"]:
		add_theme_color_override(colour, ink)
