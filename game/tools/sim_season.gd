extends SceneTree
## Plays a regular season of the roster pack's league (three divisions of ten) with the stat
## resolver, as the manager league does it (Season: schedule, rotations, bullpen rest, days
## off), and prints for one division the spread of team records and the league leaders next to
## the S7 targets and the KBO's 2025 figures (docs/13 S7).
##
##   godot --headless --path game --script res://tools/sim_season.gd -- --division 2
##
## Options: --pack <res://data/rosters/x.json>  --division <1..3, default 2>  --seed <n>
##          --games <36|72|144, default 144>  --all (every division's summary)


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var division := int(str(args.get("division", "2")))
	var pack := str(args.get("pack", "res://data/rosters/fiction-2026.json"))
	var games := int(str(args.get("games", "144")))
	var seed_value := int(str(args.get("seed", "99")))
	var teams := RosterIO.load_pack(pack)
	var season := Season.create(teams, 10, games, seed_value, RuleSet.kbo_2026(), LeagueEnvIO.load_default(), PitchCatalogIO.load_default(), LeagueEnvIO.load_overall())
	var started := Time.get_ticks_msec()
	season.play_to_end()
	print("%d games per club, %d days, %.1f s" % [games, season.total_days(), (Time.get_ticks_msec() - started) / 1000.0])
	if args.has("all"):
		for d: int in season.divisions.size():
			_report(season, d, true)
	_report(season, division - 1, false)
	quit()


func _report(season: Season, d: int, brief: bool) -> void:
	var ids := season.divisions[d]
	var names: Dictionary[String, String] = {}
	var on_division: Dictionary[String, bool] = {}
	for id: String in ids:
		for p: Player in season.teams[id].players:
			names[p.id] = p.name + ("*" if p.is_foreign() else "")
			on_division[p.id] = true
	var pcts: Array[float] = []
	var ties := 0
	for row: StandingsRow in season.standings[d].ranked():
		pcts.append(row.pct())
		ties += row.ties
	var mean := 0.0
	for p: float in pcts:
		mean += p
	mean /= pcts.size()
	var sd := 0.0
	for p: float in pcts:
		sd += (p - mean) * (p - mean)
	sd = sqrt(sd / pcts.size())
	print("\n== division %d: team win%% %.3f to %.3f, sd %.3f   (target .060-.085; KBO 2025 .336-.603), ties %d" % [d + 1, pcts[-1], pcts[0], sd, ties / 2])
	if brief:
		print("   " + _key_figures(season, ids))
		return
	for row: StandingsRow in season.standings[d].ranked():
		print("  %-14s %3d-%3d-%2d  %s  GB %4.1f  RS %3d RA %3d" % [season.teams[row.team_id].name, row.wins, row.losses, row.ties, row.pct_text(), season.standings[d].games_behind(row.team_id), row.runs_for, row.runs_against])
	var bat: Dictionary[String, BattingLine] = {}
	var pit: Dictionary[String, PitchingLine] = {}
	for id: String in season.book.batting:
		if on_division.has(id):
			bat[id] = season.book.batting[id]
	for id: String in season.book.pitching:
		if on_division.has(id):
			pit[id] = season.book.pitching[id]
	var qualified: Array[String] = []
	for id: String in bat:
		if bat[id].pa >= season.qualifying_pa():
			qualified.append(id)
	var top := func(arr: Array[String], key: Callable, n: int) -> String:
		var a := arr.duplicate()
		a.sort_custom(func(x: String, y: String) -> bool: return key.call(x) > key.call(y))
		var parts: Array[String] = []
		for k: int in mini(n, a.size()):
			parts.append("%s %s" % [names.get(a[k], a[k]), str(snappedf(key.call(a[k]), 0.001))])
		return ", ".join(parts)
	var all_hitters: Array[String] = bat.keys()
	var all_p: Array[String] = pit.keys()
	print("qualified hitters (%d PA): %d   (* foreign)" % [season.qualifying_pa(), qualified.size()])
	print("AVG: " + top.call(qualified, func(id: String) -> float: return bat[id].average(), 5) + "   (KBO 2025 leader .337)")
	print("OPS: " + top.call(qualified, func(id: String) -> float: return bat[id].ops(), 5) + "   (KBO 2025 leader 1.025)")
	print("HR: " + top.call(all_hitters, func(id: String) -> float: return bat[id].home_runs, 5) + "   (target 35-50; KBO 2025 leader 50)")
	print("RBI: " + top.call(all_hitters, func(id: String) -> float: return bat[id].rbi, 5))
	print("SB: " + top.call(all_hitters, func(id: String) -> float: return bat[id].stolen_bases, 5))
	if not qualified.is_empty():
		var worst: Array[String] = qualified.duplicate()
		worst.sort_custom(func(x: String, y: String) -> bool: return bat[x].average() < bat[y].average())
		print("lowest qualified AVG: %s %.3f   (target .200 or more)" % [names.get(worst[0], worst[0]), bat[worst[0]].average()])
	var q_p: Array[String] = []
	for id: String in pit:
		if pit[id].outs >= season.qualifying_outs():
			q_p.append(id)
	print("qualified pitchers: %d" % q_p.size())
	print("ERA (lowest): " + top.call(q_p, func(id: String) -> float: return -pit[id].era(), 5).replace(" -", " ") + "   (KBO 2025 leader 1.89)")
	print("W: " + top.call(all_p, func(id: String) -> float: return pit[id].wins, 5))
	print("SV: " + top.call(all_p, func(id: String) -> float: return pit[id].saves, 5) + "   (target 30-42)")
	print("HLD: " + top.call(all_p, func(id: String) -> float: return pit[id].holds, 5) + "   (target 25-38)")
	print("SO: " + top.call(all_p, func(id: String) -> float: return pit[id].strikeouts, 5) + "   (KBO 2025 leader ~245)")
	print("IP top: " + top.call(all_p, func(id: String) -> float: return pit[id].outs / 3.0, 5) + "   (KBO top starters ~170-190)")
	print("G (pitchers): " + top.call(all_p, func(id: String) -> float: return pit[id].games, 5) + "   (KBO 2025 most ~75)")


## HR, SV, HLD leaders, most games pitched and the lowest qualified average, on one line.
func _key_figures(season: Season, ids: PackedStringArray) -> String:
	var mine: Dictionary[String, bool] = {}
	for id: String in ids:
		for p: Player in season.teams[id].players:
			mine[p.id] = true
	var hr := 0
	var thirty := 0
	var low := 1.0
	for id: String in season.book.batting:
		if not mine.has(id):
			continue
		var b: BattingLine = season.book.batting[id]
		hr = maxi(hr, b.home_runs)
		if b.home_runs >= 30:
			thirty += 1
		if b.pa >= season.qualifying_pa():
			low = minf(low, b.average())
	var sv := 0
	var hld := 0
	var g := 0
	for id: String in season.book.pitching:
		if not mine.has(id):
			continue
		var p: PitchingLine = season.book.pitching[id]
		sv = maxi(sv, p.saves)
		hld = maxi(hld, p.holds)
		g = maxi(g, p.games)
	return "HR %d (35-50) 30+:%d  SV %d (30-42)  HLD %d (25-38)  lowAVG %.3f (.200+)  G %d (~75)" % [hr, thirty, sv, hld, low, g]
