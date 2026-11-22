class_name CenteredPanel
extends PanelContainer
## A menu panel in the middle of the screen in the menus' look (docs/05 section 5, docs/08 R5):
## the graphite plate with two corners cut (PlateFace "panel"), a head row — a slanted stroke
## in the accent, the title, a small Latin caption, a grey note on the right — over a thin
## rule; the panel's rows go into `body`. Scaled with the window like the HUD (sizes are for a
## 1080-line screen).

var body: VBoxContainer
var _face: PlateFace
var _title: Label
var _note: Label


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	add_theme_stylebox_override("panel", UiTheme.margins(26.0, 18.0, 26.0, 22.0))
	_face = PlateFace.behind(self, "panel")
	# Placed by hand after the container sorts (anchors would fight the size set here).
	_face.set_anchors_preset(Control.PRESET_TOP_LEFT)
	sort_children.connect(func() -> void:
		_face.position = Vector2.ZERO
		_face.size = size)
	resized.connect(_fit)


## The head row and the body under it; call once from _ready.
func build(title: String, caption: String, accent: Color = UiTheme.ACCENT) -> void:
	var column := UiKit.vbox(12)
	add_child(column)
	var head := UiKit.hbox(10)
	column.add_child(head)
	head.add_child(UiKit.slash(accent, 24.0))
	_title = UiKit.heading(title, 24)
	head.add_child(_title)
	var small := UiKit.latin(caption, 15, Color(accent, 0.85), true)
	small.size_flags_vertical = Control.SIZE_SHRINK_END
	small.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(small)
	_note = UiKit.label("", 15, UiTheme.DIM, 500)
	_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_note)
	column.add_child(UiKit.rule())
	body = UiKit.vbox(8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)


func set_title(text: String) -> void:
	if _title != null:
		_title.text = text


func set_note(text: String) -> void:
	if _note != null:
		_note.text = text


## Keeps the panel centred and at the HUD's scale.
func _fit() -> void:
	var screen := get_viewport().get_visible_rect().size
	var k := UiTheme.scale_for(screen.y)
	scale = Vector2(k, k)
	position = (screen - size * k) * 0.5


func _process(_delta: float) -> void:
	if visible:
		_fit()


## A section's title inside the body: a short stroke and the words in white.
static func section(text: String, accent: Color = UiTheme.ACCENT) -> HBoxContainer:
	var row := UiKit.hbox(8)
	row.add_child(UiKit.slash(accent, 16.0))
	row.add_child(UiKit.label(text, 17, Color.WHITE, 700))
	return row


## A quiet button across the panel, its words on the left.
static func row_button(text: String, action: Callable) -> GameButton:
	var b := GameButton.make(text, action)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


## A setting: its name on the left, the choices on the right (the current one white).
static func choice_row(label: String, ids: Array, labels: Array, current: String, pick: Callable) -> HBoxContainer:
	var row := UiKit.hbox(12)
	var name := UiKit.label(label, 18, UiTheme.INK, 600)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	row.add_child(UiKit.segmented(ids, labels, current, pick))
	return row
