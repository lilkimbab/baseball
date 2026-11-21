class_name UiKit
extends RefCounted
## The parts the menus are built from (docs/05 section 5): labelled glass panels, buttons with
## icons, rows of choices, tabs, switches, badges. One place, so every screen looks alike.


static func label(text: String, font_size: int = 20, colour: Color = UiTheme.INK, weight: int = 600) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_font_override("font", UiTheme.font(weight))
	return l


## A small heading over a group: capitals-sized, dim, wide-spaced.
static func caption(text: String, colour: Color = UiTheme.DIM) -> Label:
	var l := label(text, 15, colour, 700)
	return l


static func icon(name: String, side: float = 24.0, colour: Color = UiTheme.INK) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = UiTheme.icon(name)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(side, side)
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.modulate = colour
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## A heading in the display face (Paperlogy ExtraBold).
static func heading(text: String, font_size: int = 26, colour: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.display(700))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", colour)
	return l


## Latin capitals and numbers in the condensed face (a small caption, a score, a rating).
static func latin(text: String, font_size: int = 16, colour: Color = UiTheme.DIM, italic: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.numeric(italic, true))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", colour)
	return l


## A big number (a rating, an average) in the slanted condensed face.
static func number(text: String, font_size: int = 40, colour: Color = Color.WHITE) -> Label:
	return latin(text, font_size, colour, true)


## The icon at the head of a panel or a screen, in its colour.
static func orb_icon(name: String, side: float = 36.0, tint: Color = UiTheme.ACCENT) -> Control:
	return icon(name, side * 0.72, tint)


## A slanted mark in a colour (before a title).
static func slash(colour: Color, height: float = 28.0) -> Control:
	var mark := Control.new()
	mark.custom_minimum_size = Vector2(height * 0.5, height)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.draw.connect(func() -> void:
		var h := mark.size.y
		mark.draw_colored_polygon(PackedVector2Array([Vector2(h * 0.28, 0.0), Vector2(h * 0.5, 0.0), Vector2(h * 0.22, h), Vector2(0.0, h)]), colour))
	return mark


## A button: "button" (quiet), "primary" (the brand red: a screen's main action), or the old
## names for those ("PrimaryButton").
static func button(text: String, action: Callable, icon_name: String = "", variation: String = "", width: float = 0.0) -> GameButton:
	var look := "primary" if variation == "PrimaryButton" or variation == "primary" else "button"
	return GameButton.make(text, action, icon_name, look, width)


static func hbox(separation: int = 10) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func vbox(separation: int = 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box


static func spacer(width: float = 0.0, height: float = 0.0, grow: bool = false) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(width, height)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if grow:
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


## A thin line across a panel.
static func rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = UiTheme.STROKE
	r.custom_minimum_size = Vector2(0.0, 1.0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A row of choices, the current one in the accent; pick(id) when another is pressed.
static func segmented(ids: Array, labels: Array, current: String, pick: Callable) -> HBoxContainer:
	var box := hbox(6)
	var group := ButtonGroup.new()
	for i: int in ids.size():
		var id := str(ids[i])
		var b := GameButton.make(str(labels[i]), func() -> void: pick.call(id), "", "segment")
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = id == current
		box.add_child(b)
	return box


## Tabs across the top of a panel or a screen: slanted ribbons, the chosen one white.
static func tabs(ids: Array, labels: Array, current: String, pick: Callable, icons: Array = []) -> HBoxContainer:
	var box := hbox(2)
	var group := ButtonGroup.new()
	for i: int in ids.size():
		var id := str(ids[i])
		var b := GameButton.make(str(labels[i]), func() -> void: pick.call(id), str(icons[i]) if i < icons.size() else "", "tab")
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = id == current
		box.add_child(b)
	return box


## A small rounded badge ("1군", "외국인", a grade).
static func badge(text: String, colour: Color = UiTheme.ACCENT, dark_text: bool = true) -> PanelContainer:
	var p := PanelContainer.new()
	var box := UiTheme.flat(colour, 2)
	box.content_margin_left = 9.0
	box.content_margin_right = 9.0
	box.content_margin_top = 2.0
	box.content_margin_bottom = 2.0
	p.add_theme_stylebox_override("panel", box)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(label(text, 14, Color(0.06, 0.05, 0.02) if dark_text else UiTheme.INK, 700))
	return p


## A big number over a small name ("OVR 78", ".312 타율").
static func figure(value: String, name: String, colour: Color = UiTheme.INK, number_size: int = 34) -> VBoxContainer:
	var box := vbox(-4)
	var n := number(value, number_size + 6, colour)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(n)
	var c := caption(name)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(c)
	return box


## A club's emblem (drawn from its colours and id).
static func club_mark(team: Team, side: float = 44.0) -> Emblem:
	return Emblem.make(team, side)


## One side of a match-up: the club's emblem with AWAY or HOME and its name beside it.
static func club_side(team: Team, tag: String, side: float = 96.0, name_size: int = 26) -> HBoxContainer:
	var box := hbox(14)
	box.add_child(club_mark(team, side))
	var words := vbox(-2)
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_child(latin(tag, 16, UiTheme.DIM, true))
	words.add_child(heading(team.name if team != null else "", name_size))
	box.add_child(words)
	return box


## A dark inset area inside a panel (a row of a list, a group of figures).
static func well(margin: float = 12.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.margins(margin, margin, margin, margin))
	PlateFace.behind(p, "well")
	p.sort_children.connect(func() -> void:
		var face := p.get_child(0) as Control
		face.position = Vector2.ZERO
		face.size = p.size)
	return p


## A scroll area holding one column.
static func scroll(height: float = 0.0) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if height > 0.0:
		s.custom_minimum_size.y = height
	return s
