class_name DuelHud
extends HudCanvas
## On-screen display for the pitcher-batter duel. Everything is drawn in _draw() from the
## scene's state; world positions are projected through the active camera.

const INK := Color(1.0, 1.0, 1.0, 0.95)
const GOLD := Color(1.0, 0.82, 0.25)
const GREEN := Color(0.4, 0.9, 0.45)
const BLUE := Color(0.45, 0.7, 1.0)
const ORANGE := Color(1.0, 0.6, 0.25)
const RED := Color(1.0, 0.35, 0.3)

const JUDGMENT_TEXT := {&"perfect": "완벽", &"good": "좋음", &"early": "빠름", &"late": "늦음", &"miss": "헛스윙"}
const MODE_TEXT := {&"bat": "타격", &"pitch": "투구", &"watch": "관전"}

var scene: DuelScene
## The full game hides the duel's own count and help line (it has a scoreboard and a bottom
## bar) and keeps the bottom of the screen clear by this many HUD units.
var show_count := true
var show_help := true
var bottom_reserved := 0.0


func _draw() -> void:
	if scene == null or scene.duel == null:
		return
	begin()
	var at_the_plate := scene.plate_marks_visible()
	if at_the_plate:
		_draw_zone()
	if show_count:
		_draw_count()
	if at_the_plate and scene.human_pitches():
		_draw_preview()
		_draw_pitch_list()
		_draw_target_gauge()
	if at_the_plate and scene.human_bats():
		_draw_arrival()
	if at_the_plate:
		_draw_pitch_readout()
	_draw_swing_feedback()
	_draw_banner()
	if show_help:
		_draw_help()


func _screen(field_pos: Vector3) -> Vector2:
	return from_screen(scene.camera.unproject_position(Field.to_world(field_pos)))


func _visible(field_pos: Vector3) -> bool:
	return not scene.camera.is_position_behind(Field.to_world(field_pos))


func _text(at: Vector2, line: String, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	text(at, line, font_size, color, align, width)


func _draw_zone() -> void:
	var zone := scene.duel.zone
	var y := Field.PLATE_FRONT_Y
	var corners: Array[Vector3] = [
		Vector3(-zone.half_width, y, zone.bottom), Vector3(zone.half_width, y, zone.bottom),
		Vector3(zone.half_width, y, zone.top), Vector3(-zone.half_width, y, zone.top),
	]
	if not _visible(corners[0]):
		return
	var points := PackedVector2Array()
	for c: Vector3 in corners:
		points.append(_screen(c))
	points.append(points[0])
	var glow := scene.duel.swing != null and scene.duel.swing.made_contact and scene.state == DuelScene.State.LIVE
	draw_polyline(points, GOLD if glow else Color(1.0, 1.0, 1.0, 0.55), 3.0 if glow else 1.6, true)


func _draw_count() -> void:
	var box := Rect2(Vector2(view.x * 0.5 - 150.0, 14.0), Vector2(300.0, 44.0))
	panel(box, UiTheme.PANEL, 8.0)
	_text(box.position + Vector2(16.0, 30.0), "B", 20, GREEN)
	for i: int in 3:
		draw_circle(box.position + Vector2(44.0 + i * 20.0, 23.0), 7.0, GREEN if i < scene.balls else Color(1, 1, 1, 0.18))
	_text(box.position + Vector2(116.0, 30.0), "S", 20, GOLD)
	for i: int in 2:
		draw_circle(box.position + Vector2(144.0 + i * 20.0, 23.0), 7.0, GOLD if i < scene.strikes else Color(1, 1, 1, 0.18))
	var mode_text: String = MODE_TEXT.get(scene.mode, "")
	_text(box.position + Vector2(196.0, 30.0), mode_text + " 모드", 18, INK)


func _draw_pitch_list() -> void:
	# A small ring at the side shows the pitcher's pitches where they are on the wheel; the
	# larger one opens at the pointer while the right mouse button is held.
	_wheel(Vector2(view.x - 150.0, view.y * 0.5 - 10.0), 74.0, 36.0, scene.selected_pitch, -1, false)
	if scene.wheel_open:
		_wheel(from_screen(scene.wheel_centre), 124.0, 58.0, scene.selected_pitch, scene.wheel_pick, true)


## The pitch wheel (the user: "a ring, a doughnut, cut in six; no more circles inside it"):
## six segments of a ring, a pitch in each — the first straight up, the rest clockwise. The
## segment the pointer is toward is filled; the pitch already chosen is edged. Nothing in the
## middle but the name of the pitch.
func _wheel(centre: Vector2, outer: float, inner: float, chosen: int, toward: int, large: bool) -> void:
	var count := mini(scene.pitch_ids.size(), DuelScene.WHEEL_SLOTS)
	var step := TAU / DuelScene.WHEEL_SLOTS
	var gap := deg_to_rad(2.2 if large else 3.0)
	for slot: int in DuelScene.WHEEL_SLOTS:
		# The segment: from 30 degrees before its direction to 30 after, less a gap.
		var mid := -PI * 0.5 + step * slot
		var from := mid - step * 0.5 + gap
		var to := mid + step * 0.5 - gap
		var shape := PackedVector2Array()
		var edge := PackedVector2Array()
		for i: int in 13:
			var a := lerpf(from, to, i / 12.0)
			shape.append(centre + Vector2(cos(a), sin(a)) * outer)
		for i: int in 13:
			var a := lerpf(to, from, i / 12.0)
			shape.append(centre + Vector2(cos(a), sin(a)) * inner)
		edge = shape.duplicate()
		edge.append(shape[0])
		var has_pitch := slot < count
		var lit := has_pitch and slot == toward
		var is_chosen := has_pitch and slot == chosen
		var fill := Color(0.05, 0.06, 0.08, 0.3)
		if has_pitch:
			fill = Color(GOLD, 0.95) if lit else (Color(0.16, 0.17, 0.21, 0.9) if is_chosen else Color(0.06, 0.07, 0.1, 0.82))
		draw_colored_polygon(shape, fill)
		if is_chosen and not lit:
			draw_polyline(edge, GOLD, 2.5, true)
		elif has_pitch and not lit:
			draw_polyline(edge, Color(1, 1, 1, 0.22), 1.2, true)
		if not has_pitch:
			continue
		var type := scene.catalog[scene.pitch_ids[slot]]
		var at := centre + Vector2(cos(mid), sin(mid)) * (outer + inner) * 0.5
		var ink := Color(0.07, 0.06, 0.03) if lit else (GOLD if is_chosen else INK)
		if large:
			_plain(at + Vector2(-60.0, -3.0), _short(type.label, 5), 16, ink, 120.0)
			_plain_figure(at + Vector2(-60.0, 18.0), "%d" % roundi(type.speed_kmh), 21, ink, 120.0)
		else:
			_plain(at + Vector2(-40.0, 5.0), _short(type.label, 2), 13, ink, 80.0)
	var shown := toward if toward >= 0 else chosen
	if shown >= 0 and shown < count:
		var name := scene.catalog[scene.pitch_ids[shown]].label
		if large:
			_text(centre + Vector2(-inner, 6.0), _short(name, 6), 16, GOLD if toward >= 0 else INK, HORIZONTAL_ALIGNMENT_CENTER, inner * 2.0)
		else:
			_text(centre + Vector2(-110.0, outer + 26.0), name, 16, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 220.0)


## A pitch's name cut to fit a segment ("포심 패스트볼" → "포심").
static func _short(label: String, letters: int) -> String:
	var first := label.split(" ")[0]
	return first.substr(0, letters)


## Text and figures without the dark edge the HUD's text has (inside a filled segment).
func _plain(at: Vector2, line: String, font_size: int, colour: Color, width: float) -> void:
	draw_string(UiTheme.face(&"broadcast", 700), at, line, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, colour)


func _plain_figure(at: Vector2, line: String, font_size: int, colour: Color, width: float) -> void:
	draw_string(UiTheme.numeric(false, true), at, line, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, colour)


## Ring drawn around the pitch target: fills while charging power, then closes in while the
## player times the accuracy click.
func _draw_target_gauge() -> void:
	var state := scene.state
	if state == DuelScene.State.WINDUP and scene.human_pitches():
		_draw_pitch_grade()
		return
	if state != DuelScene.State.PRE_PITCH and state != DuelScene.State.CHARGE:
		return
	# The wheel opens where the pointer is, on the target: its name and circle under the wheel
	# ran into the wheel's own labels.
	if scene.wheel_open or not _visible(scene.target):
		return
	var centre := _screen(scene.target)
	var per_metre := (_screen(scene.target + Vector3(0.1, 0.0, 0.0)) - centre).length() * 10.0
	var base := maxf(per_metre * 0.11, 16.0)
	_text(centre + Vector2(-90.0, -base * GAUGE_FROM - 12.0 if state == DuelScene.State.CHARGE else -base - 14.0), scene.selected_type().label, 18, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 180.0)
	if state != DuelScene.State.CHARGE:
		draw_arc(centre, base, 0.0, TAU, 48, Color(1, 1, 1, 0.85), 2.0, true)
		return
	# The button is down: a ring closes on the target's circle. Let go when they meet. The
	# circle is a green band as wide as a good pitch's window; the ring is green inside it,
	# red once it has gone by.
	var sweet := DuelScene.ACCURACY_SWEET
	var at := scene.ring
	var good := DuelScene.gauge_accuracy(at)
	draw_arc(centre, base, 0.0, TAU, 64, Color(GREEN, 0.35), maxf(base * 0.42, 9.0), true)
	draw_arc(centre, base, 0.0, TAU, 64, Color(GREEN, 0.95), 2.5, true)
	var radius := base * (lerpf(GAUGE_FROM, 1.0, at / sweet) if at <= sweet else lerpf(1.0, 0.15, (at - sweet) / (1.0 - sweet)))
	var colour := GOLD if good >= 0.85 else (GREEN if good >= 0.6 else (RED if at > sweet else INK))
	draw_arc(centre, radius, 0.0, TAU, 64, Color(0.0, 0.0, 0.0, 0.55), 7.0, true)
	draw_arc(centre, radius, 0.0, TAU, 64, colour, 4.0, true)


## How many target circles wide the closing ring starts.
const GAUGE_FROM := 3.4


## How well the pitch was let go, inside the ring while the pitcher winds up.
func _draw_pitch_grade() -> void:
	if not _visible(scene.target):
		return
	var centre := _screen(scene.target)
	var grade := "완벽" if scene.accuracy >= 0.85 else ("좋음" if scene.accuracy >= 0.6 else ("보통" if scene.accuracy >= 0.3 else "빗나감"))
	var color := GOLD if scene.accuracy >= 0.85 else (GREEN if scene.accuracy >= 0.6 else (INK if scene.accuracy >= 0.3 else RED))
	draw_arc(centre, 30.0, 0.0, TAU, 40, Color(color, 0.8), 3.0, true)
	shout(centre + Vector2(-80.0, 9.0), grade, 26, color, HORIZONTAL_ALIGNMENT_CENTER, 160.0)


## For the batter, from the moment the pitch leaves the hand: a circle on the plane of the
## plate where it is going to cross, and a ring closing on it that meets it as the ball gets
## there (where to swing, and when).
func _draw_arrival() -> void:
	var duel := scene.duel
	if not Settings.pitch_marker or duel.pitch == null or scene.state != DuelScene.State.LIVE or duel.phase != PitchDuel.Phase.FLIGHT:
		return
	if duel.time > duel.pitch.flight_time + 0.05:
		return
	var spot := Vector3(duel.pitch.plate_pos.x, Field.PLATE_FRONT_Y, duel.pitch.plate_pos.z)
	if not _visible(spot):
		return
	var p := _screen(spot)
	var r := maxf((_screen(spot + Vector3(0.1, 0.0, 0.0)) - p).length() * 10.0 * 0.0366 * 1.5, 9.0)
	var inside := duel.zone.contains(spot.x, spot.z)
	var colour := GOLD if inside else Color(0.75, 0.82, 0.95)
	draw_circle(p, r, Color(colour, 0.22))
	draw_arc(p, r, 0.0, TAU, 40, Color(0.0, 0.0, 0.0, 0.5), 5.0, true)
	draw_arc(p, r, 0.0, TAU, 40, colour, 2.5, true)
	var left := clampf(1.0 - duel.time / maxf(duel.pitch.flight_time, 0.05), 0.0, 1.0)
	draw_arc(p, r * (1.0 + 2.6 * left), 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.25 + 0.5 * (1.0 - left)), 2.0, true)


## Before the pitch: where the chosen pitch will arrive. A straight fastball is a mark in the
## zone and nothing more; a pitch that moves has the last of its path bending into the mark.
func _draw_preview() -> void:
	var path := scene.preview
	if path.is_empty() or scene.wheel_open:
		return
	# (The ball itself is in the scene, where the pitch is aimed: DuelScene.aim_ball.)
	_tail(path, 1.0, Color(1.0, 0.85, 0.35))


## The last of a pitch's path as a line that thickens and brightens toward where it arrives:
## which way it is moving as it comes in. It stops short of the ball that marks the spot.
func _tail(path: PackedVector3Array, strength: float, colour: Color) -> void:
	var points := PackedVector2Array()
	for p: Vector3 in path:
		if _visible(p):
			points.append(_screen(p))
	if points.size() < 3:
		return
	var last := points.size() - 1
	var end := points[last]
	var room := maxf((_screen(path[path.size() - 1] + Vector3(0.1, 0.0, 0.0)) - end).length() * 10.0 * 0.0366 * DuelScene.AIM_BALL_SCALE + 3.0, 6.0)
	for i: int in last:
		var f := float(i + 1) / last
		var a := points[i]
		var b := points[i + 1]
		if a.distance_to(end) <= room:
			break
		if b.distance_to(end) < room:
			b = end + (a - end).normalized() * room
		draw_line(a, b, Color(colour, strength * (0.18 + 0.75 * f * f)), 2.0 + 3.5 * f, true)


## Speed and pitch type where the ball crossed the plate.
func _draw_pitch_readout() -> void:
	var duel := scene.duel
	if duel.pitch == null or duel.phase == PitchDuel.Phase.READY:
		return
	if duel.phase == PitchDuel.Phase.FLIGHT and duel.time < duel.pitch.flight_time:
		return
	if not _visible(duel.pitch.plate_pos):
		return
	var at := _screen(duel.pitch.plate_pos)
	draw_circle(at, 26.0, Color(0.05, 0.05, 0.08, 0.8))
	draw_arc(at, 26.0, 0.0, TAU, 32, INK, 2.0, true)
	figure(at + Vector2(-26.0, 6.0), "%d" % roundi(duel.pitch.release_speed_kmh()), 27, INK, HORIZONTAL_ALIGNMENT_CENTER, 52.0, true)
	figure(at + Vector2(-26.0, 19.0), "KM/H", 11, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, 52.0)
	_text(at + Vector2(-110.0, 50.0), duel.decision.type.label, 17, INK, HORIZONTAL_ALIGNMENT_CENTER, 220.0)


func _draw_swing_feedback() -> void:
	var duel := scene.duel
	if duel.swing == null or not duel.swing.resolved:
		return
	if not scene.swing_feedback_visible():
		return
	var label: String = JUDGMENT_TEXT.get(duel.swing.judgment, "")
	var color := INK
	match duel.swing.judgment:
		&"perfect":
			color = GOLD
		&"good":
			color = GREEN
		&"early":
			color = BLUE
		&"late":
			color = ORANGE
		&"miss":
			color = RED
	if scene.plate_marks_visible():
		shout(Vector2(0.0, view.y * 0.62), label, 36, color, HORIZONTAL_ALIGNMENT_CENTER, view.x)


func _draw_banner() -> void:
	if scene.banner_time <= 0.0:
		return
	var alpha := clampf(scene.banner_time / 0.4, 0.0, 1.0)
	shout(Vector2(0.0, view.y * 0.3), scene.banner, 56, Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_CENTER, view.x)


func _draw_help() -> void:
	var line := scene.help_keys()
	if scene.human_bats():
		line = "좌클릭 컨택 스윙   우클릭 파워 스윙   V 조준 %s   %s" % ["끄기" if scene.aim_enabled else "켜기", line]
	elif scene.human_pitches():
		line = "우클릭+이동 구종(또는 1~%d)   마우스 코스   좌클릭 누르고 원이 겹칠 때 떼기   %s" % [mini(scene.pitch_ids.size(), DuelScene.WHEEL_SLOTS), line]
	panel(Rect2(Vector2(0.0, view.y - 40.0), Vector2(view.x, 40.0)), UiTheme.PANEL_DARK, 0.0)
	keycaps(Vector2(0.0, view.y - 13.0), line, view.x, 15)
