class_name PitchTrack
extends HudCanvas
## The pitch track (docs/13 S6-4): where each pitch of this plate appearance crossed the
## plate, numbered in order and coloured by kind (fastball red, breaking blue, change-up
## green), drawn from the catcher's side as a broadcast does. C switches to how often this
## pitcher has thrown to each of the nine cells today.

const SIZE := Vector2(300.0, 330.0)

var scene: MatchScene
## Show the pitcher's cell counts instead of this plate appearance.
var show_spread := false


func _draw() -> void:
	if scene == null or scene.game == null or scene.duel == null:
		return
	# The detail cards use the same corner; during a play the field matters more.
	if scene.bottom_bar.detail or scene._play_time >= 0.0:
		return
	begin()
	var rect := Rect2(Vector2(view.x - SIZE.x - 16.0, view.y - BottomBar.HEIGHT - 26.0 - SIZE.y), SIZE)
	panel(rect)
	var title := "%s 코스 분포" % _pitcher_name() if show_spread else "이번 타석 투구"
	text(rect.position + Vector2(14.0, 28.0), title, 17, UiTheme.GOLD)
	text(rect.position + Vector2(rect.size.x - 70.0, 28.0), "C 전환", 13, UiTheme.DIM)
	var zone := scene.duel.zone
	# The zone takes the middle; a band around it shows pitches off the plate.
	var area := Rect2(rect.position + Vector2(30.0, 46.0), Vector2(rect.size.x - 60.0, rect.size.y - 96.0))
	var zw := area.size.x * 0.56
	var zh := area.size.y * 0.56
	var zrect := Rect2(area.get_center() - Vector2(zw, zh) * 0.5, Vector2(zw, zh))
	draw_rect(zrect, Color(1, 1, 1, 0.06))
	for i: int in 4:
		var x := zrect.position.x + zw * i / 3.0
		var y := zrect.position.y + zh * i / 3.0
		draw_line(Vector2(x, zrect.position.y), Vector2(x, zrect.end.y), Color(1, 1, 1, 0.35 if i % 3 == 0 else 0.15), 1.5)
		draw_line(Vector2(zrect.position.x, y), Vector2(zrect.end.x, y), Color(1, 1, 1, 0.35 if i % 3 == 0 else 0.15), 1.5)
	if show_spread:
		_draw_spread(zrect)
	else:
		_draw_pitches(zrect, zone)
	_legend(rect.position + Vector2(14.0, rect.size.y - 16.0))


func _pitcher_name() -> String:
	var p := scene.game.fielding_team().player(scene.game.pitcher_id())
	return p.name if p != null else ""


## Plate position (x across, z up) to a point on the panel.
static func to_panel(zrect: Rect2, zone: StrikeZone, x: float, z: float) -> Vector2:
	var u := (x + zone.half_width) / (2.0 * zone.half_width)
	var v := (z - zone.bottom) / maxf(zone.top - zone.bottom, 0.01)
	return Vector2(zrect.position.x + u * zrect.size.x, zrect.end.y - v * zrect.size.y)


func _draw_pitches(zrect: Rect2, zone: StrikeZone) -> void:
	for i: int in scene.pa_pitches.size():
		var p: MatchScene.TrackedPitch = scene.pa_pitches[i]
		var at := to_panel(zrect, zone, p.x, p.z)
		at = at.clamp(zrect.position - zrect.size * 0.38, zrect.end + zrect.size * 0.38)
		draw_circle(at, 13.0, UiTheme.pitch_color(p.family))
		draw_arc(at, 13.0, 0.0, TAU, 24, Color(0, 0, 0, 0.5), 1.5, true)
		text(at + Vector2(-13.0, 6.0), str(i + 1), 16, Color(0.05, 0.05, 0.08), HORIZONTAL_ALIGNMENT_CENTER, 26.0, 700)


func _draw_spread(zrect: Rect2) -> void:
	var cells: PackedInt32Array = scene.pitcher_cells.get(scene.game.pitcher_id(), PackedInt32Array())
	if cells.is_empty():
		return
	var total := 0
	for c: int in cells:
		total += c
	for cell: int in 9:
		var col := cell % 3
		var row := cell / 3
		var r := Rect2(zrect.position + Vector2(zrect.size.x * col / 3.0, zrect.size.y * row / 3.0), zrect.size / 3.0)
		var share := float(cells[cell]) / maxf(total, 1.0)
		draw_rect(r.grow(-2.0), Color(1.0, 0.45, 0.2, clampf(share * 2.5, 0.0, 0.85)))
		text(r.position + Vector2(0.0, r.size.y * 0.5 + 7.0), str(cells[cell]), 18, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	text(zrect.position + Vector2(0.0, zrect.size.y + 48.0), "존 밖 %d / 전체 %d" % [cells[9], total], 14, UiTheme.DIM, HORIZONTAL_ALIGNMENT_CENTER, zrect.size.x)


func _legend(at: Vector2) -> void:
	var items: Array = [["직구", UiTheme.FASTBALL], ["변화구", UiTheme.BREAKING], ["체인지업", UiTheme.OFFSPEED]]
	var x := at.x
	for item: Array in items:
		draw_circle(Vector2(x + 6.0, at.y - 5.0), 6.0, item[1])
		text(Vector2(x + 16.0, at.y), item[0], 14, UiTheme.DIM)
		x += 90.0
