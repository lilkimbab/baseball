class_name UiTheme
extends RefCounted
## The look of every screen (docs/05 section 3.1, docs/13 S6-1): one place for the fonts,
## colours and sizes, so the HUD and the menus agree. Sizes are given for a 1080-line
## screen and scaled to the window, so 720p shows the same layout smaller.
##
## Font: Pretendard (SIL Open Font License 1.1), github.com/orioncactus/pretendard,
## licence text in ui/fonts/Pretendard-LICENSE.txt.

const PANEL := Color(0.05, 0.08, 0.16, 0.78)
const PANEL_DARK := Color(0.02, 0.03, 0.07, 0.86)
const LINE := Color(1.0, 1.0, 1.0, 0.14)
const INK := Color(1.0, 1.0, 1.0, 0.95)
const DIM := Color(1.0, 1.0, 1.0, 0.6)
const GOLD := Color(1.0, 0.82, 0.25)
const GREEN := Color(0.4, 0.9, 0.45)
const BLUE := Color(0.45, 0.7, 1.0)
const ORANGE := Color(1.0, 0.6, 0.25)
const RED := Color(1.0, 0.35, 0.3)
const SHADOW := Color(0.0, 0.0, 0.0, 0.6)
## Pitch types on the pitch track, by family.
const FASTBALL := Color(1.0, 0.36, 0.32)
const BREAKING := Color(0.4, 0.72, 1.0)
const OFFSPEED := Color(0.48, 0.92, 0.5)

const REFERENCE_HEIGHT := 1080.0

static var _fonts: Dictionary[int, Font] = {}
static var _theme: Theme


## Pretendard at a weight: 400 regular, 600 semibold, 700 bold.
static func font(weight: int = 600) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var file := "Pretendard-SemiBold.otf"
	if weight <= 500:
		file = "Pretendard-Regular.otf"
	elif weight >= 700:
		file = "Pretendard-Bold.otf"
	var loaded := load("res://ui/fonts/" + file) as Font
	if loaded == null:
		var system := SystemFont.new()
		system.font_names = PackedStringArray(["Pretendard", "Noto Sans KR", "Malgun Gothic"])
		system.font_weight = weight
		loaded = system
	_fonts[weight] = loaded
	return loaded


## How much to scale a 1080-line size for a screen this tall.
static func scale_for(height: float) -> float:
	return clampf(height / REFERENCE_HEIGHT, 0.5, 2.0)


## Colour for a pitch type's family.
static func pitch_color(family: StringName) -> Color:
	match family:
		&"breaking":
			return BREAKING
		&"offspeed":
			return OFFSPEED
	return FASTBALL


## The theme for menus and panels built from Control nodes.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font(600)
	t.default_font_size = 20
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL_DARK
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(16)
	t.set_stylebox("panel", "PanelContainer", panel)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1.0, 1.0, 1.0, 0.06)
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(8)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 0.82, 0.25, 0.22)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(1.0, 0.82, 0.25, 0.4)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", hover)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_color", "Label", INK)
	_theme = t
	return t
