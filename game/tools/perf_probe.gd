extends SceneTree
## Runs a scene for a fixed time and reports frame-rate statistics, then quits.
##
##   godot --path game --disable-vsync --script res://tools/perf_probe.gd -- --scene res://match/duel.tscn --seconds 5
##
## Options: --scene <res path>  --seconds <n, default 5>  --warmup <seconds, default 1>
## Run on the machine and GPU you care about (Windows for this project); software
## rendering under WSL says nothing about real performance.

var _seconds := 5.0
var _warmup := 1.0
var _elapsed := 0.0
var _frame_ms: PackedFloat32Array = PackedFloat32Array()
## Each frame's script time (process + physics) and the GPU's time, to tell which one stutters.
var _cpu_ms: PackedFloat32Array = PackedFloat32Array()
var _gpu_ms: PackedFloat32Array = PackedFloat32Array()
var _render_ms: PackedFloat32Array = PackedFloat32Array()
## --hide-hud: the drawn HUD layers kept hidden, to weigh what drawing them costs; --hide
## <Class,Class>: only those layers.
var _hide_hud := false
var _hide := PackedStringArray()


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var scene_path: String = args.get("scene", "res://match/duel.tscn")
	_seconds = float(str(args.get("seconds", "5")))
	_warmup = float(str(args.get("warmup", "1")))
	_hide_hud = args.has("hide-hud")
	if args.has("hide"):
		_hide = str(args["hide"]).split(",")

	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("perf_probe: cannot load scene %s" % scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)


func _process(delta: float) -> bool:
	_elapsed += delta
	if _hide_hud or not _hide.is_empty():
		for n: Node in root.find_children("*", "Control", true, false):
			if n is HudCanvas and (_hide_hud or _hide.has((n.get_script() as Script).get_global_name())):
				(n as Control).visible = false
	if _elapsed < _warmup:
		return false
	_frame_ms.append(delta * 1000.0)
	if delta > 0.04:
		var what := ""
		var scene := root.get_child(root.get_child_count() - 1)
		if scene is MatchScene:
			var m := scene as MatchScene
			what = "log %d '%s' seg %s play %s" % [m.log.size(), str(m.log[-1]) if not m.log.is_empty() else "", Broadcast.Kind.keys()[m.broadcast.current.kind] if m.broadcast.current != null else "-", m._play_time >= 0.0]
		print("frame %.0fms at %.1fs %s" % [delta * 1000.0, _elapsed, what])
	_cpu_ms.append((Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
	_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	_render_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu())
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
	# The hitches (the user, 2026-11-23: "it stutters a little"): the longest frames and when.
	var over25 := 0
	var over50 := 0
	var worst: Array = []
	var t := _warmup
	for i: int in _frame_ms.size():
		var ms: float = _frame_ms[i]
		t += ms / 1000.0
		if ms > 25.0:
			over25 += 1
		if ms > 50.0:
			over50 += 1
		worst.append([ms, t, _cpu_ms[i], _gpu_ms[i], _render_ms[i]])
	worst.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var top := PackedStringArray()
	for w: Array in worst.slice(0, 8):
		top.append("%.0fms@%.1fs(cpu %.0f render %.0f gpu %.0f)" % [w[0], w[1], w[2], w[4], w[3]])
	print("perf_probe: max=%.1fms over25=%d over50=%d worst: %s" % [sorted[-1], over25, over50, ", ".join(top)])
	var cpu := 0.0
	var gpu := 0.0
	for i: int in _cpu_ms.size():
		cpu += _cpu_ms[i]
		gpu += _gpu_ms[i]
	print("perf_probe: script avg %.1fms · gpu avg %.1fms" % [cpu / maxf(_cpu_ms.size(), 1.0), gpu / maxf(_gpu_ms.size(), 1.0)])
	return true
