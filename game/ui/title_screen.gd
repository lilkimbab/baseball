class_name TitleScreen
extends Screen
## The title (docs/04 section 5), as a released sports game's (the user, 2026-11-23: "a start
## screen that looks made by a game company"): the live park behind, darkened at the edges and
## from the left; a cover player in his club's uniform at the right, his number huge behind
## him; the game's name with "PRO BASEBALL" and the season; "PRESS ANY KEY" pulsing until a
## key or a click, then the menu slides in under the name — start, carry on with the latest
## save, settings, leave. The version and the engine at the foot.

const VERSION_LINE := "VER 1.0  ·  2026 SEASON"
## The fictional league the cover player is taken from (the same every day, another the next).
const COVER_PACK := "res://data/rosters/fiction-2026.json"

var _menu: VBoxContainer
var _prompt: Control
var _opened := false
var _clock := 0.0


func setup() -> void:
	vantage = &"title"
	show_top = false
	show_dock = false
	back = ""
	hints = []


func _ready() -> void:
	# A tool's window is opened so that it cannot take the keyboard (./dev tool-win); should
	# the game itself ever be started in that moment, its window is put right.
	if not Profile.tool_run() and DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, false)
		get_window().grab_focus()
	# Saves and settings from before the game was called Moneyball.
	UserData.carry_over()
	Settings.ensure_loaded()
	Settings.apply(get_tree())
	super._ready()


func build() -> void:
	# The shade over the park: dark from the left (the words) and round the edges.
	var shade := Control.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.draw.connect(func() -> void: _shade(shade))
	add_child(shade)
	move_child(shade, 0)
	_cover()
	content.add_child(UiKit.spacer(0.0, 150.0))
	var column := UiKit.vbox(2)
	var holder := UiKit.hbox(0)
	holder.add_child(UiKit.spacer(110.0, 0.0))
	holder.add_child(column)
	content.add_child(holder)
	var mark := UiKit.hbox(14)
	mark.add_child(UiKit.slash(UiTheme.BRAND, 40.0))
	mark.add_child(UiKit.latin("PRO BASEBALL", 40, UiTheme.ACCENT, true))
	column.add_child(mark)
	column.add_child(UiKit.latin("MONEYBALL", 200, Color.WHITE, true))
	var season := UiKit.hbox(12)
	season.add_child(UiKit.badge("2026 SEASON", UiTheme.BRAND, false))
	column.add_child(season)
	column.add_child(UiKit.spacer(0.0, 44.0))
	_menu = UiKit.vbox(10)
	_menu.visible = false
	column.add_child(_menu)
	# "PRESS ANY KEY", at the foot in the middle.
	_prompt = Control.new()
	_prompt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.draw.connect(func() -> void: _draw_prompt(_prompt))
	add_child(_prompt)
	# The foot: the version at the left, the engine at the right.
	var foot := Control.new()
	foot.set_anchors_preset(Control.PRESET_FULL_RECT)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.draw.connect(func() -> void: _draw_foot(foot))
	add_child(foot)


## The cover player: a star hitter of a club of the fictional league, swinging, his number huge
## behind him.
func _cover() -> void:
	if DisplayServer.get_name() == "headless" or not ResourceLoader.exists(COVER_PACK):
		return
	var clubs := RosterIO.load_pack(COVER_PACK).slice(0, 10)
	if clubs.is_empty():
		return
	var team: Team = clubs[absi(int(Time.get_unix_time_from_system() / 86400.0)) % clubs.size()]
	var star: Player = null
	for p: Player in team.players:
		if p.is_pitcher():
			continue
		if star == null or p.batting.power() + p.batting.contact() > star.batting.power() + star.batting.contact():
			star = p
	if star == null:
		return
	var stand := Control.new()
	stand.anchor_left = 0.5
	stand.anchor_right = 1.0
	stand.anchor_top = 0.0
	stand.anchor_bottom = 1.0
	# (Somewhat left of the right half, so his finish stays clear of the edge.)
	stand.offset_left = -80.0
	stand.offset_right = -150.0
	stand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stand)
	move_child(stand, 1)
	var big := UiKit.latin("%d" % star.number, 720, Color(1.0, 1.0, 1.0, 0.07), true)
	big.set_anchors_preset(Control.PRESET_FULL_RECT)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stand.add_child(big)
	var stage := PlayerStage.make(760.0, 900.0)
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.offset_top = 70.0
	# Swinging, his own recorded swing round and round (the user, 2026-11-23: "not standing
	# there: a batter swinging hard").
	stage.swinging = true
	stage.turning = false
	stage.show_player(star, team)
	stand.add_child(stage)


func _process(delta: float) -> void:
	_clock += delta
	if _prompt != null:
		_prompt.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _opened and ((event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)):
		get_viewport().set_input_as_handled()
		_open()
		return
	super._unhandled_input(event)


## The menu comes in under the name; the prompt goes.
func _open() -> void:
	if _opened:
		return
	_opened = true
	GameAudio.ui(get_tree(), "ui/confirm")
	var start_button := UiKit.button("게임 시작", func() -> void: go(HUB), "play", "menu", 520.0)
	_menu.add_child(start_button)
	var latest := SaveIO.slots()
	if not latest.is_empty():
		var m := latest[0]
		var what := "이어하기 · %s %d년 %d일차" % [m.get("team", ""), int(m.get("year", 0)), int(m.get("day", 0))]
		_menu.add_child(UiKit.button(what, func() -> void: HubScreen.load_slot(self, str(m["slot"]), str(m["mode"])), "fast-forward", "menu", 520.0))
	_menu.add_child(UiKit.button("환경 설정", func() -> void: go(SETTINGS), "gear-six", "menu", 520.0))
	_menu.add_child(UiKit.button("게임 종료", func() -> void: get_tree().quit(), "power", "menu", 520.0))
	_menu.visible = true
	_menu.modulate.a = 0.0
	_menu.position.x = -60.0
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_menu, "modulate:a", 1.0, 0.35)
	tween.tween_property(_menu, "position:x", 0.0, 0.35)
	start_button.grab_focus.call_deferred()


func _shade(on: Control) -> void:
	var s := on.size
	# From the left, where the words are.
	on.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x * 0.62, 0.0), Vector2(s.x * 0.62, s.y), Vector2(0.0, s.y)]),
		PackedColorArray([Color(0.01, 0.012, 0.02, 0.88), Color(0.01, 0.012, 0.02, 0.0), Color(0.01, 0.012, 0.02, 0.0), Color(0.01, 0.012, 0.02, 0.88)]))
	# Top and foot.
	on.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0.0), Vector2(s.x, s.y * 0.18), Vector2(0.0, s.y * 0.18)]),
		PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0)]))
	on.draw_polygon(PackedVector2Array([Vector2(0.0, s.y * 0.7), Vector2(s.x, s.y * 0.7), Vector2(s.x, s.y), Vector2(0.0, s.y)]),
		PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.75), Color(0, 0, 0, 0.75)]))


func _draw_prompt(on: Control) -> void:
	if _opened:
		return
	var s := on.size
	var k := UiTheme.scale_for(s.y)
	var a := 0.45 + 0.55 * (0.5 + 0.5 * sin(_clock * 3.2))
	var font := UiTheme.numeric(true, true)
	var word := "PRESS ANY KEY"
	var w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(34 * k)).x
	var y := s.y - 150.0 * k
	on.draw_string(font, Vector2(s.x * 0.5 - w * 0.5, y), word, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(34 * k), Color(1, 1, 1, a))
	var sub := UiTheme.font(600)
	var line := "아무 키나 누르세요"
	var lw := sub.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(20 * k)).x
	on.draw_string(sub, Vector2(s.x * 0.5 - lw * 0.5, y + 34.0 * k), line, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(20 * k), Color(1, 1, 1, 0.6 * a))
	# Thin lines either side of the word.
	for side: float in [-1.0, 1.0] as Array[float]:
		var from := s.x * 0.5 + side * (w * 0.5 + 24.0 * k)
		on.draw_line(Vector2(from, y - 12.0 * k), Vector2(from + side * 120.0 * k, y - 12.0 * k), Color(1, 1, 1, 0.35 * a), 2.0 * k)


func _draw_foot(on: Control) -> void:
	var s := on.size
	var k := UiTheme.scale_for(s.y)
	var font := UiTheme.numeric(false, false)
	on.draw_string(font, Vector2(48.0 * k, s.y - 34.0 * k), VERSION_LINE, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(18 * k), Color(1, 1, 1, 0.5))
	var engine := "MADE WITH GODOT ENGINE"
	var w := font.get_string_size(engine, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(18 * k)).x
	on.draw_string(font, Vector2(s.x - w - 48.0 * k, s.y - 34.0 * k), engine, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(18 * k), Color(1, 1, 1, 0.4))
