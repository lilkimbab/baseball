class_name ScoreboardScreen
extends Control
## What the park's scoreboard shows during a game (docs/13 S13-6), drawn into the board's
## viewport: the line score by innings with runs, hits and errors, the count and outs, the man
## at bat with his number and average, and the speed of the last pitch.

const INNINGS := 10
const AMBER := Color(1.0, 0.78, 0.2)
const LED := Color(0.95, 0.95, 0.92)
const DIM := Color(0.55, 0.56, 0.6)

var scene: MatchScene


## The man at bat's face for his introduction (PortraitStudio), and whose it is.
var portrait: Texture2D
var _portrait_for := ""
var _asked_for := ""
## The batter's song is playing (MatchSound): its line shows under his introduction.
var song_on := false


## What the board would show now, as text: it is redrawn only when this changes.
func signature() -> String:
	if scene == null or scene.game == null:
		return ""
	var g := scene.game
	var speed := roundi(scene.duel.pitch.release_speed_kmh()) if scene.duel != null and scene.duel.pitch != null and scene.duel.phase != PitchDuel.Phase.READY else 0
	var intro := introducing()
	if intro:
		_ask_portrait()
	return "%s|%s|%d%d%d|%s|%d|%d-%d|%s|%s|%s|%s" % [g.line[0], g.line[1], g.balls, g.strikes, g.outs, g.batter_id(), speed, scene.scorer.book.hits[0], scene.scorer.book.hits[1], g.over, intro, _portrait_for, song_on]


## The batter's introduction fills the board (a KBO park's board between batters: his face,
## number, name, position and season) from when he comes up until the first pitch to him.
func introducing() -> bool:
	if scene == null or scene.game == null or scene.game.over:
		return false
	var g := scene.game
	if g.balls != 0 or g.strikes != 0:
		return false
	return scene.duel == null or scene.duel.pitch == null or scene.duel.phase == PitchDuel.Phase.READY


func _ask_portrait() -> void:
	var g := scene.game
	var id := g.batter_id()
	if id == _asked_for:
		return
	_asked_for = id
	var p := g.batting_team().player(id)
	if p == null:
		return
	PortraitStudio.request(self, p, scene.club(g.batting()), func(face: Texture2D) -> void:
		if id == _asked_for:
			portrait = face
			_portrait_for = id)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.035))
	if scene == null or scene.game == null:
		return
	var g := scene.game
	if introducing() and g.batting_team().player(g.batter_id()) != null:
		_draw_intro(g)
		return
	# A board of lamps: a dot-matrix face.
	var font := UiTheme.face(&"board")
	var regular := UiTheme.face(&"board")
	# The line score: a row a team, a column an inning, then R H E.
	var left := 300.0
	var col := 74.0
	var top := 70.0
	var row := 86.0
	var first := maxi(1, g.inning - INNINGS + 1)
	for i: int in INNINGS:
		draw_string(regular, Vector2(left + col * i, top), str(first + i), HORIZONTAL_ALIGNMENT_CENTER, col, 40, DIM)
	for k: int in 3:
		draw_string(regular, Vector2(left + col * (INNINGS + 0.4 + k), top), ["R", "H", "E"][k], HORIZONTAL_ALIGNMENT_CENTER, col, 40, AMBER)
	for t: int in 2:
		var y := top + 28.0 + row * (t + 1) - 20.0
		var team := g.teams[t]
		var at_bat := g.batting() == t and not g.over
		draw_string(font, Vector2(40.0, y), team.short_name, HORIZONTAL_ALIGNMENT_LEFT, 240.0, 52, AMBER if at_bat else LED)
		for i: int in INNINGS:
			var inning := first + i - 1
			if inning < g.line[t].size():
				draw_string(font, Vector2(left + col * i, y), str(g.line[t][inning]), HORIZONTAL_ALIGNMENT_CENTER, col, 52, LED)
		var book := scene.scorer.book
		var figures := [g.score[t], book.hits[t], book.errors[t]]
		for k: int in 3:
			draw_string(font, Vector2(left + col * (INNINGS + 0.4 + k), y), str(figures[k]), HORIZONTAL_ALIGNMENT_CENTER, col, 52, AMBER if k == 0 else LED)
	draw_line(Vector2(30.0, 300.0), Vector2(size.x - 30.0, 300.0), Color(1, 1, 1, 0.15), 3.0)
	if g.over:
		draw_string(font, Vector2(40.0, 420.0), "경기 종료", HORIZONTAL_ALIGNMENT_LEFT, -1, 72, AMBER)
		return
	# The batter.
	var team := g.batting_team()
	var batter := team.player(g.batter_id())
	if batter != null:
		draw_string(font, Vector2(40.0, 390.0), "%d  %s" % [batter.number, batter.name], HORIZONTAL_ALIGNMENT_LEFT, 760.0, 64, LED)
		var line: BattingLine = scene.scorer.book.batting.get(batter.id)
		var today := "%d타수 %d안타" % [line.ab, line.hits] if line != null else ""
		draw_string(regular, Vector2(40.0, 460.0), today, HORIZONTAL_ALIGNMENT_LEFT, 760.0, 40, DIM)
	# Count and outs as lamps, the last pitch's speed.
	var lamps := [["B", g.balls, 3, Color(0.3, 0.9, 0.4)], ["S", g.strikes, 2, Color(1.0, 0.8, 0.2)], ["O", g.outs, 2, Color(1.0, 0.3, 0.25)]]
	for k: int in 3:
		var y := 360.0 + k * 62.0
		draw_string(font, Vector2(860.0, y + 18.0), lamps[k][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 44, DIM)
		for n: int in int(lamps[k][2]):
			var lit: bool = n < int(lamps[k][1])
			draw_circle(Vector2(930.0 + n * 52.0, y), 20.0, lamps[k][3] if lit else Color(1, 1, 1, 0.08))
	if scene.duel != null and scene.duel.pitch != null and scene.duel.phase != PitchDuel.Phase.READY:
		draw_string(font, Vector2(1100.0, 420.0), "%d" % roundi(scene.duel.pitch.release_speed_kmh()), HORIZONTAL_ALIGNMENT_CENTER, 260.0, 120, AMBER)
		draw_string(regular, Vector2(1100.0, 480.0), "km/h", HORIZONTAL_ALIGNMENT_CENTER, 260.0, 40, DIM)


## The batter's introduction: his face in a frame of his club's colour on the left; his number
## large, his name, position and hands; his season's figures in boxes; today's line and the
## score along the foot.
func _draw_intro(g: GameState) -> void:
	var team := g.batting_team()
	var p := team.player(g.batter_id())
	var club := scene.club(g.batting())
	var primary := club.primary if club != null else Color(0.12, 0.16, 0.3)
	var accent := club.accent if club != null else AMBER
	var font := UiTheme.face(&"board")
	var w := size.x
	# The club's colour in a band down the left.
	draw_rect(Rect2(0.0, 0.0, 470.0, size.y), primary.darkened(0.35))
	draw_rect(Rect2(470.0, 0.0, 8.0, size.y), accent)
	var frame := Rect2(55.0, 50.0, 360.0, 360.0)
	draw_rect(frame, Color(0.05, 0.06, 0.08))
	if portrait != null and _portrait_for == p.id:
		draw_texture_rect(portrait, frame, false)
	else:
		draw_string(font, Vector2(frame.position.x, frame.get_center().y + 60.0), str(p.number), HORIZONTAL_ALIGNMENT_CENTER, frame.size.x, 180, Color(1, 1, 1, 0.25))
	draw_rect(frame, accent, false, 6.0)
	draw_string(font, Vector2(55.0, 490.0), team.short_name, HORIZONTAL_ALIGNMENT_CENTER, 360.0, 52, LED)
	# The number and the name, his place in the order, his position and hands.
	var x := 520.0
	draw_string(font, Vector2(x, 150.0), str(p.number), HORIZONTAL_ALIGNMENT_LEFT, -1, 140, AMBER)
	var nw := font.get_string_size(str(p.number), HORIZONTAL_ALIGNMENT_LEFT, -1, 140).x
	draw_string(font, Vector2(x + nw + 36.0, 140.0), p.name, HORIZONTAL_ALIGNMENT_LEFT, w - x - nw - 60.0, 104, LED)
	var slot := team.slot_of(p.id)
	var kind := team.lineup[slot].position if slot >= 0 else p.primary_position()
	var hands := "%s투%s타" % ["좌" if p.throws == &"L" else "우", "양" if p.bats == &"S" else ("좌" if p.bats == &"L" else "우")]
	var order := "%d번 타자 · " % (slot + 1) if slot >= 0 else ""
	draw_string(font, Vector2(x, 220.0), "%s%s · %s" % [order, Position.name_of(kind), hands], HORIZONTAL_ALIGNMENT_LEFT, w - x - 40.0, 46, DIM)
	# His season (or his ratings in a game outside a season), in four boxes.
	var figures: Array = scene.season_figures(p)
	var box_w := (w - x - 60.0) / 4.0
	for k: int in mini(figures.size(), 4):
		var r := Rect2(x + k * box_w, 258.0, box_w - 16.0, 170.0)
		draw_rect(r, Color(1, 1, 1, 0.06))
		draw_string(font, Vector2(r.position.x, r.position.y + 50.0), str(figures[k][0]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 38, DIM)
		draw_string(font, Vector2(r.position.x, r.position.y + 140.0), str(figures[k][1]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 80, LED)
	# Today, and the song when it plays.
	var line: BattingLine = scene.scorer.book.batting.get(p.id)
	var today := "오늘 %d타수 %d안타" % [line.ab, line.hits] if line != null and line.pa > 0 else "오늘 첫 타석"
	draw_string(font, Vector2(x, 510.0), today, HORIZONTAL_ALIGNMENT_LEFT, 380.0, 46, LED)
	if song_on:
		draw_string(font, Vector2(x + 400.0, 510.0), "♪ 응원가", HORIZONTAL_ALIGNMENT_LEFT, -1, 46, AMBER)
