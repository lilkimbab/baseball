class_name GameButton
extends Button
## A button of the menus (docs/04 section 5): a drawn shape behind its words (PlateFace), its
## look chosen by what it does (the user, 2026-11-23: "every button looks the same everywhere —
## change shapes, colours, effects, as other games do"):
##
## - "button": an outline on a slant; under the pointer its screen's colour (Screen.tint: the
##   league's gold, the career's blue …) sweeps in from the left.
## - "primary": a screen's main action, the brand red; light passes over it under the pointer.
## - "gold": a reward or a purchase, gold with dark words; light passes over it.
## - "danger": something that cannot be undone; it turns red under the pointer.
## - "menu": a line of the title's menu: large words on a dark slant; the red sweeps in and the
##   words step right.
## - "segment": one of a row of choices, white when chosen; "tab": words over a line that lights
##   in `tint` when chosen.
## Every look presses in a little when pressed.

const LOOKS: Array[String] = ["button", "primary", "gold", "danger", "menu", "segment", "tab"]
const PADS := {"button": [18.0, 10.0], "primary": [36.0, 16.0], "gold": [36.0, 16.0], "danger": [18.0, 10.0], "menu": [34.0, 14.0], "segment": [16.0, 8.0], "tab": [20.0, 12.0]}
## The looks that must stand out from the rest: larger, in the heading face (Giants Bold, as
## the broadcast graphics), and how large (the user, 2026-11-23: "those buttons' words should be
## bigger and stand out from the other buttons").
const HEADLINE := {"primary": 27, "gold": 27, "menu": 32}
## How long the fill takes to sweep in (s), and how often light passes over a lit button (s).
const SWEEP := 0.16
const SHINE_EVERY := 1.6

var look := "button"
## The colour of a chosen tab's line, and of an ordinary button's fill (its screen's, unless set).
var tint := UiTheme.BRAND
var _face: PlateFace
var _shown := ""
var _hover := 0.0
var _shine := 0.0
var _press := 0.0
var _margins: StyleBoxEmpty
## Drawn as if the pointer were on it (the capture tools: they never move the pointer).
var preview_lit := false


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
	# An ordinary button takes its screen's colour (its tabs and lines already do).
	if (look == "button") and tint == UiTheme.BRAND:
		var up := get_parent()
		while up != null and not (up is Screen):
			up = up.get_parent()
		if up != null:
			tint = (up as Screen).tint
	_face = PlateFace.behind(self, look)
	mouse_entered.connect(func() -> void:
		if not disabled:
			GameAudio.ui(get_tree(), "ui/move"))
	pressed.connect(func() -> void: GameAudio.ui(get_tree(), "ui/confirm" if look == "primary" or look == "gold" or look == "menu" else "ui/select"))
	var pad: Array = PADS.get(look, PADS["button"])
	var side := float(pad[0]) if text != "" else float(pad[1])
	_margins = UiTheme.margins(side, float(pad[1]), side, float(pad[1]))
	for state: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, _margins)
	if look == "segment":
		add_theme_font_size_override("font_size", 18)
	if HEADLINE.has(look):
		add_theme_font_override("font", UiTheme.display(800))
		# (A size set by its screen stays: a small gold button on a card.)
		if not has_theme_font_size_override("font_size"):
			add_theme_font_size_override("font_size", int(HEADLINE[look]))
		add_theme_constant_override("icon_max_width", get_theme_font_size("font_size"))
	if look == "menu":
		alignment = HORIZONTAL_ALIGNMENT_LEFT
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	_show_state()


func _state() -> String:
	if disabled:
		return look + "_off"
	if toggle_mode and button_pressed:
		return look + "_on"
	if is_pressed():
		return look + "_down"
	if is_hovered() or has_focus() or preview_lit:
		return look + "_hover"
	return look


func _process(delta: float) -> void:
	_show_state()
	if _face == null:
		return
	var lit := not disabled and (is_hovered() or has_focus() or preview_lit)
	_hover = move_toward(_hover, 1.0 if lit else 0.0, delta / SWEEP)
	_press = move_toward(_press, 1.0 if is_pressed() and not disabled else 0.0, delta / 0.06)
	scale = Vector2.ONE * (1.0 - 0.035 * _press)
	# The fill: an ordinary button's screen colour, a menu line's red, a dangerous one's.
	var fill := Color(0, 0, 0, 0)
	match look:
		"button":
			fill = Color(tint, 0.88)
		"menu":
			fill = Color(UiTheme.BRAND, 0.95)
		"danger":
			fill = Color(0.78, 0.1, 0.13, 0.92)
	if fill.a > 0.0:
		_face.set_value(&"fill", ease(_hover, -1.6))
		_face.set_value(&"fill_color", fill)
	# Light passing over a lit main action, reward or menu line.
	if look == "primary" or look == "gold" or look == "menu":
		_shine = _shine + delta if lit else 0.0
		var at := fmod(_shine, SHINE_EVERY) / 0.55
		_face.set_value(&"shine", at if lit and at <= 1.0 else -1.0)
	# A menu line's words step right as it lights.
	if look == "menu" and _margins != null:
		var pad: Array = PADS["menu"]
		_margins.content_margin_left = float(pad[0]) + 16.0 * ease(_hover, -1.6)
	_ink(fill)


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


## The words' colour: dark on a light face (gold, a chosen segment, a light screen colour swept
## in), white otherwise.
func _ink(fill: Color) -> void:
	var style := _shown if UiTheme.PLATES.has(_shown) else look
	var dark := (UiTheme.PLATES[style] as Dictionary).has("dark")
	if fill.a > 0.0 and _hover > 0.5 and fill.get_luminance() > 0.6:
		dark = true
	var ink := UiTheme.NAVY_TEXT if dark else Color.WHITE
	if look == "tab" and _shown != "tab_on" and _shown != "tab_hover":
		ink = Color(1.0, 1.0, 1.0, 0.62)
	if look == "menu" and _hover < 0.5:
		ink = Color(1.0, 1.0, 1.0, 0.86)
	if disabled:
		ink = Color(1.0, 1.0, 1.0, 0.35)
	if ink == get_theme_color("font_color"):
		return
	for colour: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color",
			"icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color", "icon_disabled_color"]:
		add_theme_color_override(colour, ink)
