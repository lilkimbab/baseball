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
	subheading = "변경 사항은 자동 저장됩니다"
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
			_pick(main, "기본 이닝", "친선 경기와 리그 경기의 기본 이닝 수", ["3", "6", "9"], ["3이닝", "6이닝", "9이닝"], str(Settings.innings), func(v: String) -> void: Settings.innings = int(v))
			_switch(main, "피치 클락", "주자가 없으면 20초, 있으면 25초 안에 투구해야 합니다", Settings.pitch_clock, func(on: bool) -> void: Settings.pitch_clock = on)
			_switch(main, "선수 교체 보조", "켜면 대타와 투수 교체를 컴퓨터가 함께 판단합니다", Settings.auto_changes, func(on: bool) -> void: Settings.auto_changes = on)
			_pick(main, "감독 지휘 중 직접 플레이 횟수", "감독 지휘 경기에서 직접 타석·마운드에 설 수 있는 횟수", ["0", "3", "5", "-1"], ["0", "3", "5", "무제한"], str(Settings.interventions), func(v: String) -> void: Settings.interventions = int(v))
			_pick(main, "수비 방식", "수동: 타구 쪽 야수를 W A S D로 직접 움직이고 Space로 몸을 날립니다. 송구는 두 방식 모두 방향 키", ["0", "1"], ["자동", "수동"], "1" if Settings.manual_fielding else "0", func(v: String) -> void: Settings.manual_fielding = v == "1")
			_switch(main, "커리어 투수: 전 타자 상대", "끄면 승부처의 타자만 직접 상대합니다", Settings.pitch_all, func(on: bool) -> void: Settings.pitch_all = on)
		"screen":
			_switch(main, "전체 화면", "창 모드와 전체 화면을 전환합니다", Settings.fullscreen, func(on: bool) -> void: Settings.fullscreen = on)
			var res_ids: Array = []
			var res_names: Array = []
			for i: int in Settings.RESOLUTIONS.size():
				res_ids.append(str(i))
				res_names.append("%d×%d" % [Settings.RESOLUTIONS[i].x, Settings.RESOLUTIONS[i].y])
			_pick(main, "해상도", "창 모드에서의 화면 크기", res_ids, res_names, str(Settings.resolution), func(v: String) -> void: Settings.resolution = int(v))
			_pick(main, "품질", "그림자, 관중 수, 안티앨리어싱 수준", ["0", "1", "2"], ["낮음", "보통", "높음"], str(Settings.quality), func(v: String) -> void: Settings.quality = int(v))
			_pick(main, "업스케일링 (FSR 2)", "낮은 해상도로 그린 뒤 선명하게 키워 프레임을 확보합니다", ["0", "1", "2", "3"], ["끄기", "품질", "균형", "원본 크기"], str(Settings.upscale), func(v: String) -> void: Settings.upscale = int(v))
			_pick(main, "프레임 제한", "초당 프레임 수의 상한", ["30", "60", "0"], ["30", "60", "없음"], str(Settings.fps_limit), func(v: String) -> void: Settings.fps_limit = int(v))
		"sound":
			var levels: Array[String] = ["0.0", "0.4", "0.7", "0.9", "1.0"]
			var level_names := ["끔", "작게", "조금 작게", "보통", "크게"]
			var near := func(v: float) -> String:
				var best: String = levels[0]
				for l: String in levels:
					if absf(float(l) - v) < absf(float(best) - v):
						best = l
				return best
			_pick(main, "전체 볼륨", "모든 소리의 크기", levels, level_names, near.call(Settings.volume), func(v: String) -> void:
				Settings.volume = float(v)
				GameAudio.apply_volumes())
			_pick(main, "음악", "메뉴 음악, 징글, 오르간", levels, level_names, near.call(Settings.music_volume), func(v: String) -> void:
				Settings.music_volume = float(v)
				GameAudio.apply_volumes())
			_pick(main, "관중", "웅성임, 환호, 응원", levels, level_names, near.call(Settings.crowd_volume), func(v: String) -> void:
				Settings.crowd_volume = float(v)
				GameAudio.apply_volumes())
			_pick(main, "효과음", "타격, 포구, 바운드, 메뉴", levels, level_names, near.call(Settings.sfx_volume), func(v: String) -> void:
				Settings.sfx_volume = float(v)
				GameAudio.apply_volumes())
			_pick(main, "음성", "심판 콜과 장내 방송", levels, level_names, near.call(Settings.voice_volume), func(v: String) -> void:
				Settings.voice_volume = float(v)
				GameAudio.apply_volumes())
			_switch(main, "심판·장내 방송 음성", "운영체제의 한국어 음성으로 읽습니다(없으면 소리 없이)", Settings.voices, func(on: bool) -> void: Settings.voices = on)
		"show":
			_switch(main, "낙하 지점", "뜬공의 낙하 예상 지점을 표시합니다", Settings.landing_spot, func(on: bool) -> void: Settings.landing_spot = on)
			_switch(main, "투구 도착 지점", "타석에서 공이 손을 떠나는 순간 들어올 자리를 원으로 표시합니다", Settings.pitch_marker, func(on: bool) -> void: Settings.pitch_marker = on)
			_switch(main, "타구 정보", "타구 속도, 발사각, 비거리를 표시합니다", Settings.hit_info, func(on: bool) -> void: Settings.hit_info = on)
			_switch(main, "승리 확률", "현재 상황의 승리 확률을 표시합니다", Settings.win_chance, func(on: bool) -> void: Settings.win_chance = on)
			_switch(main, "명장면 슬로모션", "큰 타구와 아슬아슬한 수비를 가끔 느린 화면으로 가까이 보여 줍니다", Settings.highlights, func(on: bool) -> void: Settings.highlights = on)
			_switch(main, "문자 중계", "플레이 결과를 한 줄로 알려 줍니다", Settings.commentary, func(on: bool) -> void: Settings.commentary = on)
			_switch(main, "중계 연출", "경기 전 소개, 이닝 카드, 타자 소개, 투수 교체, 홈런 리플레이(Space로 건너뜀)", Settings.broadcast, func(on: bool) -> void: Settings.broadcast = on)


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
