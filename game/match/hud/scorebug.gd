class_name Scorebug
extends HudCanvas
## The score bug at the top left, as a broadcast has it (docs/13 S6-2, docs/08 R5: the menus'
## plates): the two clubs one over the other — their colour down the edge, the emblem, the
## name, the score, a ball beside the side at bat — then the inning (▲ top, ▼ bottom), the
## bases and the count in B-S-O order (three ball lamps, two strike, two out). Under it a thin
## strip with the pitcher's pitch count and the weather; the pitch clock beside it.

const AT := Vector2(28.0, 22.0)
const ROW := 40.0
const TEAMS := 292.0
const INNING := 62.0
const SITUATION := 176.0
const WIDTH := TEAMS + INNING + SITUATION
const HEIGHT := ROW * 2.0
const STRIP := 30.0
## Where things under the bug may start (the play's mini diamond).
const BOTTOM := AT.y + HEIGHT + 4.0 + STRIP

var scene: MatchScene


func _draw() -> void:
	if scene == null or scene.game == null:
		return
	if scene.pregame_showing() or scene.post_game_showing():
		return
	# The manager's situation board has its own line score where the bug would be.
	var board := scene as ManagerMatch
	if board != null and not board.game.over and board.board_visible():
		return
	begin()
	var g := scene.game
	# Each club's row in its own colours; the inning, the bases and the count on the broadcast's
	# red (the user, 2026-11-23: "less black, more to look at").
	brand_plate(Rect2(AT + Vector2(TEAMS - 6.0, 0.0), Vector2(INNING + SITUATION + 6.0, HEIGHT)), 0.0)
	for t: int in 2:
		_team_row(Rect2(AT + Vector2(0.0, ROW * t), Vector2(TEAMS, ROW)), t, g)
	var rule := Color(1, 1, 1, 0.22)
	draw_line(AT + Vector2(TEAMS + INNING, 10.0), AT + Vector2(TEAMS + INNING, HEIGHT - 10.0), rule, 1.2)
	_inning(Rect2(AT + Vector2(TEAMS, 0.0), Vector2(INNING, HEIGHT)), g)
	_draw_bases(AT + Vector2(TEAMS + INNING + 46.0, HEIGHT * 0.5 + 6.0), g)
	_draw_count(AT + Vector2(TEAMS + INNING + 96.0, 20.0), g)
	_strip(Rect2(AT + Vector2(0.0, HEIGHT + 4.0), Vector2(WIDTH, STRIP)), g)
	if scene.pitch_clock >= 0.0:
		_clock(Rect2(AT + Vector2(WIDTH + 8.0, 0.0), Vector2(84.0, HEIGHT)))
	_pip_frame()


## The small picture at the top right (the lead runner, or the pitcher from the side) sits in
## a plate of its own: the plate shows round its edge and a label tab hangs under it.
func _pip_frame() -> void:
	var pip := scene.pip_rect
	if pip == null or not pip.visible:
		return
	var r := Rect2(from_screen(pip.position), pip.size / k)
	panel(r.grow(4.0), UiTheme.PANEL, 0.0)
	var label := "주자 리드" if scene.game.runners_on() > 0 else "마운드"
	var tab := Rect2(Vector2(r.end.x - 130.0, r.end.y + 4.0), Vector2(130.0, 26.0))
	brand_plate(tab, 0.0)
	text(tab.position + Vector2(0.0, 19.0), label, 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, tab.size.x, 700)


func _team_row(row: Rect2, t: int, g: GameState) -> void:
	var team := g.teams[t]
	var club := scene.club(t)
	team_plate(row, club, 12.0 if t == 0 else 0.0)
	# The score in a dark well at the row's end.
	draw_rect(Rect2(Vector2(row.end.x - 70.0, row.position.y + 5.0), Vector2(62.0, row.size.y - 10.0)), Color(0.0, 0.0, 0.0, 0.35))
	if club != null:
		Emblem.draw_emblem(self, club, Rect2(row.position + Vector2(12.0, 4.0), Vector2(32.0, 32.0)))
	var at_bat := g.batting() == t and not g.over
	var name_x := row.position.x + 56.0
	text(Vector2(name_x, row.position.y + 28.0), team.short_name, 21, Color.WHITE if at_bat or g.over else Color(1, 1, 1, 0.82), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 800)
	if at_bat:
		_ball(Vector2(name_x + text_width(team.short_name, 21, 700) + 14.0, row.position.y + ROW * 0.5))
	figure(Vector2(row.end.x - 74.0, row.position.y + 33.0), str(g.score[t]), 34, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 60.0)


## A small ball beside the name of the side at bat.
func _ball(centre: Vector2) -> void:
	draw_circle(centre, 5.5, Color(0.97, 0.96, 0.92))
	draw_arc(centre + Vector2(-5.5, 0.0), 4.0, -0.9, 0.9, 8, Color(0.85, 0.15, 0.15), 1.2, true)
	draw_arc(centre + Vector2(5.5, 0.0), 4.0, PI - 0.9, PI + 0.9, 8, Color(0.85, 0.15, 0.15), 1.2, true)


## The inning between two arrows, the half being played lit.
func _inning(r: Rect2, g: GameState) -> void:
	var c := r.position.x + r.size.x * 0.5
	var lit := UiTheme.ACCENT
	var off := Color(1, 1, 1, 0.2)
	var up := r.position.y + 15.0
	draw_colored_polygon(PackedVector2Array([Vector2(c, up - 6.0), Vector2(c + 8.0, up + 5.0), Vector2(c - 8.0, up + 5.0)]), lit if g.top else off)
	var down := r.end.y - 15.0
	draw_colored_polygon(PackedVector2Array([Vector2(c, down + 6.0), Vector2(c + 8.0, down - 5.0), Vector2(c - 8.0, down - 5.0)]), lit if not g.top else off)
	figure(Vector2(r.position.x, r.position.y + 52.0), str(g.inning), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_bases(centre: Vector2, g: GameState) -> void:
	var spots: Array[Vector2] = [centre + Vector2(17.0, 0.0), centre + Vector2(0.0, -17.0), centre + Vector2(-17.0, 0.0)]
	for b: int in 3:
		var p := spots[b]
		var r := 10.0
		var pts := PackedVector2Array([p + Vector2(0.0, -r), p + Vector2(r, 0.0), p + Vector2(0.0, r), p + Vector2(-r, 0.0)])
		var on := not g.base_empty(b + 1)
		draw_colored_polygon(pts, UiTheme.ACCENT if on else Color(1, 1, 1, 0.07))
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.0 if on else 0.4), 1.2, true)


## B-S-O lamps.
func _draw_count(at: Vector2, g: GameState) -> void:
	var rows: Array = [["B", 3, g.balls, UiTheme.GREEN], ["S", 2, g.strikes, UiTheme.GOLD], ["O", 2, g.outs, UiTheme.RED]]
	for i: int in rows.size():
		var row: Array = rows[i]
		var y := at.y + i * 21.0
		var colour: Color = row[3]
		figure(Vector2(at.x, y + 7.0), row[0], 18, Color(colour, 0.9))
		for j: int in int(row[1]):
			var lamp := Vector2(at.x + 25.0 + j * 18.0, y + 1.0)
			if j < int(row[2]):
				draw_circle(lamp, 6.0, colour)
			else:
				draw_circle(lamp, 6.0, Color(1, 1, 1, 0.07))
				draw_arc(lamp, 6.0, 0.0, TAU, 16, Color(1, 1, 1, 0.3), 1.0, true)


## Under the bug: the pitcher's pitch count on the left; on the right the sky and the
## temperature, and the wind as an arrow the way it blows as seen from behind home plate (up
## is out toward centre field) with its speed (docs/08 R3: the player can tell which way the
## wind goes).
func _strip(r: Rect2, g: GameState) -> void:
	panel(r, UiTheme.PANEL_DARK, 0.0)
	var pitches: int = g.pitch_counts.get(g.pitcher_id(), 0)
	text(r.position + Vector2(14.0, 21.0), "투구", 15, UiTheme.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500)
	figure(r.position + Vector2(52.0, 23.0), str(pitches), 20, Color.WHITE)
	# (The weather is told before the game only: the user, 2026-11-23.)


func _draw_weather(r: Rect2) -> void:
	var w := scene.weather
	if w == null:
		return
	var sky: String = {Weather.Cover.CLEAR: "맑음", Weather.Cover.CLOUDY: "구름", Weather.Cover.OVERCAST: "흐림"}[w.cover]
	if w.indoor:
		sky = "돔"
	text(r.position + Vector2(14.0, 21.0), sky, 15, UiTheme.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500)
	figure(r.position + Vector2(18.0 + text_width(sky, 15, 500), 23.0), "%d°" % roundi(w.temp_c), 20, Color.WHITE)
	var park_def := scene.stadium if scene.stadium != null else scene.park.def
	var wind := w.wind_field(park_def.orientation_deg)
	var speed := Vector2(wind.x, wind.y).length()
	if w.indoor or speed < 0.8:
		text(r.position + Vector2(126.0, 21.0), "바람 없음", 15, UiTheme.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500)
		return
	text(r.position + Vector2(108.0, 21.0), "바람", 15, UiTheme.DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 500)
	var centre := r.position + Vector2(160.0, r.size.y * 0.5)
	var dir := Vector2(wind.x, -wind.y).normalized()
	var side := Vector2(-dir.y, dir.x)
	var tip := centre + dir * 10.0
	var tail := centre - dir * 10.0
	draw_line(tail, tip - dir * 4.0, UiTheme.CYAN, 2.5, true)
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * 8.0 + side * 5.5, tip - dir * 8.0 - side * 5.5]), UiTheme.CYAN)
	figure(r.position + Vector2(178.0, 23.0), "%dm/s" % roundi(speed), 20, Color.WHITE)


## The pitch clock beside the bug: red in its last five seconds.
func _clock(r: Rect2) -> void:
	var urgent := scene.pitch_clock <= 5.0
	panel(r, UiTheme.PANEL, 10.0)
	if urgent:
		draw_rect(Rect2(r.position + Vector2(0.0, r.size.y - 4.0), Vector2(r.size.x - 4.0, 4.0)), UiTheme.RED)
	figure(r.position + Vector2(0.0, 66.0), str(ceili(scene.pitch_clock)), 40, UiTheme.RED if urgent else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
