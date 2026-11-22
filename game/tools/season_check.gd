extends SceneTree

const BuildRoster := preload("res://tools/build_roster.gd")
const RosterRoundtrip := preload("res://tools/roster_roundtrip.gd")
## Plays a real season's pack again and compares it with what really happened (docs/07 4.3,
## docs/13 S17): the clubs of a season pack (SeasonPack) play its season several times with
## the statistical resolver; each qualified hitter's average OPS is set against his real OPS
## (from the builder's batting table), each club's winning percentage against the real table,
## and the league's totals against the real ones.
##
##   godot --headless --path game --script res://tools/season_check.gd -- --season kbo-2025 --raw ../content-local/raw/kbo-2025 [--replays 6] [--roster ../content-local/rosters/variant.json]


func _init() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	# --pack-file <season.json>: a season not in the game's list (a roster-only one).
	var pack := SeasonPack.load_file(ProjectSettings.globalize_path("res://").path_join(str(args["pack-file"])).simplify_path()) if args.has("pack-file") else SeasonPack.by_id(str(args.get("season", "kbo-2025")))
	if pack == null:
		print("season_check: no such season pack")
		quit(1)
		return
	var raw := ProjectSettings.globalize_path("res://").path_join(str(args.get("raw", "../content-local/raw/kbo-2025"))).simplify_path()
	var replays := int(str(args.get("replays", "6")))
	# --roster <pack.json>: another roster pack for the same season (a variant of the builder).
	if args.has("roster"):
		var path := str(args["roster"])
		pack.roster = path if path.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(path).simplify_path()
	if pack.clubs().is_empty():
		print("season_check: no clubs in %s" % pack.roster)
		quit(1)
		return
	var real := BuildRoster.read_csv(raw.path_join("batting.csv"))
	var real_ops: Dictionary[String, float] = {}
	var real_pa: Dictionary[String, int] = {}
	var tot := {"pa": 0.0, "ab": 0.0, "h": 0.0, "hr": 0.0, "bb": 0.0, "so": 0.0}
	for row: Dictionary in real:
		var pa := float(row["pa"])
		var ab := maxf(float(row["ab"]), 1.0)
		var h := float(row["h"])
		var tb := h + float(row["2b"]) + 2.0 * float(row["3b"]) + 3.0 * float(row["hr"])
		real_ops[str(row["id"])] = (h + float(row["bb"]) + float(row["hbp"])) / maxf(pa, 1.0) + tb / ab
		real_pa[str(row["id"])] = int(pa)
		for k: String in ["pa", "ab", "h", "hr", "bb", "so"]:
			tot[k] = float(tot[k]) + float(row[k])
	print("season_check: real %s  AVG %.3f  HR/PA %.4f  BB/PA %.3f  K/PA %.3f" % [pack.id, tot["h"] / tot["ab"], tot["hr"] / tot["pa"], tot["bb"] / tot["pa"], tot["so"] / tot["pa"]])
	var ops_sum: Dictionary[String, float] = {}
	var ops_n: Dictionary[String, int] = {}
	var pa_sum: Dictionary[String, float] = {}
	var on_sum: Dictionary[String, float] = {}
	var tb_sum: Dictionary[String, float] = {}
	var ab_sum: Dictionary[String, float] = {}
	var wins: Dictionary[String, float] = {}
	var env := LeagueEnvIO.load_default()
	var catalog := PitchCatalogIO.load_default()
	var ovr := LeagueEnvIO.load_overall()
	for i: int in replays:
		var clubs := pack.clubs()
		for t: Team in clubs:
			for p: Player in t.players:
				p.potential = 0.0
		var s := Season.create(clubs, clubs.size(), pack.games, 500 + i, pack.rule_set(), env, catalog, ovr, null)
		s.history = pack
		for t: Team in clubs:
			for p: Player in t.players:
				p.potential = 0.0
		var guard := 0
		while s.phase == Season.Phase.REGULAR and guard < 400:
			s.play_day(true)
			s.advance()
			guard += 1
		var sim := {"pa": 0.0, "ab": 0.0, "h": 0.0, "hr": 0.0, "bb": 0.0, "so": 0.0, "r": 0.0, "er": 0.0, "outs": 0.0}
		for id: String in s.book.batting:
			var line: BattingLine = s.book.batting[id]
			if line.pa > 0:
				ops_sum[id] = float(ops_sum.get(id, 0.0)) + line.ops()
				ops_n[id] = int(ops_n.get(id, 0)) + 1
				# Pooled over the replays (a few lucky plate appearances do not count for much).
				pa_sum[id] = float(pa_sum.get(id, 0.0)) + line.pa
				on_sum[id] = float(on_sum.get(id, 0.0)) + line.hits + line.walks + line.intentional_walks + line.hit_by_pitch
				tb_sum[id] = float(tb_sum.get(id, 0.0)) + line.total_bases()
				ab_sum[id] = float(ab_sum.get(id, 0.0)) + line.ab
			sim["pa"] = float(sim["pa"]) + line.pa
			sim["ab"] = float(sim["ab"]) + line.ab
			sim["h"] = float(sim["h"]) + line.hits
			sim["hr"] = float(sim["hr"]) + line.home_runs
			sim["bb"] = float(sim["bb"]) + line.walks + line.intentional_walks
			sim["so"] = float(sim["so"]) + line.strikeouts
		for id: String in s.book.pitching:
			var l: PitchingLine = s.book.pitching[id]
			sim["er"] = float(sim["er"]) + l.earned_runs
			sim["outs"] = float(sim["outs"]) + l.outs
		print("season_check: replay %d  AVG %.3f  HR/PA %.4f  BB/PA %.3f  K/PA %.3f  ERA %.2f" % [i + 1, sim["h"] / sim["ab"], sim["hr"] / sim["pa"], sim["bb"] / sim["pa"], sim["so"] / sim["pa"], sim["er"] * 27.0 / maxf(sim["outs"], 1.0)])
		for r: StandingsRow in s.standings[0].ranked():
			wins[r.team_id] = float(wins.get(r.team_id, 0.0)) + r.pct() / replays
	var a: Array = []
	var b: Array = []
	var worst: Array = []
	for id: String in real_ops:
		# Regulars in both: qualified in the real season, 300 plate appearances a season here.
		if real_pa[id] >= 446 and pa_sum.has(id) and pa_sum[id] / replays >= 300.0:
			var mean := on_sum[id] / pa_sum[id] + tb_sum[id] / maxf(ab_sum[id], 1.0)
			a.append(real_ops[id])
			b.append(mean)
			worst.append([absf(mean - real_ops[id]), id, real_ops[id], mean])
	print("season_check: qualified hitters' OPS r = %.3f (n %d; target 0.85)" % [RosterRoundtrip.correlation(a, b), a.size()])
	worst.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
	for w: Array in worst.slice(0, 5):
		print("season_check:   furthest off %s real %.3f played %.3f" % [w[1], w[2], w[3]])
	var aw: Array = []
	var pw: Array = []
	for row: Array in pack.standings:
		var w := float(row[1])
		var l := float(row[2])
		aw.append(w / maxf(w + l, 1.0))
		pw.append(float(wins.get(str(row[0]), 0.0)))
		print("season_check:   %-8s real %.3f played %.3f" % [str(row[0]), aw[aw.size() - 1], pw[pw.size() - 1]])
	print("season_check: clubs' winning percentage r = %.3f (target 0.7)" % RosterRoundtrip.correlation(aw, pw))
	quit()
