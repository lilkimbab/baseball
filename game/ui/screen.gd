class_name Screen
extends Control
## A menu screen (docs/05 section 5): the ballpark behind (MenuBackdrop); a bar along the top
## with the game's mark, the parts of the game as tabs, the points and three small buttons
## (load, settings, quit); under it the screen's own title row — the way back, its name in
## the colour of its part of the game, its own tabs — and its content; along the foot the keys.
## Laid out for a 1080-line screen and scaled to the window like the HUD.
##
## A screen sets what its shell shows in setup() and fills `content` in build(); refresh()
## builds it again after something changes.

const HUB := "res://ui/hub_screen.tscn"
const TITLE := "res://ui/title_screen.tscn"
const QUICK := "res://ui/quick_match_screen.tscn"
const LOAD := "res://ui/load_screen.tscn"
const SETTINGS := "res://ui/settings_screen.tscn"
const PRACTICE := "res://ui/practice_screen.tscn"
const SHOP := "res://ui/shop_screen.tscn"
const ACHIEVEMENTS := "res://ui/achievements_screen.tscn"

## The parts of the game: id, word, icon, and the screen it opens ("" where it depends on what
## is saved). The first TABS of them are tabs in the top bar; the rest small buttons.
const DOCK: Array[Array] = [
	["hub", "홈", "house", HUB],
	["quick", "친선 경기", "baseball", QUICK],
	["league", "리그", "trophy", ""],
	["career", "전설의 시작", "user-circle", ""],
	["practice", "연습", "target", PRACTICE],
	["shop", "상점", "storefront", SHOP],
	["achievements", "업적", "medal", ACHIEVEMENTS],
	["load", "불러오기", "floppy-disk", LOAD],
	["settings", "환경 설정", "gear-six", SETTINGS],
]
const TABS := 7

## The screen's name, its Latin caption and a line beside it.
var heading := ""
var heading_latin := ""
var heading_icon := ""
var subheading := ""
## Where the backdrop's camera stands for this screen (MenuBackdrop.VIEWS).
var vantage: StringName = &"home"
## Where Esc and the back button go ("" for nowhere), and the button's word.
var back := HUB
var back_label := "뒤로"
## Which part of the game this screen is ("" for none); its colour is the screen's `tint`.
var dock_id := ""
var tint := UiTheme.BRAND
var show_dock := true
var show_top := true
## The keys shown along the foot: [key, what it does].
var hints: Array[Array] = [["ESC", "뒤로"], ["CLICK", "선택"]]

var content: VBoxContainer
## Room in the title row for a screen's own tabs.
var tab_bar: HBoxContainer
var _body: MarginContainer
var _heading_label: Label
var _sub_label: Label
var _points_label: Label


## What the shell shows; screens set heading, vantage, back and dock_id here.
func setup() -> void:
	pass


func _ready() -> void:
	theme = UiTheme.theme()
	add_to_group(&"menu")
	Settings.ensure_loaded()
	Profile.ensure_loaded()
	MenuMusic.play(get_tree())
	setup()
	tint = UiTheme.MODE_COLOURS.get(dock_id, UiTheme.BRAND)
	MenuBackdrop.show_for(self, vantage)
	if DisplayServer.get_name() == "headless":
		var bg := ColorRect.new()
		bg.color = Color(0.05, 0.055, 0.07)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
	_build_shell()
	get_viewport().size_changed.connect(_fit)
	_fit()
	refresh()
	# The content comes up into place.
	content.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(content, "modulate:a", 1.0, 0.25)


func _build_shell() -> void:
	_body = MarginContainer.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.add_theme_constant_override("margin_left", int(UiTheme.MARGIN))
	_body.add_theme_constant_override("margin_right", int(UiTheme.MARGIN))
	_body.add_theme_constant_override("margin_top", int(UiTheme.TOP_BAR + 22.0) if show_top else 30)
	_body.add_theme_constant_override("margin_bottom", int(UiTheme.DOCK + 22.0) if show_dock else 30)
	add_child(_body)
	var frame := UiKit.vbox(16)
	_body.add_child(frame)
	if show_top and heading != "":
		frame.add_child(_title_row())
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(content)
	if show_top:
		_build_top()
	if show_dock:
		_build_foot()


## The way back, the screen's name with its mark and caption, a line about it, its tabs.
func _title_row() -> Control:
	var row := UiKit.hbox(14)
	row.custom_minimum_size.y = 56.0
	if back != "":
		var b := UiKit.button(back_label, func() -> void: go(back), "arrow-left")
		b.tooltip_text = "Esc"
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
	row.add_child(UiKit.slash(tint, 44.0))
	_heading_label = UiKit.heading(heading, 42)
	row.add_child(_heading_label)
	var latin := UiKit.latin(heading_latin, 24, tint, true)
	latin.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(latin)
	_sub_label = UiKit.label(subheading, 18, UiTheme.DIM, 500)
	_sub_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sub_label.size_flags_vertical = Control.SIZE_SHRINK_END
	_sub_label.clip_text = true
	row.add_child(_sub_label)
	tab_bar = UiKit.hbox(2)
	tab_bar.size_flags_vertical = Control.SIZE_FILL
	row.add_child(tab_bar)
	return row


func _build_top() -> void:
	var top := Control.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = UiTheme.TOP_BAR
	add_child(top)
	PlateFace.behind(top, "strip").show_behind_parent = false
	# The part's colour washes in from the left behind the mark, and lines the foot of the bar.
	var fade := Gradient.new()
	fade.set_color(0, Color(tint.r, tint.g, tint.b, 0.34))
	fade.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	var ramp := GradientTexture2D.new()
	ramp.gradient = fade
	ramp.width = 64
	ramp.height = 4
	var wash := TextureRect.new()
	wash.texture = ramp
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.size = Vector2(560.0, UiTheme.TOP_BAR)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(wash)
	var line := ColorRect.new()
	line.color = tint
	line.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	line.offset_top = -2.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(line)
	var bar := UiKit.hbox(4)
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.offset_left = UiTheme.MARGIN
	bar.offset_right = -UiTheme.MARGIN
	top.add_child(bar)
	bar.add_child(UiKit.icon("baseball", 30.0, Color.WHITE))
	var mark := UiKit.latin("MONEYBALL", 36, Color.WHITE, true)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(mark)
	bar.add_child(UiKit.spacer(28.0))
	for i: int in TABS:
		var item := DOCK[i]
		var id := str(item[0])
		var tab := GameButton.make(str(item[1]), func() -> void: go(dock_path(id)), "", "tab")
		tab.tint = UiTheme.MODE_COLOURS.get(id, UiTheme.BRAND)
		tab.toggle_mode = true
		tab.button_pressed = id == dock_id
		tab.add_theme_font_size_override("font_size", 21)
		bar.add_child(tab)
	bar.add_child(UiKit.spacer(0.0, 0.0, true))
	bar.add_child(_points_block())
	bar.add_child(UiKit.spacer(8.0))
	for i: int in range(TABS, DOCK.size()):
		var item := DOCK[i]
		var id := str(item[0])
		bar.add_child(_small(str(item[2]), str(item[1]), func() -> void: go(dock_path(id))))
	bar.add_child(_small("power", "게임 종료", func() -> void: get_tree().quit()))


## A small square button with an icon (the words are its tooltip, and its text for tests).
func _small(icon_name: String, word: String, action: Callable) -> GameButton:
	var b := GameButton.make("", action, icon_name)
	b.tooltip_text = word
	b.set_meta(&"word", word)
	b.custom_minimum_size = Vector2(44.0, 44.0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## The points: a coin and the number.
func _points_block() -> Control:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UiTheme.margins(12.0, 5.0, 16.0, 5.0))
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var face := PlateFace.behind(pill, "pill")
	pill.sort_children.connect(func() -> void:
		face.position = Vector2.ZERO
		face.size = pill.size)
	var row := UiKit.hbox(8)
	pill.add_child(row)
	row.add_child(GradeCoin.make("P", 26.0))
	_points_label = UiKit.number(_points_text(), 28, UiTheme.ACCENT)
	_points_label.custom_minimum_size.x = 70.0
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_points_label)
	pill.tooltip_text = "포인트: 경기를 마치면 받고 상점에서 사용합니다"
	return pill


## The keys along the foot.
func _build_foot() -> void:
	var foot := Control.new()
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -UiTheme.DOCK
	add_child(foot)
	PlateFace.behind(foot, "strip", {"shadow": 0.0}).show_behind_parent = false
	var row := UiKit.hbox(10)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = UiTheme.MARGIN
	row.offset_right = -UiTheme.MARGIN
	foot.add_child(row)
	for hint: Array in hints:
		var cap := PanelContainer.new()
		cap.add_theme_stylebox_override("panel", UiTheme.margins(9.0, 1.0, 9.0, 1.0))
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var face := PlateFace.behind(cap, "key")
		cap.sort_children.connect(func() -> void:
			face.position = Vector2.ZERO
			face.size = cap.size)
		cap.add_child(UiKit.latin(str(hint[0]), 16, Color.WHITE))
		row.add_child(cap)
		row.add_child(UiKit.label(str(hint[1]), 16, UiTheme.DIM, 500))
		row.add_child(UiKit.spacer(14.0))
	row.add_child(UiKit.spacer(0.0, 0.0, true))
	var where := UiKit.latin(heading_latin if heading_latin != "" else "PRO BASEBALL MONEYBALL", 17, Color(1.0, 1.0, 1.0, 0.35), true)
	where.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(where)


## The screen a dock item opens now (the league and the career go to what is in progress).
static func dock_path(id: String) -> String:
	match id:
		"league":
			return LeagueSession.SCREEN
		"career":
			return CareerSession.HUB if CareerSession.career_season != null else CareerSession.CREATE
	for item: Array in DOCK:
		if str(item[0]) == id:
			return str(item[3])
	return HUB


func _points_text() -> String:
	var text := str(Profile.points)
	var out := ""
	for i: int in text.length():
		if i > 0 and (text.length() - i) % 3 == 0:
			out += ","
		out += text[i]
	return out


## Changes the words in the top strip (a screen whose name depends on what it shows).
func set_heading(text: String, sub: String = "") -> void:
	heading = text
	subheading = sub
	if _heading_label != null:
		_heading_label.text = text
		_sub_label.text = sub


func _fit() -> void:
	var screen := get_viewport().get_visible_rect().size
	var k := UiTheme.scale_for(screen.y)
	scale = Vector2(k, k)
	size = screen / k


## Rebuilds the screen's content.
func refresh() -> void:
	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()
	if tab_bar != null:
		for child: Node in tab_bar.get_children():
			tab_bar.remove_child(child)
			child.queue_free()
	if _points_label != null:
		_points_label.text = _points_text()
	build()
	_show_toasts()


## Achievements unlocked since the last screen (Achievements.toasts): a card for each at the
## top right, gone after a few seconds.
func _show_toasts() -> void:
	if Achievements.toasts.is_empty() or not is_inside_tree():
		return
	var stack := UiKit.vbox(8)
	stack.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stack.offset_left = -560.0
	stack.offset_right = -UiTheme.MARGIN
	stack.offset_top = UiTheme.TOP_BAR + 16.0
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	for line: String in Achievements.toasts.slice(0, 4):
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.06, 0.07, 0.09, 0.95), 8, Color(1.0, 0.84, 0.36, 0.8), 2, 12.0))
		var row := UiKit.hbox(10)
		card.add_child(row)
		row.add_child(TraitBadge.make(2, "medal", 40.0))
		var words := UiKit.label(line, 17, Color.WHITE, 700)
		words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(words)
		stack.add_child(card)
	Achievements.toasts.clear()
	var tween := create_tween()
	tween.tween_interval(4.5)
	tween.tween_property(stack, "modulate:a", 0.0, 0.6)
	tween.tween_callback(stack.queue_free)


## What the screen shows; screens fill this in.
func build() -> void:
	pass


## Goes to another screen (a wipe between menus) or into a game (behind a loading screen;
## `info` says what it shows: the clubs, a line about the park).
func go(path: String, info: Dictionary = {}) -> void:
	if path != "" and is_inside_tree():
		Loading.go(get_tree(), path, info)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE and back != "":
		get_viewport().set_input_as_handled()
		go(back)


# --- Small builders (into `content` unless a parent is given) ---


func title(line_text: String, font_size: int = 26) -> Label:
	var l := UiKit.heading(line_text, font_size, Color.WHITE)
	content.add_child(l)
	return l


func line(text: String, color: Color = UiTheme.INK, font_size: int = 20, parent: Control = null) -> Label:
	var l := UiKit.label(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(parent if parent != null else content).add_child(l)
	return l


func button(label: String, action: Callable, parent: Control = null, width: float = 0.0) -> Button:
	var b := UiKit.button(label, action, "", "", width)
	(parent if parent != null else content).add_child(b)
	return b


func row(parent: Control = null) -> HBoxContainer:
	var r := UiKit.hbox(8)
	(parent if parent != null else content).add_child(r)
	return r


## A named row of choices with the current one in the accent; the screen is rebuilt after a pick.
func choices(label: String, ids: Array, labels: Array, current: String, pick: Callable, parent: Control = null) -> HBoxContainer:
	var r := row(parent)
	var l := UiKit.label(label, 18, UiTheme.DIM, 600)
	l.custom_minimum_size = Vector2(200.0, 0.0)
	r.add_child(l)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	r.add_child(flow)
	var group := ButtonGroup.new()
	for i: int in ids.size():
		var id := str(ids[i])
		var b := GameButton.make(str(labels[i]), func() -> void:
			pick.call(id)
			refresh(), "", "segment")
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = id == current
		flow.add_child(b)
	return r


## A panel added to a parent (or the content column).
func panel(heading_text: String = "", icon_name: String = "", parent: Control = null, min_width: float = 0.0, caption: String = "") -> GlassPanel:
	var p := GlassPanel.make(heading_text, icon_name, min_width, tint, caption)
	(parent if parent != null else content).add_child(p)
	return p
