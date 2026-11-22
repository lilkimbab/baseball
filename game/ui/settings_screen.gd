class_name SettingsScreen
extends Screen
## Settings (docs/05 section 6, docs/13 S9-5): game, screen, sound and what the match screen
## shows, a group at a time. Saved as soon as they change; the screen ones take effect at once.

const GROUPS: Array[Array] = [["game", "게임", "baseball"], ["screen", "화면", "monitor"], ["sound", "소리", "speaker-high"], ["show", "표시", "eye"]]

static var group := "game"


func setup() -> void:
	heading = "환경 설정"
	heading_latin = "OPTIONS"
	heading_icon = "gear-six"
	vantage = &"stands"
	dock_id = "settings"


func build() -> void:
	Settings.ensure_loaded()
	var columns := UiKit.hbox(20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	var side := panel("분류", "list-bullets", columns, 300.0, "CATEGORY")
	for g: Array in GROUPS:
		var id := str(g[0])
		var b := GameButton.make(str(g[1]), func() -> void:
			group = id
			refresh(), str(g[2]), "segment")
		b.toggle_mode = true
		b.button_pressed = id == group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 56.0
		b.add_theme_font_size_override("font_size", 22)
		side.body.add_child(b)
	var names := {"game": "게임", "screen": "화면", "sound": "소리", "show": "경기 화면 표시"}
	var icons := {"game": "baseball", "screen": "monitor", "sound": "speaker-high", "show": "eye"}
	var main := panel(str(names[group]), str(icons[group]), columns, 0.0, str({"game": "GAMEPLAY", "screen": "DISPLAY", "sound": "AUDIO", "show": "HUD"}[group]))
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match group:
		"game":
			_pick(main, "기본 이닝", "", ["3", "6", "9"], ["3이닝", "6이닝", "9이닝"], str(Settings.innings), func(v: String) -> void: Settings.innings = int(v))
			_switch(main, "피치 클락", "", Settings.pitch_clock, func(on: bool) -> void: Settings.pitch_clock = on)
			_switch(main, "선수 교체 보조", "", Settings.auto_changes, func(on: bool) -> void: Settings.auto_changes = on)
			_pick(main, "감독 지휘 중 직접 플레이 횟수", "", ["0", "3", "5", "-1"], ["0", "3", "5", "무제한"], str(Settings.interventions), func(v: String) -> void: Settings.interventions = int(v))
			_pick(main, "수비 방식", "수동: 타구 쪽 야수를 W A S D로 직접 움직이고 Space로 몸을 날립니다. 송구는 두 방식 모두 방향 키", ["0", "1"], ["자동", "수동"], "1" if Settings.manual_fielding else "0", func(v: String) -> void: Settings.manual_fielding = v == "1")
			_switch(main, "커리어 투수: 전 타자 상대", "", Settings.pitch_all, func(on: bool) -> void: Settings.pitch_all = on)
		"screen":
			_switch(main, "전체 화면", "", Settings.fullscreen, func(on: bool) -> void: Settings.fullscreen = on)
			var res_ids: Array = []
			var res_names: Array = []
			for i: int in Settings.RESOLUTIONS.size():
				res_ids.append(str(i))
				res_names.append("%d×%d" % [Settings.RESOLUTIONS[i].x, Settings.RESOLUTIONS[i].y])
			_pick(main, "해상도", "", res_ids, res_names, str(Settings.resolution), func(v: String) -> void: Settings.resolution = int(v))
			_pick(main, "품질", "", ["0", "1", "2"], ["낮음", "보통", "높음"], str(Settings.quality), func(v: String) -> void: Settings.quality = int(v))
			_pick(main, "업스케일링 (FSR 2)", "", ["0", "1", "2", "3"], ["끄기", "품질", "균형", "원본 크기"], str(Settings.upscale), func(v: String) -> void: Settings.upscale = int(v))
			_pick(main, "프레임 제한", "", ["30", "60", "0"], ["30", "60", "없음"], str(Settings.fps_limit), func(v: String) -> void: Settings.fps_limit = int(v))
			_pick(main, "글꼴", "", ["paperlogy", "football", "nanum_neo", "score", "dos_gothic", "dos_saemmul", "sam3"], ["페이퍼로지", "풋볼고딕", "나눔스퀘어", "에스코어", "도스고딕", "도스샘물", "삼국지3"], Settings.menu_font, func(v: String) -> void:
				Settings.menu_font = v
				UiTheme.set_menu_family(v)
				# Everything on screen was drawn in the old face.
				get_tree().reload_current_scene.call_deferred())
		"sound":
			var levels: Array[String] = ["0.0", "0.4", "0.7", "0.9", "1.0"]
			var level_names := ["끔", "작게", "조금 작게", "보통", "크게"]
			var near := func(v: float) -> String:
				var best: String = levels[0]
				for l: String in levels:
					if absf(float(l) - v) < absf(float(best) - v):
						best = l
				return best
			_pick(main, "전체 볼륨", "", levels, level_names, near.call(Settings.volume), func(v: String) -> void:
				Settings.volume = float(v)
				GameAudio.apply_volumes())
			_pick(main, "음악", "", levels, level_names, near.call(Settings.music_volume), func(v: String) -> void:
				Settings.music_volume = float(v)
				GameAudio.apply_volumes())
			_pick(main, "관중", "", levels, level_names, near.call(Settings.crowd_volume), func(v: String) -> void:
				Settings.crowd_volume = float(v)
				GameAudio.apply_volumes())
			_pick(main, "효과음", "", levels, level_names, near.call(Settings.sfx_volume), func(v: String) -> void:
				Settings.sfx_volume = float(v)
				GameAudio.apply_volumes())
			_pick(main, "음성", "", levels, level_names, near.call(Settings.voice_volume), func(v: String) -> void:
				Settings.voice_volume = float(v)
				GameAudio.apply_volumes())
			_switch(main, "심판·장내 방송 음성", "", Settings.voices, func(on: bool) -> void: Settings.voices = on)
		"show":
			_switch(main, "낙하 지점", "", Settings.landing_spot, func(on: bool) -> void: Settings.landing_spot = on)
			_switch(main, "투구 도착 지점", "", Settings.pitch_marker, func(on: bool) -> void: Settings.pitch_marker = on)
			_switch(main, "명장면 슬로모션", "", Settings.highlights, func(on: bool) -> void: Settings.highlights = on)
			_switch(main, "문자 중계", "", Settings.commentary, func(on: bool) -> void: Settings.commentary = on)
			_switch(main, "중계 연출", "", Settings.broadcast, func(on: bool) -> void: Settings.broadcast = on)


## One setting: its name and a line about it on the left, the control on the right.
func _setting(main: GlassPanel, label: String, about: String, control: Control) -> void:
	var r := UiKit.hbox(16)
	r.custom_minimum_size.y = 64.0
	main.body.add_child(r)
	var words := UiKit.vbox(0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_child(UiKit.heading(label, 22))
	if about != "":
		words.add_child(UiKit.label(about, 15, UiTheme.DIM, 500))
	r.add_child(words)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(control)
	main.body.add_child(UiKit.rule())


func _pick(main: GlassPanel, label: String, about: String, ids: Array, labels: Array, current: String, setter: Callable) -> void:
	_setting(main, label, about, UiKit.segmented(ids, labels, current, func(v: String) -> void: _change(func() -> void: setter.call(v))))


func _switch(main: GlassPanel, label: String, about: String, on: bool, setter: Callable) -> void:
	_setting(main, label, about, Switch.make(on, func(now: bool) -> void: _change(func() -> void: setter.call(now))))


func _change(change: Callable) -> void:
	change.call()
	Settings.save_file()
	if is_inside_tree():
		Settings.apply(get_tree())
