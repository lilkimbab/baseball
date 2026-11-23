class_name LeagueAllStar
extends RefCounted
## The all-star break of a league season (2026-11-23: "the career has it, the
## league should too"): at the season's middle (the career's own share, data/career.ko.json
## all_star.at_share) the league's twenty-two most voted players make two teams (청팀·백팀, the
## first five clubs against the other five: AllStar), and the four with the most home runs meet
## in a derby. The manager may play the game himself (his men's side), let it be settled, and
## send one of his hitters in the derby to swing himself or have it settled. Then the season
## goes on.
##
## What it pays (kept small beside a season's: a game played oneself pays 60 + 90 for a win;
## a season's end 400 to 2,400 and more):
## - club points: CLUB_PER_MAN for each of his men picked (a club's players going to the
##   all-star game is the club's pride; ten to sixty points against a season's hundreds),
## - his game played himself: GAME_WIN or GAME_LOSS points, by the difficulty (an exhibition:
##   less than a game that counts, more than nothing),
## - the derby swung himself: DERBY_PER_HOME_RUN for each home run, DERBY_WIN for the title,
##   by the difficulty; settled at once, DERBY_WIN_QUICK when his man wins.
## Played at once, the game pays nothing but the club points.

const CLUB_PER_MAN := 15
const GAME_WIN := 100
const GAME_LOSS := 60
const DERBY_PER_HOME_RUN := 5
const DERBY_WIN := 150
const DERBY_WIN_QUICK := 50
const PICKED := 22
const DERBY_FIELD := 4
const DERBY_OUTS := 10


## Its time has come and it has not been held.
static func due(s: Season) -> bool:
	if s.history != null or s.school or s.my_team == "" or s.divisions.size() != 1:
		return false
	if s.phase != Season.Phase.REGULAR or s.all_star.has("selected"):
		return false
	var share := float(CareerIO.load_default().all_star.get("at_share", 0.5))
	return s.day >= int(s.total_days() * share)


## Picks the players and the derby's field (the break begins).
static func hold(s: Season) -> void:
	var selected := AllStar.select(s, 0, null, PICKED)
	var field := AllStar.derby_field(s, 0, null, selected, DERBY_FIELD)
	s.all_star = {"selected": selected, "field": field, "derby": {}, "game": [], "day": s.day, "paid": []}
	var mine := of_my_club(s)
	if not mine.is_empty() and s.club != null:
		s.club.points += CLUB_PER_MAN * mine.size()
		(s.all_star["paid"] as Array).append("올스타 선정 %d명 (구단 포인트 +%d)" % [mine.size(), CLUB_PER_MAN * mine.size()])


## The break is on (held, and the game or the derby still to be played).
static func on(s: Season) -> bool:
	return s.all_star.has("selected") and not done(s)


static func done(s: Season) -> bool:
	return s.all_star.has("selected") and not (s.all_star["game"] as Array).is_empty() and derby_over(s)


static func derby_over(s: Season) -> bool:
	var field: Array = s.all_star.get("field", [])
	return (s.all_star.get("derby", {}) as Dictionary).size() >= field.size()


## His men among the picked.
static func of_my_club(s: Season) -> Array[String]:
	var out: Array[String] = []
	var team: Team = s.teams.get(s.my_team)
	for id: Variant in s.all_star.get("selected", []):
		if team != null and team.player(str(id)) != null:
			out.append(str(id))
	return out


## His hitter in the derby ("" none).
static func my_derby_man(s: Season) -> String:
	var team: Team = s.teams.get(s.my_team)
	for id: Variant in s.all_star.get("field", []):
		if team != null and team.player(str(id)) != null:
			return str(id)
	return ""


## The two teams (청팀, 백팀: AllStar.TEAM_COLOURS).
static func teams(s: Season) -> Array[Team]:
	var selected: Array[String] = []
	selected.assign(s.all_star.get("selected", []))
	var out := AllStar.teams(s, 0, selected, null)
	for i: int in out.size():
		out[i].stadium = s.teams[s.divisions[0][0]].stadium
		for p: Player in out[i].players:
			out[i].registered.append(p.id)
	return out


## The side his men play for (the one with more of them; home when even).
static func my_side(s: Season) -> int:
	var mine := of_my_club(s)
	var sides := teams(s)
	var count := [0, 0]
	for i: int in 2:
		for p: Player in sides[i].players:
			if mine.has(p.id):
				count[i] += 1
	return 0 if count[0] > count[1] else 1


## The game settled at once.
static func quick_game(s: Season) -> void:
	var sides := teams(s)
	var sim := GameSim.create(sides[0], sides[1], RuleSet.kbo_2026(), s.env, s.catalog, s.ovr, s.rng.fork(hash("all_star:%d" % s.season_year)))
	sim.play()
	s.all_star["game"] = [sim.state.score[0], sim.state.score[1], false]


## The game he played himself: its score, and what it paid him.
static func played_game(s: Season, away_runs: int, home_runs: int, level: int) -> PackedStringArray:
	s.all_star["game"] = [away_runs, home_runs, true]
	var won := (away_runs > home_runs) == (my_side(s) == 0) and away_runs != home_runs
	var pay := roundi((GAME_WIN if won else GAME_LOSS) * Difficulty.reward(level, "points"))
	Profile.earn(pay)
	var line := "올스타전 %s +%dP" % ["승리" if won else "출전", pay]
	(s.all_star["paid"] as Array).append(line)
	return PackedStringArray([line])


## The derby's turns settled at once (his hitter's too unless he swung himself).
static func quick_derby(s: Season) -> void:
	var derby: Dictionary = s.all_star["derby"]
	var rng := s.rng.fork(hash("derby:%d" % s.season_year))
	for id: Variant in s.all_star.get("field", []):
		if derby.has(str(id)):
			continue
		var p := _find(s, str(id))
		derby[str(id)] = AllStar.derby_swings(p.batting.power() if p != null else 50.0, DERBY_OUTS, rng)
	var mine := my_derby_man(s)
	if mine != "" and winner(s) == mine and not s.all_star.get("swung", false):
		Profile.earn(DERBY_WIN_QUICK)
		(s.all_star["paid"] as Array).append("홈런 더비 우승 +%dP" % DERBY_WIN_QUICK)


## His hitter's turn swung himself: the rest settled, and what it paid.
static func swung_derby(s: Season, home_runs: int, level: int) -> PackedStringArray:
	var mine := my_derby_man(s)
	if mine == "":
		return PackedStringArray()
	s.all_star["swung"] = true
	(s.all_star["derby"] as Dictionary)[mine] = home_runs
	quick_derby(s)
	var lines := PackedStringArray()
	var pay := roundi(DERBY_PER_HOME_RUN * home_runs * Difficulty.reward(level, "points"))
	if winner(s) == mine:
		pay += roundi(DERBY_WIN * Difficulty.reward(level, "points"))
		lines.append("홈런 더비 우승!")
	if pay > 0:
		Profile.earn(pay)
		lines.append("홈런 더비 홈런 %d개 +%dP" % [home_runs, pay])
		(s.all_star["paid"] as Array).append(lines[lines.size() - 1])
	return lines


## The derby's winner (most home runs; the first of the field on a tie).
static func winner(s: Season) -> String:
	var best := ""
	var most := -1
	for id: Variant in s.all_star.get("field", []):
		var hr := int((s.all_star["derby"] as Dictionary).get(str(id), -1))
		if hr > most:
			most = hr
			best = str(id)
	return best


## Everything at once (days skipped through the break).
static func settle(s: Season) -> void:
	if not s.all_star.has("selected"):
		hold(s)
	if (s.all_star["game"] as Array).is_empty():
		quick_game(s)
	if not derby_over(s):
		quick_derby(s)


static func _find(s: Season, id: String) -> Player:
	for t: Team in s.teams.values():
		var p := t.player(id)
		if p != null:
			return p
	return null
