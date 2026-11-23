class_name PostGame
extends HudCanvas
## After the game (docs/13 S6-10; the user, 2026-11-23: "too plain: richer, and show what the
## game paid"): the final score large between the two clubs with the result for the person's
## side, the line score with runs, hits, errors and walks, the player of the game on a card
## with his face, the winning, losing and saving pitchers with their lines, each side's best
## hitters, and what the game earned as tiles that come in one after another with the total
## counting up. Enter plays again, Esc leaves.

## Seconds: the screen comes in, then the earnings' tiles one after another, the total counting.
const ENTER := 0.35
const REWARDS_AT := 0.55
const REWARD_STEP := 0.16
const COUNT_UP := 0.9

var scene: MatchScene
var _since := -1
var _asked := ""


func _draw() -> void:
	if scene == null or scene.game == null or not scene.game.over:
		_since = -1
		return
	# The last out's card first.
	if scene.broadcast.current != null:
		return
	if _since < 0:
		_since = Time.get_ticks_msec()
	# (A tool photographs it as it ends up: it takes its picture the moment it is shown.)
	var t := 10.0 if Profile.tool_run() else (Time.get_ticks_msec() - _since) / 1000.0
	var a := clampf(t / ENTER, 0.0, 1.0)
	begin()
	var g := scene.game
	var book := scene.scorer.book
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.0, 0.0, 0.0, 0.5 * a))
	var earned := not scene.profile_lines.is_empty()
	var width := 1600.0
	var height := 912.0 if earned else 760.0
	var rect := Rect2(Vector2(view.x * 0.5 - width * 0.5, (view.y - height) * 0.5 + (1.0 - a) * 30.0), Vector2(width, height))
	_hero(Rect2(rect.position, Vector2(width, 250.0)), g, a)
	_line_score(Rect2(rect.position + Vector2(0.0, 262.0), Vector2(width, 136.0)), g, book, a)
	var cards := rect.position.y + 410.0
	_mvp(Rect2(Vector2(rect.position.x, cards), Vector2(520.0, 300.0)), g, book, a)
	_pitchers(Rect2(Vector2(rect.position.x + 540.0, cards), Vector2(480.0, 300.0)), g, book, a)
	_best_hitters(Rect2(Vector2(rect.position.x + 1040.0, cards), Vector2(560.0, 300.0)), g, book, a)
	if earned:
		_rewards(Rect2(Vector2(rect.position.x, cards + 312.0), Vector2(width, 150.0)), t, a)
	keycaps(Vector2(rect.position.x, rect.end.y + 34.0), scene.post_game_hint(), rect.size.x, 17)


## The final score between the two clubs: the winner's colour behind his side and his score
## in white, the loser's dimmed; over it the result for the person's side (or "경기 종료").
func _hero(r: Rect2, g: GameState, a: float) -> void:
	panel(r, Color(UiTheme.PANEL_DARK, 0.97 * a), 18.0)
	var mid := r.position.x + r.size.x * 0.5
	for side: int in 2:
		var club := scene.club(side)
		var colour := HudCanvas.club_colour(club)
		var won := g.winner == side
		# His colour from his end toward the middle, stronger for the winner.
		var from := r.position.x if side == 0 else r.end.x
		var to := mid - 120.0 if side == 0 else mid + 120.0
		var wash := PackedVector2Array([Vector2(from, r.position.y + (18.0 if side == 0 else 0.0)), Vector2(to, r.position.y), Vector2(to, r.end.y), Vector2(from, r.end.y - (0.0 if side == 0 else 18.0))])
		var strong := Color(colour, (0.75 if won else 0.3) * a)
		draw_polygon(wash, PackedColorArray([strong, Color(colour, 0.0), Color(colour, 0.0), strong]))
		var emblem := Rect2(Vector2(r.position.x + 56.0 if side == 0 else r.end.x - 56.0 - 150.0, r.position.y + 50.0), Vector2(150.0, 150.0))
		if club != null and a > 0.3:
			Emblem.draw_emblem(self, club, emblem)
		var name_x := emblem.end.x + 28.0 if side == 0 else emblem.position.x - 28.0 - 420.0
		var align := HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		text(Vector2(name_x, r.position.y + 118.0), g.teams[side].name, 38, Color(Color.WHITE if won or g.winner < 0 else UiTheme.INK, a), align, 420.0, 800)
		text(Vector2(name_x, r.position.y + 150.0), "원정" if side == 0 else "홈", 18, Color(UiTheme.DIM, a), align, 420.0, 500)
		if won:
			var chip := Rect2(Vector2(name_x if side == 0 else name_x + 420.0 - 76.0, r.position.y + 168.0), Vector2(76.0, 30.0))
			draw_rect(chip, Color(UiTheme.GOLD, a))
			text(chip.position + Vector2(0.0, 22.0), "승리", 17, Color(0.08, 0.07, 0.03, a), HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 800)
		var score_at := Vector2(mid - 270.0 if side == 0 else mid + 30.0, r.position.y + 176.0)
		figure(score_at, str(g.score[side]), 132, Color(Color.WHITE if won or g.winner < 0 else UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_CENTER, 240.0)
	# The result, over the middle.
	var mine := scene.own_team()
	var word := "경기 종료"
	var word_colour := UiTheme.ACCENT
	if g.winner < 0:
		word = "무승부"
		word_colour = UiTheme.INK
	elif mine >= 0:
		word = "승리" if g.winner == mine else "패배"
		word_colour = UiTheme.GOLD if g.winner == mine else Color(0.82, 0.42, 0.4)
	shout(Vector2(mid - 200.0, r.position.y + 58.0), word, 38, Color(word_colour, a), HORIZONTAL_ALIGNMENT_CENTER, 400.0)
	figure(Vector2(mid - 60.0, r.position.y + 160.0), ":", 80, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_CENTER, 120.0)
	text(Vector2(mid - 200.0, r.position.y + 222.0), "FINAL · %d이닝" % maxi(g.line[0].size(), g.line[1].size()), 17, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_CENTER, 400.0, 600)


func _line_score(r: Rect2, g: GameState, book: StatBook, a: float) -> void:
	panel(r, Color(UiTheme.PANEL_DARK, 0.95 * a), 12.0)
	var innings := maxi(g.line[0].size(), g.line[1].size())
	var heads: Array[String] = ["R", "H", "E", "B"]
	var name_w := 250.0
	var col := minf(64.0, (r.size.x - 80.0 - name_w - 4.0 * 72.0 - 30.0) / maxf(innings, 1.0))
	var x0 := r.position.x + 40.0 + name_w
	var xr := r.end.x - 40.0 - 4.0 * 72.0
	for i: int in innings:
		text(Vector2(x0 + i * col, r.position.y + 32.0), str(i + 1), 18, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_CENTER, col)
	for j: int in 4:
		figure(Vector2(xr + j * 72.0, r.position.y + 32.0), heads[j], 20, Color(UiTheme.ACCENT, a), HORIZONTAL_ALIGNMENT_CENTER, 72.0)
	draw_rect(Rect2(Vector2(xr - 14.0, r.position.y + 12.0), Vector2(1.0, r.size.y - 24.0)), Color(1.0, 1.0, 1.0, 0.1 * a))
	for t: int in 2:
		var y := r.position.y + 72.0 + t * 42.0
		var club := scene.club(t)
		club_band(Rect2(Vector2(r.position.x + 40.0, y - 25.0), Vector2(6.0, 32.0)), Color(HudCanvas.club_colour(club), a))
		if club != null and a > 0.3:
			Emblem.draw_emblem(self, club, Rect2(Vector2(r.position.x + 56.0, y - 26.0), Vector2(34.0, 34.0)))
		text(Vector2(r.position.x + 100.0, y), g.teams[t].short_name, 23, Color(Color.WHITE if g.winner == t else UiTheme.INK, a), HORIZONTAL_ALIGNMENT_LEFT, name_w - 70.0, 700)
		for i: int in innings:
			var cell := str(g.line[t][i]) if i < g.line[t].size() else "X"
			var scored := i < g.line[t].size() and int(g.line[t][i]) > 0
			figure(Vector2(x0 + i * col, y + 1.0), cell, 24, Color(Color.WHITE if scored else UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_CENTER, col)
		var totals: Array[int] = [g.score[t], book.hits[t], book.errors[t], book.bases_on_balls[t]]
		for j: int in 4:
			figure(Vector2(xr + j * 72.0, y + 2.0), str(totals[j]), 30 if j == 0 else 24, Color(Color.WHITE if j == 0 else UiTheme.INK, a), HORIZONTAL_ALIGNMENT_CENTER, 72.0)


## A card's frame and its heading.
func _card(r: Rect2, title: String, accent: Color, a: float) -> void:
	panel(r, Color(UiTheme.PANEL_DARK, 0.95 * a), 12.0)
	draw_rect(Rect2(r.position + Vector2(12.0, 0.0), Vector2(r.size.x - 12.0, 4.0)), Color(accent, a))
	heading(r.position + Vector2(28.0, 46.0), title, "", Color(accent, a), 20)


func _mvp(r: Rect2, g: GameState, book: StatBook, a: float) -> void:
	_card(r, "경기 MVP", UiTheme.GOLD, a)
	var id := GameMvp.pick(g, book)
	if id == "":
		return
	var side := 0 if g.teams[0].player(id) != null else 1
	var p := g.teams[side].player(id)
	var club := scene.club(side)
	var face := PortraitStudio.cached(p, club) if p != null else null
	if face == null and p != null and _asked != id:
		_asked = id
		PortraitStudio.request(self, p, club, func(_shot: Variant = null) -> void: queue_redraw())
	var box := Rect2(r.position + Vector2(28.0, 78.0), Vector2(190.0, 190.0))
	draw_rect(box, Color(HudCanvas.club_colour(club), 0.35 * a))
	if face != null:
		draw_texture_rect(face, box, false, Color(1, 1, 1, a))
	elif club != null and a > 0.3:
		Emblem.draw_emblem(self, club, box.grow(-30.0))
	var x := box.end.x + 26.0
	var w := r.end.x - x - 20.0
	text(Vector2(x, r.position.y + 112.0), g.teams[side].short_name, 18, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_LEFT, w, 600)
	text(Vector2(x, r.position.y + 156.0), _name(g, id), 38, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_LEFT, w, 800)
	var tiles: Array = []
	if book.pitching.has(id) and book.pitching[id].outs > 0 and not book.batting.has(id):
		var q := book.pitching[id]
		tiles = [["이닝", q.innings_text()], ["실점", "%d" % q.runs], ["탈삼진", "%d" % q.strikeouts]]
	elif book.batting.has(id):
		var b := book.batting[id]
		tiles = [["타수", "%d" % b.ab], ["안타", "%d" % b.hits], ["타점", "%d" % b.rbi]]
		if b.home_runs > 0:
			tiles.append(["홈런", "%d" % b.home_runs])
	var gap := 8.0
	var tw := (w - gap * (tiles.size() - 1)) / maxf(tiles.size(), 1.0)
	for i: int in tiles.size():
		var entry: Array = tiles[i]
		var tile := Rect2(Vector2(x + (tw + gap) * i, r.position.y + 186.0), Vector2(tw, 82.0))
		draw_rect(tile, Color(1.0, 1.0, 1.0, 0.06 * a))
		text(tile.position + Vector2(0.0, 28.0), str(entry[0]), 15, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_CENTER, tw, 500)
		figure(tile.position + Vector2(0.0, 66.0), str(entry[1]), 32, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_CENTER, tw)


## The pitchers of record: a mark (승, 패, 세), the man, his line.
func _pitchers(r: Rect2, g: GameState, book: StatBook, a: float) -> void:
	_card(r, "투수 기록", UiTheme.ACCENT, a)
	var rows: Array = []
	if book.winner_id != "":
		rows.append(["승", UiTheme.GOLD, book.winner_id])
	if book.loser_id != "":
		rows.append(["패", Color(0.62, 0.64, 0.7), book.loser_id])
	if book.save_id != "":
		rows.append(["세", UiTheme.BLUE, book.save_id])
	if rows.is_empty():
		text(r.position + Vector2(0.0, r.size.y * 0.5 + 16.0), "승패 없음", 20, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 500)
		return
	for i: int in rows.size():
		var row: Array = rows[i]
		var y := r.position.y + 84.0 + i * 68.0
		var mark := Rect2(Vector2(r.position.x + 28.0, y), Vector2(44.0, 44.0))
		draw_rect(mark, Color(row[1] as Color, a))
		text(mark.position + Vector2(0.0, 31.0), str(row[0]), 22, Color(0.06, 0.06, 0.08, a), HORIZONTAL_ALIGNMENT_CENTER, mark.size.x, 800)
		var id := str(row[2])
		text(Vector2(mark.end.x + 18.0, y + 20.0), _name(g, id), 24, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 120.0, 700)
		if book.pitching.has(id):
			var q := book.pitching[id]
			text(Vector2(mark.end.x + 18.0, y + 46.0), "%s이닝 · %d실점 · %d탈삼진" % [q.innings_text(), q.runs, q.strikeouts], 17, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 120.0, 500)


## Each side's three best hitters of the day.
func _best_hitters(r: Rect2, g: GameState, book: StatBook, a: float) -> void:
	_card(r, "타자 기록", UiTheme.ACCENT, a)
	var half := (r.size.x - 56.0 - 20.0) * 0.5
	for t: int in 2:
		var x := r.position.x + 28.0 + t * (half + 20.0)
		var colour := HudCanvas.club_colour(scene.club(t))
		draw_rect(Rect2(Vector2(x, r.position.y + 70.0), Vector2(half, 34.0)), Color(colour, 0.45 * a))
		text(Vector2(x + 12.0, r.position.y + 94.0), g.teams[t].short_name, 18, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_LEFT, half - 24.0, 700)
		var ids: Array[String] = []
		ids.assign(book.batters[t])
		ids.sort_custom(func(one: String, two: String) -> bool: return GameMvp.batter_score(book.batting[one]) > GameMvp.batter_score(book.batting[two]))
		for i: int in mini(3, ids.size()):
			var line := book.batting[ids[i]]
			var y := r.position.y + 136.0 + i * 54.0
			text(Vector2(x + 4.0, y), _name(g, ids[i]), 21, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_LEFT, half - 8.0, 700)
			var desc := "%d타수 %d안타 %d타점" % [line.ab, line.hits, line.rbi]
			if line.home_runs > 0:
				desc += " · %d홈런" % line.home_runs
			text(Vector2(x + 4.0, y + 23.0), desc, 16, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_LEFT, half - 8.0, 500)


## What the game earned (points, goals met, levels, achievements): a tile each, coming in one
## after another, and the points of all of them counting up at the end of the row.
func _rewards(r: Rect2, t: float, a: float) -> void:
	panel(r, Color(0.09, 0.075, 0.03, 0.96 * a), 12.0)
	draw_rect(r, Color(UiTheme.GOLD, 0.55 * a), false, 2.0)
	heading(r.position + Vector2(28.0, 44.0), "획득 보상", "", Color(UiTheme.GOLD, a), 20)
	var lines := scene.profile_lines
	var total := 0
	var total_w := 250.0
	var room := r.size.x - 56.0 - total_w - 16.0
	var n := lines.size()
	var gap := 10.0
	var w := minf(300.0, (room - gap * (n - 1)) / maxf(n, 1.0))
	for i: int in n:
		var parts := split_reward(lines[i])
		total += int(parts[2])
		var k := clampf((t - REWARDS_AT - REWARD_STEP * i) / 0.25, 0.0, 1.0)
		if k <= 0.0:
			continue
		var tile := Rect2(Vector2(r.position.x + 28.0 + (w + gap) * i, r.position.y + 60.0 + (1.0 - k) * 14.0), Vector2(w, 74.0))
		draw_rect(tile, Color(1.0, 0.92, 0.6, 0.09 * a * k))
		draw_rect(Rect2(tile.position, Vector2(4.0, tile.size.y)), Color(UiTheme.GOLD, a * k))
		text(tile.position + Vector2(16.0, 28.0), str(parts[0]), 17, Color(UiTheme.INK, a * k), HORIZONTAL_ALIGNMENT_LEFT, w - 24.0, 600)
		figure(tile.position + Vector2(16.0, 62.0), str(parts[1]), 28, Color(UiTheme.GOLD, a * k), HORIZONTAL_ALIGNMENT_LEFT, w - 24.0)
	# The total, counting up once the tiles are in.
	var from := REWARDS_AT + REWARD_STEP * n
	var counted := roundi(total * clampf((t - from) / COUNT_UP, 0.0, 1.0))
	var box := Rect2(Vector2(r.end.x - 28.0 - total_w, r.position.y + 22.0), Vector2(total_w, r.size.y - 44.0))
	draw_rect(box, Color(UiTheme.GOLD, 0.16 * a))
	text(box.position + Vector2(0.0, 32.0), "합계", 17, Color(UiTheme.INK, a), HORIZONTAL_ALIGNMENT_CENTER, total_w, 600)
	figure(box.position + Vector2(0.0, 84.0), "+%dP" % counted, 46, Color(UiTheme.GOLD, a), HORIZONTAL_ALIGNMENT_CENTER, total_w)


## A line of what the game paid ("승리 +150P  (올스타 ×1.3)") as [what, how much, points]:
## what it was for (with any note after the points), the amount as written, and the points.
static func split_reward(line: String) -> Array:
	var at := line.rfind("+")
	if at < 0:
		return [line.strip_edges(), "", 0]
	var end := at + 1
	while end < line.length() and line[end] >= "0" and line[end] <= "9":
		end += 1
	var points := int(line.substr(at + 1, end - at - 1))
	var unit := end < line.length() and line[end] == "P"
	var what := line.substr(0, at).strip_edges()
	var note := line.substr(end + (1 if unit else 0)).strip_edges()
	if note != "":
		what = "%s %s" % [what, note]
	return [what, "+%d%s" % [points, "P" if unit else ""], points if unit else 0]


func _name(g: GameState, id: String) -> String:
	for t: int in 2:
		var p := g.teams[t].player(id)
		if p != null:
			return p.name
	return id
