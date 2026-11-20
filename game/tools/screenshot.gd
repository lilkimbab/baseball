extends SceneTree
## Renders a scene for a few frames and saves the viewport as a PNG, then quits.
##
##   godot --path game --script res://tools/screenshot.gd -- --scene res://match/duel.tscn --out /tmp/shot.png
##
## Options: --scene <res path>  --out <file>  --frames <n, default 30>
## Needs a real rendering driver, so do not combine with --headless.

var _frames_left := 30
var _out_path := "user://screenshot.png"


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var scene_path: String = args.get("scene", "res://match/duel.tscn")
	_out_path = args.get("out", _out_path)
	_frames_left = int(str(args.get("frames", "30")))

	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("screenshot: cannot load scene %s" % scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())


func _process(_delta: float) -> bool:
	_frames_left -= 1
	if _frames_left > 0:
		return false
	var image := root.get_texture().get_image()
	var err := image.save_png(_out_path)
	if err != OK:
		push_error("screenshot: save failed (%d) for %s" % [err, _out_path])
		quit(1)
		return true
	print("screenshot: %s %dx%d renderer=%s adapter=%s" % [
		_out_path, image.get_width(), image.get_height(),
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(),
	])
	return true
