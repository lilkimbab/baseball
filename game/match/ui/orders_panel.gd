class_name OrdersPanel
extends CenteredPanel
## The manager's orders menu (docs/05 section 2.5, docs/13 S7-6): F opens it and the game
## waits. Orders for the coming plate appearance (batting or fielding, as it is our turn),
## the standing defence and baserunning, substitutions, and reservations.

var scene: ManagerMatch
var _list: VBoxContainer


func _ready() -> void:
	super._ready()
	custom_minimum_size = Vector2(560, 0)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	add_child(_list)
	visible = false


func open() -> void:
	visible = true
	_rebuild()


func close() -> void:
	visible = false


func _rebuild() -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	var g := scene.game
	var ours := scene.resolver.tactics[scene.my_team]
	_title("작전 지시")
	var batting := g.batting() == scene.my_team
	var orders: Array[Tactics.Order] = Tactics.OFFENCE_ORDERS if batting else Tactics.DEFENCE_ORDERS
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	_list.add_child(row)
	for o: Tactics.Order in orders:
		var b := Button.new()
		var on := ours.order == o
		b.text = ("● " if on else "") + Tactics.order_name(o)
		b.disabled = not Tactics.can_give(o, g)
		b.pressed.connect(func() -> void:
			ours.order = Tactics.Order.NONE if on else o
			_rebuild())
		row.add_child(b)
	_note("이번 타석만. 지금: %s" % (Tactics.order_name(ours.order) if ours.order != Tactics.Order.NONE else "감독(컴퓨터)에게 맡김"))
	_button("수비 위치: %s" % Tactics.defence_name(ours.defence), func() -> void:
		ours.defence = ((ours.defence + 1) % Tactics.Defence.size()) as Tactics.Defence
		_rebuild())
	_button("주루 성향: %s" % Tactics.running_name(ours.running).trim_prefix("주루 "), func() -> void:
		ours.running = ((ours.running + 1) % Tactics.Running.size()) as Tactics.Running
		_rebuild())
	_button("선수 교체…", func() -> void:
		close()
		scene.toggle_menu())
	_title("예약")
	for preset: Reservation in scene.reservation_presets:
		var active := scene.reservations.has(preset)
		_button(("☑ " if active else "☐ ") + preset.label, func() -> void:
			if active:
				scene.reservations.erase(preset)
			else:
				preset.used = false
				scene.reservations.append(preset)
			_rebuild())
	_button("닫기 (F)", close)


func _title(line: String) -> void:
	var t := Label.new()
	t.text = line
	t.add_theme_color_override("font_color", UiTheme.GOLD)
	t.add_theme_font_size_override("font_size", 24)
	_list.add_child(t)


func _note(line: String) -> void:
	var t := Label.new()
	t.text = line
	t.add_theme_color_override("font_color", UiTheme.DIM)
	t.add_theme_font_size_override("font_size", 16)
	_list.add_child(t)


func _button(label: String, action: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(action)
	_list.add_child(b)
