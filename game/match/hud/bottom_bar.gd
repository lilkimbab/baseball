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
const CARD := 560.0

var scene: MatchScene
## Tab is held: show the detail cards.
var detail := false
var _ovr: Overall


func _draw() -> void:
	if scene == null or scene.game == null:
		return
	begin()
	if _ovr == null:
		_ovr = LeagueEnvIO.load_overall()
	var g := scene.game
	var top := view.y - HEIGHT - 10.0
	var bat := g.batting_team()
	var field := g.fielding_team()
	var batter := bat.player(g.batter_id())
	var pitcher := field.player(g.pitcher_id())
	_batter_card(Rect2(Vector2(16.0, top), Vector2(CARD, HEIGHT)), bat, batter, g)
	_pitcher_card(Rect2(Vector2(view.x - CARD - 16.0, top), Vector2(CARD, HEIGHT)), field, pitcher, g)
	var keys := Rect2(Vector2(CARD + 28.0, top + HEIGHT - 34.0), Vector2(view.x - 2.0 * CARD - 56.0, 34.0))
	panel(keys)
	text(keys.position + Vector2(0.0, 23.0), scene.help_keys() + "   Tab 상세", 16, UiTheme.DIM, HORIZONTAL_ALIGNMENT_CENTER, keys.size.x)
	if scene.last_text != "" and Settings.commentary:
		var line := Rect2(Vector2(CARD + 28.0, top), Vector2(view.x - 2.0 * CARD - 56.0, 48.0))
		panel(line)
		text(line.position + Vector2(0.0, 32.0), scene.last_text, 20, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER, line.size.x)
	if detail:
		_batter_detail(Rect2(Vector2(16.0, top - 250.0), Vector2(CARD, 238.0)), batter, g)
		_pitcher_detail(Rect2(Vector2(view.x - CARD - 16.0, top - 250.0), Vector2(CARD, 238.0)), pitcher, g)


func _batter_card(rect: Rect2, team: TeamInGame, p: Player, g: GameState) -> void:
	panel(rect)
	if p == null:
		return
	var slot := team.slot_of(p.id)
	var pos := team.lineup[slot].position if slot >= 0 else Position.Kind.DH
	var throws := g.fielding_team().player(g.pitcher_id())
	var side := p.batting_side(throws.throws if throws != null else &"R")
	var head := "%d번 · %s · %s타" % [slot + 1, Position.name_of(pos), "좌" if side == &"L" else "우"]
	text(rect.position + Vector2(18.0, 28.0), head, 17, UiTheme.DIM)
	text(rect.position + Vector2(18.0, 66.0), p.name, 30, UiTheme.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
	text(rect.position + Vector2(rect.size.x - 120.0, 30.0), "OVR %d" % roundi(_ovr.batter(p, pos)), 18, UiTheme.GOLD)
	text(rect.position + Vector2(rect.size.x - 260.0, 70.0), today_batting(scene.scorer.book.bat(p.id)), 18, UiTheme.INK, HORIZONTAL_ALIGNMENT_RIGHT, 240.0)


func _pitcher_card(rect: Rect2, team: TeamInGame, p: Player, g: GameState) -> void:
	panel(rect)
	if p == null or p.pitching == null:
		return
	var starter := p.id == team.starter_id
	var head := "%s · %s투" % ["선발" if starter else "구원", "좌" if p.throws == &"L" else "우"]
	text(rect.position + Vector2(18.0, 28.0), head, 17, UiTheme.DIM)
	text(rect.position + Vector2(18.0, 66.0), p.name, 30, UiTheme.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
	text(rect.position + Vector2(rect.size.x - 120.0, 30.0), "OVR %d" % roundi(Overall.pitcher(p, scene.catalog)), 18, UiTheme.GOLD)
	var pitches: int = g.pitch_counts.get(p.id, 0)
	text(rect.position + Vector2(rect.size.x - 300.0, 70.0), "투구 %d" % pitches, 18, UiTheme.INK)
	var left := stamina_left(p, pitches, starter)
	bar(Rect2(rect.position + Vector2(rect.size.x - 190.0, 58.0), Vector2(160.0, 12.0)), left, UiTheme.GREEN if left > 0.35 else (UiTheme.ORANGE if left > 0.15 else UiTheme.RED))


func _batter_detail(rect: Rect2, p: Player, g: GameState) -> void:
	panel(rect, UiTheme.PANEL_DARK)
	if p == null:
		return
	var throws := g.fielding_team().player(g.pitcher_id())
	var hand: StringName = throws.throws if throws != null else &"R"
	text(rect.position + Vector2(18.0, 32.0), "%s  능력치 (상대 %s투)" % [p.name, "좌" if hand == &"L" else "우"], 20, UiTheme.GOLD)
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
	panel(rect, UiTheme.PANEL_DARK)
	if p == null or p.pitching == null:
		return
	text(rect.position + Vector2(18.0, 32.0), "%s  능력치" % p.name, 20, UiTheme.GOLD)
	var pitches: int = g.pitch_counts.get(p.id, 0)
	var left := stamina_left(p, pitches, p.id == g.fielding_team().starter_id)
	text(rect.position + Vector2(18.0, 64.0), "체력", 17, UiTheme.DIM)
	bar(Rect2(rect.position + Vector2(80.0, 53.0), Vector2(170.0, 12.0)), left, UiTheme.GREEN)
	text(rect.position + Vector2(18.0, 90.0), "평정", 17, UiTheme.DIM)
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
		bar(Rect2(Vector2(at.x + 62.0, y - 4.0), Vector2(150.0, 10.0)), float(row[1]) / 99.0, UiTheme.GOLD)
		text(Vector2(at.x + 220.0, y + 8.0), str(roundi(float(row[1]))), 17, UiTheme.INK)


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
