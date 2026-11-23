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


## The batter's introduction, laid out as a KBO park's board shows it (Gocheok's, for one): the
## batting side's order down the left with each man's average, the man up lit; in the middle his
## face, number and name, his season in eight boxes (average, at-bats, hits, home runs; runs
## batted in, steals, on-base, slugging) and what he has done today; the fielding side's order on
## the right; the line score and the count along the foot.
func _draw_intro(g: GameState) -> void:
	var team := g.batting_team()
	var p := team.player(g.batter_id())
	var club := scene.club(g.batting())
	var primary := club.primary if club != null else Color(0.12, 0.16, 0.3)
	var accent := club.accent if club != null else AMBER
	var font := UiTheme.face(&"board")
	var w := size.x
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.035))
	# The two orders.
	_draw_order(g, g.batting(), Rect2(14.0, 14.0, 330.0, 452.0), g.batter_id())
	_draw_order(g, g.fielding(), Rect2(w - 344.0, 14.0, 330.0, 452.0), "")
	# The middle: his face, number and name.
	var mid := Rect2(360.0, 14.0, w - 720.0, 452.0)
	draw_rect(mid, primary.darkened(0.55))
	draw_rect(Rect2(mid.position, Vector2(mid.size.x, 6.0)), accent)
	var frame := Rect2(mid.position + Vector2(16.0, 22.0), Vector2(190.0, 190.0))
	draw_rect(frame, Color(0.05, 0.06, 0.08))
	if portrait != null and _portrait_for == p.id:
		draw_texture_rect(portrait, frame, false)
	draw_rect(frame, accent, false, 4.0)
	var x := frame.end.x + 22.0
	draw_string(font, Vector2(x, mid.position.y + 70.0), "NO.%d" % p.number, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, AMBER)
	draw_string(font, Vector2(x, mid.position.y + 140.0), p.name, HORIZONTAL_ALIGNMENT_LEFT, mid.end.x - x - 10.0, 64, LED)
	var slot := team.slot_of(p.id)
	var kind := team.lineup[slot].position if slot >= 0 else p.primary_position()
	draw_string(font, Vector2(x, mid.position.y + 190.0), ("%d번 · " % (slot + 1) if slot >= 0 else "") + Position.name_of(kind), HORIZONTAL_ALIGNMENT_LEFT, mid.end.x - x - 10.0, 34, DIM)
	# His season, eight boxes in two rows.
	var st: Dictionary = scene.board_stats(p)
	var cells := [["타율", "avg"], ["타수", "ab"], ["안타", "h"], ["홈런", "hr"], ["타점", "rbi"], ["도루", "sb"], ["출루율", "obp"], ["장타율", "slg"]]
	var cw := (mid.size.x - 32.0) / 4.0
	var top := mid.position.y + 230.0
	draw_string(font, Vector2(x, mid.position.y + 222.0), str(st.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, mid.end.x - x - 10.0, 26, AMBER)
	for i: int in 8:
		var r := Rect2(mid.position.x + 16.0 + cw * (i % 4), top + 8.0 + 62.0 * (i / 4), cw - 6.0, 56.0)
		draw_rect(r, Color(1, 1, 1, 0.06))
		draw_string(font, Vector2(r.position.x + 10.0, r.position.y + 38.0), str(cells[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, DIM)
		draw_string(font, Vector2(r.position.x, r.position.y + 40.0), str(st.get(cells[i][1], "-")), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 10.0, 34, LED)
	# Today.
	var today: PackedStringArray = scene.pa_results.get(p.id, PackedStringArray())
	var line := ""
	for i: int in today.size():
		line += "%d. %s   " % [i + 1, today[i]]
	var ty := top + 8.0 + 62.0 * 2 + 10.0
	draw_rect(Rect2(mid.position.x + 16.0, ty, mid.size.x - 32.0, 52.0), Color(1, 1, 1, 0.05))
	draw_string(font, Vector2(mid.position.x + 28.0, ty + 37.0), "오늘 기록", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, AMBER)
	draw_string(font, Vector2(mid.position.x + 180.0, ty + 37.0), line if line != "" else "-", HORIZONTAL_ALIGNMENT_LEFT, mid.size.x - 200.0, 28, LED)
	# The foot: the line score and the count.
	_draw_foot(g, Rect2(14.0, 478.0, w - 28.0, 108.0))


## A side's order as the board lists it: its name, then each slot's number, name, position and
## average; `lit` (the man up) on a bar of light.
func _draw_order(g: GameState, side: int, box: Rect2, lit: String) -> void:
	var font := UiTheme.face(&"board")
	var t := g.teams[side]
	var club := scene.club(side)
	draw_rect(box, Color(1, 1, 1, 0.04))
	draw_rect(Rect2(box.position, Vector2(box.size.x, 42.0)), (club.primary if club != null else Color(0.2, 0.25, 0.4)).darkened(0.2))
	draw_string(font, Vector2(box.position.x + 12.0, box.position.y + 32.0), t.short_name, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 24.0, 30, LED)
	var row := (box.size.y - 50.0) / 9.0
	for i: int in mini(t.lineup.size(), 9):
		var slot := t.lineup[i]
		var man := t.player(slot.player_id)
		if man == null:
			continue
		var y := box.position.y + 50.0 + row * i
		if slot.player_id == lit:
			draw_rect(Rect2(box.position.x, y, box.size.x, row - 2.0), Color(AMBER, 0.85))
		var ink := Color(0.05, 0.05, 0.06) if slot.player_id == lit else LED
		draw_string(font, Vector2(box.position.x + 8.0, y + row * 0.72), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink if slot.player_id == lit else AMBER)
		draw_string(font, Vector2(box.position.x + 34.0, y + row * 0.72), man.name, HORIZONTAL_ALIGNMENT_LEFT, 150.0, 26, ink)
		draw_string(font, Vector2(box.position.x + 186.0, y + row * 0.72), Position.code(slot.position), HORIZONTAL_ALIGNMENT_LEFT, 50.0, 24, ink if slot.player_id == lit else DIM)
		draw_string(font, Vector2(box.position.x + 236.0, y + row * 0.72), str(scene.board_stats(man).get("avg", "-")), HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 246.0, 26, ink)


## The line score by innings with R H E, and the balls, strikes and outs as lamps.
func _draw_foot(g: GameState, box: Rect2) -> void:
	var font := UiTheme.face(&"board")
	draw_rect(box, Color(1, 1, 1, 0.04))
	var col := 48.0
	var left := box.position.x + 150.0
	var first := maxi(1, g.inning - 8)
	for i: int in 9:
		draw_string(font, Vector2(left + col * i, box.position.y + 28.0), str(first + i), HORIZONTAL_ALIGNMENT_CENTER, col, 22, DIM)
	for k: int in 3:
		draw_string(font, Vector2(left + col * (9.4 + k), box.position.y + 28.0), ["R", "H", "E"][k], HORIZONTAL_ALIGNMENT_CENTER, col, 22, AMBER)
	for t: int in 2:
		var y := box.position.y + 62.0 + 38.0 * t
		draw_string(font, Vector2(box.position.x + 12.0, y), g.teams[t].short_name, HORIZONTAL_ALIGNMENT_LEFT, 130.0, 28, AMBER if g.batting() == t else LED)
		for i: int in 9:
			var inning := first + i - 1
			if inning < g.line[t].size():
				draw_string(font, Vector2(left + col * i, y), str(g.line[t][inning]), HORIZONTAL_ALIGNMENT_CENTER, col, 28, LED)
		var figures := [g.score[t], scene.scorer.book.hits[t], scene.scorer.book.errors[t]]
		for k: int in 3:
			draw_string(font, Vector2(left + col * (9.4 + k), y), str(figures[k]), HORIZONTAL_ALIGNMENT_CENTER, col, 28, AMBER if k == 0 else LED)
	var lamps := [["B", g.balls, 3, Color(0.3, 0.9, 0.4)], ["S", g.strikes, 2, Color(1.0, 0.8, 0.2)], ["O", g.outs, 2, Color(1.0, 0.3, 0.25)]]
	var lx := box.end.x - 230.0
	for k: int in 3:
		var y := box.position.y + 26.0 + k * 34.0
		draw_string(font, Vector2(lx, y + 10.0), lamps[k][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, DIM)
		for n: int in int(lamps[k][2]):
			draw_circle(Vector2(lx + 50.0 + n * 40.0, y), 13.0, lamps[k][3] if n < int(lamps[k][1]) else Color(1, 1, 1, 0.08))
