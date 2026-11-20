class_name MatchHud
extends Control
## The game's scoreboard (stage S5; the full broadcast layout of docs/05 section 3 comes in
## S6): score, inning, outs, bases, count, who is up and pitching, and the last few plays.

const INK := Color(1.0, 1.0, 1.0, 0.95)
const DIM := Color(1.0, 1.0, 1.0, 0.6)
const PANEL := Color(0.05, 0.08, 0.16, 0.78)
const GOLD := Color(1.0, 0.82, 0.25)
const GREEN := Color(0.4, 0.9, 0.45)
const RED := Color(1.0, 0.35, 0.3)

var scene: MatchScene
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Pretendard", "Noto Sans KR", "Noto Sans CJK KR", "Malgun Gothic", "NanumGothic", "Apple SD Gothic Neo"])
	system.font_weight = 600
	_font = system


func _text(at: Vector2, text: String, size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	draw_string_outline(_font, at, text, align, width, size, 4, Color(0.0, 0.0, 0.0, 0.6))
	draw_string(_font, at, text, align, width, size, color)


func _draw() -> void:
	if scene == null or scene.game == null:
		return
	var g := scene.game
	var w := size.x
	# Scoreboard, top right.
	var box := Rect2(Vector2(w - 330.0, 16.0), Vector2(314.0, 112.0))
	draw_rect(box, PANEL)
	for t: int in 2:
		var y := box.position.y + 30.0 + 30.0 * t
		var team := g.teams[t]
		var up := g.batting() == t and not g.over
		_text(Vector2(box.position.x + 14.0, y), ("▶ " if up else "   ") + team.short_name, 20, GOLD if up else INK)
		_text(Vector2(box.position.x + 150.0, y), str(g.score[t]), 24, INK, HORIZONTAL_ALIGNMENT_RIGHT, 40.0)
	var inning := "%d회%s" % [g.inning, "초" if g.top else "말"]
	_text(Vector2(box.position.x + 210.0, box.position.y + 30.0), inning, 20, INK)
	# Outs.
	for i: int in 2:
		var c := Vector2(box.position.x + 222.0 + 22.0 * i, box.position.y + 52.0)
		draw_circle(c, 7.0, RED if g.outs > i else Color(1, 1, 1, 0.2))
	# Bases as a small diamond.
	var centre := Vector2(box.position.x + 270.0, box.position.y + 50.0)
	var spots: Array[Vector2] = [centre + Vector2(16, 0), centre + Vector2(0, -16), centre + Vector2(-16, 0)]
	for b: int in 3:
		var p := spots[b]
		var pts := PackedVector2Array([p + Vector2(0, -8), p + Vector2(8, 0), p + Vector2(0, 8), p + Vector2(-8, 0)])
		draw_colored_polygon(pts, GOLD if not g.base_empty(b + 1) else Color(1, 1, 1, 0.2))
	_text(Vector2(box.position.x + 14.0, box.position.y + 100.0), "B %d  S %d" % [g.balls, g.strikes], 18, GREEN)
	# Who is up and who is pitching.
	var bat := g.batting_team()
	var batter := bat.player(g.batter_id())
	var line := scene.scorer.book.bat(g.batter_id())
	var pitcher := g.fielding_team().player(g.pitcher_id())
	var pitches: int = g.pitch_counts.get(g.pitcher_id(), 0)
	_text(Vector2(box.position.x + 90.0, box.position.y + 100.0), "%s %d타수 %d안타" % [batter.name if batter != null else "", line.ab, line.hits], 16, INK)
	draw_rect(Rect2(Vector2(w - 330.0, 132.0), Vector2(314.0, 30.0)), PANEL)
	_text(Vector2(w - 316.0, 154.0), "투수 %s  투구 %d" % [pitcher.name if pitcher != null else "", pitches], 16, DIM)
	# Last plays, bottom left.
	var shown := mini(scene.log.size(), 4)
	for i: int in shown:
		var text := scene.log[scene.log.size() - shown + i]
		_text(Vector2(18.0, size.y - 120.0 + 24.0 * i), text, 16, INK if i == shown - 1 else DIM)
	var who := "관전" if scene.human_team < 0 else ("타격" if scene.human_bats() else "투구")
	_text(Vector2(w - 330.0, 186.0), "%s · Space 번트 · F 작전 · F3 관전" % who, 14, DIM)
