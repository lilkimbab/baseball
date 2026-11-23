extends SceneTree
## A side-by-side sheet of uniform faces for the user to choose from (the user, 2026-11-23: the
## public build cannot carry the personal-use faces, "bring free faces that suit the game
## instead"). Each row is one kind of lettering; each cell the same words in one face, white on
## a club navy as on a jersey.
##
##   ./dev tool-win font_sheet build/fontcheck/sheet.png --dir build/fontcheck

const ROWS := [
	["블록 (등번호·이름)", "32 FALCONS", [
		["지금 개인용 · Jersey M54", "local:jersey_m54.ttf"],
		["지금 공개판 · College Block", "res://assets/fonts/uniform/CollegeBlock-Bold.ttf"],
		["후보 · Graduate (OFL)", "dir:Graduate-Regular.ttf"],
		["후보 · Anton (OFL)", "dir:Anton-Regular.ttf"],
		["후보 · Bebas Neue (OFL)", "dir:BebasNeue-Regular.ttf"],
	]],
	["터스칸 (갈라진 세리프)", "17 TIGERS", [
		["지금 개인용 · MLB Tuscan", "local:mlb_tuscan.ttf"],
		["지금 공개판 · Rye (OFL)", "res://assets/fonts/uniform/Rye-Regular.ttf"],
		["후보 · Sancreek (OFL)", "dir:Sancreek-Regular.ttf"],
	]],
	["스크립트 (가슴 글씨)", "Falcons", [
		["지금 개인용 · Ballpark Weiner", "local:ballpark_weiner.ttf"],
		["지금 공개판 · Lobster (OFL)", "res://assets/fonts/uniform/Lobster-Regular.ttf"],
		["후보 · Yellowtail (Apache)", "dir:Yellowtail-Regular.ttf"],
		["후보 · Damion (OFL)", "dir:Damion-Regular.ttf"],
		["후보 · Kaushan Script (OFL)", "dir:KaushanScript-Regular.ttf"],
	]],
]
const NAVY := Color(0.07, 0.13, 0.27)


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var out := str(args.get("out", "user://font_sheet.png"))
	var dir := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join(str(args.get("dir", "build/fontcheck")))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1920, 1080)
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.115, 0.13)
	bg.size = Vector2(1920, 1080)
	root.add_child(bg)
	var label_font := load("res://ui/fonts/nexon_lv2/NEXONLv2Gothic-Bold.woff") as Font
	var y := 24.0
	for row: Array in ROWS:
		_text(str(row[0]), label_font, 30, Vector2(32, y), Color(1, 0.85, 0.4))
		y += 46.0
		var cells: Array = row[2]
		var w := (1920.0 - 64.0 - 16.0 * (cells.size() - 1)) / cells.size()
		for i: int in cells.size():
			var cell: Array = cells[i]
			var x := 32.0 + i * (w + 16.0)
			var plate := ColorRect.new()
			plate.color = NAVY
			plate.position = Vector2(x, y)
			plate.size = Vector2(w, 220)
			root.add_child(plate)
			var font := _font(str(cell[1]), dir)
			if font != null:
				var size := 92 if cells.size() <= 3 else 62
				var words := Label.new()
				words.text = str(row[1])
				words.add_theme_font_override(&"font", font)
				words.add_theme_font_size_override(&"font_size", size)
				words.add_theme_color_override(&"font_color", Color.WHITE)
				words.add_theme_color_override(&"font_outline_color", Color(0.85, 0.15, 0.2))
				words.add_theme_constant_override(&"outline_size", 10)
				words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				words.position = Vector2(x, y)
				words.size = Vector2(w, 170)
				root.add_child(words)
			else:
				_text("(없음)", label_font, 26, Vector2(x + 20, y + 70), Color(0.7, 0.7, 0.7))
			_text(str(cell[0]), label_font, 22, Vector2(x + 14, y + 178), Color(0.85, 0.88, 0.95))
		y += 250.0
	for i: int in 8:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(out)
	print("font_sheet: %s" % out)
	quit()


func _font(spec: String, dir: String) -> Font:
	var path := spec
	if spec.begins_with("local:"):
		path = LocalContent.dir().path_join("fonts/uniform").path_join(spec.trim_prefix("local:"))
	elif spec.begins_with("dir:"):
		path = dir.path_join(spec.trim_prefix("dir:"))
	else:
		return load(spec) as Font
	if not FileAccess.file_exists(path):
		return null
	var file := FontFile.new()
	return file if file.load_dynamic_font(path) == OK else null


func _text(s: String, font: Font, size: int, at: Vector2, colour: Color) -> void:
	var l := Label.new()
	l.text = s
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", colour)
	l.position = at
	root.add_child(l)
