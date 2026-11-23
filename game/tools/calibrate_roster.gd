extends SceneTree
## Brings a real season's roster pack level with that season (docs/06 4.3 step 3).
##
## The league: the builder's ratings are relative to the season's averages, but the engine adds
## its own (calibration multipliers, platoon, fatigue, who the managers play), so a league of
## them can strike out or homer a little more or less than the real one did. This plays the
## season, compares the league's strikeouts, walks and home runs per plate appearance with the
## real totals, and moves every hitter's contact, eye and power by the same amount to close the
## gap; a few rounds.
##
## The clubs: a rating pulled toward the average for its small sample makes a poor club's many
## part-timers too good and a strong club's too plain, and what a club did beyond its men's
## strikeouts, walks and home runs (hits on balls in play, its fielding, its bench) is not in
## the ratings at all — so the clubs come out closer together than they were. This compares each
## club's runs scored and allowed (relative to the league's) with the real ones — the runs of
## the records, moved so that they give the record the club really had (Pythagorean) — and
## moves all its hitters, and all its pitchers, by the same amount; a few rounds, the league's
## level kept. Then the pack is written back, and what was moved beside it (calibration.json).
##
##   godot --headless --path game --script res://tools/calibrate_roster.gd -- --season kbo-2025 --raw ../content-local/raw/kbo-2025 [--rounds 3] [--seasons 2] [--club-rounds 4] [--club-seasons 3]

const BuildRoster := preload("res://tools/build_roster.gd")
const RosterRoundtrip := preload("res://tools/roster_roundtrip.gd")

## Runs to wins: W/L = (RS/RA)^1.83.
const PYTHAGOREAN := 1.83
## Rating points for a unit of log runs to begin with (measured again after each round), and
## the most a club is moved.
const GAIN := 30.0
const GAIN_RANGE := Vector2(10.0, 70.0)
const DAMPING := 0.8
const MOST := 14.0

var env: LeagueEnv
var catalog: Dictionary[StringName, PitchType]
var ovr: Overall


func _init() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	# --pack-file <season.json>: a season not in the game's list (a roster-only one).
	var pack := SeasonPack.load_file(ProjectSettings.globalize_path("res://").path_join(str(args["pack-file"])).simplify_path()) if args.has("pack-file") else SeasonPack.by_id(str(args.get("season", "kbo-2025")))
	if pack == null:
		print("calibrate: no such season pack")
		quit(1)
		return
	var raw := ProjectSettings.globalize_path("res://").path_join(str(args.get("raw", "../content-local/raw/kbo-2025"))).simplify_path()
	var rounds := int(str(args.get("rounds", "3")))
	var seasons := int(str(args.get("seasons", "2")))
	var club_rounds := int(str(args.get("club-rounds", "4")))
	var club_seasons := int(str(args.get("club-seasons", "3")))
	var real := {"pa": 0.0, "so": 0.0, "bb": 0.0, "hr": 0.0}
	for row: Dictionary in BuildRoster.read_csv(raw.path_join("batting.csv")):
		for k: String in real:
			real[k] = float(real[k]) + float(row[k])
	var target := {"K": real["so"] / real["pa"], "BB": real["bb"] / real["pa"], "HR": real["hr"] / real["pa"]}
	env = LeagueEnvIO.load_default()
	catalog = PitchCatalogIO.load_default()
	ovr = LeagueEnvIO.load_overall()
	var clubs := pack.clubs()
	var offsets := {"contact": 0.0, "eye": 0.0, "power": 0.0}
	var seed_at := 900
	for r: int in rounds:
		var got := _league(clubs, pack, seasons, seed_at)
		seed_at += seasons
		print("calibrate: league round %d  K %.3f (real %.3f)  BB %.3f (%.3f)  HR %.4f (%.4f)" % [r, got["K"], target["K"], got["BB"], target["BB"], got["HR"], target["HR"]])
		_move_league(clubs, got, target, offsets)
	# The clubs.
	var goal := _club_targets(BuildRoster.read_csv(raw.path_join("teams.csv")))
	var shift_o: Dictionary[String, float] = {}
	var shift_p: Dictionary[String, float] = {}
	var gain_o := GAIN
	var gain_p := GAIN
	var before: Dictionary = {}
	var last_o: Dictionary[String, float] = {}
	var last_p: Dictionary[String, float] = {}
	if not goal.is_empty():
		for r: int in club_rounds:
			var got := _league(clubs, pack, club_seasons, seed_at)
			seed_at += club_seasons
			var runs: Dictionary = got["clubs"]
			if not before.is_empty():
				# What a point was worth this time.
				gain_o = _gain(last_o, before, runs, "rs", 1.0, gain_o)
				gain_p = _gain(last_p, before, runs, "ra", -1.0, gain_p)
			var worst := 0.0
			var mean_o := 0.0
			var mean_p := 0.0
			for t: Team in clubs:
				var d_o := DAMPING * gain_o * (float(goal[t.id]["rs"]) - float(runs[t.id]["rs"]))
				var d_p := DAMPING * gain_p * (float(runs[t.id]["ra"]) - float(goal[t.id]["ra"]))
				last_o[t.id] = d_o
				last_p[t.id] = d_p
				mean_o += d_o / clubs.size()
				mean_p += d_p / clubs.size()
				worst = maxf(worst, maxf(absf(float(goal[t.id]["rs"]) - float(runs[t.id]["rs"])), absf(float(goal[t.id]["ra"]) - float(runs[t.id]["ra"]))))
			for t: Team in clubs:
				# The league's level stays: the clubs move about their mean.
				last_o[t.id] = clampf(float(shift_o.get(t.id, 0.0)) + last_o[t.id] - mean_o, -MOST, MOST) - float(shift_o.get(t.id, 0.0))
				last_p[t.id] = clampf(float(shift_p.get(t.id, 0.0)) + last_p[t.id] - mean_p, -MOST, MOST) - float(shift_p.get(t.id, 0.0))
				shift_o[t.id] = float(shift_o.get(t.id, 0.0)) + last_o[t.id]
				shift_p[t.id] = float(shift_p.get(t.id, 0.0)) + last_p[t.id]
				_move_club(t, last_o[t.id], last_p[t.id])
			before = runs
			print("calibrate: club round %d  furthest off %.1f%% in runs  (a point worth %.1f%% / %.1f%%)" % [r, 100.0 * worst, 100.0 / gain_o, 100.0 / gain_p])
		# The league once more: the clubs' moves may have nudged its totals.
		var again := _league(clubs, pack, seasons, seed_at)
		seed_at += seasons
		_move_league(clubs, again, target, offsets)
	var last := _league(clubs, pack, maxi(seasons, club_seasons), seed_at)
	print("calibrate: final  K %.3f (real %.3f)  BB %.3f (%.3f)  HR %.4f (%.4f)" % [last["K"], target["K"], last["BB"], target["BB"], last["HR"], target["HR"]])
	var real_pct: Array = []
	var played_pct: Array = []
	for row: Array in pack.standings:
		var id := str(row[0])
		var w := float(row[1])
		var l := float(row[2])
		real_pct.append(w / maxf(w + l, 1.0))
		played_pct.append(float(last["clubs"][id]["pct"]))
		print("calibrate:   %-8s real %.3f played %.3f   hitters %+.1f pitchers %+.1f" % [id, real_pct[-1], played_pct[-1], float(shift_o.get(id, 0.0)), float(shift_p.get(id, 0.0))])
	print("calibrate: clubs' winning percentage r = %.3f" % RosterRoundtrip.correlation(real_pct, played_pct))
	var err := RosterIO.save_pack(pack.roster, pack.id, _pack_name(pack), pack.year, clubs)
	var note := FileAccess.open(raw.path_join("calibration.json"), FileAccess.WRITE)
	if note != null:
		note.store_string(JSON.stringify({"league": offsets, "hitters": shift_o, "pitchers": shift_p}, "  "))
		note.close()
	print("calibrate: wrote %s (%s), league offsets %s" % [pack.roster, error_string(err), offsets])
	quit()


## The roster pack's own name (what the quick match's list shows), kept.
func _pack_name(pack: SeasonPack) -> String:
	var head := JsonIO.read_object(pack.roster)
	return str(head.get("name", pack.title))


## rate = μ·exp(k·Δ/15): the change that closes the league's gap, for each of the three.
func _move_league(clubs: Array[Team], got: Dictionary, target: Dictionary, offsets: Dictionary) -> void:
	var d_contact := 15.0 * log(float(target["K"]) / float(got["K"])) / float(env.batter_k["K"]["contact"])
	var d_eye := 15.0 * log(float(target["BB"]) / float(got["BB"])) / float(env.batter_k["BB"]["eye"])
	var d_power := 15.0 * log(float(target["HR"]) / float(got["HR"])) / float(env.batter_k["HR"]["power"])
	offsets["contact"] = float(offsets["contact"]) + d_contact
	offsets["eye"] = float(offsets["eye"]) + d_eye
	offsets["power"] = float(offsets["power"]) + d_power
	for t: Team in clubs:
		for p: Player in t.players:
			if not p.is_pitcher():
				_move_hitter(p, d_contact, d_eye, d_power)


func _move_hitter(p: Player, contact: float, eye: float, power: float) -> void:
	p.batting.contact_r = clampf(p.batting.contact_r + contact, RosterBuilder.LOW, RosterBuilder.HIGH)
	p.batting.contact_l = clampf(p.batting.contact_l + contact, RosterBuilder.LOW, RosterBuilder.HIGH)
	p.batting.eye = clampf(p.batting.eye + eye, RosterBuilder.LOW, RosterBuilder.HIGH)
	p.batting.power_r = clampf(p.batting.power_r + power, RosterBuilder.LOW, RosterBuilder.HIGH)
	p.batting.power_l = clampf(p.batting.power_l + power, RosterBuilder.LOW, RosterBuilder.HIGH)


## All a club's hitters, and all its pitchers, by the same amounts.
func _move_club(t: Team, hitters: float, pitchers: float) -> void:
	for p: Player in t.players:
		if p.is_pitcher():
			RosterBuilder.set_stuff(p, clampf(p.pitching.stuff(catalog) + pitchers, RosterBuilder.LOW, RosterBuilder.HIGH), catalog)
			p.pitching.control = clampf(p.pitching.control + pitchers, RosterBuilder.LOW, RosterBuilder.HIGH)
		else:
			_move_hitter(p, hitters, hitters, hitters)


## Each club's log runs scored and allowed relative to the league's mean, as they should be:
## the records' runs, moved (half on each side) to give the club's real record.
func _club_targets(teams: Array) -> Dictionary:
	var out: Dictionary = {}
	var mean_rs := 0.0
	var mean_ra := 0.0
	for row: Dictionary in teams:
		var rs := float(row.get("rs", 0))
		var ra := float(row.get("ra", 0))
		var w := float(row.get("wins", 0))
		var l := float(row.get("losses", 0))
		if rs <= 0.0 or ra <= 0.0 or w <= 0.0 or l <= 0.0:
			return {}
		var off := log(w / l) / PYTHAGOREAN - log(rs / ra)
		out[str(row["id"])] = {"rs": log(rs) + off * 0.5, "ra": log(ra) - off * 0.5}
		mean_rs += float(out[str(row["id"])]["rs"]) / teams.size()
		mean_ra += float(out[str(row["id"])]["ra"]) / teams.size()
	for id: String in out:
		out[id]["rs"] = float(out[id]["rs"]) - mean_rs
		out[id]["ra"] = float(out[id]["ra"]) - mean_ra
	return out


## Rating points for a unit of log runs, from what the last moves did (least squares through
## the origin over the clubs); kept within reason, and as it was when the moves were too small
## to tell.
func _gain(moves: Dictionary[String, float], before: Dictionary, after: Dictionary, key: String, direction: float, was: float) -> float:
	var num := 0.0
	var den := 0.0
	for id: String in moves:
		var change := direction * (float(after[id][key]) - float(before[id][key]))
		num += moves[id] * change
		den += moves[id] * moves[id]
	if den < 20.0 or num <= 0.0:
		return was
	return clampf(den / num, GAIN_RANGE.x, GAIN_RANGE.y)


## A few seasons played: the league's strikeouts, walks and home runs per plate appearance,
## and each club's log runs scored and allowed (relative to the mean) and winning percentage.
func _league(clubs: Array[Team], pack: SeasonPack, seasons: int, seed_value: int) -> Dictionary:
	var tot := {"pa": 0.0, "so": 0.0, "bb": 0.0, "hr": 0.0}
	var runs: Dictionary = {}
	for t: Team in clubs:
		runs[t.id] = {"rs": 0.0, "ra": 0.0, "w": 0.0, "l": 0.0}
	for i: int in seasons:
		var copies: Array[Team] = []
		for t: Team in clubs:
			var c := Team.new()
			c.id = t.id
			c.name = t.name
			c.short_name = t.short_name
			for p: Player in t.players:
				var q := RosterIO.player_from(RosterIO.player_to(p, true))
				q.potential = 0.0
				c.players.append(q)
			c.registered = t.registered.duplicate()
			copies.append(c)
		var s := Season.create(copies, copies.size(), pack.games, seed_value + i, pack.rule_set(), env, catalog, ovr, null)
		# That year's parks (and nothing else of the season's: it is only its regular season).
		s.history = pack
		for t: Team in copies:
			RosterMoves.trim(s, t, s.rules.registered_roster)
		var guard := 0
		while s.phase == Season.Phase.REGULAR and guard < 400:
			s.play_day(true)
			s.advance()
			guard += 1
		for id: String in s.book.batting:
			var line: BattingLine = s.book.batting[id]
			tot["pa"] = float(tot["pa"]) + line.pa
			tot["so"] = float(tot["so"]) + line.strikeouts
			tot["bb"] = float(tot["bb"]) + line.walks + line.intentional_walks
			tot["hr"] = float(tot["hr"]) + line.home_runs
		for row: StandingsRow in s.standings[0].ranked():
			runs[row.team_id]["rs"] = float(runs[row.team_id]["rs"]) + row.runs_for
			runs[row.team_id]["ra"] = float(runs[row.team_id]["ra"]) + row.runs_against
			runs[row.team_id]["w"] = float(runs[row.team_id]["w"]) + row.wins
			runs[row.team_id]["l"] = float(runs[row.team_id]["l"]) + row.losses
	var mean_rs := 0.0
	var mean_ra := 0.0
	for id: String in runs:
		runs[id]["pct"] = float(runs[id]["w"]) / maxf(float(runs[id]["w"]) + float(runs[id]["l"]), 1.0)
		runs[id]["rs"] = log(maxf(float(runs[id]["rs"]), 1.0))
		runs[id]["ra"] = log(maxf(float(runs[id]["ra"]), 1.0))
		mean_rs += float(runs[id]["rs"]) / runs.size()
		mean_ra += float(runs[id]["ra"]) / runs.size()
	for id: String in runs:
		runs[id]["rs"] = float(runs[id]["rs"]) - mean_rs
		runs[id]["ra"] = float(runs[id]["ra"]) - mean_ra
	return {"K": tot["so"] / tot["pa"], "BB": tot["bb"] / tot["pa"], "HR": tot["hr"] / tot["pa"], "clubs": runs}
