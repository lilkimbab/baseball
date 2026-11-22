extends SceneTree
## How the game's numbers feel to someone playing it (the user, 2026-11-22: "think about the
## balance from the player's side — is raising ratings right, is earning right, is the game's
## difficulty right"). Plays careers and league seasons with the stat resolver and prints:
##   careers   for each kind of player: his overall (as shown) at the start, at the call-up and
##             at the end of a season, growth points earned per game in each field, what they
##             bought, his season line; growth points spent the way a player would (the
##             cheapest point of his field first)
##   league    the club points a manager's club earns in a season, and what they buy
##
##   godot --headless --path game --script res://tools/balance_report.gd -- [--games 144] [--seeds 3]

const KINDS := [["SS", "contact"], ["CF", "speed"], ["1B", "power"], ["C", "defence"], ["SP", "power_arm"], ["RP", "control"]]


func _init() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var games := int(args.get("games", "144"))
	var seeds := int(args.get("seeds", "3"))
	var only := str(args.get("only", ""))
	if only == "" or only == "career":
		_careers(games, seeds)
	if only == "" or only == "league":
		_league(games, seeds)
	quit()


func _careers(games: int, seeds: int) -> void:
	var rules := CareerIO.load_default()
	var catalog := PitchCatalogIO.load_default()
	var overall := LeagueEnvIO.load_overall()
	print("== careers, %d games, %d seeds ==" % [games, seeds])
	print("kind            ovr start  call-up day  ovr end  gp/game bat run fld pit   line")
	for kind: Array in KINDS:
		var starts := 0.0
		var ends := 0.0
		var call_days := 0.0
		var called := 0
		var gp_sum: Dictionary[String, float] = {}
		var played := 0
		var lines := PackedStringArray()
		for seed_value: int in seeds:
			var spec := PlayerCreator.Spec.new()
			spec.name = "측정"
			spec.position = str(kind[0])
			spec.type_id = str(kind[1])
			var c := PlayerCreator.create(spec, rules, catalog)
			var clubs := RosterIO.load_pack(LeagueSession.PACK)
			var season := Season.create(clubs, 10, games, 100 + seed_value, RuleSet.kbo_2026(), LeagueEnvIO.load_default(), catalog, overall, ClubIO.load_default())
			c.join(season.teams[season.divisions[0][4]])
			var cs := CareerSeason.start(season, c, rules)
			starts += _shown(cs, c.player)
			var guard := 0
			var call_day := -1
			while not cs.season.finished() and guard < games * 3:
				if cs.has_game():
					var report := cs.quick()
					played += 1
					for field: String in report.gp:
						gp_sum[field] = float(gp_sum.get(field, 0.0)) + float(report.gp[field])
					if report.called_up and call_day < 0:
						call_day = cs.season.day
					_spend(c, rules)
				cs.next_day()
				guard += 1
			ends += _shown(cs, c.player)
			if call_day >= 0:
				called += 1
				call_days += call_day
			lines.append(_line(cs))
		var n := float(seeds)
		var per := maxf(float(played), 1.0)
		print("%-14s  %6.1f     %8s     %6.1f   %5.1f %5.1f %5.1f %5.1f   %s" % ["%s %s" % kind, starts / n,
			("%.0f (%d/%d)" % [call_days / maxf(called, 1), called, seeds]) if called > 0 else "-", ends / n,
			gp_sum.get("batting", 0.0) / per, gp_sum.get("running", 0.0) / per, gp_sum.get("fielding", 0.0) / per,
			gp_sum.get("pitching", 0.0) / per, lines[0]])


## Spends growth points as a player would: in each field, the cheapest point first, until none
## can be bought.
func _spend(c: CareerPlayer, rules: CareerRules) -> void:
	for field: String in ["batting", "running", "fielding", "pitching"]:
		var guard := 0
		while guard < 200:
			guard += 1
			var best := ""
			var best_cost := INF
			for rating: String in rules.ratings.get(field, []):
				if (field == "pitching") != c.is_pitcher():
					continue
				if Growth.value(c.player, rating) >= 99.0:
					continue
				var price := Growth.cost(c, rating, rules)
				if price < best_cost:
					best_cost = price
					best = rating
			if best == "" or not Growth.raise(c, best, rules):
				break


func _shown(cs: CareerSeason, p: Player) -> float:
	return UiTheme.shown(ClubRules.player_ovr(p, cs.season.ovr, cs.season.catalog))


func _line(cs: CareerSeason) -> String:
	var id := cs.career.player.id
	if cs.career.is_pitcher():
		var q: PitchingLine = cs.season.book.pitching.get(id)
		if q == null or q.outs == 0:
			return "(1군 등판 없음)"
		return "1군 %d이닝 평균자책점 %.2f 탈삼진 %d" % [q.outs / 3, q.era(), q.strikeouts]
	var b: BattingLine = cs.season.book.batting.get(id)
	if b == null or b.pa == 0:
		return "(1군 타석 없음)"
	return "1군 %d타석 타율 %s 홈런 %d OPS %s" % [b.pa, BattingLine.rate_text(b.average()), b.home_runs, BattingLine.rate_text(b.ops())]


func _league(games: int, seeds: int) -> void:
	print("== league, %d games: the manager's club by difficulty (other clubs' form) ==" % games)
	var rules := ClubIO.load_default()
	print("difficulty  club       W%   club points / season")
	for level: int in 4:
		for which: String in ["average", "best"]:
			var won := 0
			var played := 0
			var earned := 0
			for seed_value: int in seeds:
				var clubs := RosterIO.load_pack(LeagueSession.PACK)
				var season := Season.create(clubs, 10, games, 200 + seed_value, RuleSet.kbo_2026(), LeagueEnvIO.load_default(), PitchCatalogIO.load_default(), LeagueEnvIO.load_overall(), rules)
				var ids: Array = season.divisions[0].duplicate()
				ids.sort_custom(func(a: String, b: String) -> bool: return _strength(season, a) > _strength(season, b))
				season.manage(ids[0] if which == "best" else ids[ids.size() / 2])
				season.difficulty = level
				var start := season.club.points
				season.play_regular_season()
				var row: StandingsRow = season.standings[0].row(season.my_team)
				won += row.wins
				played += row.wins + row.losses
				earned += season.club.points - start
			print("%-10s  %-8s  %.3f   %d" % [Difficulty.NAMES[level], which, float(won) / maxf(played, 1.0), earned / seeds])


## A club's strength: the mean overall of its first team.
func _strength(season: Season, id: String) -> float:
	var team: Team = season.teams[id]
	var total := 0.0
	var men := team.first_team()
	for p: Player in men:
		total += ClubRules.player_ovr(p, season.ovr, season.catalog)
	return total / maxf(men.size(), 1.0)
