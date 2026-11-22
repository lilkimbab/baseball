class_name PostGame
extends HudCanvas
## After the game (docs/13 S6-10): the line score with runs, hits, errors and walks, the
## winning, losing and saving pitchers, the player of the game, and each side's best
## hitters. Enter plays again, Esc leaves.

var scene: MatchScene


func _draw() -> void:
	if scene == null or scene.game == null or not scene.game.over:
		return
	# The last out's card first.
	if scene.broadcast.current != null:
		return
	begin()
	var g := scene.game
	var book := scene.scorer.book
	var rect := Rect2(Vector2(view.x * 0.5 - 620.0, 156.0), Vector2(1240.0, 760.0))
	panel(rect, UiTheme.PANEL_DARK, 16.0)
	# The head row as the menus' panels have it, with the winner's colour along the top.
	var title := "경기 종료" if g.winner >= 0 else "경기 종료 · 무승부"
	if g.winner >= 0:
		draw_rect(Rect2(rect.position + Vector2(16.0, 0.0), Vector2(rect.size.x - 16.0, 5.0)), HudCanvas.club_colour(scene.club(g.winner)))
	heading(rect.position + Vector2(40.0, 62.0), title, "FINAL", UiTheme.ACCENT, 34)
	draw_line(rect.position + Vector2(40.0, 84.0), rect.position + Vector2(rect.size.x - 40.0, 84.0), Color(1, 1, 1, 0.1), 1.0)
	_line_score(rect.position + Vector2(40.0, 100.0), g, book)
	_decisions(rect.position + Vector2(40.0, 270.0), g, book)
	_mvp(rect.position + Vector2(40.0, 360.0), g, book)
	_best_hitters(rect.position + Vector2(40.0, 470.0), g, book)
	# What the game earned (points, experience) over the keys.
	if not scene.profile_lines.is_empty():
		text(Vector2(rect.position.x, rect.end.y - 66.0), "  ·  ".join(scene.profile_lines), 19, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 600)
	keycaps(Vector2(rect.position.x, rect.end.y - 26.0), scene.post_game_hint(), rect.size.x, 17)


func _line_score(at: Vector2, g: GameState, book: StatBook) -> void:
	var innings := maxi(g.line[0].size(), g.line[1].size())
	var col := 54.0
	var x0 := at.x + 180.0
	for i: int in innings:
		text(Vector2(x0 + i * col, at.y + 26.0), str(i + 1), 20, UiTheme.DIM, HORIZONTAL_ALIGNMENT_CENTER, col)
	var heads: Array[String] = ["R", "H", "E", "B"]
	var xr := x0 + innings * col + 24.0
	for j: int in 4:
		figure(Vector2(xr + j * col, at.y + 26.0), heads[j], 22, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, col)
	for t: int in 2:
		var y := at.y + 70.0 + t * 46.0
		var club := scene.club(t)
		club_band(Rect2(Vector2(at.x, y - 26.0), Vector2(6.0, 34.0)), HudCanvas.club_colour(club))
		if club != null:
			Emblem.draw_emblem(self, club, Rect2(Vector2(at.x + 14.0, y - 27.0), Vector2(34.0, 34.0)))
		text(Vector2(at.x + 56.0, y), g.teams[t].short_name, 24, Color.WHITE if g.winner == t else UiTheme.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
		for i: int in innings:
			var cell := str(g.line[t][i]) if i < g.line[t].size() else "X"
			figure(Vector2(x0 + i * col, y + 1.0), cell, 26, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER, col)
		var totals: Array[int] = [g.score[t], book.hits[t], book.errors[t], book.bases_on_balls[t]]
		for j: int in 4:
			figure(Vector2(xr + j * col, y + 2.0), str(totals[j]), 30 if j == 0 else 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, col)


func _decisions(at: Vector2, g: GameState, book: StatBook) -> void:
	var parts := PackedStringArray()
	if book.winner_id != "":
		parts.append("승리 %s" % _name(g, book.winner_id))
	if book.loser_id != "":
		parts.append("패배 %s" % _name(g, book.loser_id))
	if book.save_id != "":
		parts.append("세이브 %s" % _name(g, book.save_id))
	text(at, "   ·   ".join(parts), 22, UiTheme.INK)


func _mvp(at: Vector2, g: GameState, book: StatBook) -> void:
	var id := GameMvp.pick(g, book)
	if id == "":
		return
	heading(at, "경기 MVP", "", UiTheme.ACCENT, 20)
	var line := ""
	if book.pitching.has(id) and book.pitching[id].outs > 0 and not book.batting.has(id):
		var p := book.pitching[id]
		line = "%s  %s이닝 %d실점 %d삼진" % [_name(g, id), p.innings_text(), p.runs, p.strikeouts]
	elif book.batting.has(id):
		var b := book.batting[id]
		line = "%s  %d타수 %d안타 %d타점" % [_name(g, id), b.ab, b.hits, b.rbi]
		if b.home_runs > 0:
			line += " %d홈런" % b.home_runs
	text(at + Vector2(0.0, 40.0), line, 30, UiTheme.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)


## Each side's three best hitters of the day.
func _best_hitters(at: Vector2, g: GameState, book: StatBook) -> void:
	for t: int in 2:
		var x := at.x + t * 590.0
		heading(Vector2(x, at.y), "%s 타자" % g.teams[t].short_name, "", HudCanvas.club_colour(scene.club(t)), 20)
		var ids: Array[String] = []
		ids.assign(book.batters[t])
		ids.sort_custom(func(a: String, b: String) -> bool: return GameMvp.batter_score(book.batting[a]) > GameMvp.batter_score(book.batting[b]))
		for i: int in mini(3, ids.size()):
			var line := book.batting[ids[i]]
			var desc := "%s  %d타수 %d안타 %d타점" % [_name(g, ids[i]), line.ab, line.hits, line.rbi]
			text(Vector2(x, at.y + 38.0 + i * 34.0), desc, 21, UiTheme.INK)


func _name(g: GameState, id: String) -> String:
	for t: int in 2:
		var p := g.teams[t].player(id)
		if p != null:
			return p.name
	return id
