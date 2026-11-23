class_name UiKit
extends RefCounted
## The parts the menus are built from (docs/04 section 5): labelled glass panels, buttons with
## icons, rows of choices, tabs, switches, badges. One place, so every screen looks alike.


static func label(text: String, font_size: int = 20, colour: Color = UiTheme.INK, weight: int = 600) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_font_override("font", UiTheme.font(weight))
	_edge(l, colour)
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
	_edge(l, colour)
	return l


## Dark ink (a rating's black tier) gets a light edge to be read on a dark plate.
static func _edge(l: Label, colour: Color) -> void:
	var edge := UiTheme.ink_edge(colour)
	if edge.a > 0.0:
		l.add_theme_color_override("font_outline_color", edge)
		l.add_theme_constant_override("outline_size", 4)


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


## A button (GameButton.LOOKS): "button" (an outline that fills with its screen's colour),
## "primary" (the brand red: a screen's main action), "gold" (a reward, a purchase), "danger"
## (cannot be undone), "menu" (a line of the title's menu); "PrimaryButton" is the old name.
static func button(text: String, action: Callable, icon_name: String = "", variation: String = "", width: float = 0.0) -> GameButton:
	var look := "primary" if variation == "PrimaryButton" else variation
	if not GameButton.LOOKS.has(look):
		look = "button"
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


## A band in a club's colour, fading to nothing toward the right (the top of a club's page,
## as real games head a team screen); add the content to band.get_child(1).
static func band(colour: Color, height: float) -> MarginContainer:
	var hero := MarginContainer.new()
	hero.custom_minimum_size.y = height
	var fill := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(colour.lerp(Color.BLACK, 0.1), 0.95))
	grad.set_color(1, Color(colour, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	fill.texture = tex
	fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	hero.add_child(fill)
	var inner := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 16)
	hero.add_child(inner)
	return hero


## A big figure in an inset box, a name under it (a tile of a team's season).
static func tile(value: String, name: String, width: float = 130.0, number_size: int = 26) -> PanelContainer:
	var w := well(9.0)
	w.custom_minimum_size.x = width
	w.add_child(figure(value, name, Color.WHITE, number_size))
	return w


## A setting as games show one: its name, then ◀ the value ▶ (one step at a time, round the
## ends), instead of a row of buttons for every value.
static func selector(name: String, ids: Array, labels: Array, current: String, pick: Callable) -> HBoxContainer:
	var row := hbox(10)
	var title := label(name, 19, UiTheme.DIM, 600)
	title.custom_minimum_size.x = 110.0
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	var at := maxi(ids.find(current), 0)
	var step := func(d: int) -> void:
		if not ids.is_empty():
			pick.call(str(ids[(at + d + ids.size()) % ids.size()]))
	var back := GameButton.make("", func() -> void: step.call(-1), "caret-left", "segment")
	back.custom_minimum_size = Vector2(44.0, 40.0)
	row.add_child(back)
	var box := well(6.0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := label(str(labels[at]) if not labels.is_empty() else "", 20, Color.WHITE, 700)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(value)
	row.add_child(box)
	var on := GameButton.make("", func() -> void: step.call(1), "caret-right", "segment")
	on.custom_minimum_size = Vector2(44.0, 40.0)
	row.add_child(on)
	return row


## Clubs to pick from as a grid of their emblems (a team-select screen), the one chosen lit.
static func emblem_grid(teams: Array[Team], current: int, pick: Callable, columns: int = 6, side: float = 50.0) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for i: int in teams.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(side + 16.0, side + 12.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = teams[i].name
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color(UiTheme.BRAND, 0.6) if i == current else Color(1.0, 1.0, 1.0, 0.1 if state == "hover" else 0.04)
			if state == "focus":
				box.bg_color = Color(0, 0, 0, 0)
			box.set_corner_radius_all(4)
			if i == current:
				box.set_border_width_all(2)
				box.border_color = Color(1.0, 1.0, 1.0, 0.85)
			b.add_theme_stylebox_override(state, box)
		var centre := CenterContainer.new()
		centre.set_anchors_preset(Control.PRESET_FULL_RECT)
		centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
		centre.add_child(club_mark(teams[i], side))
		b.add_child(centre)
		var index := i
		b.pressed.connect(func() -> void: pick.call(index))
		grid.add_child(b)
	return grid


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
