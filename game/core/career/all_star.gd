class_name AllStar
extends RefCounted
## The all-star break of the career mode (docs/02 section 6.4, docs/13 S8-8): at mid-season the
## division's twenty-two most voted players are picked (the fans vote by popularity and play;
## the career player's own popularity counts), the two halves of the division's clubs make two
## teams (as the KBO's 드림·나눔), and the season's top home run hitters meet in a derby.
##
## Votes for the computer's players come from their play so far (simple wins above
## replacement); the career player's from his popularity as well (A).

const TEAM_NAMES: Array[String] = ["드림 올스타", "나눔 올스타"]
## The fewest each all-star team needs: hitters (with a catcher) and pitchers.
const HITTERS := 11
const PITCHERS := 8


static func votes(season: Season, d: int, career: CareerPlayer) -> Dictionary[String, float]:
	var awards := SeasonAwards.for_division(season, d, season.season_year)
	var out: Dictionary[String, float] = {}
	for id: String in season.divisions[d]:
		for p: Player in (season.teams[id] as Team).first_team():
			var v := maxf(awards.war(p.id), 0.0) * 10.0
			if career != null and p.id == career.player.id:
				v += career.popularity * 0.6
			out[p.id] = v
	return out


static func select(season: Season, d: int, career: CareerPlayer, count: int) -> Array[String]:
	var v := votes(season, d, career)
	var ids: Array[String] = []
	ids.assign(v.keys())
	ids.sort_custom(func(a: String, b: String) -> bool: return v[a] > v[b])
	return ids.slice(0, count)


## The two teams: the division's first five clubs against the other five, the selected
## players of each half first, then its best by votes to make a full team.
static func teams(season: Season, d: int, selected: Array[String], career: CareerPlayer) -> Array[Team]:
	var v := votes(season, d, career)
	var out: Array[Team] = []
	var clubs := season.divisions[d]
	for half: int in 2:
		var t := Team.new()
		t.id = "all_star_%d" % half
		t.name = TEAM_NAMES[half]
		t.short_name = TEAM_NAMES[half].substr(0, 2)
		var pool: Array[Player] = []
		for i: int in range(half * 5, mini(half * 5 + 5, clubs.size())):
			pool.append_array((season.teams[clubs[i]] as Team).first_team())
		pool.sort_custom(func(a: Player, b: Player) -> bool:
			var sa := 1000.0 if selected.has(a.id) else 0.0
			var sb := 1000.0 if selected.has(b.id) else 0.0
			return sa + float(v.get(a.id, 0.0)) > sb + float(v.get(b.id, 0.0)))
		var hitters := 0
		var pitchers := 0
		var starters := 0
		# A catcher first, then the rest by votes.
		for p: Player in pool:
			if not p.is_pitcher() and p.primary_position() == Position.Kind.C:
				t.players.append(p)
				hitters += 1
				break
		for p: Player in pool:
			if t.players.has(p):
				continue
			if p.is_pitcher() and pitchers < PITCHERS:
				t.players.append(p)
				pitchers += 1
				if p.role() == &"SP":
					starters += 1
			elif not p.is_pitcher() and hitters < HITTERS:
				t.players.append(p)
				hitters += 1
		if starters == 0:
			for p: Player in pool:
				if p.role() == &"SP" and not t.players.has(p):
					t.players.append(p)
					break
		out.append(t)
	return out


## The derby's hitters: the most home runs so far, the career player among them if he was
## picked for the game and hits.
static func derby_field(season: Season, d: int, career: CareerPlayer, selected: Array[String], count: int) -> Array[String]:
	var ids: Array[String] = []
	for id: String in season.divisions[d]:
		for p: Player in (season.teams[id] as Team).first_team():
			if not p.is_pitcher() and season.book.batting.has(p.id):
				ids.append(p.id)
	ids.sort_custom(func(a: String, b: String) -> bool: return season.book.batting[a].home_runs > season.book.batting[b].home_runs)
	var field := ids.slice(0, count)
	if career != null and not career.is_pitcher() and selected.has(career.player.id) and not field.has(career.player.id):
		field[field.size() - 1] = career.player.id
	return field


## Home runs before `outs` outs for a computer hitter: each swing goes out with a chance set by
## his power (A).
static func derby_swings(power: float, outs: int, rng: Rng) -> int:
	var chance := clampf(0.08 + (power - 50.0) * 0.006, 0.03, 0.45)
	var hr := 0
	var made := 0
	var guard := 0
	while made < outs and guard < 200:
		if rng.chance(chance):
			hr += 1
		else:
			made += 1
		guard += 1
	return hr
