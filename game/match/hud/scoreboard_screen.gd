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


## What the board would show now, as text: it is redrawn only when this changes.
func signature() -> String:
	if scene == null or scene.game == null:
		return ""
	var g := scene.game
	var speed := roundi(scene.duel.pitch.release_speed_kmh()) if scene.duel != null and scene.duel.pitch != null and scene.duel.phase != PitchDuel.Phase.READY else 0
	return "%s|%s|%d%d%d|%s|%d|%d-%d|%s" % [g.line[0], g.line[1], g.balls, g.strikes, g.outs, g.batter_id(), speed, scene.scorer.book.hits[0], scene.scorer.book.hits[1], g.over]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.035))
	if scene == null or scene.game == null:
		return
	var g := scene.game
	var font := UiTheme.font(700)
	var regular := UiTheme.font(500)
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
