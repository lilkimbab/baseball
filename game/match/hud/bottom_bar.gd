class_name BottomBar
extends HudCanvas
## The bottom bar (docs/13 S6-3): the batter on the left (order, position, name, overall,
## today's line), the pitcher on the right (role, hand, name, overall, pitch count and
## stamina), the keys in between, and above them the last play in one line. Holding Tab
## opens the detail cards: ratings and today's record for both.
##
## Number formats follow the scorebook: averages to three places without the leading zero
## (.287), ERA to two (3.45), innings in thirds (5⅔).

const HEIGHT := 92.0
const CARD := 540.0
## The overall's block at a card's right end.
const OVR_BLOCK := 92.0

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
	begin()
	if _ovr == null:
		_ovr = LeagueEnvIO.load_overall()
	var g := scene.game
	var top := view.y - HEIGHT - 14.0
	var bat := g.batting_team()
	var field := g.fielding_team()
	var batter := bat.player(g.batter_id())
	var pitcher := field.player(g.pitcher_id())
	_batter_card(Rect2(Vector2(20.0, top), Vector2(CARD, HEIGHT)), bat, batter, g)
	_pitcher_card(Rect2(Vector2(view.x - CARD - 20.0, top), Vector2(CARD, HEIGHT)), field, pitcher, g)
	var middle_x := CARD + 36.0
	var middle_w := view.x - 2.0 * CARD - 72.0
	var keys := Rect2(Vector2(middle_x, top + HEIGHT - 34.0), Vector2(middle_w, 34.0))
	panel(keys, UiTheme.PANEL_DARK, 0.0)
	keycaps(Vector2(middle_x, keys.end.y - 10.0), scene.help_keys() + "   Tab 상세", middle_w, 15)
	if scene.last_text != "" and Settings.commentary:
		var line := Rect2(Vector2(middle_x, top), Vector2(middle_w, 50.0))
		panel(line, UiTheme.PANEL, 8.0)
		text(line.position + Vector2(0.0, 34.0), scene.last_text, 20, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER, line.size.x)
	if detail:
		_batter_detail(Rect2(Vector2(20.0, top - 252.0), Vector2(CARD, 238.0)), batter, g)
		_pitcher_detail(Rect2(Vector2(view.x - CARD - 20.0, top - 252.0), Vector2(CARD, 238.0)), pitcher, g)


## A player's card: the plate, his club's colour down the edge, a grey line over his name, the
## overall in a block of its own at the right (as the menus' player card has it).
func _card(rect: Rect2, side: int, head: String, name: String, ovr: int) -> void:
	panel(rect, UiTheme.PANEL, 12.0)
	var club := scene.club(side)
	var colour := HudCanvas.club_colour(club)
	club_band(Rect2(rect.position, Vector2(7.0, rect.size.y)), colour, 12.0)
	if club != null:
		Emblem.draw_emblem(self, club, Rect2(rect.position + Vector2(20.0, 22.0), Vector2(46.0, 46.0)))
	text(rect.position + Vector2(80.0, 32.0), head, 16, UiTheme.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500)
	text(rect.position + Vector2(80.0, 70.0), name, 30, UiTheme.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
	var block := Rect2(Vector2(rect.end.x - OVR_BLOCK, rect.position.y), Vector2(OVR_BLOCK, rect.size.y))
	draw_line(block.position + Vector2(0.0, 14.0), Vector2(block.position.x, block.end.y - 14.0), Color(1, 1, 1, 0.12), 1.2)
	figure(block.position + Vector2(0.0, 58.0), UiTheme.shown_text(ovr), 44, UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, block.size.x - 6.0, true)
	figure(block.position + Vector2(0.0, 80.0), "OVR", 14, UiTheme.DIM, HORIZONTAL_ALIGNMENT_CENTER, block.size.x - 6.0)


func _batter_card(rect: Rect2, team: TeamInGame, p: Player, g: GameState) -> void:
	if p == null:
		panel(rect, UiTheme.PANEL, 12.0)
		return
	var slot := team.slot_of(p.id)
	var pos := team.lineup[slot].position if slot >= 0 else Position.Kind.DH
	var throws := g.fielding_team().player(g.pitcher_id())
	var side := p.batting_side(throws.throws if throws != null else &"R")
	var head := "%d번 · %s · %s타" % [slot + 1, Position.name_of(pos), "좌" if side == &"L" else "우"]
	_card(rect, g.batting(), head, p.name, roundi(_ovr.batter(p, pos)))
	# Today's line at the right of the grey line, the name below with the whole width.
	text(Vector2(rect.end.x - OVR_BLOCK - 276.0, rect.position.y + 32.0), today_batting(scene.scorer.book.bat(p.id)), 16, UiTheme.INK, HORIZONTAL_ALIGNMENT_RIGHT, 260.0, 500)


func _pitcher_card(rect: Rect2, team: TeamInGame, p: Player, g: GameState) -> void:
	if p == null or p.pitching == null:
		panel(rect, UiTheme.PANEL, 12.0)
		return
	var starter := p.id == team.starter_id
	var head := "%s · %s투" % ["선발" if starter else "구원", "좌" if p.throws == &"L" else "우"]
	_card(rect, g.fielding(), head, p.name, roundi(Overall.pitcher(p, scene.catalog)))
	# The pitch count and what is left of him at the right of the grey line.
	var pitches: int = g.pitch_counts.get(p.id, 0)
	var x := rect.end.x - OVR_BLOCK - 206.0
	text(Vector2(x, rect.position.y + 32.0), "투구", 16, UiTheme.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500)
	figure(Vector2(x + 38.0, rect.position.y + 34.0), str(pitches), 22, Color.WHITE)
	var left := stamina_left(p, pitches, starter)
	bar(Rect2(Vector2(x + 82.0, rect.position.y + 22.0), Vector2(108.0, 8.0)), left, UiTheme.GREEN if left > 0.35 else (UiTheme.ORANGE if left > 0.15 else UiTheme.RED))


func _batter_detail(rect: Rect2, p: Player, g: GameState) -> void:
	panel(rect, UiTheme.PANEL_DARK, 12.0)
	if p == null:
		return
	var throws := g.fielding_team().player(g.pitcher_id())
	var hand: StringName = throws.throws if throws != null else &"R"
	heading(rect.position + Vector2(20.0, 34.0), "%s  능력치" % p.name, "상대 %s투" % ("좌" if hand == &"L" else "우"))
	var rows: Array = [["컨택", p.batting.contact_vs(hand)], ["파워", p.batting.power_vs(hand)], ["선구안", p.batting.eye], ["주력", p.batting.speed], ["수비", p.fielding.overall()]]
	_rating_rows(rect.position + Vector2(18.0, 62.0), rows)
	var line := scene.scorer.book.bat(p.id)
	text(rect.position + Vector2(300.0, 70.0), "오늘", 18, UiTheme.DIM)
	var stats: Array[String] = [
		"%d타수 %d안타" % [line.ab, line.hits],
		"홈런 %d · 타점 %d" % [line.home_runs, line.rbi],
		"볼넷 %d · 삼진 %d" % [line.walks + line.intentional_walks, line.strikeouts],
		"타율 %s" % BattingLine.rate_text(line.average()) if line.ab > 0 else "타율 -",
	]
	for i: int in stats.size():
		text(rect.position + Vector2(300.0, 100.0 + 30.0 * i), stats[i], 19, UiTheme.INK)


func _pitcher_detail(rect: Rect2, p: Player, g: GameState) -> void:
	panel(rect, UiTheme.PANEL_DARK, 12.0)
	if p == null or p.pitching == null:
		return
	heading(rect.position + Vector2(20.0, 34.0), "%s  능력치" % p.name)
	var pitches: int = g.pitch_counts.get(p.id, 0)
	var left := stamina_left(p, pitches, p.id == g.fielding_team().starter_id)
	text(rect.position + Vector2(18.0, 64.0), "체력", 17, UiTheme.DIM)
	bar(Rect2(rect.position + Vector2(80.0, 53.0), Vector2(170.0, 12.0)), left, UiTheme.GREEN)
	text(rect.position + Vector2(18.0, 90.0), "위기관리", 17, UiTheme.DIM)
	bar(Rect2(rect.position + Vector2(80.0, 79.0), Vector2(170.0, 12.0)), p.pitching.composure / 99.0, UiTheme.BLUE)
	var rows: Array = [["제구", p.pitching.control], ["구위", p.pitching.stuff(scene.catalog)], ["견제", p.pitching.hold]]
	_rating_rows(rect.position + Vector2(18.0, 120.0), rows)
	var line := scene.scorer.book.pitch(p.id)
	text(rect.position + Vector2(300.0, 70.0), "오늘", 18, UiTheme.DIM)
	var stats: Array[String] = [
		"%s이닝 · 투구 %d" % [line.innings_text(), pitches],
		"피안타 %d · 실점 %d(자책 %d)" % [line.hits, line.runs, line.earned_runs],
		"볼넷 %d · 삼진 %d" % [line.walks + line.intentional_walks, line.strikeouts],
	]
	for i: int in stats.size():
		text(rect.position + Vector2(300.0, 100.0 + 30.0 * i), stats[i], 19, UiTheme.INK)
	# His pitches and their speeds, two to a line.
	for i: int in p.pitching.arsenal.size():
		var a := p.pitching.arsenal[i]
		var type: PitchType = scene.catalog.get(a.type)
		var label := "%s %d" % [type.label if type != null else String(a.type), roundi(a.velo_avg)]
		var at := rect.position + Vector2(300.0 + (i % 2) * 130.0, 196.0 + (i / 2) * 20.0)
		text(at, label, 14, UiTheme.DIM)


func _rating_rows(at: Vector2, rows: Array) -> void:
	for i: int in rows.size():
		var row: Array = rows[i]
		var y := at.y + 30.0 * i
		text(Vector2(at.x, y + 8.0), row[0], 17, UiTheme.DIM)
		bar(Rect2(Vector2(at.x + 62.0, y - 3.0), Vector2(150.0, 7.0)), float(row[1]) / 99.0, UiTheme.RATING)
		figure(Vector2(at.x + 222.0, y + 9.0), str(roundi(float(row[1]))), 20, Color.WHITE)


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
