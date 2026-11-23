extends SceneTree
## Checks the records-to-ratings builder without real records: a division of the
## fictional league plays a season; its numbers go through RosterBuilder as if they were a
## real season's; the league built from them plays the season again several times; each
## qualified hitter's average OPS is compared with what he did in the "real" season, and the
## clubs' winning percentages likewise (docs/06 4.3: OPS correlation 0.85 or more, winning
## percentage 0.7 or more). Also how close the built ratings come to the true ones.
##
##   godot --headless --path game --script res://tools/roster_roundtrip.gd -- [--games 144] [--replays 8]


func _init() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var games := int(str(args.get("games", "144")))
	var replays := int(str(args.get("replays", "8")))
	var catalog := PitchCatalogIO.load_default()
	var env := LeagueEnvIO.load_default()
	var ovr := LeagueEnvIO.load_overall()
	var all := RosterIO.load_pack(LeagueSession.PACK)
	var clubs: Array[Team] = []
	for i: int in 10:
		clubs.append(all[i])
	for t: Team in clubs:
		for p: Player in t.players:
			p.potential = 0.0
	var real := Season.create(clubs, 10, games, 11, RuleSet.kbo_2026(), env, catalog, ovr, null)
	_regular(real)
	var tables := export(real)
	var built := RosterBuilder.build(tables[0], tables[1], tables[2], tables[3], env, catalog, RosterIO.load_names())
	# The built ratings against the true ones.
	var pairs := {"contact": [[], []], "eye": [[], []], "power": [[], []], "speed": [[], []], "stuff": [[], []], "control": [[], []]}
	for t: Team in clubs:
		var b: Team = null
		for x: Team in built:
			if x.id == t.id:
				b = x
		for p: Player in t.players:
			var q := b.player(p.id)
			if q == null:
				continue
			if p.is_pitcher():
				if real.book.pitching.has(p.id) and real.book.pitching[p.id].batters_faced >= 100:
					pairs["stuff"][0].append(p.pitching.stuff(catalog))
					pairs["stuff"][1].append(q.pitching.stuff(catalog))
					pairs["control"][0].append(p.pitching.control)
					pairs["control"][1].append(q.pitching.control)
			elif real.book.batting.has(p.id) and real.book.batting[p.id].pa >= 200:
				pairs["contact"][0].append(p.batting.contact())
				pairs["contact"][1].append(q.batting.contact())
				pairs["eye"][0].append(p.batting.eye)
				pairs["eye"][1].append(q.batting.eye)
				pairs["power"][0].append(p.batting.power())
				pairs["power"][1].append(q.batting.power())
				pairs["speed"][0].append(p.batting.speed)
				pairs["speed"][1].append(q.batting.speed)
	for key: String in pairs:
		print("roundtrip: rating %-8s r = %.2f (n %d)" % [key, correlation(pairs[key][0], pairs[key][1]), pairs[key][0].size()])
	# The built league, played again.
	var ops_sum: Dictionary[String, float] = {}
	var ops_n: Dictionary[String, int] = {}
	var wins: Dictionary[String, float] = {}
	for i: int in replays:
		var again: Array[Team] = []
		for t: Team in built:
			again.append(_copy(t))
		var s := Season.create(again, 10, games, 100 + i, RuleSet.kbo_2026(), env, catalog, ovr, null)
		for t: Team in again:
			for p: Player in t.players:
				p.potential = 0.0
		_regular(s)
		for id: String in s.book.batting:
			var line: BattingLine = s.book.batting[id]
			if line.pa > 0:
				ops_sum[id] = float(ops_sum.get(id, 0.0)) + line.ops()
				ops_n[id] = int(ops_n.get(id, 0)) + 1
		for r: StandingsRow in s.standings[0].ranked():
			wins[r.team_id] = float(wins.get(r.team_id, 0.0)) + r.pct() / replays
	var actual: Array = []
	var played: Array = []
	var need := int(floorf(games * 3.1))
	for id: String in real.book.batting:
		var line: BattingLine = real.book.batting[id]
		if line.pa >= need and ops_n.has(id):
			actual.append(line.ops())
			played.append(ops_sum[id] / ops_n[id])
	print("roundtrip: qualified hitters' OPS, real season against %d replays: r = %.3f (n %d; target 0.85)" % [replays, correlation(actual, played), actual.size()])
	var a_w: Array = []
	var p_w: Array = []
	for r: StandingsRow in real.standings[0].ranked():
		a_w.append(r.pct())
		p_w.append(wins[r.team_id])
	print("roundtrip: clubs' winning percentage: r = %.3f (target 0.7)" % correlation(a_w, p_w))
	quit()


func _regular(s: Season) -> void:
	var guard := 0
	while s.phase == Season.Phase.REGULAR and guard < 400:
		s.play_day(true)
		s.advance()
		guard += 1


func _copy(t: Team) -> Team:
	var c := Team.new()
	c.id = t.id
	c.name = t.name
	c.short_name = t.short_name
	c.stadium = t.stadium
	c.primary = t.primary
	c.secondary = t.secondary
	c.accent = t.accent
	for p: Player in t.players:
		c.players.append(RosterIO.player_from(RosterIO.player_to(p, true)))
	c.registered = t.registered.duplicate()
	return c


## A season's clubs, players and numbers as the builder's tables.
static func export(s: Season) -> Array:
	var teams: Array = []
	var players: Array = []
	var batting: Array = []
	var pitching: Array = []
	for id: String in s.teams:
		var t: Team = s.teams[id]
		teams.append({"id": t.id, "name": t.name, "short": t.short_name, "stadium": t.stadium, "primary": "#" + t.primary.to_html(false), "secondary": "#" + t.secondary.to_html(false), "accent": "#" + t.accent.to_html(false)})
		for p: Player in t.players:
			var codes := PackedStringArray()
			if p.is_pitcher():
				codes.append(String(p.role()))
			else:
				codes.append(Position.code(p.primary_position()))
			players.append({"id": p.id, "team": t.id, "name": p.name, "number": p.number, "born": p.born, "height_cm": p.height_cm, "weight_kg": p.weight_kg,
				"bats": String(p.bats), "throws": String(p.throws), "positions": "/".join(codes), "origin": String(p.origin), "registered": 1 if t.is_registered(p.id) else 0})
			if s.book.batting.has(p.id):
				var b: BattingLine = s.book.batting[p.id]
				batting.append({"id": p.id, "pa": b.pa, "ab": b.ab, "h": b.hits, "2b": b.doubles, "3b": b.triples, "hr": b.home_runs, "bb": b.walks + b.intentional_walks, "hbp": b.hit_by_pitch, "so": b.strikeouts, "sb": b.stolen_bases, "cs": b.caught_stealing})
			if s.book.pitching.has(p.id):
				var l: PitchingLine = s.book.pitching[p.id]
				pitching.append({"id": p.id, "g": l.games, "gs": l.starts, "outs": l.outs, "bf": l.batters_faced, "so": l.strikeouts, "bb": l.walks + l.intentional_walks, "hr": l.home_runs})
	return [teams, players, batting, pitching]


static func correlation(a: Array, b: Array) -> float:
	var n := a.size()
	if n < 3:
		return 0.0
	var ma := 0.0
	var mb := 0.0
	for i: int in n:
		ma += float(a[i])
		mb += float(b[i])
	ma /= n
	mb /= n
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i: int in n:
		sab += (float(a[i]) - ma) * (float(b[i]) - mb)
		saa += (float(a[i]) - ma) ** 2
		sbb += (float(b[i]) - mb) ** 2
	return sab / sqrt(maxf(saa * sbb, 1e-12))
