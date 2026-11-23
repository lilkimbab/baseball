class_name ModeTile
extends Button
## A part of the game as a card (docs/04 section 5): a picture from the game itself, darker
## toward the foot where its Latin caption (in the part's own colour), its name and a line
## about it stand; a tag when something is in progress there. Under the pointer the card
## lifts, its edge turns white and the picture brightens. Without a picture (ui/art not made
## yet) it is a plain plate with the part's icon large in it.

var title := ""
var caption := ""
var subtitle := ""
var status := ""
var icon_name := ""
var accent := UiTheme.BRAND
var art: Texture2D
var _lift := 0.0
var _face: PlateFace
var _picture: TextureRect
var _shown := ""


static func make(name: String, about: String, icon: String, action: Callable, tint: Color = UiTheme.BRAND, latin: String = "", picture: String = "") -> ModeTile:
	var tile := ModeTile.new()
	tile.title = name
	tile.subtitle = about
	tile.icon_name = icon
	tile.accent = tint
	tile.caption = latin
	var path := "res://ui/art/%s.jpg" % picture
	if picture != "" and ResourceLoader.exists(path):
		tile.art = load(path) as Texture2D
	# The button's own text is the name (for keyboards and tests); it is drawn here instead.
	tile.text = name
	if action.is_valid():
		tile.pressed.connect(action)
	return tile


func _init() -> void:
	custom_minimum_size = Vector2(260.0, 200.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var clear := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, clear)
	for colour: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(colour, Color(0, 0, 0, 0))


func _ready() -> void:
	_face = PlateFace.behind(self, "card")
	if art != null:
		_picture = TextureRect.new()
		_picture.texture = art
		_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_picture.show_behind_parent = true
		_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var material := ShaderMaterial.new()
		material.shader = preload("res://ui/kit/rounded_image.gdshader")
		_picture.material = material
		add_child(_picture)
	resized.connect(_place)
	_place()


func _place() -> void:
	var offset := Vector2(0.0, -5.0 * _lift)
	if _face != null:
		_face.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_face.position = offset
		_face.size = size
	if _picture != null:
		_picture.position = offset + Vector2(2.0, 2.0)
		_picture.size = size - Vector2(4.0, 4.0)
		var material := _picture.material as ShaderMaterial
		material.set_shader_parameter(&"size", _picture.size)
		material.set_shader_parameter(&"cut", 17.0)
		material.set_shader_parameter(&"lit", _lift)


func _process(delta: float) -> void:
	var want := 1.0 if (is_hovered() or has_focus()) and not disabled else 0.0
	var state := "card_hover" if want > 0.5 else "card"
	if state != _shown and _face != null:
		_shown = state
		_face.set_look(state)
	if not is_equal_approx(_lift, want):
		_lift = move_toward(_lift, want, delta * 6.0)
		_place()
		queue_redraw()


func _draw() -> void:
	var o := Vector2(0.0, -5.0 * _lift)
	var fade := 0.4 if disabled else 1.0
	var bold := UiTheme.display(700)
	var body := UiTheme.font(500)
	if art == null:
		var icon := UiTheme.icon(icon_name)
		if icon != null:
			var side := minf(size.y * 0.4, 110.0)
			draw_texture_rect(icon, Rect2(o + Vector2(size.x - side - 26.0, 24.0), Vector2(side, side)), false, Color(accent.r, accent.g, accent.b, 0.5 * fade))
	var x := 24.0
	var foot := size.y - 24.0
	# The part's colour: a line along the foot of the card, growing under the pointer.
	draw_rect(Rect2(o + Vector2(x, size.y - 12.0), Vector2((size.x - x * 2.0) * (0.12 + 0.88 * _lift), 3.0)), Color(accent.r, accent.g, accent.b, fade))
	draw_string(body, o + Vector2(x, foot - 8.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, size.x - x * 2.0, 16, Color(1.0, 1.0, 1.0, 0.72 * fade))
	draw_string(bold, o + Vector2(x, foot - 36.0), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - x * 2.0, 32, Color(1.0, 1.0, 1.0, fade))
	if caption != "":
		draw_string(UiTheme.numeric(true), o + Vector2(x, foot - 74.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(accent.r, accent.g, accent.b, fade))
	if status != "":
		var w := bold.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15).x + 26.0
		var tag := PackedVector2Array([o + Vector2(24.0, 18.0), o + Vector2(24.0 + w, 18.0), o + Vector2(18.0 + w, 44.0), o + Vector2(18.0, 44.0)])
		draw_colored_polygon(tag, accent)
		draw_string(bold, o + Vector2(34.0, 37.0), status, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, UiTheme.NAVY_TEXT)
