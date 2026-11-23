class_name SituationBoard
extends HudCanvas
## The situation board of the manager mode (docs/04 section 3.5): over the
## darkened field, the line score at the top, both batting orders at the sides with the man
## at bat marked, the diamond with the count and outs in the middle and the plate
## appearances so far below it, and at the bottom a key moment marked, the orders in force and
## the speed (no win chance or leverage figures: the user, "useless"). Shown while plate
## appearances go by in summary; hidden for a live moment.

const LOG_LINES := 5

var scene: ManagerMatch
var _ovr: Overall


## As a broadcast's game cast (the user, 2026-11-23: "crude, all text"): the clubs in their own
## colours, the bases and the count as lamps, the man at bat against the man on the mound as the
## card in the middle, the last play big, and only the last few plays in short lines.
func _draw() -> void:
	if scene == null or scene.game == null or scene.game.over or not scene.board_visible():
		return
	begin()
	if _ovr == null:
		_ovr = LeagueEnvIO.load_overall()
	var g := scene.game
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.0, 0.0, 0.0, 0.5))
	var top := 96.0
	_line_score(Rect2(Vector2(view.x * 0.5 - 520.0, top), Vector2(1040.0, 118.0)), g)
	for t: int in 2:
		var x := 36.0 if t == 0 else view.x - 36.0 - 400.0
		_lineup(Rect2(Vector2(x, top), Vector2(400.0, 600.0)), g, t)
	_middle(Rect2(Vector2(view.x * 0.5 - 520.0, top + 134.0), Vector2(1040.0, 330.0)), g)
	_plays(Rect2(Vector2(view.x * 0.5 - 520.0, top + 480.0), Vector2(1040.0, 170.0)))
	_footer(Rect2(Vector2(view.x * 0.5 - 520.0, top + 666.0), Vector2(1040.0, 52.0)))
	_card(scene.card_lines())


## The card the game waits on (a scene to play, a reservation's alert).
func _card(lines: PackedStringArray) -> void:
	if lines.is_empty():
		return
	var rect := Rect2(Vector2(view.x * 0.5 - 360.0, 380.0), Vector2(720.0, 70.0 + 46.0 * (lines.size() - 1)))
	brand_plate(rect, 14.0, 0.98)
	text(rect.position + Vector2(0.0, 48.0), lines[0], 30, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 700)
	for i: int in range(1, lines.size()):
		var last := i == lines.size() - 1
		text(rect.position + Vector2(0.0, 48.0 + 44.0 * i), lines[i], 22 if not last else 20, Color.WHITE if not last else Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)


## The line score: each club's row on its own colours, the inning being played lit.
func _line_score(rect: Rect2, g: GameState) -> void:
	panel(rect, Color(UiTheme.PANEL_DARK, 0.94))
	var innings := maxi(maxi(g.line[0].size(), g.line[1].size()), g.rules.innings)
	var col := minf(46.0, (rect.size.x - 430.0) / innings)
	var x0 := rect.position.x + 190.0
	var now := g.inning - 1
	if now >= 0 and now < innings:
		draw_rect(Rect2(Vector2(x0 + now * col, rect.position.y + 8.0), Vector2(col, rect.size.y - 16.0)), Color(1, 1, 1, 0.07))
	for i: int in innings:
		figure(Vector2(x0 + i * col, rect.position.y + 28.0), str(i + 1), 17, UiTheme.DIM, HORIZONTAL_ALIGNMENT_CENTER, col)
	var heads: Array[String] = ["R", "H", "E", "B"]
	var xr := x0 + innings * col + 18.0
	for j: int in 4:
		figure(Vector2(xr + j * 54.0, rect.position.y + 28.0), heads[j], 17, UiTheme.GOLD if j == 0 else UiTheme.DIM, HORIZONTAL_ALIGNMENT_CENTER, 54.0)
	var book := scene.scorer.book
	for t: int in 2:
		var y := rect.position.y + 40.0 + t * 38.0
		var row := Rect2(Vector2(rect.position.x + 10.0, y), Vector2(170.0, 32.0))
		var club := scene.club(t)
		team_plate(row, club, 8.0, 0.96, false)
		if club != null:
			Emblem.draw_emblem(self, club, Rect2(row.position + Vector2(8.0, 2.0), Vector2(28.0, 28.0)))
		text(row.position + Vector2(44.0, 23.0), g.teams[t].short_name, 19, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 120.0, 700)
		if g.batting() == t:
			draw_colored_polygon(PackedVector2Array([Vector2(row.end.x + 2.0, y + 10.0), Vector2(row.end.x + 10.0, y + 16.0), Vector2(row.end.x + 2.0, y + 22.0)]), UiTheme.GOLD)
		for i: int in g.line[t].size():
			figure(Vector2(x0 + i * col, y + 24.0), str(g.line[t][i]), 21, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, col)
		var cells: Array[int] = [g.score[t], book.hits[t], book.errors[t], book.bases_on_balls[t]]
		for j: int in 4:
			figure(Vector2(xr + j * 54.0, y + 24.0), str(cells[j]), 24 if j == 0 else 21, UiTheme.GOLD if j == 0 else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 54.0)


## A club's batting order: its colours at the head, the man at bat lit, each man's game so far
## and his overall in its tier's colour; the pitcher and what he has left at the foot.
func _lineup(rect: Rect2, g: GameState, t: int) -> void:
	panel(rect, Color(UiTheme.PANEL_DARK, 0.94))
	var team := g.teams[t]
	var head := Rect2(rect.position, Vector2(rect.size.x, 58.0))
	var club := scene.club(t)
	team_plate(head, club, 10.0, 0.98, false)
	if club != null:
		Emblem.draw_emblem(self, club, Rect2(head.position + Vector2(12.0, 7.0), Vector2(44.0, 44.0)))
	text(head.position + Vector2(66.0, 37.0), team.name, 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, head.size.x - 130.0, 700)
	if t == scene.my_team:
		figure(Vector2(head.end.x - 64.0, head.position.y + 36.0), "MY", 18, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 52.0, true)
	var up := g.batter_id() if g.batting() == t else ""
	var accent := HudCanvas.club_colour(club)
	for i: int in team.lineup.size():
		var slot := team.lineup[i]
		var p := team.player(slot.player_id)
		var y := rect.position.y + 98.0 + i * 50.0
		var row := Rect2(Vector2(rect.position.x + 8.0, y - 30.0), Vector2(rect.size.x - 16.0, 44.0))
		if slot.player_id == up:
			draw_rect(row, Color(accent, 0.32))
			draw_rect(Rect2(row.position, Vector2(5.0, row.size.y)), UiTheme.GOLD)
		elif i % 2 == 1:
			draw_rect(row, Color(1, 1, 1, 0.03))
		figure(Vector2(rect.position.x + 18.0, y), "%d" % (i + 1), 20, UiTheme.DIM, HORIZONTAL_ALIGNMENT_LEFT, 24.0)
		text(Vector2(rect.position.x + 46.0, y), Position.name_of(slot.position), 15, UiTheme.DIM, HORIZONTAL_ALIGNMENT_LEFT, 64.0)
		text(Vector2(rect.position.x + 112.0, y), p.name if p != null else slot.player_id, 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 150.0, 700)
		var line := scene.scorer.book.bat(slot.player_id)
		figure(Vector2(rect.end.x - 140.0, y), "%d-%d" % [line.ab, line.hits] if line.pa > 0 else "", 18, UiTheme.INK, HORIZONTAL_ALIGNMENT_RIGHT, 60.0)
		if p != null:
			var ovr := _ovr.batter(p, slot.position)
			figure(Vector2(rect.end.x - 66.0, y), UiTheme.shown_text(ovr), 22, UiTheme.rating_color(ovr), HORIZONTAL_ALIGNMENT_RIGHT, 48.0)
	var pitcher := team.player(team.pitcher_id)
	var py := rect.end.y - 34.0
	draw_line(Vector2(rect.position.x + 14.0, py - 32.0), Vector2(rect.end.x - 14.0, py - 32.0), UiTheme.LINE, 1.5)
	if pitcher != null:
		var pitches: int = g.pitch_counts.get(pitcher.id, 0)
		text(Vector2(rect.position.x + 18.0, py), "투수", 15, UiTheme.DIM)
		text(Vector2(rect.position.x + 70.0, py), pitcher.name, 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 150.0, 700)
		figure(Vector2(rect.end.x - 170.0, py), "%d구" % pitches, 18, UiTheme.INK, HORIZONTAL_ALIGNMENT_RIGHT, 60.0)
		var left := BottomBar.stamina_left(pitcher, pitches, pitcher.id == team.starter_id)
		bar(Rect2(Vector2(rect.end.x - 100.0, py - 10.0), Vector2(80.0, 8.0)), left, UiTheme.STAMINA)


## The moment: the inning and the bases and the count as lamps on the broadcast's plate at the
## left; the man at bat against the man on the mound, each on his club's colours, at the right;
## the last play across the foot, big.
func _middle(rect: Rect2, g: GameState) -> void:
	panel(rect, Color(UiTheme.PANEL_DARK, 0.94))
	var box := Rect2(rect.position + Vector2(16.0, 16.0), Vector2(250.0, rect.size.y - 32.0))
	brand_plate(box, 12.0)
	# The inning's number in the figures' face, "회초"/"회말" in the broadcast's.
	var half := "회초" if g.top else "회말"
	var digits := str(g.inning)
	var tag_w := shaped(UiTheme.numeric(true, true), digits, 40).get_line_width() + 6.0 + text_width(half, 26, 700)
	var x0 := box.position.x + (box.size.x - tag_w) * 0.5
	figure(Vector2(x0, box.position.y + 52.0), digits, 40, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)
	text(Vector2(x0 + tag_w - text_width(half, 26, 700), box.position.y + 50.0), half, 26, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
	var centre := Vector2(box.position.x + box.size.x * 0.5, box.position.y + 140.0)
	var d := 40.0
	var spots: Array[Vector2] = [centre + Vector2(d, 0.0), centre + Vector2(0.0, -d), centre + Vector2(-d, 0.0)]
	for b: int in 3:
		var p := spots[b]
		var r := 17.0
		var pts := PackedVector2Array([p + Vector2(0.0, -r), p + Vector2(r, 0.0), p + Vector2(0.0, r), p + Vector2(-r, 0.0)])
		var on := not g.base_empty(b + 1)
		draw_colored_polygon(pts, UiTheme.GOLD if on else Color(1, 1, 1, 0.08))
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.0 if on else 0.45), 1.5, true)
	var rows: Array = [["B", 3, g.balls, UiTheme.GREEN], ["S", 2, g.strikes, UiTheme.GOLD], ["O", 2, g.outs, UiTheme.RED]]
	for i: int in rows.size():
		var row: Array = rows[i]
		var y := box.position.y + 210.0 + i * 30.0
		figure(Vector2(box.position.x + 62.0, y + 8.0), row[0], 22, row[3])
		for j: int in int(row[1]):
			var lamp := Vector2(box.position.x + 100.0 + j * 28.0, y)
			if j < int(row[2]):
				draw_circle(lamp, 9.0, row[3])
			else:
				draw_circle(lamp, 9.0, Color(1, 1, 1, 0.08))
				draw_arc(lamp, 9.0, 0.0, TAU, 20, Color(1, 1, 1, 0.35), 1.2, true)
	# The man at bat and the man on the mound.
	var bat_team := g.batting_team()
	var field_team := g.fielding_team()
	var batter := bat_team.player(g.batter_id())
	var pitcher := field_team.player(g.pitcher_id())
	var x := box.end.x + 20.0
	var w := rect.end.x - 16.0 - x
	var duel: Array = [[scene.club(g.batting()), "AT BAT", batter, BottomBar.today_batting(scene.scorer.book.bat(batter.id)) if batter != null else ""], [scene.club(1 - g.batting()), "PITCHING", pitcher, "투구 %d" % int(g.pitch_counts.get(pitcher.id, 0)) if pitcher != null else ""]]
	for i: int in 2:
		var plate := Rect2(Vector2(x, rect.position.y + 16.0 + i * 96.0), Vector2(w, 84.0))
		var club: Team = duel[i][0]
		team_plate(plate, club, 12.0, 0.97)
		if club != null:
			Emblem.draw_emblem(self, club, Rect2(plate.position + Vector2(14.0, 14.0), Vector2(56.0, 56.0)))
		figure(Vector2(plate.position.x + 84.0, plate.position.y + 28.0), str(duel[i][1]), 16, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)
		var man: Player = duel[i][2]
		if man != null:
			text(Vector2(plate.position.x + 84.0, plate.position.y + 64.0), man.name, 30, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 300.0, 800)
			text(Vector2(plate.end.x - 300.0, plate.position.y + 56.0), str(duel[i][3]), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 280.0, 600)
	# The last play, big.
	var last := Rect2(Vector2(x, rect.position.y + 212.0), Vector2(w, rect.size.y - 228.0))
	draw_rect(last, Color(1, 1, 1, 0.04))
	var call := scene.banner if scene.banner_time > 0.0 and scene.banner != "" else ""
	if call == "" and not scene.log.is_empty():
		call = str(scene.log[-1])
	shout(Vector2(last.position.x, last.position.y + last.size.y * 0.5 + 16.0), call, 34 if call.length() <= 14 else 24, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER, last.size.x)


## The plays before it: a few, short, the newest first.
func _plays(rect: Rect2) -> void:
	panel(rect, Color(UiTheme.PANEL_DARK, 0.94))
	var lines := scene.log.slice(maxi(scene.log.size() - LOG_LINES - 1, 0), maxi(scene.log.size() - 1, 0))
	lines.reverse()
	for i: int in lines.size():
		var y := rect.position.y + 36.0 + i * 30.0
		draw_rect(Rect2(Vector2(rect.position.x + 20.0, y - 14.0), Vector2(6.0, 6.0)), UiTheme.GOLD if i == 0 else Color(1, 1, 1, 0.3))
		text(Vector2(rect.position.x + 38.0, y), str(lines[i]), 18, Color.WHITE if i == 0 else UiTheme.DIM, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 60.0, 600 if i == 0 else 500)


func _footer(rect: Rect2) -> void:
	panel(rect, Color(UiTheme.PANEL_DARK, 0.94))
	var x := rect.position.x + 20.0
	if scene.leverage >= WinExpectancy.HIGH:
		text(Vector2(x, rect.position.y + 34.0), "승부처", 20, UiTheme.RED, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
		x += 90.0
	text(Vector2(x, rect.position.y + 34.0), scene.board_note(), 19, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_LEFT, rect.end.x - x - 120.0, 600)
	figure(Vector2(rect.end.x - 100.0, rect.position.y + 34.0), "×%d" % roundi(scene.speed), 22, UiTheme.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 80.0)
