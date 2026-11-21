class_name GlassPanel
extends PanelContainer
## A panel of the menus (docs/05 section 5): graphite glass with two corners cut on the slant
## (ui/kit/plate.gdshader). With a title it has a head row — an icon in the colour of the part
## of the game it belongs to, the title, a small Latin caption, room on the right for buttons —
## over a thin rule. Screens put their rows into `body`.

var body: VBoxContainer
var head: HBoxContainer
var _title: Label
var _face: PlateFace


static func make(title: String = "", icon_name: String = "", min_width: float = 0.0, accent: Color = UiTheme.ACCENT, caption: String = "") -> GlassPanel:
	var p := GlassPanel.new()
	p._build(title, icon_name, accent, caption)
	if min_width > 0.0:
		p.custom_minimum_size.x = min_width
	return p


func _build(title: String, icon_name: String, accent: Color, caption: String) -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_face = PlateFace.behind(self, "panel")
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	margin.add_theme_constant_override("margin_top", 16)
	add_child(margin)
	var column := UiKit.vbox(12)
	margin.add_child(column)
	if title != "":
		head = UiKit.hbox(10)
		column.add_child(head)
		if icon_name != "":
			head.add_child(UiKit.icon(icon_name, 24.0, accent))
		else:
			head.add_child(UiKit.slash(accent, 22.0))
		_title = UiKit.heading(title, 22)
		head.add_child(_title)
		var small := UiKit.latin(caption, 15, Color(accent.r, accent.g, accent.b, 0.85), true)
		small.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		small.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(small)
		column.add_child(UiKit.rule())
	body = UiKit.vbox(8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	sort_children.connect(_fit_face)


## The plate fills the panel whatever the container does with its other children.
func _fit_face() -> void:
	if _face != null:
		_face.position = Vector2.ZERO
		_face.size = size


func set_title(text: String) -> void:
	if _title != null:
		_title.text = text
