class_name TitleScreen
extends Screen
## The title (docs/05 section 5): start, carry on with the latest save, or leave.


func _ready() -> void:
	Settings.ensure_loaded()
	Settings.apply(get_tree())
	super._ready()


func build() -> void:
	content.position = Vector2(140.0, 300.0)
	title("프로젝트 더그아웃", 72)
	line("감독 + 액션 야구 · 가칭", UiTheme.DIM, 24)
	line("", UiTheme.DIM, 20)
	button("시작", func() -> void: go(HUB), null, 360.0)
	var latest := SaveIO.slots()
	if not latest.is_empty():
		var m := latest[0]
		button("이어하기 · %s %d년 %d일째" % [m.get("team", ""), int(m.get("year", 0)), int(m.get("day", 0))], func() -> void: HubScreen.load_slot(self, str(m["slot"]), str(m["mode"])), null, 360.0)
	button("끝내기", func() -> void: get_tree().quit(), null, 360.0)
