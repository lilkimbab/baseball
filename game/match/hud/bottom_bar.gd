class_name BottomBar
extends HudCanvas
## The bottom bar: the batter on the left (order, position, name, overall,
## today's line), the pitcher on the right (role, hand, name, overall, pitch count and
## stamina), the keys in between, and above them the last play in one line. Holding Tab
## opens the detail cards: ratings and today's record for both.
##
## Number formats follow the scorebook: averages to three places without the leading zero
## (.287), ERA to two (3.45), innings in thirds (5⅔).

const HEIGHT := 92.0
## The batter's and the pitcher's cards (the user, 2026-11-23: "the number next to the name, the
## card too big with too much empty space"): a lower third as broadcasts draw one, sat on the
## bar's foot.
const CARD := 440.0
const CARD_HEIGHT := 78.0
## The overall's block at a card's right end.
const OVR_BLOCK := 74.0
## The detail cards (Tab).
const DETAIL_WIDTH := 540.0
const DETAIL_HEIGHT := 280.0
## Their header band in the club's colours.
const DETAIL_HEAD := 46.0

var scene: MatchScene
## Tab is held: show the detail cards.
var detail := false
var _ovr: Overall


func _draw() -> void:
	if scene == null or scene.game == null:
		return
	# Before the first pitch the broadcast has the screen (the match-up, the line-ups): no
	# batter's card under it (the user: "첫 타석" showed under the line-up).
	if scene.pregame_showing() or scene.post_game_showing():
		return
	# (Nor while the champions celebrate: their title's band has the bottom.)
	if scene.broadcast != null and scene.broadcast.current != null and scene.broadcast.current.kind == Broadcast.Kind.CHAMPION:
		return
	begin()
	if _ovr == null:
		_ovr = LeagueEnvIO.load_overall()
	var g := scene.game
	var top := view.y - HEIGHT - 14.0
	var bat := g.batting_team()
	var field := g.fielding_team()
	var batter := bat.player(g.batter_id())
	var pitcher := field.player(g.pitcher_id())
	var card_top := top + HEIGHT - CARD_HEIGHT
	_batter_card(Rect2(Vector2(20.0, card_top), Vector2(CARD, CARD_HEIGHT)), bat, batter, g)
	_pitcher_card(Rect2(Vector2(view.x - CARD - 20.0, card_top), Vector2(CARD, CARD_HEIGHT)), field, pitcher, g)
	var middle_x := CARD + 36.0
	var middle_w := view.x - 2.0 * CARD - 72.0
	var keys := Rect2(Vector2(middle_x, top + HEIGHT - 34.0), Vector2(middle_w, 34.0))
	panel(keys, UiTheme.PANEL_DARK, 0.0)
	keycaps(Vector2(middle_x, keys.end.y - 10.0), scene.help_keys() + "   Tab 상세", middle_w, 15)
	if scene.last_text != "" and Settings.commentary:
		# The play-by-play on the broadcast's plate, a white tab with the inning at its left.
		var line := Rect2(Vector2(middle_x, top), Vector2(middle_w, 50.0))
		brand_plate(line, 10.0)
		var tab := Rect2(line.position + Vector2(10.0, 9.0), Vector2(74.0, 32.0))
		draw_colored_polygon(plate_shape(tab, 6.0), Color(1, 1, 1, 0.92))
		text(tab.position + Vector2(0.0, 23.0), "%d회%s" % [g.inning, "초" if g.top else "말"], 16, HudCanvas.style_colour(3), HORIZONTAL_ALIGNMENT_CENTER, tab.size.x, 800)
		# (Smaller for a long line, so it stays on its plate.)
		var size := 20
		while size > 14 and text_width(scene.last_text, size, 700) > line.size.x - 104.0:
			size -= 1
		text(line.position + Vector2(92.0, 34.0 - (20 - size) * 0.35), scene.last_text, size, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, line.size.x - 100.0, 700)
	if detail:
		_batter_detail(Rect2(Vector2(20.0, top - DETAIL_HEIGHT - 14.0), Vector2(DETAIL_WIDTH, DETAIL_HEIGHT)), batter, g)
		_pitcher_detail(Rect2(Vector2(view.x - DETAIL_WIDTH - 20.0, top - DETAIL_HEIGHT - 14.0), Vector2(DETAIL_WIDTH, DETAIL_HEIGHT)), pitcher, g)


## A player's card: the plate, his club's colour down the edge, a grey line over his name, the
## overall in a block of its own at the right (as the menus' player card has it).
func _card(rect: Rect2, side: int, head: String, p: Player, ovr: int, note: String) -> Vector2:
	# In his club's colours (the user, 2026-11-23: "less black"), the emblem at the left.
	var club := scene.club(side)
	team_plate(rect, club, 12.0, 0.96, false)
	if club != null:
		Emblem.draw_emblem(self, club, Rect2(rect.position + Vector2(14.0, (rect.size.y - 48.0) * 0.5), Vector2(48.0, 48.0)))
	var x := rect.position.x + 74.0
	var right := rect.end.x - OVR_BLOCK - 12.0
	# Above: his place in the order (or his role) and hand; today's figures at the right.
	text(Vector2(x, rect.position.y + 26.0), head, 15, Color(1, 1, 1, 0.78), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600)
	if note != "":
		text(Vector2(x, rect.position.y + 26.0), note, 15, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, right - x, 600)
	# Below: his number on a white chip in the club's colour, then his name, as a broadcast
	# writes them (the user, 2026-11-23: no gold here).
	var number := str(p.number)
	var digits := UiTheme.numeric(true, true)
	var chip := Rect2(Vector2(x, rect.position.y + 36.0), Vector2(digits.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26).x + 16.0, 32.0))
	draw_colored_polygon(plate_shape(chip, 6.0), Color(1.0, 1.0, 1.0, 0.94))
	var ink := HudCanvas.club_colour(club)
	if ink.get_luminance() > 0.55:
		ink = ink.darkened(0.55)
	var f := digits
	draw_string(f, Vector2(chip.position.x, chip.position.y + 26.0), number, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 26, ink)
	var nx := chip.end.x + 10.0
	var size := 28
	while size > 20 and text_width(p.name, size, 800) > right - nx:
		size -= 1
	text(Vector2(nx, rect.position.y + 61.0), p.name, size, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 800)
	# The overall in white on a dark tab, its tier's colour (UiTheme.TIERS) in the line on top.
	var block := Rect2(Vector2(rect.end.x - OVR_BLOCK + 2.0, rect.position.y + 8.0), Vector2(OVR_BLOCK - 12.0, rect.size.y - 18.0))
	var tier := UiTheme.rating_color(ovr)
	draw_colored_polygon(plate_shape(block, 8.0), Color(0.0, 0.0, 0.0, 0.42))
	draw_rect(Rect2(block.position, Vector2(block.size.x, 3.0)), tier if tier.get_luminance() >= 0.2 else Color(0.75, 0.77, 0.8))
	figure(block.position + Vector2(0.0, 40.0), UiTheme.shown_text(ovr), 36, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, block.size.x, true)
	figure(block.position + Vector2(0.0, 55.0), "OVR", 12, Color(1, 1, 1, 0.65), HORIZONTAL_ALIGNMENT_CENTER, block.size.x)
	return Vector2(x, right)


func _batter_card(rect: Rect2, team: TeamInGame, p: Player, g: GameState) -> void:
	if p == null:
		panel(rect, UiTheme.PANEL, 12.0)
		return
	var slot := team.slot_of(p.id)
	var pos := team.lineup[slot].position if slot >= 0 else Position.Kind.DH
	var throws := g.fielding_team().player(g.pitcher_id())
	var side := p.batting_side(throws.throws if throws != null else &"R")
	var head := "%d번 · %s · %s타" % [slot + 1, Position.name_of(pos), "좌" if side == &"L" else "우"]
	_card(rect, g.batting(), head, p, roundi(_ovr.batter(p, pos)), today_batting(scene.scorer.book.bat(p.id)))


func _pitcher_card(rect: Rect2, team: TeamInGame, p: Player, g: GameState) -> void:
	if p == null or p.pitching == null:
		panel(rect, UiTheme.PANEL, 12.0)
		return
	var starter := p.id == team.starter_id
	var head := "%s · %s투" % ["선발" if starter else "구원", "좌" if p.throws == &"L" else "우"]
	var pitches: int = g.pitch_counts.get(p.id, 0)
	# What is left of him today, named so (the rating 체력 is on the Tab card, in its tier's
	# colour; this is the game's, in one colour of its own), and a thin bar of it at the foot.
	var left := stamina_left(p, pitches, starter)
	var span := _card(rect, g.fielding(), head, p, roundi(Overall.pitcher(p, scene.catalog)), "투구 %d  ·  남은 체력 %d%%" % [pitches, roundi(left * 100.0)])
	var foot := Rect2(Vector2(span.x, rect.end.y - 9.0), Vector2(span.y - span.x, 4.0))
	draw_rect(foot, Color(0.0, 0.0, 0.0, 0.45))
	draw_rect(Rect2(foot.position, Vector2(foot.size.x * clampf(left, 0.0, 1.0), foot.size.y)), UiTheme.STAMINA)


# --- The detail cards (Tab) ---
# The user, 2026-11-23: "the ratings are too plain; make them worth looking at, as 2K14". As
# 2K14's player sheet: a header in the club's colours, the man's shape on a pentagon, each
# rating on a segmented bar in its grade's colour with the number beside it, today's line in
# tiles, and below them his season (a batter) or his pitches and their speeds (a pitcher).


func _batter_detail(rect: Rect2, p: Player, g: GameState) -> void:
	if p == null:
		panel(rect, UiTheme.PANEL_DARK, 12.0)
		return
	var throws := g.fielding_team().player(g.pitcher_id())
	var hand: StringName = throws.throws if throws != null else &"R"
	var body := _detail_head(rect, g.batting(), p.name, "상대 %s투" % ("좌" if hand == &"L" else "우"))
	_radar(body.position + Vector2(100.0, 118.0), 58.0, ["컨택", "파워", "선구안", "주력", "수비"],
		[p.batting.contact(), p.batting.power(), p.batting.eye, p.batting.speed, p.fielding.overall()])
	var x0 := body.position.x + 196.0
	heading(Vector2(x0, body.position.y + 24.0), "%s투 상대" % ("좌" if hand == &"L" else "우"), "", UiTheme.ACCENT, 15)
	var rows: Array = [["컨택", p.batting.contact_vs(hand)], ["파워", p.batting.power_vs(hand)], ["선구안", p.batting.eye], ["주력", p.batting.speed], ["수비", p.fielding.overall()]]
	for i: int in rows.size():
		_rating_row(Vector2(x0, body.position.y + 36.0 + 32.0 * i), 188.0, rows[i][0], float(rows[i][1]))
	var line := scene.scorer.book.bat(p.id)
	var x1 := body.position.x + 396.0
	heading(Vector2(x1, body.position.y + 24.0), "오늘 기록", "", UiTheme.ACCENT, 15)
	_tiles(Rect2(Vector2(x1, body.position.y + 36.0), Vector2(132.0, 156.0)), [
		["타수", line.ab, false], ["안타", line.hits, line.hits > 0], ["홈런", line.home_runs, line.home_runs > 0],
		["타점", line.rbi, line.rbi > 0], ["볼넷", line.walks + line.intentional_walks, false], ["삼진", line.strikeouts, false]])
	_season_strip(Rect2(Vector2(x0, body.position.y + 200.0), Vector2(body.end.x - 12.0 - x0, 26.0)), p)


func _pitcher_detail(rect: Rect2, p: Player, g: GameState) -> void:
	if p == null or p.pitching == null:
		panel(rect, UiTheme.PANEL_DARK, 12.0)
		return
	var team := g.fielding_team()
	var starter := p.id == team.starter_id
	var body := _detail_head(rect, g.fielding(), p.name, "%s · %s투" % ["선발" if starter else "구원", "좌" if p.throws == &"L" else "우"])
	var stuff := p.pitching.stuff(scene.catalog)
	_radar(body.position + Vector2(100.0, 118.0), 58.0, ["구위", "제구", "견제", "체력", "위기관리"],
		[stuff, p.pitching.control, p.pitching.hold, p.pitching.stamina, p.pitching.composure])
	var x0 := body.position.x + 196.0
	heading(Vector2(x0, body.position.y + 24.0), "능력", "", UiTheme.ACCENT, 15)
	var pitches: int = g.pitch_counts.get(p.id, 0)
	_stamina_row(Vector2(x0, body.position.y + 36.0), 188.0, stamina_left(p, pitches, starter))
	var rows: Array = [["제구", p.pitching.control], ["구위", stuff], ["위기관리", p.pitching.composure]]
	for i: int in rows.size():
		_rating_row(Vector2(x0, body.position.y + 68.0 + 32.0 * i), 188.0, rows[i][0], float(rows[i][1]))
	var line := scene.scorer.book.pitch(p.id)
	var x1 := body.position.x + 396.0
	heading(Vector2(x1, body.position.y + 24.0), "오늘 기록", "", UiTheme.ACCENT, 15)
	_tiles(Rect2(Vector2(x1, body.position.y + 36.0), Vector2(132.0, 124.0)), [
		["이닝", line.innings_text(), false], ["투구", pitches, false], ["피안타", line.hits, false],
		["실점", line.runs, false], ["볼넷", line.walks + line.intentional_walks, false], ["삼진", line.strikeouts, line.strikeouts > 0]], 3)
	# His pitches and their speeds for the person's own pitcher only; an opposing pitcher's are
	# not told (the user, 2026-11-23: "at the plate I am not shown his pitches"). His season
	# instead, as a broadcast shows it.
	if scene.human_pitches():
		_pitch_chips(Rect2(Vector2(x0, body.position.y + 168.0), Vector2(body.end.x - 12.0 - x0, 64.0)), p, true)
	else:
		_season_strip(Rect2(Vector2(x0, body.position.y + 172.0), Vector2(body.end.x - 12.0 - x0, 26.0)), p)


## The card's plate and its header band in the club's colours (emblem, name, a tag at the
## right); returns the rest of the card.
func _detail_head(rect: Rect2, side: int, name: String, tag: String) -> Rect2:
	panel(rect, UiTheme.PANEL_DARK, 12.0)
	var club := scene.club(side)
	var head := Rect2(rect.position, Vector2(rect.size.x, DETAIL_HEAD))
	team_plate(head, club, 12.0)
	if club != null:
		Emblem.draw_emblem(self, club, Rect2(head.position + Vector2(12.0, 6.0), Vector2(34.0, 34.0)))
	text(head.position + Vector2(56.0, 31.0), name, 23, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 800)
	text(head.position + Vector2(66.0 + text_width(name, 23, 800), 30.0), "능력치", 15, Color(1.0, 1.0, 1.0, 0.75), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600)
	var w := text_width(tag, 14, 700) + 22.0
	var chip := Rect2(Vector2(head.end.x - w - 14.0, head.position.y + 11.0), Vector2(w, 24.0))
	draw_colored_polygon(plate_shape(chip, 5.0), Color(0.0, 0.0, 0.0, 0.4))
	text(chip.position + Vector2(0.0, 17.0), tag, 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w, 700)
	return Rect2(Vector2(rect.position.x, head.end.y), Vector2(rect.size.x, rect.size.y - DETAIL_HEAD))


## The man's shape on a pentagon: rings at a quarter, a half, three quarters and the top, the
## shape in one colour for every man (UiTheme.RADAR; the card carries the club's), each
## spoke's name and number (in its tier's colour) outside.
func _radar(centre: Vector2, radius: float, labels: Array, values: Array) -> void:
	var n := labels.size()
	var outer := PackedVector2Array()
	for i: int in n:
		outer.append(_spoke(centre, radius, i, n, 1.0))
	draw_colored_polygon(outer, Color(0.0, 0.0, 0.0, 0.38))
	for ring: int in 4:
		var points := PackedVector2Array()
		for i: int in n + 1:
			points.append(_spoke(centre, radius, i % n, n, (ring + 1) / 4.0))
		draw_polyline(points, Color(1.0, 1.0, 1.0, 0.1 if ring < 3 else 0.3), 1.0, true)
	for i: int in n:
		draw_line(centre, outer[i], Color(1.0, 1.0, 1.0, 0.1), 1.0, true)
	var shape := PackedVector2Array()
	for i: int in n:
		shape.append(_spoke(centre, radius, i, n, maxf(UiTheme.shown(float(values[i])), 4.0) / 99.0))
	draw_colored_polygon(shape, Color(UiTheme.RADAR, 0.34))
	var edge := shape.duplicate()
	edge.append(shape[0])
	draw_polyline(edge, UiTheme.RADAR, 2.0, true)
	for i: int in n:
		draw_circle(shape[i], 3.2, Color.WHITE)
	for i: int in n:
		# The name over the number, outside the spoke's end (above it at the top, below it at
		# the foot), kept inside the card's column.
		var at := _spoke(centre, radius + 14.0, i, n, 1.0)
		var dir := (at - centre).normalized()
		var top := at.y - 15.0
		if dir.y < -0.5:
			top = at.y - 32.0
		elif dir.y > 0.5:
			top = at.y - 2.0
		var x := clampf(at.x - 30.0 + dir.x * 16.0, centre.x - radius - 42.0, centre.x + radius + 42.0 - 60.0)
		text(Vector2(x, top + 12.0), str(labels[i]), 13, UiTheme.DIM, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 600)
		figure(Vector2(x, top + 31.0), UiTheme.shown_text(float(values[i])), 19, UiTheme.rating_color(float(values[i])), HORIZONTAL_ALIGNMENT_CENTER, 60.0)


func _spoke(centre: Vector2, radius: float, i: int, n: int, amount: float) -> Vector2:
	var angle := -PI * 0.5 + TAU * i / n
	return centre + Vector2(cos(angle), sin(angle)) * radius * clampf(amount, 0.0, 1.0)


## One rating in a cell: its name, a segmented bar in its grade's colour, the number.
func _rating_row(at: Vector2, width: float, label: String, value: float) -> void:
	var colour := UiTheme.rating_color(value)
	var cell := Rect2(at, Vector2(width, 28.0))
	draw_rect(cell, Color(1.0, 1.0, 1.0, 0.05))
	draw_rect(Rect2(cell.position, Vector2(3.0, cell.size.y)), colour)
	text(at + Vector2(11.0, 20.0), label, 15, Color(1.0, 1.0, 1.0, 0.82), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600)
	_meter(Rect2(at + Vector2(74.0, 10.0), Vector2(width - 74.0 - 46.0, 9.0)), UiTheme.shown(value) / 99.0, colour)
	figure(Vector2(cell.end.x - 42.0, at.y + 23.0), UiTheme.shown_text(value), 23, colour, HORIZONTAL_ALIGNMENT_CENTER, 40.0, true)


## What a starter or a reliever has left, on the same bar, in its one colour (UiTheme.STAMINA).
func _stamina_row(at: Vector2, width: float, left: float) -> void:
	var colour := UiTheme.STAMINA
	var cell := Rect2(at, Vector2(width, 28.0))
	draw_rect(cell, Color(1.0, 1.0, 1.0, 0.05))
	draw_rect(Rect2(cell.position, Vector2(3.0, cell.size.y)), colour)
	text(at + Vector2(11.0, 20.0), "남은 체력", 14, Color(1.0, 1.0, 1.0, 0.82), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600)
	_meter(Rect2(at + Vector2(88.0, 10.0), Vector2(width - 88.0 - 46.0, 9.0)), left, colour)
	figure(Vector2(cell.end.x - 42.0, at.y + 23.0), "%d%%" % roundi(left * 100.0), 20, colour, HORIZONTAL_ALIGNMENT_CENTER, 40.0, true)


## A bar in ten segments: a dark trough, the fill from the colour's deep shade to the colour,
## a gloss on its upper half.
func _meter(rect: Rect2, fraction: float, colour: Color) -> void:
	draw_rect(rect.grow(1.0), Color(0.0, 0.0, 0.0, 0.55))
	var f := clampf(fraction, 0.0, 1.0)
	if f > 0.0:
		var fill := Rect2(rect.position, Vector2(rect.size.x * f, rect.size.y))
		var deep := colour.darkened(0.5)
		draw_polygon(PackedVector2Array([fill.position, Vector2(fill.end.x, fill.position.y), fill.end, Vector2(fill.position.x, fill.end.y)]),
			PackedColorArray([deep, colour, colour, deep]))
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, fill.size.y * 0.45)), Color(1.0, 1.0, 1.0, 0.2))
		# (A black bar is outlined, or it would be lost in its track.)
		if UiTheme.ink_edge(colour).a > 0.0:
			draw_rect(fill, Color(1.0, 1.0, 1.0, 0.4), false, 1.0)
	for i: int in range(1, 10):
		var x := rect.position.x + rect.size.x * i / 10.0
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(0.0, 0.0, 0.0, 0.5), 1.5)


## Today's line in tiles, two to a row: the figure large (gold when it is something he did),
## its name small under it. Items: [name, value, lit].
func _tiles(rect: Rect2, items: Array, columns: int = 2) -> void:
	var gap := 4.0
	var rows := ceili(items.size() / float(columns))
	var w := (rect.size.x - gap * (columns - 1)) / columns
	var h := (rect.size.y - gap * (rows - 1)) / rows
	for i: int in items.size():
		var item: Array = items[i]
		var cell := Rect2(rect.position + Vector2((i % columns) * (w + gap), (i / columns) * (h + gap)), Vector2(w, h))
		draw_rect(cell, Color(0.0, 0.0, 0.0, 0.34))
		draw_rect(Rect2(cell.position, Vector2(w, 2.0)), Color(1.0, 1.0, 1.0, 0.14))
		var lit := bool(item[2])
		figure(cell.position + Vector2(0.0, h * 0.5 + 5.0), str(item[1]), 24 if h >= 44.0 else 21, UiTheme.ACCENT if lit else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w, true)
		text(cell.position + Vector2(0.0, h - 5.0), str(item[0]), 12, UiTheme.DIM, HORIZONTAL_ALIGNMENT_CENTER, w, 500)


## A man's season in one strip (the game's season, else his real one): "시즌" on a tab, then
## four figures (a batter's average, home runs …; a pitcher's ERA, record …); nothing when he
## has neither.
func _season_strip(rect: Rect2, p: Player) -> void:
	var figures := scene.season_figures(p)
	if figures.is_empty() or str(figures[0][0]) == "OVR":
		return
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.34))
	var tab := Rect2(rect.position, Vector2(46.0, rect.size.y))
	draw_rect(tab, Color(UiTheme.ACCENT, 0.9))
	text(tab.position + Vector2(0.0, 18.0), "시즌", 13, Color(0.1, 0.08, 0.04), HORIZONTAL_ALIGNMENT_CENTER, tab.size.x, 800)
	var w := (rect.size.x - tab.size.x - 8.0) / figures.size()
	for i: int in figures.size():
		var x := tab.end.x + 8.0 + w * i
		var name := str(figures[i][0])
		text(Vector2(x, rect.position.y + 18.0), name, 13, UiTheme.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600)
		figure(Vector2(x + text_width(name, 13, 600) + 5.0, rect.position.y + 20.0), str(figures[i][1]), 19, Color.WHITE)


## His pitches as chips, two to a line: the family's colour at the edge, the name, the
## average speed (not with `speeds` off).
func _pitch_chips(rect: Rect2, p: Player, speeds: bool = true) -> void:
	var per_line := 2
	var w := (rect.size.x - 6.0 * (per_line - 1)) / per_line
	for i: int in mini(p.pitching.arsenal.size(), per_line * 3):
		var a := p.pitching.arsenal[i]
		var type: PitchType = scene.catalog.get(a.type)
		var tint := UiTheme.pitch_color(type.family if type != null else &"fastball")
		var cell := Rect2(rect.position + Vector2((i % per_line) * (w + 6.0), (i / per_line) * 22.0), Vector2(w, 19.0))
		draw_colored_polygon(plate_shape(cell, 5.0), Color(0.0, 0.0, 0.0, 0.4))
		draw_rect(Rect2(cell.position, Vector2(4.0, cell.size.y)), tint)
		text(cell.position + Vector2(11.0, 15.0), type.label if type != null else String(a.type), 13, Color(1.0, 1.0, 1.0, 0.86), HORIZONTAL_ALIGNMENT_LEFT, w - 64.0, 600)
		if speeds:
			figure(Vector2(cell.end.x - 64.0, cell.position.y + 16.0), "%d km/h" % roundi(a.velo_avg), 15, tint, HORIZONTAL_ALIGNMENT_RIGHT, 58.0)


## "2타수 1안타", with a home run or RBI if he has one.
static func today_batting(line: BattingLine) -> String:
	if line.pa == 0:
		return "첫 타석"
	var out := "%d타수 %d안타" % [line.ab, line.hits]
	if line.home_runs > 0:
		out += " %d홈런" % line.home_runs
	if line.rbi > 0:
		out += " %d타점" % line.rbi
	if line.walks + line.intentional_walks + line.hit_by_pitch > 0:
		out += " %d사사구" % (line.walks + line.intentional_walks + line.hit_by_pitch)
	return out


## Share of his limit he has left (1 fresh, 0 at the end of it).
static func stamina_left(p: Player, pitches: int, starter: bool) -> float:
	var limit := p.pitching.starter_limit() if starter else p.pitching.reliever_limit()
	return clampf(1.0 - float(pitches) / maxf(limit, 1.0), 0.0, 1.0)
