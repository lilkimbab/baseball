class_name RosterBuilder
extends RefCounted
## Real records into ratings (docs/07 section 4.3, docs/09 section 5, docs/13 S17): ratings are
## not made up; they are worked out from what each man did, by running the match engine's own
## formula backwards — the statistical resolver draws an outcome at the league's rate times
## exp(k × (rating − 50) / 15) — so that a league made from a season plays that season again.
## A small sample is pulled toward an average first (x_reg = (N x + k μ) / (N + k)), the
## result kept within 20..99 — the average of men who played about as much as he did, not the
## league's: a man with fifty plate appearances is not an average hitter short of chances, he
## is a reserve, and reserves strike out more and homer less (pulled to the league's average
## the weak clubs' many part-timers came out too good, and the clubs too close together). What the records cannot tell (how a man looks, his fielding
## beyond his positions, his pitches' details) starts from the league generator's, seeded by
## his id, and is then set from the records where they speak.
##
## Input: rows (Dictionaries) as read from CSV files (tools/build_roster.gd; columns in
## docs/13 S17). Output: teams for RosterIO.save_pack.

## Sample sizes at which each rate is half the man's and half the league's (docs/07 4.3).
const REGRESS := {"K": 100.0, "BB": 170.0, "HR": 250.0, "2B": 400.0, "1B": 600.0, "3B": 300.0, "SB": 300.0, "P_K": 150.0, "P_HR": 400.0, "P_BB": 200.0}
## How much of power comes from home runs (the rest from doubles: docs/07 4.3, home runs 60%
## and isolated power 40%), and of contact from strikeouts (the rest from singles, heavily
## regressed). On the fictional league's round trip singles lowered the OPS correlation (0.85
## to 0.82 with a fifth: there a man's singles are only luck); on the real seasons they raise
## it, because some hitters really do find holes (홍창기, 손아섭: .380 and more on balls in
## play year after year) and strikeouts alone take them for ordinary. Uncalibrated packs,
## qualified hitters' OPS correlation with the real season: all from strikeouts 2025 0.84,
## 2026 0.74; a fifth from singles 0.85, 0.79; two fifths 2019 0.79 (a fifth 0.83), 2023 0.79
## (0.68), 2024 0.77 (0.71). Two fifths it is.
const POWER_FROM_HR := 0.7
const CONTACT_FROM_K := 0.6
const LOW := 20.0
const HIGH := 99.0
## Playing-time groups for the average a small sample is pulled toward: plate appearances
## (hitters) and batters faced (pitchers) up to each edge, and the rest.
const TIERS: Array[float] = [60.0, 150.0, 300.0, 450.0]
## Switches for trying a variant against real seasons (tools/build_roster.gd --league-prior,
## --contact-from-k): the league's average for everybody instead of the groups', and the share
## of contact read from strikeouts.
static var by_playing_time := true
static var contact_from_k := CONTACT_FROM_K


## The rating that gives `rate` against a league rate `mu` for a coefficient `k`.
static func invert(rate: float, mu: float, k: float) -> float:
	if rate <= 0.0 or mu <= 0.0 or is_zero_approx(k):
		return 50.0
	return 50.0 + 15.0 * log(rate / mu) / k


## A rate pulled toward the league's by its sample.
static func regress(count: float, sample: float, mu: float, k: float) -> float:
	return (count + k * mu) / maxf(sample + k, 1.0)


static func clamp_rating(r: float) -> float:
	return clampf(r, LOW, HIGH)


## The league's rates per plate appearance from all the batting rows.
static func league_rates(batting: Array) -> Dictionary:
	var pa := 0.0
	var sums := {"so": 0.0, "bb": 0.0, "hr": 0.0, "3b": 0.0, "2b": 0.0, "h": 0.0, "sb": 0.0, "cs": 0.0, "on1": 0.0}
	for row: Dictionary in batting:
		pa += float(row.get("pa", 0))
		for key: String in ["so", "bb", "hr", "3b", "2b", "h", "sb", "cs"]:
			sums[key] = float(sums[key]) + float(row.get(key, 0))
		sums["on1"] = float(sums["on1"]) + _times_on_first(row)
	pa = maxf(pa, 1.0)
	var singles := float(sums["h"]) - float(sums["2b"]) - float(sums["3b"]) - float(sums["hr"])
	return {"K": sums["so"] / pa, "BB": sums["bb"] / pa, "HR": sums["hr"] / pa, "3B": sums["3b"] / pa,
		"2B": sums["2b"] / pa, "1B": singles / pa, "SB": (sums["sb"] + sums["cs"]) / maxf(sums["on1"], 1.0)}


## Times he reached first with second open, roughly: singles, walks, hit by pitch.
static func _times_on_first(row: Dictionary) -> float:
	var singles := float(row.get("h", 0)) - float(row.get("2b", 0)) - float(row.get("3b", 0)) - float(row.get("hr", 0))
	return maxf(singles + float(row.get("bb", 0)) + float(row.get("hbp", 0)), 0.0)


## The rates of men grouped by how much they played (TIERS): [{"at": the group's mean sample,
## key: rate, ...}, ...], for `like`. `sample` is the column counted ("pa", "bf"); `counts`
## maps each rate's key to its column(s), summed.
static func tiers(rows: Array, sample: String, counts: Dictionary) -> Array:
	var groups: Array = []
	for i: int in TIERS.size() + 1:
		groups.append({"n": 0.0, "weighted": 0.0})
	for row: Dictionary in rows:
		var n := float(row.get(sample, 0))
		if n <= 0.0:
			continue
		var g := TIERS.size()
		for i: int in TIERS.size():
			if n < TIERS[i]:
				g = i
				break
		groups[g]["n"] = float(groups[g]["n"]) + n
		groups[g]["weighted"] = float(groups[g]["weighted"]) + n * n
		for key: String in counts:
			var total := 0.0
			for column: String in counts[key]:
				total += float(row.get(column, 0))
			groups[g][key] = float(groups[g].get(key, 0.0)) + total
	var out: Array = []
	for g: Dictionary in groups:
		# Too few to say anything: left out (its neighbours speak for it).
		if float(g["n"]) < 300.0:
			continue
		var entry := {"at": float(g["weighted"]) / float(g["n"])}
		for key: String in counts:
			entry[key] = float(g.get(key, 0.0)) / float(g["n"])
		out.append(entry)
	return out


## The rates of men who played about `sample`: between the two groups around it; the
## league's (`mu`) where there are no groups.
static func like(groups: Array, sample: float, mu: Dictionary) -> Dictionary:
	if groups.is_empty():
		return mu
	var out := mu.duplicate()
	var low: Dictionary = groups[0]
	var high: Dictionary = groups[-1]
	for g: Dictionary in groups:
		if float(g["at"]) <= sample:
			low = g
	for i: int in range(groups.size() - 1, -1, -1):
		if float(groups[i]["at"]) >= sample:
			high = groups[i]
	var span := float(high["at"]) - float(low["at"])
	var t := clampf((sample - float(low["at"])) / span, 0.0, 1.0) if span > 0.0 else 0.0
	for key: String in low:
		if key != "at":
			out[key] = lerpf(float(low[key]), float(high[key]), t)
	return out


## The hitters' groups: strikeouts, walks, home runs, doubles and singles per plate appearance.
static func hitter_tiers(batting: Array) -> Array:
	var rows: Array = []
	for row: Dictionary in batting:
		var with_singles := row.duplicate()
		with_singles["1b"] = float(row.get("h", 0)) - float(row.get("2b", 0)) - float(row.get("3b", 0)) - float(row.get("hr", 0))
		rows.append(with_singles)
	return tiers(rows, "pa", {"K": ["so"], "BB": ["bb"], "HR": ["hr"], "2B": ["2b"], "1B": ["1b"]})


## The pitchers' groups: strikeouts, walks and home runs per batter faced.
static func pitcher_tiers(pitching: Array) -> Array:
	return tiers(pitching, "bf", {"K": ["so"], "BB": ["bb"], "HR": ["hr"]})


## A hitter's ratings from his row: contact from strikeouts, eye from walks, power from home
## runs, speed from triples and steal attempts. Returns {"contact", "eye", "power", "speed"}.
## `prior` is what his small samples are pulled toward (the rates of men who played as much:
## `like`); the league's when it is not given.
static func hitter_ratings(row: Dictionary, mu: Dictionary, k: Dictionary, prior: Dictionary = {}) -> Dictionary:
	var pa := float(row.get("pa", 0))
	var to: Dictionary = prior if not prior.is_empty() else mu
	var k_rate := regress(float(row.get("so", 0)), pa, float(to["K"]), float(REGRESS["K"]))
	var bb_rate := regress(float(row.get("bb", 0)), pa, float(to["BB"]), float(REGRESS["BB"]))
	var hr_rate := regress(float(row.get("hr", 0)), pa, float(to["HR"]), float(REGRESS["HR"]))
	var power := invert(hr_rate, float(mu["HR"]), float(k["HR"]["power"]))
	# Doubles: mostly power, a little speed (taken as average here).
	var d_rate := regress(float(row.get("2b", 0)), pa, float(to["2B"]), float(REGRESS["2B"]))
	var from_doubles := invert(d_rate, float(mu["2B"]), float(k["2B"]["power"]))
	power = POWER_FROM_HR * power + (1.0 - POWER_FROM_HR) * from_doubles
	var t_rate := regress(float(row.get("3b", 0)), pa, float(mu["3B"]), float(REGRESS["3B"]))
	# Triples also come a little from power: take its share out before reading speed.
	var speed_from_triples := (log(t_rate / float(mu["3B"])) - float(k["3B"].get("power", 0.0)) * (power - 50.0) / 15.0) * 15.0 / float(k["3B"]["speed"]) + 50.0
	var on1 := _times_on_first(row)
	var tries := float(row.get("sb", 0)) + float(row.get("cs", 0))
	var try_rate := regress(tries, on1, float(mu["SB"]), float(REGRESS["SB"]))
	var speed_from_steals := invert(try_rate, float(mu["SB"]), float(k["SB"]))
	var singles := float(row.get("h", 0)) - float(row.get("2b", 0)) - float(row.get("3b", 0)) - float(row.get("hr", 0))
	var s_rate := regress(singles, pa, float(to["1B"]), float(REGRESS["1B"]))
	var contact := contact_from_k * invert(k_rate, float(mu["K"]), float(k["K"]["contact"])) + (1.0 - contact_from_k) * invert(s_rate, float(mu["1B"]), float(k["1B"]["contact"]))
	return {
		"contact": clamp_rating(contact),
		"eye": clamp_rating(invert(bb_rate, float(mu["BB"]), float(k["BB"]["eye"]))),
		"power": clamp_rating(power),
		"speed": clamp_rating(0.5 * speed_from_triples + 0.5 * speed_from_steals),
	}


## The league's rates per batter faced from the pitching rows.
static func pitching_rates(pitching: Array) -> Dictionary:
	var bf := 0.0
	var so := 0.0
	var bb := 0.0
	var hr := 0.0
	for row: Dictionary in pitching:
		bf += float(row.get("bf", 0))
		so += float(row.get("so", 0))
		bb += float(row.get("bb", 0))
		hr += float(row.get("hr", 0))
	bf = maxf(bf, 1.0)
	return {"K": so / bf, "BB": bb / bf, "HR": hr / bf}


## A pitcher's ratings: stuff from strikeouts and home runs, control from walks, stamina from
## how long his starts went. Returns {"stuff", "control", "stamina"}. `prior` as for a hitter.
static func pitcher_ratings(row: Dictionary, mu: Dictionary, k: Dictionary, prior: Dictionary = {}) -> Dictionary:
	var bf := float(row.get("bf", 0))
	var to: Dictionary = prior if not prior.is_empty() else mu
	var k_rate := regress(float(row.get("so", 0)), bf, float(to["K"]), float(REGRESS["P_K"]))
	var hr_rate := regress(float(row.get("hr", 0)), bf, float(to["HR"]), float(REGRESS["P_HR"]))
	var bb_rate := regress(float(row.get("bb", 0)), bf, float(to["BB"]), float(REGRESS["P_BB"]))
	var from_k := invert(k_rate, float(mu["K"]), float(k["K"]["stuff"]))
	var from_hr := invert(hr_rate, float(mu["HR"]), float(k["HR"]["stuff"]))
	var starts := float(row.get("gs", 0))
	var outs := float(row.get("outs", 0))
	var stamina := 35.0
	if starts > 0.0 and starts >= float(row.get("g", 0)) * 0.5:
		# 4 innings a start: 20; 6: 60; 7 and more: 80 and up.
		stamina = clampf(20.0 + (outs / starts / 3.0 - 4.0) * 20.0, 20.0, 95.0)
	return {"stuff": clamp_rating(0.75 * from_k + 0.25 * from_hr), "control": clamp_rating(invert(bb_rate, float(mu["BB"]), float(k["BB"]["control"]))), "stamina": stamina}


## Sets a pitcher's pitches so that his stuff (PitchingRatings.stuff) is `target`: each pitch's
## movement moves by the same amount (stuff is half speed, half movement).
static func set_stuff(p: Player, target: float, catalog: Dictionary[StringName, PitchType]) -> void:
	for i: int in 3:
		var now := p.pitching.stuff(catalog)
		var step := (target - now) * 2.0
		for a: ArsenalPitch in p.pitching.arsenal:
			a.movement = clampf(a.movement + step, 1.0, 99.0)


## A pitcher's real pitches (the user: the real men's real pitches): which, how often, how hard;
## their movement and command start from the generated ones (set_stuff then brings his stuff to
## his record). Most used first, six at most.
static func real_arsenal(p: Player, rows: Array) -> void:
	var made := p.pitching.arsenal
	var movement := made[0].movement if not made.is_empty() else 50.0
	var command := made[0].command if not made.is_empty() else 50.0
	var sorted := rows.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["usage"]) > float(b["usage"]))
	var arsenal: Array[ArsenalPitch] = []
	for row: Dictionary in sorted.slice(0, 6):
		var a := ArsenalPitch.new()
		a.type = StringName(str(row["type"]))
		a.usage = float(row["usage"])
		if row.has("usage_even") and str(row["usage_even"]) != "":
			a.by_count = PackedFloat32Array([float(row["usage_even"]), float(row["usage_ahead"]), float(row["usage_behind"])])
		a.velo_avg = clampf(float(row.get("velo", 0.0)), 90.0, 162.0) if float(row.get("velo", 0.0)) > 60.0 else 140.0
		a.velo_max = a.velo_avg + 4.0
		a.movement = movement
		a.command = command - (0.0 if arsenal.is_empty() else 2.0)
		arsenal.append(a)
	if not arsenal.is_empty():
		p.pitching.arsenal = arsenal


## The league's OPS against the other hand over the same hand (2023–2025: about .03 to .05);
## plate appearances that count half toward a man's own split; OPS for a point of rating in
## both contact and power (measured: tools/pitch_data_report.gd).
const LEAGUE_SPLIT := 0.04
const SPLIT_PRIOR := 1000.0
const OPS_PER_POINT := 0.02


## A batter's own split beyond the league's, in rating points (0 without a line or for a
## switch-hitter): his OPS against the other hand over the same hand, less the league's, pulled
## toward nothing by his plate appearances on the side he has fewer of.
static func own_split(row: Dictionary, bats: StringName) -> float:
	if row.is_empty() or bats == &"S":
		return 0.0
	var pa_l := float(row.get("pa_l", 0))
	var pa_r := float(row.get("pa_r", 0))
	var same := float(row.get("ops_l" if bats == &"L" else "ops_r", 0.0))
	var other := float(row.get("ops_r" if bats == &"L" else "ops_l", 0.0))
	var n := 2.0 * pa_l * pa_r / maxf(pa_l + pa_r, 1.0)
	var weight := n / (n + SPLIT_PRIOR)
	return clampf((other - same - LEAGUE_SPLIT) * weight / OPS_PER_POINT, -8.0, 12.0)


## Builds the clubs from the tables: teams (id, name, short, stadium, primary, secondary,
## accent), players (id, team, name, number, born, height_cm, weight_kg, bats, throws,
## positions "SS/2B", role "SP"/"RP" for pitchers, origin, registered 1/0), batting (id, pa,
## ab, h, 2b, 3b, hr, bb, hbp, so, sb, cs), pitching (id, g, gs, outs, bf, so, bb, hr).
static func build(teams: Array, players: Array, batting: Array, pitching: Array, env: LeagueEnv, catalog: Dictionary[StringName, PitchType], names: NameTable, pitches: Array = [], splits: Array = []) -> Array[Team]:
	# Each batter's own split against left- and right-handed pitchers (queue stage 3): how much
	# more (or less) he does against the other hand than the league does, pulled toward it by
	# how few plate appearances there are (SPLIT_PRIOR).
	var split_of: Dictionary = {}
	for row: Dictionary in splits:
		split_of[str(row["id"])] = row
	# Each pitcher's real pitches where the tables have them (id, type, usage, velo).
	var mix: Dictionary = {}
	for row: Dictionary in pitches:
		if catalog.has(StringName(str(row.get("type", "")))):
			if not mix.has(str(row["id"])):
				mix[str(row["id"])] = []
			(mix[str(row["id"])] as Array).append(row)
	var coeffs := coefficients(env)
	var parks := park_effects(teams)
	var team_of: Dictionary = {}
	for prow: Dictionary in players:
		team_of[str(prow["id"])] = str(prow.get("team", ""))
	if not parks.is_empty():
		var nb: Array = []
		for row: Dictionary in batting:
			nb.append(neutral(row, parks.get(team_of.get(str(row["id"]), ""), {})))
		batting = nb
		var np: Array = []
		for row: Dictionary in pitching:
			np.append(neutral(row, parks.get(team_of.get(str(row["id"]), ""), {})))
		pitching = np
	var mu := league_rates(batting)
	var mu_p := pitching_rates(pitching)
	var groups := hitter_tiers(batting) if by_playing_time else []
	var groups_p := pitcher_tiers(pitching) if by_playing_time else []
	var bat_by: Dictionary[String, Dictionary] = {}
	for row: Dictionary in batting:
		bat_by[str(row["id"])] = row
	var pitch_by: Dictionary[String, Dictionary] = {}
	for row: Dictionary in pitching:
		pitch_by[str(row["id"])] = row
	var out: Array[Team] = []
	for trow: Dictionary in teams:
		var t := Team.new()
		t.id = str(trow["id"])
		t.name = str(trow.get("name", t.id))
		t.short_name = str(trow.get("short", t.name))
		t.stadium = str(trow.get("stadium", ""))
		t.primary = Color.from_string(str(trow.get("primary", "#12355b")), t.primary)
		t.secondary = Color.from_string(str(trow.get("secondary", "#f2f2f2")), t.secondary)
		t.accent = Color.from_string(str(trow.get("accent", "#e0a100")), t.accent)
		out.append(t)
	for prow: Dictionary in players:
		var team: Team = null
		for t: Team in out:
			if t.id == str(prow.get("team", "")):
				team = t
		if team == null:
			continue
		var id := str(prow["id"])
		var positions := str(prow.get("positions", prow.get("role", "RP"))).split("/")
		var pitcher := positions[0] in ["SP", "RP", "P"]
		var role := str(prow.get("role", positions[0])) if pitcher else "/".join(positions)
		if role == "P":
			role = "SP" if float(pitch_by.get(id, {}).get("gs", 0)) > 0.0 else "RP"
		var gen := LeagueGenerator.new(names, catalog, hash("real:" + id))
		var p := gen.player(role, 50.0)
		p.id = id
		p.name = str(prow.get("name", id))
		p.number = int(prow.get("number", 0))
		p.born = int(prow.get("born", p.born))
		p.height_cm = float(prow.get("height_cm", p.height_cm))
		p.weight_kg = float(prow.get("weight_kg", p.weight_kg))
		p.bats = StringName(str(prow.get("bats", "R")))
		p.throws = StringName(str(prow.get("throws", "R")))
		p.origin = StringName(str(prow.get("origin", "")))
		if pitcher:
			if mix.has(id):
				real_arsenal(p, mix[id])
			var line: Dictionary = pitch_by.get(id, {})
			var r := pitcher_ratings(line, mu_p, coeffs["pitcher"], like(groups_p, float(line.get("bf", 0)), mu_p))
			set_stuff(p, float(r["stuff"]), catalog)
			p.pitching.control = float(r["control"])
			p.pitching.stamina = float(r["stamina"])
		else:
			var line: Dictionary = bat_by.get(id, {})
			var r := hitter_ratings(line, mu, coeffs["batter"], like(groups, float(line.get("pa", 0)), mu))
			# (The league's own split is in the outcome tables already: LeagueEnv.same_hand,
			# opposite_hand. Only his own beyond it goes into his ratings.)
			var platoon := own_split(split_of.get(id, {}), p.bats)
			# (Positive: better against right-handed pitchers.)
			var toward_r := platoon if p.bats == &"L" else (-platoon if p.bats == &"R" else 0.0)
			p.batting.contact_r = clamp_rating(float(r["contact"]) + toward_r * 0.5)
			p.batting.contact_l = clamp_rating(float(r["contact"]) - toward_r * 0.5)
			p.batting.power_r = clamp_rating(float(r["power"]) + toward_r * 0.5)
			p.batting.power_l = clamp_rating(float(r["power"]) - toward_r * 0.5)
			p.batting.eye = float(r["eye"])
			p.batting.speed = float(r["speed"])
		team.players.append(p)
		if int(prow.get("registered", 1)) == 1:
			team.registered.append(p.id)
	return out


## How much each club's men's records were helped or held back by the parks they played in:
## team id → {"HR": ×, "H": ×}, half their games at home (the team's pf_hr and pf_h columns)
## and half away (the other parks' average). Empty when the tables give no parks.
static func park_effects(teams: Array) -> Dictionary:
	var out: Dictionary = {}
	var n := 0
	var sum_hr := 0.0
	var sum_h := 0.0
	for row: Dictionary in teams:
		if not row.has("pf_hr"):
			return {}
		n += 1
		sum_hr += float(row["pf_hr"])
		sum_h += float(row.get("pf_h", 1.0))
	if n < 2:
		return {}
	for row: Dictionary in teams:
		var hr := float(row["pf_hr"])
		var h := float(row.get("pf_h", 1.0))
		out[str(row["id"])] = {"HR": 0.5 * (hr + (sum_hr - hr) / (n - 1)), "H": 0.5 * (h + (sum_h - h) / (n - 1))}
	return out


## A record with the parks taken out (docs/13 S17): home runs and other hits divided by what
## the parks did to them, so a 잠실 hitter is read as the hitter he would be anywhere (the
## resolver puts 잠실 back for the games he plays there).
static func neutral(row: Dictionary, effect: Dictionary) -> Dictionary:
	if effect.is_empty() or row.is_empty():
		return row
	var out := row.duplicate()
	var f_hr := float(effect.get("HR", 1.0))
	var f_h := float(effect.get("H", 1.0))
	if out.has("2b"):
		var hr := float(row.get("hr", 0)) / f_hr
		var doubles := float(row.get("2b", 0)) / f_h
		var triples := float(row.get("3b", 0)) / f_h
		var singles := (float(row.get("h", 0)) - float(row.get("2b", 0)) - float(row.get("3b", 0)) - float(row.get("hr", 0))) / f_h
		out["hr"] = hr
		out["2b"] = doubles
		out["3b"] = triples
		out["h"] = singles + doubles + triples + hr
	else:
		out["hr"] = float(row.get("hr", 0)) / f_hr
	return out


## The engine's coefficients as the builder reads them: per outcome, per rating; with the
## steal attempts' speed coefficient as "SB".
static func coefficients(env: LeagueEnv) -> Dictionary:
	var b: Dictionary = {}
	for key: String in env.batter_k:
		b[key] = env.batter_k[key].duplicate()
	b["SB"] = env.value("steal_speed_k", 0.6)
	var p: Dictionary = {}
	for key: String in env.pitcher_k:
		p[key] = env.pitcher_k[key].duplicate()
	return {"batter": b, "pitcher": p}
