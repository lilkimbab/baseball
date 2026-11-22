class_name BroadcastCards
extends HudCanvas
## The broadcast's cards (docs/11 section 6, docs/13 S16), on the HUD's plates: the match-up
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
			else:
				_order(0, clampf((t - 7.5) / SLIDE, 0.0, 1.0) * a)
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
	if seg.holds:
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


## The visitors' batting order, before the first pitch.
func _order(side: int, a: float) -> void:
	var team := scene.game.teams[side]
	var rect := Rect2(Vector2(60.0 - (1.0 - a) * 80.0, 180.0), Vector2(460.0, 70.0 + 40.0 * team.lineup.size()))
	panel(rect, Color(UiTheme.PANEL, 0.95 * a), 14.0)
	heading(rect.position + Vector2(24.0, 44.0), "%s 선발 라인업" % team.short_name, "", HudCanvas.club_colour(scene.club(side)), 22)
	for i: int in team.lineup.size():
		var slot := team.lineup[i]
		var p := team.player(slot.player_id)
		var y := rect.position.y + 92.0 + 40.0 * i
		figure(Vector2(rect.position.x + 26.0, y), "%d" % (i + 1), 22, Color(UiTheme.ACCENT, a))
		text(Vector2(rect.position.x + 64.0, y), Position.name_of(slot.position), 17, Color(UiTheme.DIM, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500)
		text(Vector2(rect.position.x + 170.0, y), p.name if p != null else "", 20, Color(UiTheme.INK, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 600)


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
	draw_rect(Rect2(r.position + Vector2(0.0, r.size.y - 4.0), Vector2(r.size.x - 10.0, 4.0)), Color(UiTheme.BRAND, a))
	figure(r.position + Vector2(0.0, 38.0), "REPLAY", 30, Color(Color.WHITE, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, true)
	var kind: StringName = scene.broadcast.current.data.get("kind", &"home_run")
	text(Vector2(r.position.x, r.end.y + 26.0), "홈런" if kind == &"home_run" else "호수비", 17, Color(UiTheme.INK, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 600)


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
