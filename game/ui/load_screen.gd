class_name LoadScreen
extends Screen
## Saved games (docs/07 section 7): each slot with what it holds; load or delete.


func build() -> void:
	title("불러오기")
	var list := SaveIO.slots()
	if list.is_empty():
		line("저장된 게임이 없다.", UiTheme.DIM)
	for m: Dictionary in list:
		var r := row()
		var mode := "감독 리그" if str(m.get("mode", "")) == "league" else "커리어"
		var when := Time.get_datetime_string_from_unix_time(int(m.get("saved", 0)), true)
		line("%s · %s · %d년 %d일째 · %s" % [mode, m.get("team", ""), int(m.get("year", 0)), int(m.get("day", 0)), when], UiTheme.INK, 20, r).custom_minimum_size = Vector2(900.0, 0.0)
		var slot := str(m["slot"])
		button("불러오기", func() -> void: HubScreen.load_slot(self, slot, str(m.get("mode", ""))), r)
		button("지우기", func() -> void:
			SaveIO.delete_slot(slot)
			refresh(), r)
	button("허브로", func() -> void: go(HUB))
