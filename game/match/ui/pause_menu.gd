class_name PauseMenu
extends CenteredPanel
## The pause menu (docs/13 S6-9, docs/05 2.5): Esc stops the game. Resume, the manager's
## menu, the settings that matter in a game (pitch clock, whether the computer makes our
## changes), and leaving the game.

signal resumed
signal wants_substitutions
signal quit_requested

var scene: MatchScene
var _list: VBoxContainer


func _ready() -> void:
	super._ready()
	custom_minimum_size = Vector2(460, 0)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	add_child(_list)
	visible = false


func open() -> void:
	visible = true
	_rebuild()


func close() -> void:
	visible = false
	resumed.emit()


func _rebuild() -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = "일시정지"
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	title.add_theme_font_size_override("font_size", 26)
	_list.add_child(title)
	_button("계속 (Esc)", close)
	_button("작전 · 교체 (F)", func() -> void: visible = false; wants_substitutions.emit())
	_button("투구 시간: %s" % ("켜짐" if scene.pitch_clock_on else "꺼짐"), func() -> void:
		scene.pitch_clock_on = not scene.pitch_clock_on
		_rebuild())
	if scene.own_team() >= 0:
		_button("우리 팀 교체: %s" % ("컴퓨터가 함께" if scene.auto_changes else "직접만"), func() -> void:
			scene.set_auto_changes(not scene.auto_changes)
			_rebuild())
	_button("경기 끝내기", func() -> void: quit_requested.emit())


func _button(label: String, action: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(action)
	_list.add_child(b)
