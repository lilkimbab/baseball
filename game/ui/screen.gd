class_name Screen
extends Control
## A full-screen menu (docs/05 section 5): the game's theme on a dark background, laid out for a
## 1080-line screen and scaled to the window like the HUD, with small builders for titles,
## lines, buttons and rows. The title, hub, quick game, load and settings screens use it.

const HUB := "res://ui/hub_screen.tscn"
const TITLE := "res://ui/title_screen.tscn"

var content: VBoxContainer


func _ready() -> void:
	theme = UiTheme.theme()
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	content = VBoxContainer.new()
	content.position = Vector2(64.0, 48.0)
	content.add_theme_constant_override("separation", 10)
	add_child(content)
	get_viewport().size_changed.connect(_fit)
	_fit()
	refresh()


func _fit() -> void:
	var screen := get_viewport().get_visible_rect().size
	var k := UiTheme.scale_for(screen.y)
	scale = Vector2(k, k)
	size = screen / k


## Rebuilds the screen's content.
func refresh() -> void:
	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()
	build()


## What the screen shows; screens fill this in.
func build() -> void:
	pass


func go(path: String) -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file(path)


func title(line: String, font_size: int = 34) -> Label:
	var l := Label.new()
	l.text = line
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", UiTheme.GOLD)
	content.add_child(l)
	return l


func line(text: String, color: Color = UiTheme.INK, font_size: int = 20, parent: Control = null) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	(parent if parent != null else content).add_child(l)
	return l


func button(label: String, action: Callable, parent: Control = null, width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = label
	if width > 0.0:
		b.custom_minimum_size = Vector2(width, 0.0)
	b.pressed.connect(action)
	(parent if parent != null else content).add_child(b)
	return b


func row(parent: Control = null) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	(parent if parent != null else content).add_child(r)
	return r


## A row of choices with the current one marked.
func choices(label: String, ids: Array, labels: Array, current: String, pick: Callable) -> void:
	var r := row()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(200.0, 0.0)
	l.add_theme_color_override("font_color", UiTheme.DIM)
	r.add_child(l)
	for i: int in ids.size():
		var id := str(ids[i])
		button(("● " if id == current else "") + str(labels[i]), func() -> void:
			pick.call(id)
			refresh(), r)
