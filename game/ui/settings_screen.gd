class_name SettingsScreen
extends Screen
## Settings (docs/05 section 6, docs/13 S9-5): game, screen, sound and what the match screen
## shows. Saved as soon as they change; the screen ones take effect at once.


func build() -> void:
	Settings.ensure_loaded()
	title("설정")
	line("게임", UiTheme.GOLD, 22)
	choices("기본 이닝", ["3", "6", "9"], ["3이닝", "6이닝", "9이닝"], str(Settings.innings), func(v: String) -> void: _change(func() -> void: Settings.innings = int(v)))
	_toggle("투구 시간", Settings.pitch_clock, func(on: bool) -> void: Settings.pitch_clock = on)
	_toggle("우리 팀 교체를 컴퓨터가 함께", Settings.auto_changes, func(on: bool) -> void: Settings.auto_changes = on)
	choices("빠른 경기 개입 횟수", ["0", "3", "5", "-1"], ["0", "3", "5", "무제한"], str(Settings.interventions), func(v: String) -> void: _change(func() -> void: Settings.interventions = int(v)))
	_toggle("커리어 투수: 모든 타자를 직접", Settings.pitch_all, func(on: bool) -> void: Settings.pitch_all = on)
	line("화면", UiTheme.GOLD, 22)
	_toggle("전체 화면", Settings.fullscreen, func(on: bool) -> void: Settings.fullscreen = on)
	var res_ids: Array = []
	var res_names: Array = []
	for i: int in Settings.RESOLUTIONS.size():
		res_ids.append(str(i))
		res_names.append("%d×%d" % [Settings.RESOLUTIONS[i].x, Settings.RESOLUTIONS[i].y])
	choices("해상도", res_ids, res_names, str(Settings.resolution), func(v: String) -> void: _change(func() -> void: Settings.resolution = int(v)))
	choices("품질", ["0", "1", "2"], ["낮음", "보통", "높음"], str(Settings.quality), func(v: String) -> void: _change(func() -> void: Settings.quality = int(v)))
	choices("업스케일링 (FSR 2)", ["0", "1", "2", "3"], ["끄기", "품질", "균형", "원본 크기(AA만)"], str(Settings.upscale), func(v: String) -> void: _change(func() -> void: Settings.upscale = int(v)))
	choices("프레임 제한", ["30", "60", "0"], ["30", "60", "없음"], str(Settings.fps_limit), func(v: String) -> void: _change(func() -> void: Settings.fps_limit = int(v)))
	line("소리 (소리는 아직 없다. S15)", UiTheme.GOLD, 22)
	choices("전체 볼륨", ["0.0", "0.4", "0.8", "1.0"], ["끔", "작게", "보통", "크게"], str(Settings.volume), func(v: String) -> void: _change(func() -> void: Settings.volume = float(v)))
	line("표시", UiTheme.GOLD, 22)
	_toggle("낙하 지점", Settings.landing_spot, func(on: bool) -> void: Settings.landing_spot = on)
	_toggle("타구 정보", Settings.hit_info, func(on: bool) -> void: Settings.hit_info = on)
	_toggle("승리 확률", Settings.win_chance, func(on: bool) -> void: Settings.win_chance = on)
	_toggle("한 줄 중계", Settings.commentary, func(on: bool) -> void: Settings.commentary = on)
	button("허브로", func() -> void: go(HUB))


func _toggle(label: String, on: bool, setter: Callable) -> void:
	choices(label, ["1", "0"], ["켜기", "끄기"], "1" if on else "0", func(v: String) -> void: _change(func() -> void: setter.call(v == "1")))


func _change(change: Callable) -> void:
	change.call()
	Settings.save_file()
	if is_inside_tree():
		Settings.apply(get_tree())
