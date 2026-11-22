class_name LoadScreen
extends Screen
## Saved games (docs/07 section 7): each slot as a card with what it holds; load or delete.


func setup() -> void:
	heading = "불러오기"
	heading_latin = "LOAD GAME"
	heading_icon = "floppy-disk"
	vantage = &"stands"
	dock_id = "load"


func build() -> void:
	var p := panel("저장 목록", "floppy-disk", null, 0.0, "SAVE DATA")
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := SaveIO.slots()
	if list.is_empty():
		p.body.add_child(UiKit.label("저장된 게임이 없습니다.", 20, UiTheme.DIM, 500))
		return
	var scroll := UiKit.scroll()
	p.body.add_child(scroll)
	var rows := UiKit.vbox(10)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for m: Dictionary in list:
		var card := UiKit.well(14.0)
		rows.add_child(card)
		var r := UiKit.hbox(16)
		card.add_child(r)
		var league := str(m.get("mode", "")) == "league"
		r.add_child(UiKit.icon("trophy" if league else "user-circle", 40.0, UiTheme.ACCENT if league else UiTheme.CYAN))
		var words := UiKit.vbox(2)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_child(UiKit.heading("%s · %s" % ["리그 모드" if league else "커리어 모드", m.get("team", "")], 24))
		var when := Time.get_datetime_string_from_unix_time(int(m.get("saved", 0)), true)
		words.add_child(UiKit.label("%d년 %d일차 · 저장 %s" % [int(m.get("year", 0)), int(m.get("day", 0)), when], 16, UiTheme.DIM, 500))
		r.add_child(words)
		var slot := str(m["slot"])
		r.add_child(UiKit.button("불러오기", func() -> void: HubScreen.load_slot(self, slot, str(m.get("mode", ""))), "play", "PrimaryButton"))
		r.add_child(UiKit.button("삭제", func() -> void:
			SaveIO.delete_slot(slot)
			refresh(), "trash"))
