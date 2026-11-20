class_name CenteredPanel
extends PanelContainer
## A menu panel in the middle of the screen, in the game's theme, scaled with the window
## like the HUD (sizes are for a 1080-line screen).


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	resized.connect(_fit)


## Keeps the panel centred and at the HUD's scale.
func _fit() -> void:
	var screen := get_viewport().get_visible_rect().size
	var k := UiTheme.scale_for(screen.y)
	scale = Vector2(k, k)
	position = (screen - size * k) * 0.5


func _process(_delta: float) -> void:
	if visible:
		_fit()
