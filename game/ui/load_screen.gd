class_name LoadScreen
extends Screen
## Saved games (docs/07 section 7), as the reference games lay out their save slots: a card
## for each, the picture of its mode across the top with the club's emblem and name over it,
## then where it stands (the season, the day, the record) and when it was saved; load, or
## delete (a second press confirms).

## Cards in the case, the empty ones included.
const SLOTS_SHOWN := 6
## Every card the same height, filled or empty.
const CARD_HEIGHT := 360.0

## The slot whose delete button has been pressed once.
static var _armed := ""


func setup() -> void:
	heading = "불러오기"
	heading_latin = "LOAD GAME"
	heading_icon = "floppy-disk"
	vantage = &"stands"
	dock_id = "load"


func build() -> void:
	var list := SaveIO.slots()
	var p := panel("저장 목록  %d개" % list.size(), "floppy-disk", null, 0.0, "SAVE DATA")
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if list.is_empty():
		var empty := UiKit.vbox(10)
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.alignment = BoxContainer.ALIGNMENT_CENTER
		var mark := UiKit.icon("floppy-disk", 84.0, Color(1.0, 1.0, 1.0, 0.18))
		mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		empty.add_child(mark)
		var words := UiKit.label("저장된 게임이 없습니다", 22, UiTheme.DIM, 600)
		words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(words)
		p.body.add_child(empty)
		return
	var scroll := UiKit.scroll()
	p.body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	for m: Dictionary in list:
		grid.add_child(_slot_card(m))
	# The rest of the case as empty slots, as the reference games show their save slots.
	for i: int in range(list.size(), maxi(SLOTS_SHOWN, list.size())):
		grid.add_child(_empty_card())


## One save: the mode's picture with the club over it, where it stands, and its buttons.
func _slot_card(m: Dictionary) -> Control:
	var league := str(m.get("mode", "")) == "league"
	var colour: Color = UiTheme.MODE_COLOURS["league" if league else "career"]
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = CARD_HEIGHT
	var frame := UiTheme.flat(Color(0.05, 0.055, 0.07, 0.94), 8, Color(1.0, 1.0, 1.0, 0.1), 1)
	card.add_theme_stylebox_override("panel", frame)
	var box := UiKit.vbox(0)
	card.add_child(box)
	# The picture, darkened toward its foot where the club's name stands.
	var picture := Control.new()
	picture.custom_minimum_size = Vector2(0.0, 196.0)
	picture.clip_contents = true
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(picture)
	var art := TextureRect.new()
	art.texture = load("res://ui/art/%s.jpg" % ("league" if league else "career"))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.add_child(art)
	var fade := Gradient.new()
	fade.set_color(0, Color(0.0, 0.0, 0.0, 0.05))
	fade.set_color(1, Color(0.02, 0.025, 0.035, 0.92))
	var shade_tex := GradientTexture2D.new()
	shade_tex.gradient = fade
	shade_tex.fill_from = Vector2(0.0, 0.25)
	shade_tex.fill_to = Vector2(0.0, 1.0)
	var shade := TextureRect.new()
	shade.texture = shade_tex
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.add_child(shade)
	var club := _club_of(m)
	var stripe := ColorRect.new()
	stripe.color = club.primary if club != null else colour
	stripe.custom_minimum_size = Vector2(6.0, 0.0)
	stripe.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.add_child(stripe)
	var over := UiKit.hbox(12)
	over.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	over.offset_left = 18.0
	over.offset_right = -14.0
	over.offset_top = -74.0
	over.offset_bottom = -12.0
	picture.add_child(over)
	if club != null:
		over.add_child(UiKit.club_mark(club, 58.0))
	var names := UiKit.vbox(-2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_END
	over.add_child(names)
	names.add_child(UiKit.latin("LEAGUE" if league else "CAREER", 17, colour, true))
	var title := UiKit.heading(str(m.get("club", m.get("team", ""))) if league else str(m.get("team", "")), 26)
	title.clip_text = true
	names.add_child(title)
	# Where it stands.
	var facts := UiKit.vbox(4)
	var pad := MarginContainer.new()
	for side: String in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 18)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 14)
	pad.add_child(facts)
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(pad)
	var line := UiKit.hbox(10)
	facts.add_child(line)
	line.add_child(UiKit.label("%d 시즌" % int(m.get("year", 0)), 18, Color.WHITE, 700))
	line.add_child(UiKit.label("%d일차" % int(m.get("day", 0)), 18, UiTheme.INK, 600))
	var record: Array = m.get("record", [])
	if record.size() == 3:
		var words := "%d승 %d패" % [int(record[0]), int(record[1])] + (" %d무" % int(record[2]) if int(record[2]) > 0 else "")
		line.add_child(UiKit.label(words, 18, colour, 700))
	if not league:
		var where := str(m.get("club", ""))
		if m.has("first_team"):
			where += ("  ·  1군" if bool(m["first_team"]) else "  ·  2군")
		if where.strip_edges() != "":
			facts.add_child(UiKit.label(where.strip_edges().trim_prefix("·").strip_edges(), 16, UiTheme.INK, 600))
	var when := Time.get_datetime_string_from_unix_time(int(m.get("saved", 0)), true)
	facts.add_child(UiKit.label("저장  " + when.substr(0, 16), 15, UiTheme.DIM, 500))
	var buttons := UiKit.hbox(8)
	facts.add_child(UiKit.spacer(0.0, 6.0, true))
	facts.add_child(buttons)
	var slot := str(m["slot"])
	var load_button := UiKit.button("불러오기", func() -> void: HubScreen.load_slot(self, slot, str(m.get("mode", ""))), "play", "primary")
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(load_button)
	buttons.add_child(UiKit.button("정말 삭제" if _armed == slot else "삭제", func() -> void:
		if _armed != slot:
			_armed = slot
			refresh()
			return
		_armed = ""
		SaveIO.delete_slot(slot)
		refresh(), "trash"))
	return card


## The club of a save, enough of it to draw its emblem (older saves did not keep it).
static func _club_of(m: Dictionary) -> Team:
	if not m.has("primary"):
		return null
	var t := Team.new()
	t.id = str(m.get("club_id", ""))
	t.name = str(m.get("club", ""))
	t.primary = Color.html(str(m["primary"]))
	t.accent = Color.html(str(m.get("accent", "ffffff")))
	return t


## A slot with nothing saved in it.
func _empty_card() -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = CARD_HEIGHT
	card.add_theme_stylebox_override("panel", UiTheme.flat(Color(1.0, 1.0, 1.0, 0.02), 8, Color(1.0, 1.0, 1.0, 0.08), 1))
	var box := UiKit.vbox(6)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(box)
	var mark := UiKit.icon("floppy-disk", 40.0, Color(1.0, 1.0, 1.0, 0.14))
	mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(mark)
	var words := UiKit.label("빈 슬롯", 17, Color(1.0, 1.0, 1.0, 0.28), 600)
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(words)
	return card
