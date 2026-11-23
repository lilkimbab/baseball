class_name PauseMenu
extends CenteredPanel
## The pause menu (docs/04 2.5): Esc stops the game. Resume, the manager's
## menu, the settings that matter in a game (pitch clock, whether the computer makes our
## changes, fielding by hand, slow motion), and leaving the game.

signal resumed
signal wants_substitutions
signal quit_requested

var scene: MatchScene


func _ready() -> void:
	super._ready()
	custom_minimum_size = Vector2(560, 0)
	build("일시정지", "PAUSE", UiTheme.MODE_COLOURS["quick"])
	set_note("Esc 계속")
	visible = false


func open() -> void:
	visible = true
	_rebuild()


func close() -> void:
	visible = false
	resumed.emit()


func _rebuild() -> void:
	for child: Node in body.get_children():
		child.queue_free()
	var resume := GameButton.make("경기 계속", close, "", "primary")
	resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(resume)
	body.add_child(row_button("작전 · 교체   F", func() -> void: visible = false; wants_substitutions.emit()))
	body.add_child(UiKit.spacer(0.0, 6.0))
	body.add_child(section("경기 설정"))
	body.add_child(choice_row("투구 시간", ["on", "off"], ["켜기", "끄기"], "on" if scene.pitch_clock_on else "off", func(id: String) -> void:
		scene.pitch_clock_on = id == "on"))
	if scene.own_team() >= 0:
		body.add_child(choice_row("우리 팀 교체", ["auto", "manual"], ["컴퓨터가 함께", "직접만"], "auto" if scene.auto_changes else "manual", func(id: String) -> void:
			scene.set_auto_changes(id == "auto")))
	if scene.human_team >= 0:
		body.add_child(choice_row("수비 방식", ["auto", "manual"], ["자동", "수동 (WASD)"], "manual" if Settings.manual_fielding else "auto", func(id: String) -> void:
			Settings.manual_fielding = id == "manual"
			Settings.save_file()))
		body.add_child(choice_row("명장면 슬로모션", ["on", "off"], ["켜기", "끄기"], "on" if Settings.highlights else "off", func(id: String) -> void:
			Settings.highlights = id == "on"
			Settings.save_file()))
	body.add_child(UiKit.spacer(0.0, 6.0))
	body.add_child(row_button("경기 끝내기", func() -> void: quit_requested.emit()))
