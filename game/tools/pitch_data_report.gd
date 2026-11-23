extends SceneTree
## How the game's numbers follow the pitch table: plays many games between a
## season pack's clubs with the stat resolver and prints the league's OPS against the same and
## the other hand, and the batters with the biggest and smallest own splits as the game plays
## them; then the computer pitchers' fastball share by the count (AiPitcher with each man's own
## mix), weighted as the men pitch. Compare with tools/kbo/pitch_data_facts.py on the data.
##
##   godot --headless --path game --script res://tools/pitch_data_report.gd -- --pack <pack.json> [--games 600]

var _pack := ""
var _games := 600


func _initialize() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	_pack = str(args.get("pack", ""))
	_games = int(str(args.get("games", "600")))
	if _pack == "":
		print("pitch_data_report: --pack <file>")
		quit(1)
		return
	var clubs := RosterIO.load_pack(_pack)
	_splits(clubs)
	_counts(clubs)
	quit(0)


func _splits(clubs: Array[Team]) -> void:
	var env := LeagueEnvIO.load_default()
	var catalog := PitchCatalogIO.load_default()
	var ovr := LeagueEnvIO.load_overall()
	var rules := RuleSet.kbo_2026()
	var rng := Rng.new(7)
	# Per batter and side ("same" or "other"): [pa, ab, hits, total bases, on base, sac flies].
	var lines: Dictionary = {}
	var by: Dictionary[String, Player] = {}
	for t: Team in clubs:
		for p: Player in t.players:
			by[p.id] = p
	for g: int in _games:
		var a := clubs[rng.next_int(clubs.size())]
		var h := clubs[rng.next_int(clubs.size())]
		if a == h:
			continue
		var sim := GameSim.create(a, h, rules, env, catalog, ovr, rng.fork(g))
		var guard := 0
		while not sim.state.over and guard < GameSim.MAX_EVENTS:
			guard += 1
			var batter: Player = by.get(sim.state.batter_id())
			var pitcher: Player = by.get(sim.state.pitcher_id())
			var e := sim.resolver.next_event(sim.state)
			var out := GameFlow.apply(sim.state, e)
			sim.scorer.record(sim.state, e, out)
			sim.manager.note_change(sim.state, e)
			if e.kind != GameEvent.Kind.PLATE_APPEARANCE or batter == null or pitcher == null:
				continue
			var side := "same" if batter.batting_side(pitcher.throws) == pitcher.throws else "other"
			if not lines.has(batter.id):
				lines[batter.id] = {"same": [0, 0, 0, 0, 0, 0], "other": [0, 0, 0, 0, 0, 0]}
			var l: Array = lines[batter.id][side]
			l[0] += 1
			match e.result:
				PaResult.Kind.SINGLE, PaResult.Kind.DOUBLE, PaResult.Kind.TRIPLE, PaResult.Kind.HOME_RUN:
					l[1] += 1
					l[2] += 1
					l[3] += {PaResult.Kind.SINGLE: 1, PaResult.Kind.DOUBLE: 2, PaResult.Kind.TRIPLE: 3, PaResult.Kind.HOME_RUN: 4}[e.result]
				PaResult.Kind.WALK, PaResult.Kind.INTENTIONAL_WALK, PaResult.Kind.HIT_BY_PITCH:
					l[4] += 1
				PaResult.Kind.SAC_FLY:
					l[5] += 1
				PaResult.Kind.SAC_BUNT:
					pass
				_:
					l[1] += 1
	var total := {"same": [0, 0, 0, 0, 0, 0], "other": [0, 0, 0, 0, 0, 0]}
	var own: Array = []
	for id: String in lines:
		for side: String in ["same", "other"]:
			for i: int in 6:
				total[side][i] += lines[id][side][i]
		var p: Player = by[id]
		if p.bats == &"S":
			continue
		var gap := (p.batting.contact_r - p.batting.contact_l) * (1.0 if p.bats == &"L" else -1.0)
		own.append([gap, id])
	print("pitch_data_report: %d games" % _games)
	for side: String in ["same", "other"]:
		print("pitch_data_report: OPS against the %s hand %.3f (%d PA)" % [side, _ops(total[side]), total[side][0]])
	# The quarter with the biggest own split in the ratings against the quarter with the
	# smallest: their splits as played.
	own.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
	var quarter := own.size() / 4
	for part: Array in [["biggest", own.slice(0, quarter)], ["smallest", own.slice(own.size() - quarter)]]:
		var same := [0, 0, 0, 0, 0, 0]
		var other := [0, 0, 0, 0, 0, 0]
		for entry: Array in part[1]:
			for i: int in 6:
				same[i] += lines[entry[1]]["same"][i]
				other[i] += lines[entry[1]]["other"][i]
		print("pitch_data_report: %s own splits: other %.3f − same %.3f = %.3f" % [part[0], _ops(other), _ops(same), _ops(other) - _ops(same)])


static func _ops(l: Array) -> float:
	var obp := float(l[2] + l[4]) / maxf(l[1] + l[4] + l[5], 1.0)
	var slg := float(l[3]) / maxf(l[1], 1.0)
	return obp + slg


func _counts(clubs: Array[Team]) -> void:
	var catalog := PitchCatalogIO.load_default()
	var zone := StrikeZone.new()
	var rng := Rng.new(11)
	var counts := {"even": [[0, 0], [1, 1], [2, 2]], "ahead": [[0, 1], [0, 2], [1, 2]], "behind": [[1, 0], [2, 0], [3, 0], [2, 1], [3, 1], [3, 2]]}
	for bucket: String in ["even", "ahead", "behind"]:
		var fast := 0.0
		var all := 0.0
		for t: Team in clubs:
			for p: Player in t.players:
				if not p.is_pitcher():
					continue
				var options := AiPitcher.options_for(p, catalog)
				if options.is_empty():
					continue
				for c: Array in counts[bucket]:
					for i: int in 20:
						var d := AiPitcher.decide(options, zone, int(c[0]), int(c[1]), false, PackedInt32Array(), null, rng)
						all += 1.0
						if d.type.family == &"fastball":
							fast += 1.0
		print("pitch_data_report: fastballs when %s: %.1f%%" % [bucket, 100.0 * fast / maxf(all, 1.0)])
