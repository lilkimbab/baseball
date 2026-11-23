class_name BroadcastCards
extends HudCanvas
## The broadcast's cards, on the HUD's plates: the match-up
## before the first pitch, the starting pitcher, the visitors' order; the inning with the half
## just over; the batter coming up (a lower third); the pitching change; "REPLAY". They slide
## in and out with their segment (Broadcast), and say how to skip one that holds the game.

const SLIDE := 0.25

var scene: MatchScene


func _draw() -> void:
	if scene == null or scene.game == null or scene.broadcast.current == null:
		return
	if scene.pause_menu.visible or scene.menu.visible:
		return
	begin()
	var b := scene.broadcast
	var seg := b.current
	var t := b.time
	var a := clampf(t / SLIDE, 0.0, 1.0) * clampf((seg.duration - t) / SLIDE, 0.0, 1.0)
	match seg.kind:
		Broadcast.Kind.PREGAME:
			if t < 4.5:
				_matchup(seg.data, a * clampf((4.5 - t) / SLIDE, 0.0, 1.0))
			elif t < 7.5:
				_person(seg.data.get("starter", ""), 1, "선발 투수", clampf((t - 4.5) / SLIDE, 0.0, 1.0) * clampf((7.5 - t) / SLIDE, 0.0, 1.0))
			elif t < 14.5:
				_order(0, t - 7.5, clampf((t - 7.5) / SLIDE, 0.0, 1.0) * clampf((14.5 - t) / SLIDE, 0.0, 1.0))
			else:
				_order(1, t - 14.5, clampf((t - 14.5) / SLIDE, 0.0, 1.0) * a)
		Broadcast.Kind.HALF:
			_half(seg.data, a)
		Broadcast.Kind.BATTER:
			_person(str(seg.data.get("id", "")), scene.game.batting(), "", a)
		Broadcast.Kind.PITCHER_CHANGE:
			_person(str(seg.data.get("id", "")), scene.game.fielding(), "투수 교체", a)
		Broadcast.Kind.REPLAY:
			_replay_tag(a)
		Broadcast.Kind.GAME_END:
			_game_end(a)
		Broadcast.Kind.CHAMPION:
			_champion(seg.data, t, a)
		Broadcast.Kind.FAREWELL:
			_farewell(seg.data, t, a)
	if seg.holds:
		# (In the corner when a band has the bottom of the screen.)
		if seg.kind in [Broadcast.Kind.CHAMPION, Broadcast.Kind.FAREWELL]:
			keycaps(Vector2(view.x - 260.0, view.y - 28.0), "Space 건너뛰기", 240.0, 15)
		else:
			keycaps(Vector2(0.0, view.y - BottomBar.HEIGHT - 34.0), "Space 건너뛰기", view.x, 15)


## Before the first pitch: the two clubs, their records and the park.
func _matchup(data: Dictionary, a: float) -> void:
	var rect := Rect2(Vector2(view.x * 0.5 - 560.0, view.y * 0.5 - 150.0 + (1.0 - a) * 40.0), Vector2(1120.0, 300.0))
	panel(rect, Color(UiTheme.PANEL, 0.94 * a), 16.0)
	for side: int in 2:
		var club := scene.club(side)
		var x := rect.position.x + (60.0 if side == 0 else rect.size.x - 60.0 - 180.0)
		if club != null:
			Emblem.draw_emblem(self, club, Rect2(Vector2(x, rect.position.y + 40.0), Vector2(180.0, 180.0)))
		var team := scene.game.teams[side]
		text(Vector2(x - 60.0, rect.position.y + 262.0), team.name, 26, Color(UiTheme.INK, a), HORIZONTAL_ALIGNMENT_CENTER, 300.0, 700)
		var record := str(data.get("record%d" % side, ""))
		if record != "":
			text(Vector2(x - 60.0, rect.position.y + 290.0), record, 17, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_CENTER, 300.0, 500)
	figure(Vector2(rect.position.x, rect.position.y + 150.0), "VS", 64, Color(UiTheme.ACCENT, a), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, true)
	text(Vector2(rect.position.x, rect.position.y + 196.0), str(data.get("park", "")), 18, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 500)
	text(Vector2(rect.position.x, rect.position.y + 222.0), str(data.get("weather", "")), 16, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 500)


## A lower third for a man: his club's colour, number, name, what he does, his numbers.
func _person(id: String, side: int, label: String, a: float) -> void:
	var team := scene.game.teams[side]
	var p := team.player(id)
	if p == null:
		return
	var rect := Rect2(Vector2(view.x * 0.5 - 520.0 - (1.0 - a) * 60.0, view.y - BottomBar.HEIGHT - 170.0), Vector2(1040.0, 112.0))
	panel(rect, Color(UiTheme.PANEL, 0.95 * a), 14.0)
	club_band(Rect2(rect.position, Vector2(10.0, rect.size.y)), Color(HudCanvas.club_colour(scene.club(side)), a), 14.0)
	var club := scene.club(side)
	if club != null and a > 0.5:
		Emblem.draw_emblem(self, club, Rect2(rect.position + Vector2(26.0, 20.0), Vector2(72.0, 72.0)))
	figure(rect.position + Vector2(116.0, 74.0), "%d" % p.number, 52, Color(UiTheme.ACCENT, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)
	var role := label
	if role == "":
		var slot := team.slot_of(p.id)
		var pos := team.lineup[slot].position if slot >= 0 else Position.Kind.DH
		role = "%d번 타자 · %s" % [slot + 1, Position.name_of(pos)]
	text(rect.position + Vector2(196.0, 42.0), role, 17, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500)
	text(rect.position + Vector2(196.0, 86.0), p.name, 36, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
	var lines := scene.broadcast_lines(p)
	for i: int in lines.size():
		text(Vector2(rect.end.x - 430.0, rect.position.y + 44.0 + 34.0 * i), lines[i], 19 if i == 0 else 17, Color(UiTheme.INK if i == 0 else UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_RIGHT, 400.0, 600 if i == 0 else 500)


## A club's line-up before the first pitch, as a broadcast shows it (the user: "like the KBO's
## broadcasts, the players on the shape of a ballpark, in order"; and "less empty, more to look
## at"): a header in the club's colour with the opponent; a ballpark on the left where the men
## come out to their places one after another in batting order — face, name, position, number
## in the order — the designated hitter beside the plate and the starting pitcher last; on the
## right the man just announced on a card (face, number, what he plays, four figures of his
## season) and under it the batting order filling in line by line.
const ORDER_STEP := 0.6
const TAG := Vector2(236.0, 60.0)
const BATS := {&"L": "좌타", &"R": "우타", &"S": "양타"}


func _order(side: int, t: float, a: float) -> void:
	var team := scene.game.teams[side]
	var club := scene.club(side)
	var colour := HudCanvas.club_colour(club)
	var rect := Rect2(Vector2(48.0 - (1.0 - a) * 80.0, 84.0), Vector2(view.x - 96.0, view.y - 84.0 - BottomBar.HEIGHT - 50.0))
	panel(rect, Color(UiTheme.PANEL, 0.95 * a), 18.0)
	# The header: the club's colour running out to the right, its emblem and name, the opponent.
	var head := 92.0
	var band := PackedVector2Array([rect.position + Vector2(18.0, 0.0), rect.position + Vector2(rect.size.x * 0.66, 0.0), rect.position + Vector2(rect.size.x * 0.66, head), rect.position + Vector2(0.0, head), rect.position + Vector2(0.0, 18.0)])
	draw_polygon(band, PackedColorArray([Color(colour, 0.92 * a), Color(colour, 0.0), Color(colour, 0.0), Color(colour, 0.92 * a), Color(colour, 0.92 * a)]))
	draw_rect(Rect2(rect.position + Vector2(0.0, head), Vector2(rect.size.x, 2.0)), Color(1.0, 1.0, 1.0, 0.1 * a))
	if club != null and a > 0.3:
		Emblem.draw_emblem(self, club, Rect2(rect.position + Vector2(26.0, 12.0), Vector2(68.0, 68.0)))
	text(rect.position + Vector2(110.0, 50.0), team.name, 36, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 800)
	text(rect.position + Vector2(112.0, 78.0), "선발 라인업", 19, Color(1.0, 1.0, 1.0, 0.82 * a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600)
	var other := scene.game.teams[1 - side]
	var other_club := scene.club(1 - side)
	var other_w := text_width(other.name, 24, 700)
	text(Vector2(rect.end.x - 28.0 - other_w, rect.position.y + 58.0), other.name, 24, Color(UiTheme.INK, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
	if other_club != null and a > 0.3:
		Emblem.draw_emblem(self, other_club, Rect2(Vector2(rect.end.x - 28.0 - other_w - 62.0, rect.position.y + 22.0), Vector2(50.0, 50.0)))
	figure(Vector2(rect.end.x - 28.0 - other_w - 128.0, rect.position.y + 58.0), "VS", 26, Color(UiTheme.ACCENT, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)

	var body := Rect2(rect.position + Vector2(20.0, head + 14.0), Vector2(rect.size.x - 40.0, rect.size.y - head - 32.0))
	var field := Rect2(body.position, Vector2(minf(980.0, body.size.x * 0.55), body.size.y))
	var home := Vector2(field.position.x + field.size.x * 0.5, field.end.y - 80.0)
	var reach := minf(field.size.x * 0.5 / 0.7071 - 8.0, field.size.y - 90.0)
	_field(field, home, reach, colour, a)
	# The men, one after another in batting order; the starting pitcher last.
	var count := team.lineup.size()
	var shown := mini(int(t / ORDER_STEP), count + 1)
	for i: int in mini(shown, count):
		var slot := team.lineup[i]
		var pop := clampf((t - i * ORDER_STEP) / 0.22, 0.0, 1.0)
		_tag(home + _spot(slot.position, reach) + Vector2(0.0, (1.0 - pop) * 12.0), team.player(slot.player_id), "%d" % (i + 1), Position.name_of(slot.position), colour, club, a * pop, i == shown - 1)
	if shown > count:
		var pop := clampf((t - count * ORDER_STEP) / 0.22, 0.0, 1.0)
		_tag(home + _spot(Position.Kind.P, reach) + Vector2(0.0, (1.0 - pop) * 12.0), team.player(team.pitcher_id), "P", "선발 투수", colour, club, a * pop, true)

	# The man just announced.
	var col := Rect2(Vector2(field.end.x + 20.0, body.position.y), Vector2(body.end.x - field.end.x - 20.0, body.size.y))
	var card := Rect2(col.position, Vector2(col.size.x, 286.0))
	var latest := mini(shown, count + 1) - 1
	var p: Player = null
	var role := ""
	var line := ""
	if latest >= count:
		p = team.player(team.pitcher_id)
		role = "선발 투수"
		line = "투수 · %s" % ("좌투" if p != null and p.throws == &"L" else "우투")
	elif latest >= 0:
		var slot := team.lineup[latest]
		p = team.player(slot.player_id)
		role = "%d번 타자" % (latest + 1)
		line = "%s · %s" % [Position.name_of(slot.position), BATS.get(p.bats, "우타") if p != null else ""]
	_feature(card, p, role, line, colour, club, a)

	# The order, filling in.
	var rows := count + 1
	var top := card.end.y + 12.0
	var step := (col.end.y - top) / rows
	for i: int in rows:
		var row := Rect2(Vector2(col.position.x, top + step * i), Vector2(col.size.x, step - 4.0))
		var is_pitcher := i >= count
		var out := shown > i
		var now := i == latest
		draw_rect(row, Color(colour, 0.34 * a) if now else Color(1.0, 1.0, 1.0, (0.05 if out else 0.025) * a))
		draw_rect(Rect2(row.position, Vector2(46.0, row.size.y)), Color(colour.darkened(0.15), (0.95 if out else 0.3) * a))
		figure(Vector2(row.position.x, row.position.y + row.size.y * 0.5 + 9.0), "P" if is_pitcher else "%d" % (i + 1), 24, Color(1.0, 1.0, 1.0, (1.0 if out else 0.4) * a), HORIZONTAL_ALIGNMENT_CENTER, 46.0, true)
		if now:
			draw_rect(Rect2(row.position + Vector2(46.0, 0.0), Vector2(4.0, row.size.y)), Color(UiTheme.ACCENT, a))
		if not out:
			continue
		var who := team.player(team.pitcher_id) if is_pitcher else team.player(team.lineup[i].player_id)
		if who == null:
			continue
		var mid := row.position.y + row.size.y * 0.5 + 7.0
		text(Vector2(row.position.x + 64.0, mid), who.name, 21, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_LEFT, 210.0, 700)
		var place := "선발 투수" if is_pitcher else Position.name_of(team.lineup[i].position)
		text(Vector2(row.position.x + 290.0, mid), place, 17, Color(UiTheme.INK, 0.85 * a), HORIZONTAL_ALIGNMENT_LEFT, 120.0, 500)
		var hand := ("좌투" if who.throws == &"L" else "우투") if is_pitcher else str(BATS.get(who.bats, "우타"))
		text(Vector2(row.position.x + 420.0, mid), hand, 17, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_LEFT, 70.0, 500)
		var figures := scene.season_figures(who)
		if not figures.is_empty():
			var first: Array = figures[0]
			figure(Vector2(row.position.x, mid + 1.0), str(first[1]), 22, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_RIGHT, row.size.x - 16.0)
			var value_w := text_width(str(first[1]), 22, 700) + 12.0
			text(Vector2(row.position.x, mid), str(first[0]), 15, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_RIGHT, row.size.x - 16.0 - value_w, 500)


## The man just announced, on a card: his face large, the number on his back faint behind, what
## he is in the order, his name, where he plays and how he bats, and four figures of his season.
func _feature(card: Rect2, p: Player, role: String, line: String, colour: Color, club: Team, a: float) -> void:
	panel(card, Color(0.045, 0.05, 0.065, 0.92 * a), 12.0)
	var wash := PackedVector2Array([card.position + Vector2(12.0, 0.0), card.position + Vector2(card.size.x * 0.6, 0.0), card.position + Vector2(card.size.x * 0.42, card.size.y), card.position + Vector2(0.0, card.size.y), card.position + Vector2(0.0, 12.0)])
	draw_polygon(wash, PackedColorArray([Color(colour, 0.5 * a), Color(colour, 0.0), Color(colour, 0.0), Color(colour, 0.5 * a), Color(colour, 0.5 * a)]))
	if p == null:
		text(card.position + Vector2(0.0, card.size.y * 0.5 + 8.0), "선발 라인업을 소개합니다", 24, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_CENTER, card.size.x, 600)
		return
	figure(Vector2(card.position.x, card.position.y + 196.0), "%d" % p.number, 220, Color(1.0, 1.0, 1.0, 0.06 * a), HORIZONTAL_ALIGNMENT_RIGHT, card.size.x - 18.0, true)
	var face := PortraitStudio.cached(p, club)
	if face != null:
		draw_texture_rect(face, Rect2(Vector2(card.position.x + 14.0, card.end.y - 252.0), Vector2(252.0, 252.0)), false, Color(1, 1, 1, a))
	var x := card.position.x + 286.0
	var chip_w := text_width(role, 17, 700) + 24.0
	draw_rect(Rect2(Vector2(x, card.position.y + 26.0), Vector2(chip_w, 30.0)), Color(UiTheme.ACCENT, a))
	text(Vector2(x + 12.0, card.position.y + 47.0), role, 17, Color(0.06, 0.06, 0.08, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
	text(Vector2(x, card.position.y + 112.0), p.name, 46, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_LEFT, card.end.x - x - 16.0, 800)
	text(Vector2(x, card.position.y + 146.0), "No.%d · %s" % [p.number, line], 20, Color(UiTheme.INK, 0.9 * a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600)
	# Four figures of his season (or of what he is, before it has begun).
	var figures := scene.season_figures(p)
	var n := figures.size()
	if n == 0:
		return
	var gap := 10.0
	var w := (card.end.x - 16.0 - x - gap * (n - 1)) / n
	for i: int in n:
		var entry: Array = figures[i]
		var tile := Rect2(Vector2(x + (w + gap) * i, card.end.y - 100.0), Vector2(w, 82.0))
		draw_rect(tile, Color(1.0, 1.0, 1.0, 0.06 * a))
		draw_rect(Rect2(tile.position, Vector2(tile.size.x, 3.0)), Color(colour.lightened(0.2), 0.9 * a))
		text(tile.position + Vector2(0.0, 28.0), str(entry[0]), 15, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_CENTER, w, 500)
		figure(tile.position + Vector2(0.0, 66.0), str(entry[1]), 30, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_CENTER, w)


## Where a man stands on the drawn ballpark, from home plate (px): the fielders at their
## places, the designated hitter beside the plate.
static func _spot(kind: Position.Kind, reach: float) -> Vector2:
	var base := reach * 0.3
	match kind:
		Position.Kind.P:
			return Vector2(0.0, -base * 0.72)
		Position.Kind.C:
			return Vector2(0.0, 44.0)
		Position.Kind.B1:
			return Vector2(base * 1.1, -base * 0.93)
		Position.Kind.B3:
			return Vector2(-base * 1.1, -base * 0.93)
		Position.Kind.B2:
			return Vector2.from_angle(deg_to_rad(-70.0)) * reach * 0.52
		Position.Kind.SS:
			return Vector2.from_angle(deg_to_rad(-110.0)) * reach * 0.52
		Position.Kind.LF:
			return Vector2.from_angle(deg_to_rad(-123.0)) * reach * 0.74
		Position.Kind.CF:
			return Vector2(0.0, -reach * 0.84)
		Position.Kind.RF:
			return Vector2.from_angle(deg_to_rad(-57.0)) * reach * 0.74
	return Vector2(-base * 1.55, 14.0)


## A ballpark seen from above: the wall in the club's colour, the warning track, the grass
## mown in bands, the infield's dirt and grass, the lines, the mound, the bags.
func _field(r: Rect2, home: Vector2, reach: float, colour: Color, a: float) -> void:
	draw_rect(r, Color(0.02, 0.03, 0.04, 0.45 * a))
	var arc := func(radius: float, steps: int) -> PackedVector2Array:
		var points := PackedVector2Array([home])
		for i: int in steps + 1:
			points.append(home + Vector2.from_angle(deg_to_rad(-135.0 + 90.0 * i / steps)) * radius)
		return points
	# The warning track, and the grass inside it in bands as it is mown.
	draw_colored_polygon(arc.call(reach, 32), Color(0.5, 0.36, 0.24, 0.95 * a))
	var grass := reach * 0.955
	var bands := 9
	for i: int in bands:
		var from := deg_to_rad(-135.0 + 90.0 * i / bands)
		var to := deg_to_rad(-135.0 + 90.0 * (i + 1) / bands)
		var wedge := PackedVector2Array([home])
		for k: int in 5:
			wedge.append(home + Vector2.from_angle(lerpf(from, to, k / 4.0)) * grass)
		draw_colored_polygon(wedge, Color(0.15, 0.4, 0.21, 0.96 * a) if i % 2 == 0 else Color(0.18, 0.45, 0.24, 0.96 * a))
	# The wall.
	var wall := PackedVector2Array()
	for i: int in 33:
		wall.append(home + Vector2.from_angle(deg_to_rad(-135.0 + 90.0 * i / 32.0)) * reach)
	draw_polyline(wall, Color(colour.lightened(0.15), a), 6.0, true)
	# The infield: its dirt, the grass inside the bases, the mound and the circle at the plate.
	draw_colored_polygon(arc.call(reach * 0.5, 20), Color(0.6, 0.42, 0.27, 0.97 * a))
	var base := reach * 0.3
	var first := home + Vector2.from_angle(deg_to_rad(-45.0)) * base
	var third := home + Vector2.from_angle(deg_to_rad(-135.0)) * base
	var second := home + Vector2(0.0, -base * sqrt(2.0))
	var centre := (home + second) * 0.5
	var inner := PackedVector2Array()
	for corner: Vector2 in [home, first, second, third]:
		inner.append(corner.lerp(centre, 0.24))
	draw_colored_polygon(inner, Color(0.17, 0.44, 0.23, 0.97 * a))
	draw_circle(home + Vector2(0.0, -base * 0.72), reach * 0.04, Color(0.6, 0.42, 0.27, a))
	draw_circle(home, reach * 0.055, Color(0.6, 0.42, 0.27, a))
	# The foul lines out to the wall.
	for angle: float in [-45.0, -135.0] as Array[float]:
		draw_line(home, home + Vector2.from_angle(deg_to_rad(angle)) * reach, Color(1.0, 1.0, 1.0, 0.75 * a), 2.0, true)
	for bag: Vector2 in [first, second, third]:
		draw_colored_polygon(PackedVector2Array([bag + Vector2(0.0, -8.0), bag + Vector2(8.0, 0.0), bag + Vector2(0.0, 8.0), bag + Vector2(-8.0, 0.0)]), Color(1, 1, 1, a))
	draw_colored_polygon(PackedVector2Array([home + Vector2(-7.0, -6.0), home + Vector2(7.0, -6.0), home + Vector2(7.0, 1.0), home + Vector2(0.0, 8.0), home + Vector2(-7.0, 1.0)]), Color(1, 1, 1, a))


## A man on the field: his face, his name, where he plays, and his number in the order.
func _tag(at: Vector2, p: Player, mark: String, place: String, colour: Color, club: Team, a: float, latest: bool) -> void:
	if p == null or a <= 0.0:
		return
	var r := Rect2(at - TAG * 0.5, TAG)
	draw_rect(Rect2(r.position + Vector2(0.0, 4.0), r.size), Color(0.0, 0.0, 0.0, 0.35 * a))
	draw_rect(r, Color(0.05, 0.06, 0.08, 0.94 * a))
	draw_rect(Rect2(r.position, Vector2(5.0, r.size.y)), Color(colour.lightened(0.1), a))
	if latest:
		draw_rect(r.grow(2.0), Color(UiTheme.ACCENT, a), false, 3.0)
	var face := PortraitStudio.cached(p, club)
	if face != null:
		draw_texture_rect(face, Rect2(r.position + Vector2(9.0, 4.0), Vector2(52.0, 52.0)), false, Color(1, 1, 1, a))
	text(r.position + Vector2(68.0, 27.0), p.name, 19, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 104.0, 700)
	text(r.position + Vector2(68.0, 49.0), place, 14, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 104.0, 500)
	figure(Vector2(r.position.x, r.position.y + 43.0), mark, 30, Color(UiTheme.ACCENT, a), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 10.0, true)


## The inning coming up in big letters with its batting club, and the half just over.
func _half(data: Dictionary, a: float) -> void:
	var g := scene.game
	var rect := Rect2(Vector2(view.x * 0.5 - 330.0, 150.0 - (1.0 - a) * 30.0), Vector2(660.0, 150.0 if str(data.get("summary", "")) != "" else 110.0))
	panel(rect, Color(UiTheme.PANEL, 0.95 * a), 16.0)
	draw_rect(Rect2(rect.position + Vector2(16.0, 0.0), Vector2(rect.size.x - 16.0, 5.0)), Color(HudCanvas.club_colour(scene.club(g.batting())), a))
	var club := scene.club(g.batting())
	if club != null and a > 0.5:
		Emblem.draw_emblem(self, club, Rect2(rect.position + Vector2(30.0, 18.0), Vector2(74.0, 74.0)))
	figure(Vector2(rect.position.x + 120.0, rect.position.y + 82.0), "%d" % g.inning, 70, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)
	text(Vector2(rect.position.x + 120.0 + text_width("%d" % g.inning, 70) * 0.62 + 18.0, rect.position.y + 74.0), "회초" if g.top else "회말", 36, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
	text(Vector2(rect.position.x + 330.0, rect.position.y + 74.0), "%s 공격" % g.batting_team().short_name, 24, Color(UiTheme.ACCENT, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600)
	var summary := str(data.get("summary", ""))
	if summary != "":
		draw_line(rect.position + Vector2(24.0, 106.0), rect.position + Vector2(rect.size.x - 24.0, 106.0), Color(1, 1, 1, 0.1 * a), 1.0)
		text(Vector2(rect.position.x, rect.position.y + 136.0), summary, 18, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 500)


func _replay_tag(a: float) -> void:
	var r := Rect2(Vector2(view.x - 260.0, 40.0), Vector2(220.0, 54.0))
	panel(r, Color(UiTheme.PANEL, 0.95 * a), 10.0)
	draw_rect(Rect2(r.position + Vector2(0.0, r.size.y - 4.0), Vector2(r.size.x - 10.0, 4.0)), Color(UiTheme.BRAND if HudCanvas.style == &"red" else HudCanvas.style_colour(2), a))
	figure(r.position + Vector2(0.0, 38.0), "REPLAY", 30, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)
	var kind: StringName = scene.broadcast.current.data.get("kind", &"home_run")
	text(Vector2(r.position.x, r.end.y + 26.0), "홈런" if kind == &"home_run" else "호수비", 17, Color(UiTheme.INK, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 600)


## The title won (the user, 2026-11-23: "bigger, less awkward, not that red"): as a broadcast
## crowns its champions — confetti in gold, white and the club's colours over the whole
## screen, and across the middle a wide black band edged in gold: the year and the round in
## gold, the club's emblem large, its name and "우승" in the shouting face, CHAMPIONS under it.
const CONFETTI := 150
const CROWN_FROM := 3.4
## Seconds after it comes that the band settles low (CHAMPION's toss starts soon after).
const SETTLE_AT := 3.0


func _champion(data: Dictionary, t: float, a: float) -> void:
	if t < CROWN_FROM:
		return
	var u := t - CROWN_FROM
	a *= clampf(u / 0.45, 0.0, 1.0)
	var side := int(data.get("side", GameState.HOME))
	var club := scene.club(side)
	var colours: Array[Color] = [UiTheme.GOLD, Color(1.0, 0.93, 0.66), Color.WHITE]
	if club != null:
		colours.append(HudCanvas.club_colour(club))
		colours.append(club.secondary)
	_confetti(u, colours, a)
	# Big in the middle as it comes; after a few seconds it settles smaller low on the screen,
	# out of the way of the toss (drawn about the band's middle, then moved and scaled).
	var settle := smoothstep(SETTLE_AT, SETTLE_AT + 0.8, u)
	var s := lerpf(1.0, 0.7, settle)
	var centre_y := lerpf(view.y * 0.56, view.y - 150.0, settle)
	draw_set_transform(Vector2(view.x * 0.5 * (1.0 - s), centre_y) * k, 0.0, Vector2(k * s, k * s))
	# The band: dark in the middle, fading out to the sides, gold lines along its edges.
	var h := 250.0
	var y := -h * 0.5
	var grow := 1.0 + 0.08 * (1.0 - clampf(u / 0.35, 0.0, 1.0))
	var band := Rect2(Vector2(0.0, y - h * (grow - 1.0) * 0.5), Vector2(view.x, h * grow))
	var mid := Color(0.02, 0.02, 0.03, 0.86 * a)
	var edge := Color(0.02, 0.02, 0.03, 0.0)
	draw_polygon(PackedVector2Array([band.position, Vector2(view.x * 0.5, band.position.y), Vector2(view.x * 0.5, band.end.y), Vector2(0.0, band.end.y)]), PackedColorArray([edge, mid, mid, edge]))
	draw_polygon(PackedVector2Array([Vector2(view.x * 0.5, band.position.y), Vector2(view.x, band.position.y), band.end, Vector2(view.x * 0.5, band.end.y)]), PackedColorArray([mid, edge, edge, mid]))
	for line_y: float in [band.position.y, band.end.y - 3.0]:
		var gold := Color(UiTheme.GOLD, 0.95 * a)
		var clear := Color(UiTheme.GOLD, 0.0)
		draw_polygon(PackedVector2Array([Vector2(view.x * 0.08, line_y), Vector2(view.x * 0.5, line_y), Vector2(view.x * 0.5, line_y + 3.0), Vector2(view.x * 0.08, line_y + 3.0)]), PackedColorArray([clear, gold, gold, clear]))
		draw_polygon(PackedVector2Array([Vector2(view.x * 0.5, line_y), Vector2(view.x * 0.92, line_y), Vector2(view.x * 0.92, line_y + 3.0), Vector2(view.x * 0.5, line_y + 3.0)]), PackedColorArray([gold, clear, clear, gold]))
	# The words, centred as a group with the emblem at their left.
	var name := club.name if club != null else scene.game.teams[side].short_name
	var title := "%s 우승!" % name
	var big := 96
	while big > 60 and text_width(title, big, 800) * 1.05 > view.x - 520.0:
		big -= 4
	var words := maxf(text_width(title, big, 800) * 1.05, 420.0)
	var mark := 190.0
	var left := (view.x - (mark + 40.0 + words)) * 0.5
	var slide := (1.0 - clampf(u / 0.45, 0.0, 1.0)) * 40.0
	if club != null and a > 0.3:
		# A ring of light behind it, the club's two colours as a stripe under it.
		draw_circle(Vector2(left + mark * 0.5, y + h * 0.5), mark * 0.56, Color(UiTheme.GOLD, 0.12 * a))
		Emblem.draw_emblem(self, club, Rect2(Vector2(left - slide, y + h * 0.5 - mark * 0.5), Vector2(mark, mark)))
	var tx := left + mark + 40.0 + slide
	var tag := "%d %s" % [int(data.get("year", 2026)), str(data.get("round", "")) if str(data.get("round", "")) != "" else "포스트시즌"]
	text(Vector2(tx, y + 62.0), tag, 28, Color(UiTheme.GOLD, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
	shout(Vector2(tx, y + 62.0 + big * 1.02), title, big, Color(Color.WHITE, a))
	var champs := y + 62.0 + big * 1.02 + 52.0
	figure(Vector2(tx, champs), "C H A M P I O N S", 30, Color(UiTheme.GOLD, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))


## A retirement at his park (FarewellScene): the ceremony's name in the corner from the start;
## as his number goes up, a band low across the screen — his name large, his number retired or
## his career in a line — and paper falling for the toss.
func _farewell(data: Dictionary, t: float, a: float) -> void:
	var side := GameState.HOME
	var club := scene.club(side)
	# The ceremony's name, top left, as a broadcast heads its special.
	var tag := str(data.get("title", ""))
	var tw := text_width(tag, 22, 700) + 44.0
	var tag_rect := Rect2(Vector2(40.0, 36.0), Vector2(tw, 44.0))
	team_plate(tag_rect, club, 10.0, 0.95 * a, false)
	text(Vector2(tag_rect.position.x, tag_rect.position.y + 30.0), tag, 22, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_CENTER, tw, 700)
	if t >= FieldScenes.FAREWELL_TOSS:
		var colours: Array[Color] = [UiTheme.GOLD, Color.WHITE]
		if club != null:
			colours.append(HudCanvas.club_colour(club))
		_confetti(t - FieldScenes.FAREWELL_TOSS, colours, a)
	var from := FieldScenes.FAREWELL_REVEAL - 0.4
	if t < from:
		return
	var b := clampf((t - from) / 0.5, 0.0, 1.0) * a
	var h := 150.0
	var band := Rect2(Vector2(0.0, view.y - h - 70.0 + (1.0 - b) * 40.0), Vector2(view.x, h))
	var mid := Color(0.02, 0.02, 0.03, 0.82 * b)
	var edge := Color(0.02, 0.02, 0.03, 0.0)
	draw_polygon(PackedVector2Array([band.position, Vector2(view.x * 0.5, band.position.y), Vector2(view.x * 0.5, band.end.y), Vector2(0.0, band.end.y)]), PackedColorArray([edge, mid, mid, edge]))
	draw_polygon(PackedVector2Array([Vector2(view.x * 0.5, band.position.y), Vector2(view.x, band.position.y), band.end, Vector2(view.x * 0.5, band.end.y)]), PackedColorArray([mid, edge, edge, mid]))
	draw_rect(Rect2(Vector2(view.x * 0.2, band.position.y), Vector2(view.x * 0.6, 3.0)), Color(UiTheme.GOLD, 0.9 * b))
	var name := str(data.get("name", ""))
	var retired := bool(data.get("retired", false))
	var left := view.x * 0.5 - 420.0
	if club != null:
		Emblem.draw_emblem(self, club, Rect2(Vector2(left, band.position.y + 22.0), Vector2(104.0, 104.0)))
	# As KBO clubs write it: "THANK YOU" and his name, and under it his number retired, "영원한
	# ○○맨", or his years (CareerLegacy.slogan); his career in a line beside.
	figure(Vector2(left + 128.0, band.position.y + 74.0), "THANK YOU", 50, Color(UiTheme.GOLD, b), HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)
	var thanks_w := UiTheme.numeric(true, true).get_string_size("THANK YOU", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 50).x
	shout(Vector2(left + 128.0 + thanks_w + 18.0, band.position.y + 76.0), name, 54, Color(Color.WHITE, b))
	text(Vector2(left + 130.0, band.position.y + 118.0), str(data.get("slogan", "")), 24, Color(UiTheme.GOLD if retired else Color.WHITE, b), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
	var slogan_w := text_width(str(data.get("slogan", "")), 24, 700)
	text(Vector2(left + 130.0 + slogan_w + 22.0, band.position.y + 118.0), str(data.get("line", "")), 19, Color(UiTheme.DIM, b), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500)


## Confetti falling over the screen (`u` seconds since it began): small paper strips that
## tumble (narrowing as they turn edge-on) and sway, each its own from its index.
func _confetti(u: float, colours: Array[Color], a: float) -> void:
	for i: int in CONFETTI:
		var r1 := fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		var r2 := fposmod(sin(float(i) * 78.233) * 12543.123, 1.0)
		var r3 := fposmod(sin(float(i) * 39.425) * 24634.634, 1.0)
		var speed := 150.0 + 170.0 * r2
		# (Half of it on the screen at once, as it is fired, the rest following from above.)
		var fall := (r3 - 0.5) * (view.y + 80.0) + u * speed
		if fall < -40.0:
			continue
		var y := fposmod(fall, view.y + 80.0) - 40.0
		var x := r1 * view.x + sin(u * (1.2 + r3) + i) * 38.0
		var turn := u * (2.0 + 3.0 * r2) + i
		var w := 7.0 * absf(cos(u * (3.0 + 4.0 * r1) + i))
		var c: Color = colours[i % colours.size()]
		var along := Vector2(cos(turn), sin(turn))
		var across := along.orthogonal()
		var at := Vector2(x, y)
		var quad := PackedVector2Array([at - along * 7.0 - across * w * 0.5, at + along * 7.0 - across * w * 0.5, at + along * 7.0 + across * w * 0.5, at - along * 7.0 + across * w * 0.5])
		draw_colored_polygon(quad, Color(c, 0.95 * a))


## The last out: the winner and the final score, before the summary.
func _game_end(a: float) -> void:
	var g := scene.game
	var rect := Rect2(Vector2(view.x * 0.5 - 420.0, view.y * 0.32 - (1.0 - a) * 30.0), Vector2(840.0, 190.0))
	panel(rect, Color(UiTheme.PANEL, 0.95 * a), 16.0)
	var w := g.winner
	if w >= 0:
		draw_rect(Rect2(rect.position + Vector2(16.0, 0.0), Vector2(rect.size.x - 16.0, 6.0)), Color(HudCanvas.club_colour(scene.club(w)), a))
		var club := scene.club(w)
		if club != null and a > 0.5:
			Emblem.draw_emblem(self, club, Rect2(rect.position + Vector2(36.0, 30.0), Vector2(130.0, 130.0)))
		text(Vector2(rect.position.x + 190.0, rect.position.y + 78.0), "%s 승리" % g.teams[w].short_name, 40, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
	else:
		text(Vector2(rect.position.x + 40.0, rect.position.y + 78.0), "무승부", 40, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
	figure(Vector2(rect.position.x + 190.0, rect.position.y + 150.0), "%d : %d" % [g.score[0], g.score[1]], 52, Color(UiTheme.ACCENT, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)
	text(Vector2(rect.position.x + 400.0, rect.position.y + 140.0), "%s  ·  %s" % [g.teams[0].short_name, g.teams[1].short_name], 20, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500)
	figure(Vector2(rect.position.x, rect.position.y + 30.0), "FINAL", 18, Color(UiTheme.ACCENT, a * 0.9), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 30.0, true)
