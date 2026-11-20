class_name Scorebug
extends HudCanvas
## The score display at the top centre (docs/13 S6-2): both teams and scores, the inning with
## ▲ for the top and ▼ for the bottom, the bases, and the count in B-S-O order (three ball
## lamps, two strike lamps, two out lamps), plus the pitcher's pitch count.

const WIDTH := 760.0
const HEIGHT := 78.0

var scene: MatchScene


func _draw() -> void:
	if scene == null or scene.game == null:
		return
	begin()
	var g := scene.game
	var box := Rect2(Vector2(view.x * 0.5 - WIDTH * 0.5, 14.0), Vector2(WIDTH, HEIGHT))
	panel(box)
	var side := 250.0
	# Away on the left, home on the right; the side at bat is marked.
	for t: int in 2:
		var team := g.teams[t]
		var at_bat := g.batting() == t and not g.over
		var x := box.position.x if t == 0 else box.end.x - side
		var block := Rect2(Vector2(x, box.position.y), Vector2(side, HEIGHT))
		if at_bat:
			draw_rect(Rect2(block.position + Vector2(0.0, HEIGHT - 4.0), Vector2(side, 4.0)), UiTheme.GOLD)
		var name_x := block.position.x + (18.0 if t == 0 else 96.0)
		var score_x := block.position.x + (side - 78.0 if t == 0 else 18.0)
		text(Vector2(name_x, box.position.y + 49.0), team.short_name, 26, UiTheme.GOLD if at_bat else UiTheme.INK)
		text(Vector2(score_x, box.position.y + 54.0), str(g.score[t]), 40, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 700)
	draw_line(Vector2(box.position.x + side, box.position.y + 10.0), Vector2(box.position.x + side, box.end.y - 10.0), UiTheme.LINE, 2.0)
	draw_line(Vector2(box.end.x - side, box.position.y + 10.0), Vector2(box.end.x - side, box.end.y - 10.0), UiTheme.LINE, 2.0)
	# The middle: inning, bases, count.
	var mid := box.position.x + side
	var inning := "%d%s" % [g.inning, "▲" if g.top else "▼"]
	text(Vector2(mid + 14.0, box.position.y + 34.0), inning, 26, UiTheme.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 700)
	var pitches: int = g.pitch_counts.get(g.pitcher_id(), 0)
	text(Vector2(mid + 14.0, box.position.y + 64.0), "투구 %d" % pitches, 17, UiTheme.DIM)
	_draw_bases(Vector2(mid + 112.0, box.position.y + 40.0), g)
	_draw_count(Vector2(mid + 150.0, box.position.y + 18.0), g)


func _draw_bases(centre: Vector2, g: GameState) -> void:
	var spots: Array[Vector2] = [centre + Vector2(17.0, 0.0), centre + Vector2(0.0, -17.0), centre + Vector2(-17.0, 0.0)]
	for b: int in 3:
		var p := spots[b]
		var r := 9.0
		var pts := PackedVector2Array([p + Vector2(0.0, -r), p + Vector2(r, 0.0), p + Vector2(0.0, r), p + Vector2(-r, 0.0)])
		draw_colored_polygon(pts, UiTheme.GOLD if not g.base_empty(b + 1) else Color(1, 1, 1, 0.18))


## B-S-O lamps.
func _draw_count(at: Vector2, g: GameState) -> void:
	var rows: Array = [["B", 3, g.balls, UiTheme.GREEN], ["S", 2, g.strikes, UiTheme.GOLD], ["O", 2, g.outs, UiTheme.RED]]
	for i: int in rows.size():
		var row: Array = rows[i]
		var y := at.y + i * 19.0
		text(Vector2(at.x, y + 7.0), row[0], 16, row[3])
		for j: int in int(row[1]):
			draw_circle(Vector2(at.x + 28.0 + j * 20.0, y + 1.0), 6.5, row[3] if j < int(row[2]) else Color(1, 1, 1, 0.18))
