class_name AdStrip
extends Control
## A strip of sponsors' boards (docs/06 6.2-8), drawn once into a viewport that the ad bands
## round the park show: each a coloured board with the sponsor's name in the middle.

const SPONSORS := "res://data/sponsors.ko.json"

var sponsors: Array[Dictionary] = []
var slots := 8


static func load_sponsors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(SPONSORS):
		return out
	for s: Dictionary in JsonIO.read_object(SPONSORS).get("sponsors", []):
		out.append(s)
	return out


func _draw() -> void:
	var w := size.x / slots
	var font := UiTheme.font(700)
	for i: int in slots:
		var s: Dictionary = sponsors[i % sponsors.size()] if not sponsors.is_empty() else {"name": "", "bg": "#202020", "fg": "#ffffff"}
		var rect := Rect2(Vector2(w * i, 0.0), Vector2(w, size.y))
		draw_rect(rect, Color(str(s["bg"])))
		draw_rect(Rect2(rect.position, Vector2(2.0, size.y)), Color(0, 0, 0, 0.35))
		var text := str(s["name"])
		var fs := 34
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(rect.position.x + (w - width) * 0.5, size.y * 0.5 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(str(s["fg"])))
