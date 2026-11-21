class_name DuelHud
extends HudCanvas
## On-screen display for the pitcher-batter duel. Everything is drawn in _draw() from the
## scene's state; world positions are projected through the active camera.

const INK := Color(1.0, 1.0, 1.0, 0.95)
const PANEL := Color(0.05, 0.08, 0.16, 0.72)
const GOLD := Color(1.0, 0.82, 0.25)
const GREEN := Color(0.4, 0.9, 0.45)
const BLUE := Color(0.45, 0.7, 1.0)
const ORANGE := Color(1.0, 0.6, 0.25)
const RED := Color(1.0, 0.35, 0.3)

## The see-through bat: from its knob to the sweet spot, and on past it to the tip (m).
const BAT_KNOB_TO_SWEET := 0.68
const BAT_TIP_BEYOND := 0.17
## Seconds a pitch's trail stays up after it.
const TRAIL_TIME := 2.0

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
	_draw_zone()
	if show_count:
		_draw_count()
	_draw_trail()
	if scene.human_pitches():
		_draw_preview()
		_draw_pitch_list()
		_draw_target_gauge()
	if scene.human_bats() and scene.aim_enabled:
		_draw_bat_cursor()
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
	draw_rect(box, PANEL)
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
	if state != DuelScene.State.PRE_PITCH and state != DuelScene.State.CHARGE and state != DuelScene.State.ACCURACY:
		return
	if not _visible(scene.target):
		return
	var centre := _screen(scene.target)
	var per_metre := (_screen(scene.target + Vector3(0.1, 0.0, 0.0)) - centre).length() * 10.0
	var base := maxf(per_metre * 0.11, 14.0)
	draw_circle(centre, 4.0, GOLD)
	draw_arc(centre, base, 0.0, TAU, 48, Color(1, 1, 1, 0.85), 2.0, true)
	_text(centre + Vector2(-90.0, -base - 14.0), scene.selected_type().label, 18, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 180.0)
	if state == DuelScene.State.CHARGE:
		draw_arc(centre, base + 7.0, -PI * 0.5, -PI * 0.5 + TAU * scene.power, 48, ORANGE, 6.0, true)
	elif state == DuelScene.State.ACCURACY:
		var sweep := lerpf(base * 3.2, base * 0.3, scene.ring)
		var sweet := lerpf(base * 3.2, base * 0.3, DuelScene.ACCURACY_SWEET)
		draw_arc(centre, sweet, 0.0, TAU, 48, Color(GREEN, 0.9), 5.0, true)
		draw_arc(centre, sweep, 0.0, TAU, 48, INK, 3.0, true)


## How well the accuracy click landed, inside the ring while the pitcher winds up.
func _draw_pitch_grade() -> void:
	if not _visible(scene.target):
		return
	var centre := _screen(scene.target)
	var grade := "완벽" if scene.accuracy >= 0.85 else ("좋음" if scene.accuracy >= 0.6 else ("보통" if scene.accuracy >= 0.3 else "빗나감"))
	var color := GOLD if scene.accuracy >= 0.85 else (GREEN if scene.accuracy >= 0.6 else (INK if scene.accuracy >= 0.3 else RED))
	draw_arc(centre, 30.0, 0.0, TAU, 40, Color(color, 0.8), 3.0, true)
	shout(centre + Vector2(-80.0, 9.0), grade, 26, color, HORIZONTAL_ALIGNMENT_CENTER, 160.0)


## The batter's aim: a see-through bat lying where the swing will meet the ball, its sweet
## spot on the pointer. Its barrel reaches across the plate from the batter's side, dipping
## for a low pitch. The bright ring is the sweet spot (a miss this small is forgiven,
## SwingModel.FORGIVEN_ERROR); the faint one, beyond which he is fooled.
func _draw_bat_cursor() -> void:
	if scene.duel.swing != null or not (scene.state == DuelScene.State.PRE_PITCH or scene.state == DuelScene.State.WINDUP or scene.state == DuelScene.State.LIVE):
		return
	var aim := scene.aim_point
	if not _visible(aim):
		return
	var handle_side := 1.0 if scene.settings.bats_left else -1.0
	# Knob toward the batter, a little higher than the barrel, more so for a low pitch.
	var drop := clampf((0.95 - aim.z) * 0.55, -0.12, 0.35) + 0.08
	var tip := aim + Vector3(-handle_side * BAT_TIP_BEYOND, 0.0, -drop * BAT_TIP_BEYOND / BAT_KNOB_TO_SWEET)
	var knob := aim + Vector3(handle_side * BAT_KNOB_TO_SWEET, 0.0, drop)
	var axis := (tip - knob).normalized()
	var across := Vector3(-axis.z, 0.0, axis.x)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	const STEPS := 14
	for i: int in STEPS + 1:
		var f := float(i) / STEPS
		var p := knob.lerp(tip, f)
		# Knob, thin handle, taper, barrel (radius in metres).
		var r := 0.017 if f < 0.04 else (0.013 if f < 0.4 else lerpf(0.013, 0.033, smoothstep(0.4, 0.72, f)))
		left.append(_screen(p + across * r))
		right.append(_screen(p - across * r))
	right.reverse()
	var outline := left + right
	draw_colored_polygon(outline, Color(1.0, 1.0, 1.0, 0.22))
	outline.append(outline[0])
	draw_polyline(outline, Color(1.0, 1.0, 1.0, 0.75), 1.5, true)
	var centre := _screen(aim)
	var per_metre := (_screen(aim + Vector3(0.1, 0.0, 0.0)) - centre).length() * 10.0
	draw_arc(centre, maxf(per_metre * SwingModel.FORGIVEN_ERROR, 6.0), 0.0, TAU, 32, Color(GOLD, 0.9), 2.5, true)
	draw_arc(centre, maxf(per_metre * SwingModel.FOOLED_ERROR, 14.0), 0.0, TAU, 48, Color(1, 1, 1, 0.25), 1.2, true)
	draw_circle(centre, 3.0, GOLD)


## A ball of the path, drawn its size at its distance, at least a few pixels across.
func _ghost_ball(at: Vector3, alpha: float, colour: Color = Color.WHITE) -> void:
	if not _visible(at):
		return
	var p := _screen(at)
	var r := maxf((_screen(at + Vector3(0.1, 0.0, 0.0)) - p).length() * 10.0 * 0.0366 * 1.25, 3.5)
	draw_circle(p, r, Color(colour, alpha))
	draw_arc(p, r, 0.0, TAU, 16, Color(0.15, 0.15, 0.18, alpha * 0.8), 1.2, true)


## Before the pitch: where the chosen pitch will arrive. A straight fastball is a mark in the
## zone and nothing more; a pitch that moves has the last of its path bending into the mark.
func _draw_preview() -> void:
	var path := scene.preview
	if path.is_empty():
		return
	_tail(path, 1.0, Color(1.0, 0.85, 0.35))
	var end := path[path.size() - 1]
	_ghost_ball(end, 0.9, Color(1.0, 0.95, 0.8))


## The last of a pitch's path as a line that thickens and brightens toward where it arrives,
## with the head of an arrow there: which way it is moving as it comes in.
func _tail(path: PackedVector3Array, strength: float, colour: Color) -> void:
	var points := PackedVector2Array()
	for p: Vector3 in path:
		if _visible(p):
			points.append(_screen(p))
	if points.size() < 3:
		return
	var last := points.size() - 1
	for i: int in last:
		var f := float(i + 1) / last
		draw_line(points[i], points[i + 1], Color(colour, strength * (0.18 + 0.75 * f * f)), 2.0 + 3.5 * f, true)
	var dir := points[last] - points[maxi(last - 3, 0)]
	if dir.length() > 2.0:
		dir = dir.normalized()
		var side := Vector2(-dir.y, dir.x)
		var tip := points[last] - dir * 6.0
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * 11.0 + side * 6.5, tip - dir * 11.0 - side * 6.5]), Color(colour, strength * 0.9))


## After a pitch that moved and nobody hit: the last of the path it took, for a moment.
func _draw_trail() -> void:
	var path := scene.trail
	if path.size() < 3:
		return
	var duel := scene.duel
	if duel.pitch == null:
		return
	var hit := duel.contact != null and duel.contact.made_contact
	var passed := duel.phase != PitchDuel.Phase.FLIGHT or duel.time >= duel.pitch.flight_time
	if hit or not passed:
		return
	var fade := 1.0
	if scene.state == DuelScene.State.RESULT:
		fade = 1.0 - smoothstep(TRAIL_TIME - 0.5, TRAIL_TIME, scene.state_time)
	if fade <= 0.0:
		return
	_tail(path, fade, Color(1.0, 1.0, 1.0))


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
	shout(Vector2(0.0, view.y * 0.62), label, 36, color, HORIZONTAL_ALIGNMENT_CENTER, view.x)
	if Settings.hit_info and duel.contact != null and duel.contact.made_contact:
		var info := "타구 속도 %d km/h   발사각 %d°   방향 %d°" % [roundi(duel.contact.exit_speed_kmh()), roundi(duel.contact.launch_deg()), roundi(duel.contact.spray_deg())]
		var box := Rect2(Vector2(view.x * 0.5 - 260.0, view.y - 110.0 - bottom_reserved), Vector2(520.0, 42.0))
		draw_rect(box, PANEL)
		_text(box.position + Vector2(0.0, 25.0), info, 18, INK, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)


func _draw_banner() -> void:
	if scene.banner_time <= 0.0:
		return
	var alpha := clampf(scene.banner_time / 0.4, 0.0, 1.0)
	shout(Vector2(0.0, view.y * 0.3), scene.banner, 56, Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_CENTER, view.x)


func _draw_help() -> void:
	var line := scene.help_keys()
	if scene.human_bats():
		line = "왼쪽 클릭 컨택 스윙   오른쪽 클릭 파워 스윙   V 조준 %s      %s" % ["끄기" if scene.aim_enabled else "켜기", line]
	elif scene.human_pitches():
		line = "오른쪽 버튼을 누른 채 구종 쪽으로(또는 1~%d)   마우스 코스   왼쪽 버튼 누르고 있기 → 떼기 → 고리가 맞을 때 클릭      %s" % [mini(scene.pitch_ids.size(), DuelScene.WHEEL_SLOTS), line]
	draw_rect(Rect2(Vector2(0.0, view.y - 34.0), Vector2(view.x, 34.0)), PANEL)
	_text(Vector2(16.0, view.y - 11.0), line, 15, Color(1, 1, 1, 0.85))
