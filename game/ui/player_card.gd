class_name PlayerCard
extends CenteredPanel
## The player card (docs/05 section 5: the same everywhere, docs/13 S9-4): who he is, his
## grade and overall, every rating as a bar, his pitches, and his numbers this season. Opened
## over the league and career screens; Esc or the button closes it.

var _list: VBoxContainer


func _ready() -> void:
	super._ready()
	custom_minimum_size = Vector2(760, 0)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	add_child(_list)


## Opens a card for a player over a screen.
static func open_for(parent: Node, p: Player, season: Season) -> PlayerCard:
	var card := PlayerCard.new()
	parent.add_child(card)
	card.show_player(p, season)
	return card


func show_player(p: Player, season: Season) -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	var ovr := ClubRules.player_ovr(p, season.ovr, season.catalog) if season != null else 50.0
	var grade := ClubIO.load_default().grade_of(ovr).name
	var role := "%s %s" % ["선발" if p.role() == &"SP" else "구원", "좌투" if p.throws == &"L" else "우투"] if p.is_pitcher() else "%s · %s타 %s투" % [Position.name_of(p.primary_position()), {"R": "우", "L": "좌", "S": "양"}[String(p.bats)], "좌" if p.throws == &"L" else "우"]
	_text("%s  #%d" % [p.name, p.number], 30, UiTheme.GOLD)
	var age := (season.season_year if season != null else 2026) - p.born
	_text("%s · %d세 · %dcm %dkg%s · %s등급 OVR %d" % [role, age, roundi(p.height_cm), roundi(p.weight_kg), " · 외국인" if p.origin == &"foreign" else (" · 아시아쿼터" if p.origin == &"asia" else ""), grade, roundi(ovr)], 18, UiTheme.INK)
	if p.is_pitcher():
		_bar("제구", p.pitching.control)
		_bar("체력", p.pitching.stamina)
		_bar("평정", p.pitching.composure)
		_bar("견제", p.pitching.hold)
		for a: ArsenalPitch in p.pitching.arsenal:
			var t: PitchType = season.catalog.get(a.type) if season != null else null
			_bar("%s %dkm/h" % [t.label if t != null else String(a.type), roundi(a.velo_avg)], (a.movement + a.command) * 0.5)
	else:
		_bar("컨택 (우투/좌투)", p.batting.contact_r, p.batting.contact_l)
		_bar("파워 (우투/좌투)", p.batting.power_r, p.batting.power_l)
		_bar("선구안", p.batting.eye)
		_bar("주력", p.batting.speed)
		_bar("주루", p.batting.baserunning)
		_bar("번트", p.batting.bunt)
		_bar("수비 범위", p.fielding.range)
		_bar("포구", p.fielding.hands)
		_bar("송구", p.fielding.arm)
		_bar("송구 정확도", p.fielding.accuracy)
	if season != null:
		var b: BattingLine = season.book.batting.get(p.id)
		if b != null and b.pa > 0:
			_text("올해 %d경기 타율 %s · %d홈런 · %d타점 · OPS %s" % [b.games, BattingLine.rate_text(b.average()), b.home_runs, b.rbi, BattingLine.rate_text(b.ops())], 17, UiTheme.DIM)
		var l: PitchingLine = season.book.pitching.get(p.id)
		if l != null and l.outs > 0:
			_text("올해 %d경기 %s이닝 %d승 %d패 %d세이브 · 평균자책점 %.2f · %d탈삼진" % [l.games, l.innings_text(), l.wins, l.losses, l.saves, l.era(), l.strikeouts], 17, UiTheme.DIM)
		_text("컨디션 %s" % season.condition_name(p.id), 17, UiTheme.DIM)
	var close := Button.new()
	close.text = "닫기 (Esc)"
	close.pressed.connect(queue_free)
	_list.add_child(close)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()


func _text(line: String, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = line
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	_list.add_child(l)


func _bar(label: String, value: float, second: float = -1.0) -> void:
	var row := HBoxContainer.new()
	_list.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(230.0, 0.0)
	l.add_theme_font_size_override("font_size", 17)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(330.0, 16.0)
	bar.max_value = 99.0
	bar.value = value
	bar.show_percentage = false
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var n := Label.new()
	n.text = " %d" % roundi(value) + ("/%d" % roundi(second) if second >= 0.0 else "")
	n.add_theme_font_size_override("font_size", 17)
	row.add_child(n)
