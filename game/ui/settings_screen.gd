class_name SettingsScreen
extends Screen
## Settings (docs/04 section 6): game, screen, sound and what the match screen
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
	side.body.add_child(UiKit.rule())
	side.body.add_child(UiKit.label("바꾸는 즉시 저장됩니다", 15, UiTheme.DIM, 500))
	# (Both panels as tall as what is in them: no half-empty plates, the user, 2026-11-23.)
	side.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var names := {"game": "게임", "screen": "화면", "sound": "소리", "show": "경기 화면 표시"}
	var icons := {"game": "baseball", "screen": "monitor", "sound": "speaker-high", "show": "eye"}
	var main := panel(str(names[group]), str(icons[group]), columns, 0.0, str({"game": "GAMEPLAY", "screen": "DISPLAY", "sound": "AUDIO", "show": "HUD"}[group]))
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	match group:
		"game":
			var levels: Array = []
			for id: String in Difficulty.IDS:
				levels.append(id)
			_pick(main, "난이도", "어려울수록 보상이 큽니다", levels, Difficulty.NAMES, Settings.difficulty, func(v: String) -> void: Settings.difficulty = v)
			_pick(main, "기본 이닝", "친선 경기 기본값", ["3", "6", "9"], ["3이닝", "6이닝", "9이닝"], str(Settings.innings), func(v: String) -> void: Settings.innings = int(v))
			_switch(main, "피치 클락", "투구 사이 제한 시간 (KBO 2025)", Settings.pitch_clock, func(on: bool) -> void: Settings.pitch_clock = on)
			_switch(main, "선수 교체 보조", "교체는 코치에게 맡깁니다", Settings.auto_changes, func(on: bool) -> void: Settings.auto_changes = on)
			_pick(main, "감독 지휘 중 직접 플레이 횟수", "결정적인 순간에 직접 나서는 횟수", ["0", "3", "5", "-1"], ["0", "3", "5", "무제한"], str(Settings.interventions), func(v: String) -> void: Settings.interventions = int(v))
			_pick(main, "수비 방식", "수동은 WASD로 야수를 움직이고 Space로 몸을 날립니다", ["0", "1"], ["자동", "수동"], "1" if Settings.manual_fielding else "0", func(v: String) -> void: Settings.manual_fielding = v == "1")
			_pick(main, "직접 수비 시점", "직접 수비할 때의 카메라", ["eyes", "shoulder"], ["선수 눈(1인칭)", "어깨 뒤"], Settings.fielding_view, func(v: String) -> void: Settings.fielding_view = v)
			_switch(main, "전설의 시작 투수: 전 타자 상대", "끄면 중요한 장면만 직접 던집니다", Settings.pitch_all, func(on: bool) -> void: Settings.pitch_all = on)
		"screen":
			_switch(main, "전체 화면", "끄면 창 모드", Settings.fullscreen, func(on: bool) -> void: Settings.fullscreen = on)
			var res_ids: Array = []
			var res_names: Array = []
			for i: int in Settings.RESOLUTIONS.size():
				res_ids.append(str(i))
				res_names.append("%d×%d" % [Settings.RESOLUTIONS[i].x, Settings.RESOLUTIONS[i].y])
			_pick(main, "해상도", "창 모드의 크기", res_ids, res_names, str(Settings.resolution), func(v: String) -> void: Settings.resolution = int(v))
			_pick(main, "품질", "낮을수록 빠릅니다", ["0", "1", "2"], ["낮음", "보통", "높음"], str(Settings.quality), func(v: String) -> void: Settings.quality = int(v))
			_pick(main, "업스케일링 (FSR 2)", "프레임을 올립니다", ["0", "1", "2", "3"], ["끄기", "품질", "균형", "원본 크기"], str(Settings.upscale), func(v: String) -> void: Settings.upscale = int(v))
			_pick(main, "프레임 제한", "노트북은 60 권장", ["30", "60", "0"], ["30", "60", "없음"], str(Settings.fps_limit), func(v: String) -> void: Settings.fps_limit = int(v))
			_pick(main, "글꼴", "메뉴와 경기 화면의 글꼴(바꾸면 화면을 다시 불러옵니다)", ["nexon_lv2", "paperlogy", "football", "nanum_neo", "score", "dos_gothic", "dos_saemmul", "sam3"], ["넥슨 Lv.2", "페이퍼로지", "풋볼고딕", "나눔스퀘어", "에스코어", "도스고딕", "도스샘물", "삼국지3"], Settings.menu_font, func(v: String) -> void:
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
			_pick(main, "음악", "메뉴 음악과 팡파르", levels, level_names, near.call(Settings.music_volume), func(v: String) -> void:
				Settings.music_volume = float(v)
				GameAudio.apply_volumes())
			_pick(main, "관중", "관중 함성·응원가·북", levels, level_names, near.call(Settings.crowd_volume), func(v: String) -> void:
				Settings.crowd_volume = float(v)
				GameAudio.apply_volumes())
			_pick(main, "효과음", "타격·포구·발소리", levels, level_names, near.call(Settings.sfx_volume), func(v: String) -> void:
				Settings.sfx_volume = float(v)
				GameAudio.apply_volumes())
			_pick(main, "음성", "심판 콜과 캐스터", levels, level_names, near.call(Settings.voice_volume), func(v: String) -> void:
				Settings.voice_volume = float(v)
				GameAudio.apply_volumes())
			_switch(main, "심판 콜", "생성형 음성으로 녹음한 심판 콜", Settings.voices, func(on: bool) -> void: Settings.voices = on)
		"show":
			_switch(main, "낙하 지점", "뜬공이 떨어질 자리", Settings.landing_spot, func(on: bool) -> void: Settings.landing_spot = on)
			_switch(main, "투구 도착 지점", "던진 공이 홈 플레이트를 지난 자리", Settings.pitch_marker, func(on: bool) -> void: Settings.pitch_marker = on)
			_switch(main, "명장면 슬로모션", "아슬아슬한 플레이 다시 보기", Settings.highlights, func(on: bool) -> void: Settings.highlights = on)
			_switch(main, "문자 중계", "플레이마다 한 줄 중계", Settings.commentary, func(on: bool) -> void: Settings.commentary = on)
			_switch(main, "중계 연출", "경기 전 소개·이닝 교대·다시 보기", Settings.broadcast, func(on: bool) -> void: Settings.broadcast = on)


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
