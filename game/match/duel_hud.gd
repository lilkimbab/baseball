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
	if scene.human_pitches():
		_draw_pitch_list()
		_draw_target_gauge()
	if scene.human_bats() and scene.aim_enabled:
		_draw_aim()
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
	var origin := Vector2(view.x - 250.0, view.y * 0.5 - 110.0)
	draw_rect(Rect2(origin - Vector2(14.0, 30.0), Vector2(240.0, 44.0 + scene.pitch_ids.size() * 32.0)), PANEL)
	_text(origin, "구종", 16, Color(1, 1, 1, 0.7))
	for i: int in scene.pitch_ids.size():
		var type := scene.catalog[scene.pitch_ids[i]]
		var chosen := i == scene.selected_pitch
		var line := "%d  %s  %d" % [i + 1, type.label, roundi(type.speed_kmh)]
		_text(origin + Vector2(0.0, 32.0 + i * 32.0), line, 20, GOLD if chosen else INK)


## Ring drawn around the pitch target: fills while charging power, then closes in while the
## player times the accuracy click.
func _draw_target_gauge() -> void:
	var state := scene.state
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


func _draw_aim() -> void:
	if not _visible(scene.aim_point):
		return
	var centre := _screen(scene.aim_point)
	var per_metre := (_screen(scene.aim_point + Vector3(0.1, 0.0, 0.0)) - centre).length() * 10.0
	draw_arc(centre, maxf(per_metre * 0.07, 10.0), 0.0, TAU, 32, GOLD, 2.5, true)


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
	_text(at + Vector2(-26.0, 5.0), "%d" % roundi(duel.pitch.release_speed_kmh()), 22, INK, HORIZONTAL_ALIGNMENT_CENTER, 52.0)
	_text(at + Vector2(-26.0, 20.0), "km/h", 10, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, 52.0)
	_text(at + Vector2(-110.0, 50.0), duel.decision.type.label, 17, INK, HORIZONTAL_ALIGNMENT_CENTER, 220.0)


func _draw_swing_feedback() -> void:
	var duel := scene.duel
	if duel.swing == null or not duel.swing.resolved:
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
	_text(Vector2(0.0, view.y * 0.62), label, 30, color, HORIZONTAL_ALIGNMENT_CENTER, view.x)
	if duel.contact != null and duel.contact.made_contact:
		var info := "타구 속도 %d km/h   발사각 %d°   방향 %d°" % [roundi(duel.contact.exit_speed_kmh()), roundi(duel.contact.launch_deg()), roundi(duel.contact.spray_deg())]
		var box := Rect2(Vector2(view.x * 0.5 - 260.0, view.y - 110.0 - bottom_reserved), Vector2(520.0, 42.0))
		draw_rect(box, PANEL)
		_text(box.position + Vector2(0.0, 25.0), info, 18, INK, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)


func _draw_banner() -> void:
	if scene.banner_time <= 0.0:
		return
	var alpha := clampf(scene.banner_time / 0.4, 0.0, 1.0)
	_text(Vector2(0.0, view.y * 0.3), scene.banner, 46, Color(1, 1, 1, alpha), HORIZONTAL_ALIGNMENT_CENTER, view.x)


func _draw_help() -> void:
	var line := scene.help_keys()
	if scene.human_bats():
		line = "왼쪽 클릭 컨택 스윙   오른쪽 클릭 파워 스윙   V 조준 %s      %s" % ["끄기" if scene.aim_enabled else "켜기", line]
	elif scene.human_pitches():
		line = "1~%d 구종   마우스 코스   누르고 있기 → 떼기 → 고리가 맞을 때 클릭      %s" % [scene.pitch_ids.size(), line]
	draw_rect(Rect2(Vector2(0.0, view.y - 34.0), Vector2(view.x, 34.0)), PANEL)
	_text(Vector2(16.0, view.y - 11.0), line, 15, Color(1, 1, 1, 0.85))
