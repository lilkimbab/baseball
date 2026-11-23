class_name BallShelf
extends Control
## The career's commemorative balls on a shelf (Milestones): each ball with its name and the
## day and opponent written under it, the newest first, then the next ones still ahead,
## faded, with how far there is to go.

const CELL := Vector2(156.0, 150.0)
const RADIUS := 30.0

## Each: [name, the line under it, earned].
var balls: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(CELL.x, CELL.y)


## Fills it from a career (its kept balls) and its first-team totals (the next ones).
func fill(c: CareerPlayer, totals: Array) -> void:
	balls.clear()
	for i: int in range(c.milestones.size() - 1, -1, -1):
		var m: Array = c.milestones[i]
		var when := "%d년 %d일차" % [int(m[1]), int(m[2])]
		balls.append([Milestones.name_of(str(m[0])), "%s · vs %s" % [when, str(m[3])] if str(m[3]) != "" else when, true])
	for a: Array in Milestones.ahead(totals, c.is_pitcher(), 2):
		var m: Array = a[0]
		balls.append([str(m[1]), "%d개 남음" % (int(m[3]) - int(a[1])), false])
	_fit()
	queue_redraw()


func _columns() -> int:
	return maxi(int(size.x / CELL.x), 1)


func _fit() -> void:
	var rows := ceili(float(maxi(balls.size(), 1)) / float(_columns()))
	custom_minimum_size.y = CELL.y * rows


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit()


func _draw() -> void:
	var cols := _columns()
	var head := UiTheme.display(800)
	var body := UiTheme.font(600)
	for i: int in balls.size():
		var b: Array = balls[i]
		var cell := Vector2(float(i % cols) * CELL.x, float(i / cols) * CELL.y)
		var mid := cell + Vector2(CELL.x * 0.5, 0.0)
		var earned := bool(b[2])
		var a := 1.0 if earned else 0.32
		# The stand: a small dark plinth with a gold rim, and the ball on it.
		var stand := Rect2(mid + Vector2(-34.0, 62.0), Vector2(68.0, 10.0))
		draw_rect(stand, Color(0.06, 0.06, 0.07, 0.9 * a))
		draw_rect(Rect2(stand.position, Vector2(stand.size.x, 2.0)), Color(UiTheme.GOLD, 0.8 * a))
		if earned:
			draw_circle(mid + Vector2(0.0, 30.0), RADIUS + 9.0, Color(UiTheme.GOLD, 0.10))
		Loading.ball(self, mid + Vector2(0.0, 30.0), RADIUS, 0.35, a)
		_centred(head, mid + Vector2(0.0, 98.0), str(b[0]), 17.0, Color(1.0, 1.0, 1.0, 0.96 * a + (0.0 if earned else 0.3)))
		_centred(body, mid + Vector2(0.0, 120.0), str(b[1]), 13.0, UiTheme.GOLD if not earned else UiTheme.DIM)


func _centred(font: Font, at: Vector2, text: String, px: float, colour: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(px)).x
	if w > CELL.x - 8.0:
		px *= (CELL.x - 8.0) / w
		w = CELL.x - 8.0
	draw_string(font, Vector2(at.x - w * 0.5, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(px), colour)
