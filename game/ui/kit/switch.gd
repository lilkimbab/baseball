class_name Switch
extends Button
## An on/off switch (docs/05 section 6): a pill with a knob that slides across, in the accent
## when on.

var _slide := 0.0


static func make(on: bool, changed: Callable) -> Switch:
	var s := Switch.new()
	s.button_pressed = on
	s._slide = 1.0 if on else 0.0
	if changed.is_valid():
		s.toggled.connect(changed)
	return s


func _init() -> void:
	toggle_mode = true
	custom_minimum_size = Vector2(58.0, 30.0)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var clear := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, clear)


func _process(delta: float) -> void:
	var want := 1.0 if button_pressed else 0.0
	if not is_equal_approx(_slide, want):
		_slide = move_toward(_slide, want, delta * 8.0)
		queue_redraw()


func _draw() -> void:
	var off := Color(1.0, 1.0, 1.0, 0.14 if not is_hovered() else 0.22)
	var track := UiTheme.flat(off.lerp(UiTheme.ACCENT, _slide), roundi(size.y * 0.5))
	draw_style_box(track, Rect2(Vector2.ZERO, size))
	var r := size.y * 0.5 - 4.0
	var x := lerpf(size.y * 0.5, size.x - size.y * 0.5, _slide)
	draw_circle(Vector2(x, size.y * 0.5), r, Color.WHITE)
