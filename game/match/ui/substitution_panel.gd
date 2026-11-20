class_name SubstitutionPanel
extends PanelContainer
## The manager's menu (docs/13 S5-11, docs/05 2.5): opening it stops the game. Pitching
## change and defensive changes while the player's team is in the field; pinch hitter and
## pinch runners while it bats. Only players who can still come in are listed, and a change
## is made only if the line-up stays legal (SubstitutionOptions).

signal closed

var scene: MatchScene
var _list: VBoxContainer
## Chosen position for a defensive change, waiting for the player to come in.
var _defence_slot: Position.Kind = Position.Kind.DH


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(520, 420)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.16, 0.92)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	add_theme_stylebox_override("panel", style)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 400)
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	visible = false


func open() -> void:
	_defence_slot = Position.Kind.DH
	visible = true
	_rebuild("")


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key != null and key.pressed and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _rebuild(message: String) -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	var g := scene.game
	_header("작전 · 교체   (F 또는 Esc로 닫기)")
	if message != "":
		var note := Label.new()
		note.text = message
		note.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
		_list.add_child(note)
	var mine := scene.human_team
	if mine < 0:
		_header("관전 중에는 교체할 수 없습니다")
		return
	var team := g.teams[mine]
	if g.fielding() == mine:
		_header("투수 교체 (현재 %s, 투구 %d)" % [_name(team, team.pitcher_id), int(g.pitch_counts.get(team.pitcher_id, 0))])
		for id: String in SubstitutionOptions.relievers(team):
			var p := team.player(id)
			_button("%s  %s" % [p.name, _pitcher_note(p)], _apply.bind(SubstitutionOptions.pitcher_change(g, mine, id)))
		_header("수비 교체: 바꿀 자리")
		for kind: Position.Kind in Position.FIELD:
			if kind == Position.Kind.P:
				continue
			var who := team.fielder_at(kind)
			_button("%s  %s" % [Position.name_of(kind), _name(team, who)], _choose_slot.bind(kind))
		if _defence_slot != Position.Kind.DH:
			_header("%s 자리에 들어갈 선수" % Position.name_of(_defence_slot))
			for id: String in SubstitutionOptions.bench(team):
				var p := team.player(id)
				_button("%s  (%s)" % [p.name, Position.name_of(p.primary_position())], _apply.bind(SubstitutionOptions.defensive_change(mine, team.fielder_at(_defence_slot), id, _defence_slot)))
	else:
		_header("대타 (지금 타자 %s)" % _name(team, g.batter_id()))
		for id: String in SubstitutionOptions.bench(team):
			var p := team.player(id)
			_button("%s  컨택 %d 파워 %d" % [p.name, roundi(p.batting.contact()), roundi(p.batting.power())], _apply.bind(SubstitutionOptions.pinch_hitter(g, id)))
		for base: int in [1, 2, 3]:
			if g.base_empty(base):
				continue
			_header("대주자: %d루 %s" % [base, _name(team, g.runner_on(base).player_id)])
			for id: String in SubstitutionOptions.bench(team):
				var p := team.player(id)
				_button("%s  주력 %d" % [p.name, roundi(p.batting.speed)], _apply.bind(SubstitutionOptions.pinch_runner(g, base, id)))


func _pitcher_note(p: Player) -> String:
	return "제구 %d 체력 %d" % [roundi(p.pitching.control), roundi(p.pitching.stamina)] if p.pitching != null else ""


func _name(team: TeamInGame, id: String) -> String:
	var p := team.player(id)
	return p.name if p != null else id


func _header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	_list.add_child(label)


func _button(text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(action)
	_list.add_child(b)


func _choose_slot(kind: Position.Kind) -> void:
	_defence_slot = kind
	_rebuild("")


func _apply(event: GameEvent) -> void:
	var problems := SubstitutionOptions.check(scene.game, event)
	if not problems.is_empty():
		_rebuild(", ".join(problems))
		return
	scene.substitute(event)
	_defence_slot = Position.Kind.DH
	_rebuild("교체했습니다")
