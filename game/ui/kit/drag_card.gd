class_name DragCard
extends PanelContainer
## A card that can be picked up and dropped on another (the line-up board: a bench player onto
## a position, a starter onto an order slot, a reliever onto the closer's place). It carries a
## tag (what it stands for) and a kind (what may be dropped where); dropping calls `dropped`
## with the tags of the card carried and the card under it. A click without a drag calls
## `clicked` (the old pick-two-to-swap still works).

signal dropped(from_tag: String, to_tag: String)
signal clicked(tag: String)

var tag := ""
## What it is when carried ("bat", "pitch"); "" it cannot be picked up.
var kind := ""
## Kinds that may be dropped on it.
var accepts: Array[String] = []
var lit := false
var _box: StyleBoxFlat
var _hover := false
var _press_at := Vector2.ZERO


static func make(card_tag: String, card_kind: String, card_accepts: Array[String], tint: Color = Color(1, 1, 1, 0.06)) -> DragCard:
	var c := DragCard.new()
	c.tag = card_tag
	c.kind = card_kind
	c.accepts = card_accepts
	c._box = StyleBoxFlat.new()
	c._box.bg_color = tint
	c._box.set_corner_radius_all(6)
	c._box.content_margin_left = 8.0
	c._box.content_margin_right = 8.0
	c._box.content_margin_top = 5.0
	c._box.content_margin_bottom = 5.0
	c.add_theme_stylebox_override("panel", c._box)
	return c


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void:
		_hover = true
		_paint())
	mouse_exited.connect(func() -> void:
		_hover = false
		_paint())
	for c: Node in find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paint()


## Smaller margins, for rows and chips.
func tight() -> void:
	_box.content_margin_top = 3.0
	_box.content_margin_bottom = 3.0
	_box.content_margin_left = 6.0
	_box.content_margin_right = 6.0


func set_lit(on: bool) -> void:
	lit = on
	if _box != null:
		_paint()


func _paint() -> void:
	_box.border_color = UiTheme.BRAND if lit else Color(1.0, 1.0, 1.0, 0.35 if _hover else 0.12)
	_box.set_border_width_all(3 if lit else 1)


func _gui_input(event: InputEvent) -> void:
	var b := event as InputEventMouseButton
	if b != null and b.button_index == MOUSE_BUTTON_LEFT:
		if b.pressed:
			_press_at = b.position
		elif b.position.distance_to(_press_at) < 6.0:
			clicked.emit(tag)


func _get_drag_data(_at: Vector2) -> Variant:
	if kind == "":
		return null
	# What follows the pointer: a faint copy of the card.
	var ghost := duplicate(0) as Control
	ghost.modulate = Color(1.0, 1.0, 1.0, 0.75)
	ghost.size = size
	var holder := Control.new()
	holder.add_child(ghost)
	ghost.position = -size * 0.5
	set_drag_preview(holder)
	return {"tag": tag, "kind": kind}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	var d := data as Dictionary
	return d != null and accepts.has(str(d.get("kind", ""))) and str(d.get("tag", "")) != tag


func _drop_data(_at: Vector2, data: Variant) -> void:
	dropped.emit(str((data as Dictionary).get("tag", "")), tag)
