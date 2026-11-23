class_name DataTable
extends VBoxContainer
## A table as the menus show them (docs/04 section 5; the reference's line-up and roster
## tables): a header that stays put, rows under it that scroll, striped, lit under the
## pointer, one of them chosen. A row can carry a small portrait, coloured cells and a tag the
## screen reads back when it is picked.
##
##   var t := DataTable.new()
##   t.set_columns([["선수", 220.0, 0], ["타율", 80.0, 2]])        # title, width, 0 left 1 centre 2 right
##   t.add_row(["박건우", ".312"], player, {1: UiTheme.ACCENT}, portrait)

signal row_pressed(index: int, tag: Variant)
signal row_hovered(index: int, tag: Variant)

const HEADER_HEIGHT := 34.0

var row_height := 38.0
## The column a row's portrait sits in (the player's name, as a rule).
var portrait_column := 0
var selected := -1
## Rows drawn dim (a player who cannot be picked, say).
var dim_rows: Dictionary[int, bool] = {}

var _columns: Array[Array] = []
var _rows: Array[Dictionary] = []
var _header: Control
var _scroll: ScrollContainer
var _body: Control
var _hover := -1


func _init() -> void:
	add_theme_constant_override("separation", 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_header = Control.new()
	_header.custom_minimum_size = Vector2(0.0, HEADER_HEIGHT)
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.draw.connect(_draw_header)
	add_child(_header)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	_body = Control.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.mouse_filter = Control.MOUSE_FILTER_STOP
	_body.draw.connect(_draw_rows)
	_body.gui_input.connect(_on_input)
	_body.mouse_exited.connect(func() -> void:
		_hover = -1
		_body.queue_redraw())
	_scroll.add_child(_body)


## Each column: [title, width, align]; align 0 left, 1 centre, 2 right.
func set_columns(columns: Array) -> void:
	_columns.clear()
	var total := 0.0
	for c: Array in columns:
		_columns.append([str(c[0]), float(c[1]), int(c[2]) if c.size() > 2 else 0])
		total += float(c[1])
	custom_minimum_size.x = total + 20.0
	_header.queue_redraw()


func clear() -> void:
	_rows.clear()
	dim_rows.clear()
	selected = -1
	_hover = -1
	_resize()


func add_row(cells: Array, tag: Variant = null, colours: Dictionary = {}, portrait: Texture2D = null) -> int:
	_rows.append({"cells": cells, "tag": tag, "colours": colours, "portrait": portrait})
	_resize()
	return _rows.size() - 1


func row_count() -> int:
	return _rows.size()


func cell_text(row: int, column: int) -> String:
	return str((_rows[row]["cells"] as Array)[column])


func tag_of(row: int) -> Variant:
	return _rows[row]["tag"] if row >= 0 and row < _rows.size() else null


## Sets a row's portrait once it has been drawn (PortraitStudio makes them a few a frame).
func set_portrait(row: int, portrait: Texture2D) -> void:
	if row >= 0 and row < _rows.size():
		_rows[row]["portrait"] = portrait
		_body.queue_redraw()


## Picks a row as a click on it does.
func press_row(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	selected = index
	_body.queue_redraw()
	row_pressed.emit(index, _rows[index]["tag"])


func _resize() -> void:
	_body.custom_minimum_size = Vector2(0.0, _rows.size() * row_height)
	_body.queue_redraw()


func _on_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		var at := int(motion.position.y / row_height)
		at = at if at >= 0 and at < _rows.size() else -1
		if at != _hover:
			_hover = at
			_body.queue_redraw()
			if at >= 0:
				row_hovered.emit(at, _rows[at]["tag"])
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		press_row(int(click.position.y / row_height))


## How much wider than their set widths the columns are drawn: a table always fills its panel
## (the user: "half of it is empty space"), the columns keeping their proportions.
func _stretch() -> float:
	var total := 0.0
	for c: Array in _columns:
		total += float(c[1])
	return maxf((_header.size.x - 20.0) / maxf(total, 1.0), 1.0)


func _draw_header() -> void:
	var font := UiTheme.font(600)
	_header.draw_rect(Rect2(Vector2.ZERO, _header.size), Color(1.0, 1.0, 1.0, 0.06))
	_header.draw_line(Vector2(0.0, _header.size.y - 1.0), Vector2(_header.size.x, _header.size.y - 1.0), Color(1.0, 1.0, 1.0, 0.28), 1.0)
	var k := _stretch()
	var x := 10.0
	for c: Array in _columns:
		_text(_header, font, str(c[0]), x, float(c[1]) * k, int(c[2]), HEADER_HEIGHT * 0.5 + 5.0, 15, UiTheme.DIM)
		x += float(c[1]) * k


func _draw_rows() -> void:
	var font := UiTheme.font(600)
	# Only the rows in view are drawn (a second team is fifty rows long).
	var first := maxi(int(_scroll.scroll_vertical / row_height) - 1, 0)
	var last := mini(first + int(_scroll.size.y / row_height) + 3, _rows.size())
	var k := _stretch()
	for i: int in range(first, last):
		var y := i * row_height
		var rect := Rect2(0.0, y, _body.size.x, row_height)
		if i == selected:
			_body.draw_rect(rect, UiTheme.ROW_SELECTED)
			_body.draw_rect(Rect2(0.0, y, 3.0, row_height), UiTheme.BRAND)
		elif i == _hover:
			_body.draw_rect(rect, UiTheme.ROW_HOVER)
		elif i % 2 == 1:
			_body.draw_rect(rect, UiTheme.ROW_ALT)
		var row := _rows[i]
		var cells: Array = row["cells"]
		var colours: Dictionary = row["colours"]
		var faded := bool(dim_rows.get(i, false))
		var x := 10.0
		for c: int in _columns.size():
			var width := float(_columns[c][1]) * k
			var left := x
			if c == portrait_column and row["portrait"] != null:
				var side := row_height - 6.0
				_body.draw_texture_rect(row["portrait"] as Texture2D, Rect2(x, y + 3.0, side, side), false)
				left += side + 8.0
				width -= side + 8.0
			var colour: Color = colours.get(c, UiTheme.INK)
			if faded:
				colour.a *= 0.4
			if c < cells.size():
				_text(_body, font, str(cells[c]), left, width, int(_columns[c][2]), y + row_height * 0.5 + 6.0, 17, colour)
			x += float(_columns[c][1]) * k


static func _text(on: Control, font: Font, text: String, x: float, width: float, align: int, baseline: float, font_size: int, colour: Color) -> void:
	var how := [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT][clampi(align, 0, 2)] as HorizontalAlignment
	var edge := UiTheme.ink_edge(colour)
	if edge.a > 0.0:
		on.draw_string_outline(font, Vector2(x, baseline), text, how, maxf(width - 10.0, 10.0), font_size, 3, edge)
	on.draw_string(font, Vector2(x, baseline), text, how, maxf(width - 10.0, 10.0), font_size, colour)


func _process(_delta: float) -> void:
	# Scrolling moves which rows are in view.
	if _scroll.scroll_vertical != _last_scroll:
		_last_scroll = _scroll.scroll_vertical
		_body.queue_redraw()


var _last_scroll := 0
