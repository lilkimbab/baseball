class_name PlayOverlay
extends HudCanvas
## What the screen shows while a ball is in play (docs/13 S6-6, S6-7): the bases marked on
## the field, where a fly ball will come down, the fielder going after it ("자동 이동" while
## fielding is automatic), an edge that lights up toward a ball off the screen, the runners
## on a small diamond, and the umpire's call on a close play. When the player's team is in
## the field, the throw keys and the gauge; at bat, the running keys (S12).

## Calls closer than this (seconds between ball and runner) are shown.
const CLOSE := 0.25
const CALL_SHOWN := 1.1

var scene: MatchScene


func _draw() -> void:
	if scene == null or scene._play == null or scene._play_time < 0.0:
		return
	begin()
	var t := scene._play_time
	var tl := scene._play.timeline
	_base_markers()
	_landing_spot(t)
	_fielder_ring(tl, t)
	_edge_glow(scene.ball_position(t))
	_mini_diamond(tl, t)
	_call(t)
	_controls()


func _project(field_pos: Vector3) -> Vector2:
	return from_screen(scene.camera.unproject_position(Field.to_world(field_pos)))


func _in_front(field_pos: Vector3) -> bool:
	return not scene.camera.is_position_behind(Field.to_world(field_pos))


func _base_markers() -> void:
	var labels: Array[String] = ["1", "2", "3", "H"]
	for i: int in 4:
		var b := PlaySim.base_xy(i + 1)
		var at := Vector3(b.x, b.y, 1.3)
		if not _in_front(at):
			continue
		var p := _project(at)
		var r := 13.0
		var pts := PackedVector2Array([p + Vector2(0.0, -r), p + Vector2(r, 0.0), p + Vector2(0.0, r), p + Vector2(-r, 0.0)])
		draw_colored_polygon(pts, Color(UiTheme.GOLD, 0.85))
		text(p + Vector2(-13.0, 6.0), labels[i], 15, Color(0.05, 0.05, 0.08), HORIZONTAL_ALIGNMENT_CENTER, 26.0, 700)


## A ring where a ball in the air will first come down, until it does.
func _landing_spot(t: float) -> void:
	if not Settings.landing_spot or not scene.landing_known or t > scene.landing_time:
		return
	var at := scene.landing_point
	if not _in_front(at):
		return
	var p := _project(at)
	var edge := _project(at + Vector3(1.2, 0.0, 0.0))
	var r := maxf(p.distance_to(edge), 8.0)
	var pulse := 0.6 + 0.4 * sin(t * 8.0)
	draw_arc(p, r, 0.0, TAU, 40, Color(UiTheme.GOLD, pulse), 3.0, true)
	draw_arc(p, r * 0.45, 0.0, TAU, 24, Color(UiTheme.GOLD, pulse * 0.7), 2.0, true)


## The fielder who plays the ball: a ring at his feet and "자동 이동" beside him.
func _fielder_ring(tl: PlayTimeline, t: float) -> void:
	var kind := scene.chasing_fielder()
	if kind == Position.Kind.DH:
		return
	var key := "F:%s" % Position.code(kind)
	if not tl.tracks.has(key):
		return
	var at := tl.position(key, t)
	if not _in_front(at):
		return
	var p := _project(at)
	var edge := _project(at + Vector3(0.8, 0.0, 0.0))
	var r := maxf(p.distance_to(edge), 9.0)
	draw_arc(p, r, 0.0, TAU, 32, UiTheme.BLUE, 3.0, true)
	text(p + Vector2(r + 6.0, -18.0), "자동 이동", 15, UiTheme.BLUE)


## When the ball is off the screen, the edge toward it lights up.
func _edge_glow(ball: Vector3) -> void:
	var world := Field.to_world(ball)
	var behind := scene.camera.is_position_behind(world)
	var p := from_screen(scene.camera.unproject_position(world))
	if not behind and Rect2(Vector2.ZERO, view).has_point(p):
		return
	if behind:
		p = view - p
	var c := Color(UiTheme.GOLD, 0.55)
	var thick := 10.0
	if p.x < 0.0:
		draw_rect(Rect2(Vector2(0.0, 0.0), Vector2(thick, view.y)), c)
	elif p.x > view.x:
		draw_rect(Rect2(Vector2(view.x - thick, 0.0), Vector2(thick, view.y)), c)
	if p.y < 0.0:
		draw_rect(Rect2(Vector2(0.0, 0.0), Vector2(view.x, thick)), c)
	elif p.y > view.y:
		draw_rect(Rect2(Vector2(0.0, view.y - thick), Vector2(view.x, thick)), c)


## Top left: the diamond with the runners where they are now, numbered by batting order.
func _mini_diamond(tl: PlayTimeline, t: float) -> void:
	var box := Rect2(Vector2(16.0, 110.0), Vector2(190.0, 190.0))
	panel(box)
	var centre := box.get_center() + Vector2(0.0, 48.0)
	var scale := 2.5
	var corners := PackedVector2Array()
	for b: int in [4, 1, 2, 3, 4]:
		var xy := PlaySim.base_xy(b)
		corners.append(centre + Vector2(xy.x, -xy.y) * scale)
	draw_polyline(corners, Color(1, 1, 1, 0.5), 2.0, true)
	for id: String in scene.runner_ids_in_play():
		var key := "R:%s" % id
		if not tl.tracks.has(key):
			continue
		var at := tl.position(key, t)
		var p := centre + Vector2(at.x, -at.y) * scale
		draw_circle(p, 11.0, UiTheme.ORANGE)
		text(p + Vector2(-11.0, 6.0), str(scene.order_of(id)), 14, Color(0.05, 0.05, 0.08), HORIZONTAL_ALIGNMENT_CENTER, 22.0, 700)
	var ball := scene.ball_position(t)
	draw_circle(centre + Vector2(ball.x, -ball.y) * scale, 4.0, UiTheme.INK)


## The umpire's call on a close play, for a moment after it is made.
func _call(t: float) -> void:
	for c: PlayCall in scene._play.calls:
		if c.margin >= CLOSE or t < c.time or t > c.time + CALL_SHOWN:
			continue
		var line := "아웃!" if c.out else "세이프!"
		var alpha := clampf((c.time + CALL_SHOWN - t) / 0.3, 0.0, 1.0)
		text(Vector2(0.0, view.y * 0.42), line, 64, Color(UiTheme.RED if c.out else UiTheme.GREEN, alpha), HORIZONTAL_ALIGNMENT_CENTER, view.x, 700)


## Bottom centre, until the fielder has the ball: where the throw can go and the gauge, or
## the runners' keys. What is chosen is lit.
func _controls() -> void:
	if not scene.choice_open():
		return
	var chosen := scene.choice()
	var box := Rect2(Vector2(view.x * 0.5 - 300.0, view.y - BottomBar.HEIGHT - 260.0), Vector2(600.0, 122.0))
	panel(box)
	if scene._controls_fielding():
		text(box.position + Vector2(20.0, 34.0), "송구", 20, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
		var keys: Array[String] = ["→ 1루", "↑ 2루", "← 3루", "↓ 홈"]
		for i: int in 4:
			var base := i + 1
			var lit := chosen.throw_to == base or (scene.charge() >= 0.0 and scene.charging_base() == base)
			text(box.position + Vector2(100.0 + i * 120.0, 34.0), keys[i], 20, UiTheme.INK if lit else Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700 if lit else 500)
		# The gauge: let go in the green for a firm, accurate throw.
		var gauge := Rect2(box.position + Vector2(20.0, 60.0), Vector2(560.0, 22.0))
		draw_rect(gauge, Color(1, 1, 1, 0.12))
		var per := gauge.size.x / PlayChoice.FULL
		draw_rect(Rect2(gauge.position + Vector2(PlayChoice.GREEN.x * per, 0.0), Vector2((PlayChoice.GREEN.y - PlayChoice.GREEN.x) * per, gauge.size.y)), Color(UiTheme.GREEN, 0.35))
		var level := scene.charge() if scene.charge() >= 0.0 else (chosen.gauge if chosen.throw_to > 0 else 0.0)
		var hot := level > PlayChoice.GREEN.y
		draw_rect(Rect2(gauge.position, Vector2(level * per, gauge.size.y)), UiTheme.RED if hot else UiTheme.GOLD)
		text(box.position + Vector2(20.0, 108.0), "방향 키를 누르고 초록에서 떼기 · 안 누르면 자동", 15, Color(1, 1, 1, 0.6))
	elif scene._controls_running():
		text(box.position + Vector2(20.0, 34.0), "주루", 20, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
		var go := chosen.running == 1
		var back := chosen.running == -1
		text(box.position + Vector2(100.0, 34.0), "E  모두 진루", 20, UiTheme.INK if go else Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700 if go else 500)
		text(box.position + Vector2(300.0, 34.0), "Q  모두 귀루", 20, UiTheme.INK if back else Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700 if back else 500)
		text(box.position + Vector2(20.0, 80.0), "누르지 않으면 주자가 스스로 판단", 15, Color(1, 1, 1, 0.6))
