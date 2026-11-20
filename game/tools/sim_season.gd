extends SceneTree
## Plays a 144-game season among the ten clubs of one division of a roster pack and prints the
## spread of team records and the league leaders next to the KBO's 2025 figures, to check
## that individual records are as spread out as real ones (docs/13 S4).
##
##   godot --headless --path game --script res://tools/sim_season.gd -- --division 2
##
## Options: --pack <res://data/rosters/x.json>  --division <1..3, default 2>  --seed <n>
func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var division := int(str(args.get("division", "2")))
	var pack := str(args.get("pack", "res://data/rosters/fiction-2026.json"))
	var catalog := PitchCatalogIO.load_default()
	var env := LeagueEnvIO.load_default()
	var ovr := LeagueEnvIO.load_overall()
	var teams := RosterIO.load_pack(pack).slice((division - 1) * 10, division * 10)
	var bat: Dictionary[String, BattingLine] = {}
	var pit: Dictionary[String, PitchingLine] = {}
	var names: Dictionary[String, String] = {}
	var wins := PackedInt32Array(); wins.resize(10)
	var losses := PackedInt32Array(); losses.resize(10)
	var rng := Rng.new(int(str(args.get("seed", "99"))))
	var g := 0
	for round: int in 16:
		for i: int in 10:
			for j: int in range(i + 1, 10):
				var home := i if (round % 2 == 0) else j
				var away := j if home == i else i
				var sim := GameSim.create(teams[away], teams[home], RuleSet.kbo_2026(), env, catalog, ovr, rng.fork(g))
				sim.play()
				g += 1
				if sim.state.winner == 1: wins[home] += 1; losses[away] += 1
				elif sim.state.winner == 0: wins[away] += 1; losses[home] += 1
				for id: String in sim.scorer.book.batting:
					if not bat.has(id): bat[id] = BattingLine.new()
					bat[id].add(sim.scorer.book.batting[id])
				for id: String in sim.scorer.book.pitching:
					if not pit.has(id): pit[id] = PitchingLine.new()
					pit[id].add(sim.scorer.book.pitching[id])
	for t: Team in teams:
		for p: Player in t.players:
			names[p.id] = p.name
	print("games %d (each team %d)" % [g, g * 2 / 10])
	var pcts: Array[float] = []
	for i: int in 10:
		var pct := float(wins[i]) / maxi(wins[i] + losses[i], 1)
		pcts.append(pct)
	pcts.sort()
	var mean := 0.0
	for p: float in pcts: mean += p
	mean /= pcts.size()
	var sd := 0.0
	for p: float in pcts: sd += (p - mean) * (p - mean)
	sd = sqrt(sd / pcts.size())
	print("team win%%: min %.3f max %.3f sd %.3f   (KBO 2025: .336 to .603)" % [pcts[0], pcts[-1], sd])
	var qualified: Array[String] = []
	for id: String in bat:
		if bat[id].pa >= 446: qualified.append(id)
	var top := func(arr: Array[String], key: Callable, n: int) -> String:
		var a := arr.duplicate()
		a.sort_custom(func(x: String, y: String) -> bool: return key.call(x) > key.call(y))
		var parts: Array[String] = []
		for k: int in mini(n, a.size()):
			parts.append("%s %s" % [names.get(a[k], a[k]), str(snappedf(key.call(a[k]), 0.001))])
		return ", ".join(parts)
	print("qualified hitters: %d" % qualified.size())
	print("AVG: " + top.call(qualified, func(id: String) -> float: return bat[id].average(), 5) + "   (KBO 2025 leader .337)")
	print("OPS: " + top.call(qualified, func(id: String) -> float: return bat[id].ops(), 5) + "   (KBO 2025 leader 1.025)")
	var all_hitters: Array[String] = bat.keys()
	print("HR: " + top.call(all_hitters, func(id: String) -> float: return bat[id].home_runs, 5) + "   (KBO 2025 leader 50)")
	print("SB: " + top.call(all_hitters, func(id: String) -> float: return bat[id].stolen_bases, 5))
	var worst_avg: Array[String] = qualified.duplicate()
	worst_avg.sort_custom(func(x: String, y: String) -> bool: return bat[x].average() < bat[y].average())
	print("lowest qualified AVG: %.3f" % bat[worst_avg[0]].average())
	var q_p: Array[String] = []
	for id: String in pit:
		if pit[id].outs >= 144 * 3: q_p.append(id)
	print("qualified pitchers: %d" % q_p.size())
	print("ERA (lowest): " + top.call(q_p, func(id: String) -> float: return -pit[id].era(), 5).replace(" -", " ") + "   (KBO 2025 leader 1.89)")
	var all_p: Array[String] = pit.keys()
	print("W: " + top.call(all_p, func(id: String) -> float: return pit[id].wins, 5))
	print("SV: " + top.call(all_p, func(id: String) -> float: return pit[id].saves, 5) + "   (KBO 2025 leaders ~35-40)")
	print("HLD: " + top.call(all_p, func(id: String) -> float: return pit[id].holds, 5) + "   (KBO 2025 leaders ~30-35)")
	print("SO: " + top.call(all_p, func(id: String) -> float: return pit[id].strikeouts, 5) + "   (KBO 2025 leader ~245)")
	print("IP top: " + top.call(all_p, func(id: String) -> float: return pit[id].outs / 3.0, 5) + "   (KBO top starters ~170-190)")
	quit()
