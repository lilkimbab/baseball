class_name TitleScreen
extends Screen
## The title (docs/05 section 5): the park from high behind the plate, the game's name, and
## three things to do — start, carry on with the latest save, or leave.


func setup() -> void:
	vantage = &"title"
	show_top = false
	show_dock = false
	back = ""


func _ready() -> void:
	# Saves and settings from before the game was called Moneyball.
	UserData.carry_over()
	Settings.ensure_loaded()
	Settings.apply(get_tree())
	super._ready()


func build() -> void:
	content.add_child(UiKit.spacer(0.0, 190.0))
	var column := UiKit.vbox(4)
	var holder := UiKit.hbox(0)
	holder.add_child(UiKit.spacer(90.0, 0.0))
	holder.add_child(column)
	content.add_child(holder)
	var mark := UiKit.hbox(12)
	mark.add_child(UiKit.slash(UiTheme.BRAND, 40.0))
	mark.add_child(UiKit.latin("PRO BASEBALL", 40, Color.WHITE, true))
	column.add_child(mark)
	column.add_child(UiKit.latin("MONEYBALL", 190, Color.WHITE, true))
	column.add_child(UiKit.spacer(0.0, 40.0))
	var start_button := UiKit.button("게임 시작", func() -> void: go(HUB), "play", "primary", 440.0)
	start_button.add_theme_font_size_override("font_size", 30)
	column.add_child(start_button)
	column.add_child(UiKit.spacer(0.0, 4.0))
	var latest := SaveIO.slots()
	if not latest.is_empty():
		var m := latest[0]
		var what := "이어하기 · %s %d년 %d일차" % [m.get("team", ""), int(m.get("year", 0)), int(m.get("day", 0))]
		column.add_child(UiKit.button(what, func() -> void: HubScreen.load_slot(self, str(m["slot"]), str(m["mode"])), "fast-forward", "", 440.0))
		column.add_child(UiKit.spacer(0.0, 4.0))
	column.add_child(UiKit.button("게임 종료", func() -> void: get_tree().quit(), "power", "", 440.0))
