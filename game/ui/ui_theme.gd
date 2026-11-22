class_name UiTheme
extends RefCounted
## The look of every screen (docs/05 section 3.1, docs/13 S6-1): one place for the fonts,
## colours and sizes, so the HUD and the menus agree. Sizes are given for a 1080-line
## screen and scaled to the window, so 720p shows the same layout smaller.
##
## Fonts: Paperlogy (text and headings) and Barlow Condensed (numbers, Latin), both SIL Open
## Font License 1.1; licence texts in ui/fonts/.

## The HUD's plates: the menus' graphite (docs/05 section 5), a little more see-through over
## the field.
const PANEL := Color(0.085, 0.09, 0.11, 0.88)
const PANEL_DARK := Color(0.045, 0.048, 0.06, 0.92)
const LINE := Color(1.0, 1.0, 1.0, 0.14)
const INK := Color(1.0, 1.0, 1.0, 0.95)
const DIM := Color(1.0, 1.0, 1.0, 0.6)
const GOLD := Color(1.0, 0.82, 0.25)
const GREEN := Color(0.4, 0.9, 0.45)
const BLUE := Color(0.45, 0.7, 1.0)
const ORANGE := Color(1.0, 0.6, 0.25)
const RED := Color(1.0, 0.35, 0.3)
const SHADOW := Color(0.0, 0.0, 0.0, 0.6)
## A rating's bar, as the menus' player panel draws it.
const RATING := Color(0.72, 0.78, 0.9)
## Pitch types on the pitch track, by family.
const FASTBALL := Color(1.0, 0.36, 0.32)
const BREAKING := Color(0.4, 0.72, 1.0)
const OFFSPEED := Color(0.48, 0.92, 0.5)

const REFERENCE_HEIGHT := 1080.0

static var _fonts: Dictionary[int, Font] = {}
static var _icons: Dictionary[String, Texture2D] = {}
static var _theme: Theme
## The menus' family (Settings.menu_font): Paperlogy, or one of the DOS-era bitmap faces the
## user suggested (github.com/hurss/fonts, MIT; cut to Korean and Latin in ui/fonts/dos/).
## Each: [text at 500, 600, 700], heading.
const MENU_FAMILIES := {
	"paperlogy": [["Paperlogy-Medium.woff2", "Paperlogy-SemiBold.woff2", "Paperlogy-Bold.woff2"], "Paperlogy-ExtraBold.woff2"],
	# NEXON Football Gothic: drawn for a football game (FIFA Online 4); free to bundle unmodified.
	"football": [["football/NEXONFootballGothic-L.otf", "football/NEXONFootballGothic-B.otf", "football/NEXONFootballGothic-B.otf"], "football/NEXONFootballGothic-B.otf"],
	# NanumSquare Neo (Naver, OFL): a plain, sturdy screen gothic.
	"nanum_neo": [["nanum/NanumSquareNeo-Regular.woff2", "nanum/NanumSquareNeo-Bold.woff2", "nanum/NanumSquareNeo-Bold.woff2"], "nanum/NanumSquareNeo-ExtraBold.woff2"],
	# S-Core Dream (OFL), the broadcast graphics' face, for the menus too.
	"score": [["SCoreDream-Medium.woff", "SCoreDream-Bold.woff", "SCoreDream-Bold.woff"], "SCoreDream-Heavy.woff"],
	"dos_gothic": [["dos/DOSGothic.ttf", "dos/DOSGothic.ttf", "dos/DOSIyagiBoldface.ttf"], "dos/DOSIyagiBoldface.ttf"],
	"dos_saemmul": [["dos/DOSSaemmul.ttf", "dos/DOSSaemmul.ttf", "dos/DOSIyagiBoldface.ttf"], "dos/DOSIyagiBoldface.ttf"],
	"sam3": [["dos/Sam3KRFont.ttf", "dos/Sam3KRFont.ttf", "dos/Sam3KRFont.ttf"], "dos/Sam3KRFont.ttf"],
}
static var menu_family := "football"


## Changes the menus' family; screens built after this use it.
static func set_menu_family(id: String) -> void:
	var pick := id if MENU_FAMILIES.has(id) else "paperlogy"
	if pick == menu_family:
		return
	menu_family = pick
	_fonts.clear()
	_faces.clear()
	_theme = null


## The text face at a weight: Paperlogy 500 medium, 600 semibold, 700 bold, or the family
## chosen (a system face if the files are missing). One family for everything Korean, heavier
## for what matters more.
static func font(weight: int = 600) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var files: Array = MENU_FAMILIES[menu_family][0]
	var file: String = files[1]
	if weight <= 500:
		file = files[0]
	elif weight >= 700:
		file = files[2]
	var loaded := load("res://ui/fonts/" + file) as Font if ResourceLoader.exists("res://ui/fonts/" + file) else null
	if loaded == null:
		var system := SystemFont.new()
		system.font_names = PackedStringArray(["Noto Sans KR", "Malgun Gothic", "NanumGothic"])
		system.font_weight = weight
		loaded = system
	_fonts[weight] = loaded
	return loaded


## A face for a place in the game (docs/05 section 5; the user: "the same font is used
## everywhere: find the right one for each situation"). Real broadcasts, scoreboards and
## advertising each have their own lettering, and the game reads as one flat layer without it:
##   &"menu"       the menus (Paperlogy)
##   &"broadcast"  the graphics a broadcast lays over a game: the score bug, the bottom bar,
##                 the pitch panel, the commentary line (S-Core Dream, a television gothic)
##   &"impact"     what is shouted: an umpire's call, a judgment on a swing or a pitch
##                 (Black Han Sans, heavy and tight)
##   &"board"      the stadium's scoreboard: lamps, so a dot-matrix face (Galmuri)
##   &"wall"       painted on the park: distances on the fence (College Block)
##   &"ad_*"       sponsors' boards, each brand its own: ad_heavy, ad_square, ad_round,
##                 ad_script, ad_slab, ad_plain
## Figures and Latin capitals everywhere are numeric() (Barlow Condensed).
const FACES := {
	&"broadcast": ["res://ui/fonts/SCoreDream-Medium.woff", "res://ui/fonts/SCoreDream-Bold.woff", "res://ui/fonts/SCoreDream-Heavy.woff"],
	&"impact": ["res://assets/fonts/uniform/BlackHanSans-Regular.ttf"],
	&"board": ["res://ui/fonts/Galmuri11-Bold.ttf"],
	&"wall": ["res://assets/fonts/uniform/CollegeBlock-Bold.ttf"],
	&"ad_heavy": ["res://assets/fonts/uniform/BlackHanSans-Regular.ttf"],
	&"ad_square": ["res://assets/fonts/uniform/DoHyeon-Regular.ttf"],
	&"ad_round": ["res://ui/fonts/GmarketSans-Medium.woff", "res://ui/fonts/GmarketSans-Bold.woff"],
	&"ad_script": ["res://assets/fonts/uniform/Lobster-Regular.ttf"],
	&"ad_slab": ["res://assets/fonts/uniform/Rye-Regular.ttf"],
}
static var _faces: Dictionary[String, Font] = {}


## The face for a place (see FACES) at a weight; the menus' face if there is none for it.
static func face(role: StringName, weight: int = 600) -> Font:
	var key := "%s:%d" % [role, weight]
	if _faces.has(key):
		return _faces[key]
	var out: Font = null
	if FACES.has(role):
		var files: Array = FACES[role]
		# Lighter to heavier: the first for text, the last for the heaviest.
		var pick := 0 if weight <= 500 else (files.size() - 1 if weight >= 800 else mini(1, files.size() - 1))
		var path := str(files[pick])
		if ResourceLoader.exists(path):
			var loaded := load(path) as Font
			# Anything the face lacks (Korean in a Latin face, a rare sign) comes from the menus'.
			var with_spare := FontVariation.new()
			with_spare.base_font = loaded
			with_spare.fallbacks = [font(weight)]
			out = with_spare
	if out == null:
		out = font(weight)
	_faces[key] = out
	return out


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


# --- Menus (docs/05 section 5; the fourth look: graphite over the ballpark, one brand red,
# white type, corners cut on the slant — colour comes from the clubs and the pictures) ---

## The brand colour: main actions, what is chosen, small marks. Gold stays for points and grades.
const BRAND := Color(0.88, 0.13, 0.17)
const ACCENT := Color(1.0, 0.8, 0.3)
const ACCENT_DARK := Color(0.9, 0.5, 0.08)
const CYAN := Color(0.45, 0.82, 1.0)
const NAVY := Color(0.05, 0.055, 0.07)
const NAVY_TEXT := Color(0.06, 0.065, 0.08)
const STROKE := Color(1.0, 1.0, 1.0, 0.1)
const ROW_ALT := Color(1.0, 1.0, 1.0, 0.03)
const ROW_HOVER := Color(1.0, 1.0, 1.0, 0.09)
const ROW_SELECTED := Color(0.88, 0.13, 0.17, 0.3)
## Each part of the game has its own colour (its tab, its screen's marks, its card): warm for
## playing now, gold for the league, blue for the career, green for practice, violet for the shop.
const MODE_COLOURS := {
	"hub": Color(0.93, 0.2, 0.22), "quick": Color(1.0, 0.42, 0.26), "league": Color(1.0, 0.76, 0.24), "career": Color(0.3, 0.64, 1.0),
	"practice": Color(0.36, 0.84, 0.52), "shop": Color(0.68, 0.52, 1.0), "achievements": Color(0.3, 0.82, 0.78),
	"load": Color(0.62, 0.7, 0.82), "settings": Color(0.62, 0.7, 0.82),
}
## Sizes of the shell (1080-line units).
const TOP_BAR := 72.0
const DOCK := 44.0
const MARGIN := 48.0

## The looks of the drawn shapes (ui/kit/plate.gdshader), by name. A button's states are its
## name with _hover, _down, _on and _off after it; "dark" marks a light shape (dark words).
const PLATES := {
	"panel": {"cut": 14.0, "top": Color(0.105, 0.112, 0.135, 0.9), "bottom": Color(0.055, 0.06, 0.075, 0.93), "border": Color(1.0, 1.0, 1.0, 0.13), "shadow": 0.5},
	"well": {"radius": 2.0, "top": Color(1.0, 1.0, 1.0, 0.05), "bottom": Color(1.0, 1.0, 1.0, 0.03), "border": Color(1.0, 1.0, 1.0, 0.07)},
	"button": {"radius": 2.0, "top": Color(1.0, 1.0, 1.0, 0.11), "bottom": Color(1.0, 1.0, 1.0, 0.06), "border": Color(1.0, 1.0, 1.0, 0.24)},
	"button_hover": {"radius": 2.0, "top": Color(1.0, 1.0, 1.0, 0.97), "bottom": Color(0.9, 0.9, 0.92, 0.97), "border": Color(1.0, 1.0, 1.0, 1.0), "dark": 1.0},
	"button_down": {"radius": 2.0, "top": Color(0.72, 0.72, 0.75, 0.97), "bottom": Color(0.82, 0.82, 0.85, 0.97), "border": Color(1.0, 1.0, 1.0, 1.0), "dark": 1.0},
	"button_off": {"radius": 2.0, "top": Color(1.0, 1.0, 1.0, 0.04), "bottom": Color(1.0, 1.0, 1.0, 0.03), "border": Color(1.0, 1.0, 1.0, 0.08)},
	"primary": {"radius": 2.0, "cut": 10.0, "top": Color(0.93, 0.17, 0.2, 1.0), "bottom": Color(0.74, 0.08, 0.12, 1.0), "border": Color(1.0, 0.45, 0.45, 0.55), "shadow": 0.35},
	"primary_hover": {"radius": 2.0, "cut": 10.0, "top": Color(1.0, 0.3, 0.32, 1.0), "bottom": Color(0.86, 0.13, 0.17, 1.0), "border": Color(1.0, 1.0, 1.0, 0.95), "border_width": 2.0, "shadow": 0.35},
	"primary_down": {"radius": 2.0, "cut": 10.0, "top": Color(0.62, 0.06, 0.1, 1.0), "bottom": Color(0.78, 0.1, 0.14, 1.0), "border": Color(1.0, 0.45, 0.45, 0.55)},
	"primary_off": {"radius": 2.0, "cut": 10.0, "top": Color(0.36, 0.2, 0.21, 0.8), "bottom": Color(0.28, 0.15, 0.16, 0.8), "border": Color(1.0, 1.0, 1.0, 0.1)},
	"segment": {"radius": 2.0, "top": Color(1.0, 1.0, 1.0, 0.04), "bottom": Color(1.0, 1.0, 1.0, 0.04), "border": Color(1.0, 1.0, 1.0, 0.2)},
	"segment_hover": {"radius": 2.0, "top": Color(1.0, 1.0, 1.0, 0.16), "bottom": Color(1.0, 1.0, 1.0, 0.12), "border": Color(1.0, 1.0, 1.0, 0.6)},
	"segment_on": {"radius": 2.0, "top": Color(1.0, 1.0, 1.0, 0.98), "bottom": Color(0.9, 0.9, 0.92, 0.98), "border": Color(1.0, 1.0, 1.0, 1.0), "dark": 1.0},
	"tab": {"radius": 0.0, "top": Color(1.0, 1.0, 1.0, 0.0), "bottom": Color(1.0, 1.0, 1.0, 0.0), "border": Color(1.0, 1.0, 1.0, 0.0), "border_width": 0.0},
	"tab_hover": {"radius": 0.0, "top": Color(1.0, 1.0, 1.0, 0.0), "bottom": Color(1.0, 1.0, 1.0, 0.1), "border": Color(1.0, 1.0, 1.0, 0.0), "border_width": 0.0, "bar_height": 3.0, "bar": Color(1.0, 1.0, 1.0, 0.5)},
	"tab_on": {"radius": 0.0, "top": Color(0.88, 0.13, 0.17, 0.0), "bottom": Color(0.88, 0.13, 0.17, 0.22), "border": Color(1.0, 1.0, 1.0, 0.0), "border_width": 0.0, "bar_height": 3.0, "bar": Color(0.92, 0.16, 0.2, 1.0)},
	"strip": {"radius": 0.0, "top": Color(0.035, 0.038, 0.048, 0.9), "bottom": Color(0.02, 0.022, 0.03, 0.86), "border": Color(1.0, 1.0, 1.0, 0.0), "border_width": 0.0, "shadow": 0.5},
	"pill": {"radius": 3.0, "top": Color(0.0, 0.0, 0.0, 0.45), "bottom": Color(0.0, 0.0, 0.0, 0.45), "border": Color(1.0, 1.0, 1.0, 0.14)},
	"tag": {"radius": 1.0, "cut": 6.0, "top": Color(0.93, 0.17, 0.2, 1.0), "bottom": Color(0.78, 0.1, 0.14, 1.0), "border": Color(1.0, 1.0, 1.0, 0.0), "border_width": 0.0},
	"key": {"radius": 4.0, "top": Color(1.0, 1.0, 1.0, 0.16), "bottom": Color(1.0, 1.0, 1.0, 0.08), "border": Color(1.0, 1.0, 1.0, 0.4)},
	"card": {"cut": 18.0, "top": Color(0.1, 0.105, 0.125, 1.0), "bottom": Color(0.04, 0.042, 0.052, 1.0), "border": Color(1.0, 1.0, 1.0, 0.16), "shadow": 0.55},
	"card_hover": {"cut": 18.0, "top": Color(0.1, 0.105, 0.125, 1.0), "bottom": Color(0.04, 0.042, 0.052, 1.0), "border": Color(1.0, 1.0, 1.0, 1.0), "border_width": 2.0, "shadow": 0.6, "glow": 0.22, "glow_color": Color(1.0, 1.0, 1.0, 1.0)},
}


## A rating's colour, by tier: below 50 plain, 50 green, 65 blue, 80 gold, 90 red.
## A rating as the screens show it (the user: "OVR is too low on average; compare with 2K14,
## but not the same"). The engine's ratings run 20..99 with the league's average at 50; shown,
## the average player reads 68, a good one in the 70s and low 80s, a star the high 80s and
## 90s: one for one up to 65 (so a point of growth is a point on screen), squeezed above it
## so that 99 stays 99. The engine never sees these numbers.
static func shown(value: float) -> float:
	if value <= 65.0:
		return maxf(value + 18.0, 1.0)
	return minf(83.0 + (value - 65.0) * 16.0 / 34.0, 99.0)


static func shown_text(value: float) -> String:
	return "%d" % roundi(shown(value))


static func rating_color(value: float) -> Color:
	if value >= 90.0:
		return Color(1.0, 0.42, 0.4)
	if value >= 80.0:
		return Color(1.0, 0.8, 0.28)
	if value >= 65.0:
		return Color(0.4, 0.8, 1.0)
	if value >= 50.0:
		return Color(0.5, 0.9, 0.55)
	return Color(0.72, 0.78, 0.88)


## The heading face: Paperlogy ExtraBold (titles, buttons, names).
static func display(_weight: int = 700) -> Font:
	if not _fonts.has(1000):
		var path := "res://ui/fonts/" + str(MENU_FAMILIES[menu_family][1])
		var loaded := load(path) as Font if ResourceLoader.exists(path) else null
		_fonts[1000] = loaded if loaded != null else font(700)
	return _fonts[1000]


## The face for numbers and Latin labels: Barlow Condensed, bold or slanted (scores, ratings).
static func numeric(italic: bool = false, heavy: bool = true) -> Font:
	var key := 2000 + int(italic) * 2 + int(heavy)
	if not _fonts.has(key):
		var file := "BarlowCondensed-ExtraBoldItalic.ttf" if italic and heavy else ("BarlowCondensed-BoldItalic.ttf" if italic else ("BarlowCondensed-Bold.ttf" if heavy else "BarlowCondensed-SemiBold.ttf"))
		var loaded := load("res://ui/fonts/" + file) as FontFile
		if loaded != null:
			# Korean beside the numbers falls back to the heading face.
			var with_korean := FontVariation.new()
			with_korean.base_font = loaded
			with_korean.fallbacks = [display(700)]
			_fonts[key] = with_korean
		else:
			_fonts[key] = font(700)
	return _fonts[key]


static func flat(bg: Color, radius: int = 8, border: Color = Color(0, 0, 0, 0), border_width: int = 0, margin: float = 0.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	if border_width > 0:
		box.border_color = border
		box.set_border_width_all(border_width)
	if margin > 0.0:
		box.set_content_margin_all(margin)
	box.anti_aliasing = true
	return box


static func margins(left: float, top: float, right: float, bottom: float) -> StyleBoxEmpty:
	var box := StyleBoxEmpty.new()
	box.content_margin_left = left
	box.content_margin_top = top
	box.content_margin_right = right
	box.content_margin_bottom = bottom
	return box


## A menu icon (ui/icons, Phosphor, MIT; white, tinted by the control that shows it).
## They are kept once loaded: a control that only draws one (and holds no reference to it)
## would otherwise have it freed under the renderer, which then draws a plain square.
static func icon(name: String) -> Texture2D:
	if _icons.has(name):
		return _icons[name]
	var path := "res://ui/icons/%s.svg" % name
	var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
	_icons[name] = texture
	return texture


## The theme for menus and panels built from Control nodes. Buttons have no box of their own
## here: GameButton draws one behind them.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font(600)
	t.default_font_size = 20
	t.set_stylebox("panel", "PanelContainer", flat(Color(0.06, 0.065, 0.08, 0.93), 3, Color(1.0, 1.0, 1.0, 0.13), 1, 16.0))
	t.set_stylebox("panel", "Panel", flat(Color(0.06, 0.065, 0.08, 0.93), 3, Color(1.0, 1.0, 1.0, 0.13), 1, 16.0))
	for state: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		t.set_stylebox(state, "Button", margins(20.0, 11.0, 20.0, 11.0))
	t.set_font("font", "Button", display(700))
	t.set_font_size("font_size", "Button", 20)
	for colour: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(colour, "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1.0, 1.0, 1.0, 0.4))
	t.set_constant("outline_size", "Button", 0)
	for colour: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
		t.set_color(colour, "Button", Color.WHITE)
	t.set_color("icon_disabled_color", "Button", Color(1.0, 1.0, 1.0, 0.4))
	t.set_constant("h_separation", "Button", 10)
	t.set_constant("icon_max_width", "Button", 24)
	t.set_color("font_color", "Label", INK)
	t.set_color("font_shadow_color", "Label", Color(0.0, 0.0, 0.0, 0.45))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 1)
	# Bars, scrollbars, tooltips, text boxes.
	t.set_stylebox("background", "ProgressBar", flat(Color(1.0, 1.0, 1.0, 0.1), 1))
	t.set_stylebox("fill", "ProgressBar", flat(BRAND, 1))
	var grabber := flat(Color(1.0, 1.0, 1.0, 0.3), 2)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", flat(Color(1.0, 1.0, 1.0, 0.6), 2))
	t.set_stylebox("grabber_pressed", "VScrollBar", flat(BRAND, 2))
	var track := flat(Color(1.0, 1.0, 1.0, 0.05), 2)
	track.content_margin_left = 5.0
	track.content_margin_right = 5.0
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("panel", "TooltipPanel", flat(Color(0.04, 0.045, 0.055, 0.98), 2, Color(1.0, 1.0, 1.0, 0.25), 1, 10.0))
	var edit := flat(Color(0.0, 0.0, 0.0, 0.45), 2, Color(1.0, 1.0, 1.0, 0.25), 1, 10.0)
	t.set_stylebox("normal", "LineEdit", edit)
	var edit_focus := edit.duplicate() as StyleBoxFlat
	edit_focus.border_color = Color.WHITE
	t.set_stylebox("focus", "LineEdit", edit_focus)
	_theme = t
	return t
