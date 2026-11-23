class_name AllStar
extends RefCounted
## The all-star break of the career mode: at mid-season the
## division's twenty-two most voted players are picked (the fans vote by popularity and play;
## the career player's own popularity counts), the two halves of the division's clubs make two
## teams, 청팀 in blue and 백팀 in white (the user, 2026-11-23), and the season's top home run
## hitters meet in a derby. The fans' vote is announced as a show of its own (AllStarVote: each
## team's best twelve, `board`).
##
## Votes for the computer's players come from their play so far (simple wins above
## replacement); the career player's from his popularity as well (A).

const TEAM_NAMES: Array[String] = ["청팀 올스타", "백팀 올스타"]
## 청팀 blue (its road jerseys in it), 백팀 white (home whites with slate trim): primary,
## secondary, accent.
const TEAM_COLOURS: Array = [[Color("#1f4e9c"), Color("#f2f2f2"), Color("#7fb2ff")], [Color("#4a5260"), Color("#f2f2f2"), Color("#d9dee5")]]
## The fans' best twelve of each team, as the KBO's ballot has them.
const SLOTS: Array = [["선발투수", "SP"], ["중간투수", "RP"], ["마무리투수", "RP"], ["포수", "C"], ["1루수", "1B"], ["2루수", "2B"], ["3루수", "3B"], ["유격수", "SS"], ["외야수", "OF"], ["외야수", "OF"], ["외야수", "OF"], ["지명타자", "DH"]]
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
		t.primary = TEAM_COLOURS[half][0]
		t.secondary = TEAM_COLOURS[half][1]
		t.accent = TEAM_COLOURS[half][2]
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


## The fans' vote as it is announced: each team's best twelve (SLOTS), one line each —
## "side|slot|name|club id|votes|mine" (mine 1 for the career player or the managed club's
## man, voted in). Votes are shown as a ballot's counts, from the same votes that picked them.
static func board(season: Season, d: int, selected: Array[String], career: CareerPlayer, my_club: String = "") -> PackedStringArray:
	var v := votes(season, d, career)
	var sides := teams(season, d, selected, career)
	var out := PackedStringArray()
	for half: int in sides.size():
		var pool: Array[Player] = []
		for p: Player in sides[half].players:
			pool.append(p)
		# The voted-in first (a place nobody voted for is filled from the rest, as the manager's
		# pick), each by his votes.
		pool.sort_custom(func(a: Player, b: Player) -> bool:
			var sa := 1e6 if selected.has(a.id) else 0.0
			var sb := 1e6 if selected.has(b.id) else 0.0
			return sa + float(v.get(a.id, 0.0)) > sb + float(v.get(b.id, 0.0)))
		var used: Array[String] = []
		for slot: Array in SLOTS:
			var pick: Player = null
			for p: Player in pool:
				if used.has(p.id) or not _fits(p, str(slot[1])):
					continue
				pick = p
				break
			if pick == null:
				# (Nobody of that place: the best of the kind left.)
				for p: Player in pool:
					if not used.has(p.id) and p.is_pitcher() == (str(slot[1]) in ["SP", "RP"]):
						pick = p
						break
			if pick == null:
				continue
			used.append(pick.id)
			var club_id := ""
			for id: String in season.divisions[d]:
				if (season.teams[id] as Team).player(pick.id) != null:
					club_id = id
			var mine := selected.has(pick.id) and ((career != null and pick.id == career.player.id) or (my_club != "" and club_id == my_club))
			out.append("%d|%s|%s|%s|%d|%d" % [half, str(slot[0]), pick.name, club_id, ballot(float(v.get(pick.id, 0.0)), pick.id), 1 if mine else 0])
	return out


## A vote (play and popularity) as a ballot's count: a few hundred thousand, the stars past a
## million, the same each time for the same man.
static func ballot(vote: float, id: String) -> int:
	var spread := float(hash(id) % 1000) / 1000.0
	return roundi(180000.0 + maxf(vote, 0.0) * 14000.0 + spread * 60000.0)


static func _fits(p: Player, slot: String) -> bool:
	match slot:
		"SP":
			return p.role() == &"SP"
		"RP":
			return p.is_pitcher() and p.role() == &"RP"
		"OF":
			return not p.is_pitcher() and p.primary_position() in Position.OUTFIELD
		"DH":
			return not p.is_pitcher()
		_:
			return not p.is_pitcher() and Position.code(p.primary_position()) == slot
