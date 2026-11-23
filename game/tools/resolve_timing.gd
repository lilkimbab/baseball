extends SceneTree
## How long the physical resolver takes for each event of a game (the user, 2026-11-23: "it
## stutters a little" — a manager's game hitched about every three seconds, one plate appearance
## at a time). Plays games with the physical resolver and prints the time per event by kind.
##
##   godot --headless --path game --script res://tools/resolve_timing.gd -- --games 3


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var games := int(str(args.get("games", "3")))
	var clubs := LeagueSession.league_clubs()
	var env := LeagueEnvIO.load_default()
	var catalog := PitchCatalogIO.load_default()
	var ovr := LeagueEnvIO.load_overall()
	var times: Dictionary = {}
	print("native physics: %s" % NativePhysics.available())
	for n: int in games:
		var sim := GameSim.create(clubs[n % clubs.size()], clubs[(n + 1) % clubs.size()], RuleSet.kbo_2026(), env, catalog, ovr, Rng.new(100 + n), null, null, true)
		var guard := 0
		while not sim.state.over and guard < GameSim.MAX_EVENTS:
			var t0 := Time.get_ticks_usec()
			var e := sim.resolver.next_event(sim.state)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			var kind := "in play" if e.fielders != "" else "no contact"
			if not times.has(kind):
				times[kind] = PackedFloat32Array()
			(times[kind] as PackedFloat32Array).append(ms)
			if guard % 25 == 0:
				print("  event %d: %s %.1fms" % [guard, kind, ms])
			var out := GameFlow.apply(sim.state, e)
			sim.scorer.record(sim.state, e, out)
			sim.manager.note_change(sim.state, e)
			guard += 1
	for kind: String in times:
		var a: PackedFloat32Array = times[kind]
		var sorted := a.duplicate()
		sorted.sort()
		var total := 0.0
		for v: float in sorted:
			total += v
		print("%s: n=%d avg=%.1fms p95=%.1fms max=%.1fms" % [kind, sorted.size(), total / sorted.size(), sorted[int(sorted.size() * 0.95)], sorted[-1]])
	quit()
