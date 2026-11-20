extends SceneTree
## Runs a scene for a fixed time and reports frame-rate statistics, then quits.
##
##   godot --path game --disable-vsync --script res://tools/perf_probe.gd -- --scene res://boot/boot.tscn --seconds 5
##
## Options: --scene <res path>  --seconds <n, default 5>  --warmup <seconds, default 1>
## Run on the machine and GPU you care about (Windows for this project); software
## rendering under WSL says nothing about real performance.

var _seconds := 5.0
var _warmup := 1.0
var _elapsed := 0.0
var _frame_ms: PackedFloat32Array = PackedFloat32Array()


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var scene_path: String = args.get("scene", "res://boot/boot.tscn")
	_seconds = float(str(args.get("seconds", "5")))
	_warmup = float(str(args.get("warmup", "1")))

	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("perf_probe: cannot load scene %s" % scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed < _warmup:
		return false
	_frame_ms.append(delta * 1000.0)
	if _elapsed < _warmup + _seconds:
		return false

	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var total := 0.0
	for ms: float in sorted:
		total += ms
	var count := sorted.size()
	var avg_ms := total / maxf(float(count), 1.0)
	var p99_ms: float = sorted[mini(count - 1, int(float(count) * 0.99))]
	var size := DisplayServer.window_get_size()
	print("perf_probe: frames=%d avg=%.2fms (%.0f fps) p99=%.2fms (%.0f fps) window=%dx%d renderer=%s adapter=%s" % [
		count, avg_ms, 1000.0 / avg_ms, p99_ms, 1000.0 / p99_ms, size.x, size.y,
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(),
	])
	return true
