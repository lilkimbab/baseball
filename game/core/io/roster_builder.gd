class_name RosterBuilder
extends RefCounted
## Real records into ratings (docs/07 section 4.3, docs/09 section 5, docs/13 S17): ratings are
## not made up; they are worked out from what each man did, by running the match engine's own
## formula backwards — the statistical resolver draws an outcome at the league's rate times
## exp(k × (rating − 50) / 15) — so that a league made from a season plays that season again.
## A small sample is pulled toward the league's average first (x_reg = (N x + k μ) / (N + k)),
## the result kept within 20..99. What the records cannot tell (how a man looks, his fielding
## beyond his positions, his pitches' details) starts from the league generator's, seeded by
## his id, and is then set from the records where they speak.
##
## Input: rows (Dictionaries) as read from CSV files (tools/build_roster.gd; columns in
## docs/13 S17). Output: teams for RosterIO.save_pack.

## Sample sizes at which each rate is half the man's and half the league's (docs/07 4.3).
const REGRESS := {"K": 100.0, "BB": 170.0, "HR": 250.0, "2B": 400.0, "1B": 600.0, "3B": 300.0, "SB": 300.0, "P_K": 150.0, "P_HR": 400.0, "P_BB": 200.0}
## How much of power comes from home runs (the rest from doubles: docs/07 4.3, home runs 60%
## and isolated power 40%), and of contact from strikeouts (the rest from singles; a share of
## 0.2 from singles lowered the round trip's OPS correlation from 0.85 to 0.82: singles carry
## too much luck).
const POWER_FROM_HR := 0.7
const CONTACT_FROM_K := 1.0
const LOW := 20.0
const HIGH := 99.0


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


## A hitter's ratings from his row: contact from strikeouts, eye from walks, power from home
## runs, speed from triples and steal attempts. Returns {"contact", "eye", "power", "speed"}.
static func hitter_ratings(row: Dictionary, mu: Dictionary, k: Dictionary) -> Dictionary:
	var pa := float(row.get("pa", 0))
	var k_rate := regress(float(row.get("so", 0)), pa, float(mu["K"]), float(REGRESS["K"]))
	var bb_rate := regress(float(row.get("bb", 0)), pa, float(mu["BB"]), float(REGRESS["BB"]))
	var hr_rate := regress(float(row.get("hr", 0)), pa, float(mu["HR"]), float(REGRESS["HR"]))
	var power := invert(hr_rate, float(mu["HR"]), float(k["HR"]["power"]))
	# Doubles: mostly power, a little speed (taken as average here).
	var d_rate := regress(float(row.get("2b", 0)), pa, float(mu["2B"]), float(REGRESS["2B"]))
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
	var s_rate := regress(singles, pa, float(mu["1B"]), float(REGRESS["1B"]))
	var contact := CONTACT_FROM_K * invert(k_rate, float(mu["K"]), float(k["K"]["contact"])) + (1.0 - CONTACT_FROM_K) * invert(s_rate, float(mu["1B"]), float(k["1B"]["contact"]))
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
## how long his starts went. Returns {"stuff", "control", "stamina"}.
static func pitcher_ratings(row: Dictionary, mu: Dictionary, k: Dictionary) -> Dictionary:
	var bf := float(row.get("bf", 0))
	var k_rate := regress(float(row.get("so", 0)), bf, float(mu["K"]), float(REGRESS["P_K"]))
	var hr_rate := regress(float(row.get("hr", 0)), bf, float(mu["HR"]), float(REGRESS["P_HR"]))
	var bb_rate := regress(float(row.get("bb", 0)), bf, float(mu["BB"]), float(REGRESS["P_BB"]))
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


## Builds the clubs from the tables: teams (id, name, short, stadium, primary, secondary,
## accent), players (id, team, name, number, born, height_cm, weight_kg, bats, throws,
## positions "SS/2B", role "SP"/"RP" for pitchers, origin, registered 1/0), batting (id, pa,
## ab, h, 2b, 3b, hr, bb, hbp, so, sb, cs), pitching (id, g, gs, outs, bf, so, bb, hr).
static func build(teams: Array, players: Array, batting: Array, pitching: Array, env: LeagueEnv, catalog: Dictionary[StringName, PitchType], names: NameTable) -> Array[Team]:
	var coeffs := coefficients(env)
	var mu := league_rates(batting)
	var mu_p := pitching_rates(pitching)
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
			var r := pitcher_ratings(pitch_by.get(id, {}), mu_p, coeffs["pitcher"])
			set_stuff(p, float(r["stuff"]), catalog)
			p.pitching.control = float(r["control"])
			p.pitching.stamina = float(r["stamina"])
		else:
			var r := hitter_ratings(bat_by.get(id, {}), mu, coeffs["batter"])
			var platoon := 2.0
			p.batting.contact_r = clamp_rating(float(r["contact"]) + (platoon if p.bats == &"L" else -platoon) * 0.5)
			p.batting.contact_l = clamp_rating(float(r["contact"]) - (platoon if p.bats == &"L" else -platoon) * 0.5)
			p.batting.power_r = float(r["power"])
			p.batting.power_l = float(r["power"])
			p.batting.eye = float(r["eye"])
			p.batting.speed = float(r["speed"])
		team.players.append(p)
		if int(prow.get("registered", 1)) == 1:
			team.registered.append(p.id)
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
