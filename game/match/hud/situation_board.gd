class_name SituationBoard
extends HudCanvas
## The situation board of the manager mode (docs/05 section 3.5, docs/13 S7-6): over the
## darkened field, the line score at the top, both batting orders at the sides with the man
## at bat marked, the diamond with the count and outs in the middle and the plate
## appearances so far below it, and at the bottom the win chance, the leverage and the orders
## in force. Shown while plate appearances go by in summary; hidden for a live moment.

const LOG_LINES := 9

var scene: ManagerMatch
var _ovr: Overall


func _draw() -> void:
	if scene == null or scene.game == null or scene.game.over or not scene.board_visible():
		return
	begin()
	if _ovr == null:
		_ovr = LeagueEnvIO.load_overall()
	var g := scene.game
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.0, 0.0, 0.0, 0.55))
	_line_score(Rect2(Vector2(view.x * 0.5 - 520.0, 110.0), Vector2(1040.0, 128.0)), g)
	for t: int in 2:
		var x := 40.0 if t == 0 else view.x - 40.0 - 400.0
		_lineup(Rect2(Vector2(x, 110.0), Vector2(400.0, 560.0)), g, t)
	_middle(Rect2(Vector2(view.x * 0.5 - 420.0, 256.0), Vector2(840.0, 520.0)), g)
	_footer(Rect2(Vector2(view.x * 0.5 - 520.0, 790.0), Vector2(1040.0, 64.0)), g)


func _line_score(rect: Rect2, g: GameState) -> void:
	panel(rect, UiTheme.PANEL_DARK)
	var innings := maxi(maxi(g.line[0].size(), g.line[1].size()), g.rules.innings)
	var col := minf(48.0, (rect.size.x - 400.0) / innings)
	var x0 := rect.position.x + 170.0
	for i: int in innings:
		text(Vector2(x0 + i * col, rect.position.y + 30.0), str(i + 1), 17, UiTheme.DIM, HORIZONTAL_ALIGNMENT_CENTER, col)
	var heads: Array[String] = ["R", "H", "E", "B"]
	var xr := x0 + innings * col + 16.0
	for j: int in 4:
		text(Vector2(xr + j * 52.0, rect.position.y + 30.0), heads[j], 17, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 52.0)
	var book := scene.scorer.book
	for t: int in 2:
		var y := rect.position.y + 68.0 + t * 40.0
		var at_bat := g.batting() == t
		text(Vector2(rect.position.x + 20.0, y), g.teams[t].short_name, 22, UiTheme.GOLD if at_bat else UiTheme.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
		for i: int in g.line[t].size():
			text(Vector2(x0 + i * col, y), str(g.line[t][i]), 20, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER, col)
		var cells: Array[int] = [g.score[t], book.hits[t], book.errors[t], book.bases_on_balls[t]]
		for j: int in 4:
			text(Vector2(xr + j * 52.0, y), str(cells[j]), 20, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER, 52.0, 700)


func _lineup(rect: Rect2, g: GameState, t: int) -> void:
	panel(rect, UiTheme.PANEL_DARK)
	var team := g.teams[t]
	var mine := t == scene.my_team
	text(rect.position + Vector2(18.0, 34.0), team.name + ("  (우리)" if mine else ""), 20, UiTheme.GOLD if mine else UiTheme.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
	var up := g.batter_id() if g.batting() == t else ""
	for i: int in team.lineup.size():
		var slot := team.lineup[i]
		var p := team.player(slot.player_id)
		var y := rect.position.y + 74.0 + i * 46.0
		if slot.player_id == up:
			draw_rect(Rect2(Vector2(rect.position.x + 8.0, y - 26.0), Vector2(rect.size.x - 16.0, 38.0)), Color(UiTheme.GOLD, 0.18))
		text(Vector2(rect.position.x + 18.0, y), "%d" % (i + 1), 18, UiTheme.DIM)
		text(Vector2(rect.position.x + 44.0, y), Position.name_of(slot.position), 16, UiTheme.DIM)
		text(Vector2(rect.position.x + 110.0, y), p.name if p != null else slot.player_id, 19, UiTheme.INK)
		var line := scene.scorer.book.bat(slot.player_id)
		text(Vector2(rect.end.x - 160.0, y), "%d-%d" % [line.ab, line.hits] if line.pa > 0 else "", 17, UiTheme.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 70.0)
		if p != null:
			text(Vector2(rect.end.x - 80.0, y), str(roundi(_ovr.batter(p, slot.position))), 17, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 60.0)
	var pitcher := team.player(team.pitcher_id)
	var py := rect.position.y + 74.0 + 9.0 * 46.0 + 10.0
	draw_line(Vector2(rect.position.x + 14.0, py - 30.0), Vector2(rect.end.x - 14.0, py - 30.0), UiTheme.LINE, 1.5)
	if pitcher != null:
		var pitches: int = g.pitch_counts.get(pitcher.id, 0)
		text(Vector2(rect.position.x + 18.0, py), "투수", 16, UiTheme.DIM)
		text(Vector2(rect.position.x + 110.0, py), pitcher.name, 19, UiTheme.INK)
		text(Vector2(rect.end.x - 160.0, py), "%d구" % pitches, 17, UiTheme.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 70.0)
		var left := BottomBar.stamina_left(pitcher, pitches, pitcher.id == team.starter_id)
		bar(Rect2(Vector2(rect.end.x - 80.0, py - 12.0), Vector2(60.0, 10.0)), left, UiTheme.GREEN if left > 0.35 else UiTheme.ORANGE)


func _middle(rect: Rect2, g: GameState) -> void:
	panel(rect, UiTheme.PANEL_DARK)
	var centre := rect.position + Vector2(130.0, 130.0)
	var d := 52.0
	var spots: Array[Vector2] = [centre + Vector2(d, 0.0), centre + Vector2(0.0, -d), centre + Vector2(-d, 0.0), centre + Vector2(0.0, d)]
	draw_polyline(PackedVector2Array([spots[3], spots[0], spots[1], spots[2], spots[3]]), Color(1, 1, 1, 0.4), 2.0, true)
	for b: int in 3:
		var p := spots[b]
		var r := 14.0
		var on := not g.base_empty(b + 1)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0.0, -r), p + Vector2(r, 0.0), p + Vector2(0.0, r), p + Vector2(-r, 0.0)]), UiTheme.GOLD if on else Color(1, 1, 1, 0.18))
	text(centre + Vector2(-110.0, 108.0), "%d회%s  %d아웃" % [g.inning, "초" if g.top else "말", g.outs], 22, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER, 220.0, 700)
	text(centre + Vector2(-110.0, 138.0), "B %d  S %d" % [g.balls, g.strikes], 20, UiTheme.DIM, HORIZONTAL_ALIGNMENT_CENTER, 220.0)
	# Now batting against now pitching.
	var bat := g.batting_team()
	var batter := bat.player(g.batter_id())
	var pitcher := g.fielding_team().player(g.pitcher_id())
	var x := rect.position.x + 290.0
	if batter != null:
		text(Vector2(x, rect.position.y + 50.0), "타자  %s" % batter.name, 22, UiTheme.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
		text(Vector2(x, rect.position.y + 80.0), BottomBar.today_batting(scene.scorer.book.bat(batter.id)), 18, UiTheme.DIM)
	if pitcher != null:
		text(Vector2(x, rect.position.y + 122.0), "투수  %s" % pitcher.name, 22, UiTheme.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
		text(Vector2(x, rect.position.y + 152.0), "투구 %d" % int(g.pitch_counts.get(pitcher.id, 0)), 18, UiTheme.DIM)
	if scene.banner_time > 0.0 and scene.banner != "":
		text(Vector2(rect.position.x, rect.position.y + 232.0), scene.banner, 26, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 700)
	# The plate appearances so far, newest last.
	var lines := scene.log.slice(maxi(scene.log.size() - LOG_LINES, 0))
	for i: int in lines.size():
		var y := rect.position.y + 300.0 + i * 25.0
		text(Vector2(rect.position.x + 24.0, y), lines[i], 17, UiTheme.INK if i == lines.size() - 1 else UiTheme.DIM, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 48.0)


func _footer(rect: Rect2, g: GameState) -> void:
	panel(rect, UiTheme.PANEL_DARK)
	var home := scene.win_chance
	var mine := home if scene.my_team == 1 else 1.0 - home
	text(rect.position + Vector2(20.0, 40.0), "승리 확률  %s %d%%" % [g.teams[scene.my_team].short_name, roundi(mine * 100.0)], 20, UiTheme.INK)
	bar(Rect2(rect.position + Vector2(250.0, 28.0), Vector2(160.0, 12.0)), mine, UiTheme.BLUE)
	var key := scene.leverage >= WinExpectancy.HIGH
	text(rect.position + Vector2(440.0, 40.0), "레버리지 %.1f%s" % [scene.leverage, "  승부처" if key else ""], 20, UiTheme.RED if key else UiTheme.DIM)
	text(rect.position + Vector2(660.0, 40.0), "개입 %d회 남음" % scene.interventions_left, 20, UiTheme.GOLD)
	text(rect.position + Vector2(840.0, 40.0), "×%d" % roundi(scene.speed), 20, UiTheme.DIM)
