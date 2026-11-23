class_name OrdersPanel
extends CenteredPanel
## The manager's orders menu (docs/04 section 2.5): F opens it and the game
## waits. Orders for the coming plate appearance (batting or fielding, as it is our turn),
## the standing defence and baserunning, substitutions, and reservations.

var scene: ManagerMatch


func _ready() -> void:
	super._ready()
	custom_minimum_size = Vector2(600, 0)
	build("작전 지시", "ORDERS", UiTheme.MODE_COLOURS["league"])
	set_note("F 닫기")
	visible = false


func open() -> void:
	visible = true
	_rebuild()


func close() -> void:
	visible = false


func _rebuild() -> void:
	for child: Node in body.get_children():
		child.queue_free()
	var g := scene.game
	var ours := scene.resolver.tactics[scene.my_team]
	var batting := g.batting() == scene.my_team
	body.add_child(section("이번 타석 (%s)" % ("공격" if batting else "수비")))
	var orders: Array[Tactics.Order] = Tactics.OFFENCE_ORDERS if batting else Tactics.DEFENCE_ORDERS
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	body.add_child(row)
	for o: Tactics.Order in orders:
		var on := ours.order == o
		var b := GameButton.make(Tactics.order_name(o), func() -> void:
			ours.order = Tactics.Order.NONE if on else o
			_rebuild(), "", "segment")
		b.toggle_mode = true
		b.button_pressed = on
		b.disabled = not Tactics.can_give(o, g)
		row.add_child(b)
	body.add_child(UiKit.label("지금: %s" % (Tactics.order_name(ours.order) if ours.order != Tactics.Order.NONE else "감독(컴퓨터)에게 맡김"), 15, UiTheme.DIM, 500))
	body.add_child(UiKit.spacer(0.0, 4.0))
	body.add_child(section("기본 작전"))
	body.add_child(row_button("수비 위치: %s" % Tactics.defence_name(ours.defence), func() -> void:
		ours.defence = ((ours.defence + 1) % Tactics.Defence.size()) as Tactics.Defence
		_rebuild()))
	body.add_child(row_button("주루 성향: %s" % Tactics.running_name(ours.running).trim_prefix("주루 "), func() -> void:
		ours.running = ((ours.running + 1) % Tactics.Running.size()) as Tactics.Running
		_rebuild()))
	body.add_child(row_button("선수 교체…", func() -> void:
		close()
		scene.toggle_menu()))
	body.add_child(UiKit.spacer(0.0, 4.0))
	body.add_child(section("예약"))
	for preset: Reservation in scene.reservation_presets:
		var active := scene.reservations.has(preset)
		body.add_child(row_button(("☑ " if active else "☐ ") + preset.label, func() -> void:
			if active:
				scene.reservations.erase(preset)
			else:
				preset.used = false
				scene.reservations.append(preset)
			_rebuild()))
	body.add_child(UiKit.spacer(0.0, 4.0))
	var done := GameButton.make("닫기", close, "", "primary")
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(done)
