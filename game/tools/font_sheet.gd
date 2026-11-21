extends SceneTree
## Draws a specimen of every font in a folder (or of the uniform fonts the game uses), for
## choosing lettering: a word, a number and a Korean name in each.
##
##   ./dev tool-win font_sheet build/fonts/sheet --dir <folder of .ttf/.otf> [--word Otters] [--size 54]

var _out := "user://fonts.png"
var _frames := 0


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_out = str(args.get("out", _out))
	if not _out.ends_with(".png"):
		_out += ".png"
	var word := str(args.get("word", "Otters"))
	var size := int(str(args.get("size", "54")))
	var dir := str(args.get("dir", ""))
	var files: Array[String] = []
	for name: String in DirAccess.get_files_at(dir):
		if name.get_extension().to_lower() in ["ttf", "otf", "woff2"]:
			files.append(dir.path_join(name))
	files.sort()
	var sheet := Control.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(sheet)
	var back := ColorRect.new()
	back.color = Color(0.93, 0.93, 0.94)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.add_child(back)
	var columns := 2
	var row_height := size * 1.45
	var column_width := root.get_visible_rect().size.x / columns
	var per_column := ceili(files.size() / float(columns))
	for i: int in files.size():
		var font := FontFile.new()
		font.load_dynamic_font(files[i])
		var at := Vector2((i / per_column) * column_width + 16.0, (i % per_column) * row_height + 8.0)
		var caption := Label.new()
		caption.text = files[i].get_file().get_basename()
		caption.position = at
		caption.add_theme_font_size_override("font_size", 13)
		caption.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4))
		sheet.add_child(caption)
		var sample := Label.new()
		sample.text = "%s  %s  0123456789  배준율" % [word, word.to_upper()]
		sample.position = at + Vector2(0.0, 12.0)
		sample.add_theme_font_override("font", font)
		sample.add_theme_font_size_override("font_size", size)
		sample.add_theme_color_override("font_color", Color(0.1, 0.14, 0.4))
		sheet.add_child(sample)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 6:
		return false
	root.get_texture().get_image().save_png(_out)
	print("font_sheet: ", _out)
	return true
