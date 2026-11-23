class_name Development
extends RefCounted
## How players change from year to year in the league (IDEAS 12): the young grow
## toward a peak they were born with, the old lose a little every winter, the oldest retire,
## and their places go to rookies drafted into the second team.
##
## A player's `potential` is the room left between him and his peak, in rating points on his
## main ratings (a hitter's contact, power, eye and fielding; a pitcher's control and his
## pitches). It is hidden; scouts see it as stars. Growth comes during the season, game day
## by game day, a share of the room each year — larger for the young, and slower for a man
## who did not play that day. Decline comes in the winter from 31 on, harder on legs, power
## and arm than on the eye and the hands.
##
## The numbers keep a league in balance over the years (tests/core/league/test_development.gd:
## the first teams' average stays put over ten winters): what the young gain and the rookies
## bring is what the old lose and take with them.

## Share of his room a man realises over a season of regular play, by age (A: by 27 most of
## it is used).
const GROWTH_SHARE: Array[Vector2] = [Vector2(21, 0.3), Vector2(24, 0.38), Vector2(27, 0.5), Vector2(99, 0.7)]
## A man who did not play that day grows at this share of the pace.
const BENCH_PACE := 0.45
## A pitcher's room turns into fewer rating points than a hitter's (his overall answers more
## to each, and more of the pitchers are young): so that hitting and pitching stay level over
## the years (measured: tests/core/league/test_development.gd).
const PITCHER_PACE := 0.6
## Players already in a pack were drawn with their age in their ratings; they get this share
## of the room a rookie of their age would have.
const PACK_ROOM := 0.6
## A young man's room when he is first given one: on average this much plus PER_YEAR for each
## year he is under 24, spread SPREAD; 25 to 27: a little; older: none.
const ROOM_BASE := 4.0
const ROOM_PER_YEAR := 1.6
const ROOM_SPREAD := 3.0
## Drafted rookies were picked for their upside.
const DRAFT_UPSIDE := 2.0
const DRAFT_FLOOR := 1.0
## Winter decline from DECLINE_FROM: BASE plus SLOPE a year past it, in rating points;
## physical ratings take more of it, skills less.
const DECLINE_FROM := 31
const DECLINE_BASE := 0.6
const DECLINE_SLOPE := 0.35
const PHYSICAL := 1.3
const SKILL := 0.7
## Retirement in the winter: from RETIRE_FROM, this chance a year past 32; regulars of the
## first team hold on longer. Nobody plays past RETIRE_ALL.
const RETIRE_FROM := 33
const RETIRE_PER_YEAR := 0.15
const REGULAR_HOLDS := 0.6
const RETIRE_ALL := 40
## Rookies: ages 19 to 22, drafted at second-team level.
const ROOKIE_AGES := Vector2i(19, 22)

const HITTER_GROWTH: PackedStringArray = ["contact", "power", "eye", "range", "hands", "arm"]
const PITCHER_GROWTH: PackedStringArray = ["control", "command", "movement", "velocity"]


## What a winter did to a league: who retired, who came in, who grew most.
class Winter:
	var year := 0
	## [team id, player name, age, role] of each man who retired.
	var retired: Array = []
	## [team id, player id] of each rookie drafted, in the order they were picked.
	var rookies: Array = []
	## [team id, player id, points gained over the season] of the ten who grew most.
	var risers: Array = []
	## The free agency's news, a line each (FreeAgency.news).
	var free_agents := PackedStringArray()


static func by_age(table: Array[Vector2], age: int) -> float:
	for row: Vector2 in table:
		if age <= int(row.x):
			return row.y
	return table[table.size() - 1].y


## Room for a man of this age who has none yet. Rookies (drafted) get a little more.
static func initial_room(age: int, rng: Rng, drafted: bool = false) -> float:
	var room := 0.0
	if age <= 24:
		room = ROOM_BASE + ROOM_PER_YEAR * (24 - age) + rng.next_normal() * ROOM_SPREAD
	elif age <= 27:
		room = 1.5 + rng.next_normal() * 1.5
	if drafted:
		room += DRAFT_UPSIDE
		# A club drafts a man for what he may become: never one with nothing left to gain
		# (three deviations low, one rookie in a few hundred had none).
		return maxf(room, DRAFT_FLOOR)
	return maxf(room, 0.0)


## Gives every player of a league who has no room yet his room (from his id, so the same pack
## gets the same rooms every time).
static func give_rooms(teams: Array, year: int) -> void:
	for team: Team in teams:
		for p: Player in team.players:
			if p.potential >= 0.0:
				continue
			# A career player grows by his own points (an old career save has none set).
			if p.id.begins_with("career_"):
				p.potential = 0.0
			else:
				p.potential = initial_room(year - p.born, Rng.new(hash("room:" + p.id))) * PACK_ROOM


## One game day's growth: `played` when he played in a game today (first or second team).
## Returns the rating points gained.
static func grow_day(p: Player, age: int, played: bool, games_per_team: int) -> float:
	if p.potential <= 0.0:
		return 0.0
	var step := p.potential * by_age(GROWTH_SHARE, age) / maxf(games_per_team, 1.0)
	if not played:
		step *= BENCH_PACE
	step = minf(step, p.potential)
	Training.grow(p, PITCHER_GROWTH if p.is_pitcher() else HITTER_GROWTH, step * (PITCHER_PACE if p.is_pitcher() else 1.0))
	p.potential -= step
	return step


## The winter's decline for a man of this age (the age he will be next season).
## `scale`: less for a man who paid for his conditioning (the career's own: CareerSeason).
static func decline(p: Player, age: int, scale: float = 1.0) -> float:
	if age < DECLINE_FROM:
		return 0.0
	var amount := (DECLINE_BASE + DECLINE_SLOPE * (age - DECLINE_FROM)) * scale
	var hard := amount * PHYSICAL
	var soft := amount * SKILL
	var down := func(v: float, by: float) -> float: return maxf(v - by, 1.0)
	p.batting.power_r = down.call(p.batting.power_r, hard)
	p.batting.power_l = down.call(p.batting.power_l, hard)
	p.batting.speed = down.call(p.batting.speed, hard)
	p.batting.baserunning = down.call(p.batting.baserunning, amount)
	p.fielding.range = down.call(p.fielding.range, hard)
	p.fielding.arm = down.call(p.fielding.arm, hard)
	p.batting.contact_r = down.call(p.batting.contact_r, soft)
	p.batting.contact_l = down.call(p.batting.contact_l, soft)
	p.fielding.hands = down.call(p.fielding.hands, soft)
	if p.pitching != null:
		p.pitching.control = down.call(p.pitching.control, soft)
		p.pitching.stamina = down.call(p.pitching.stamina, amount)
		for a: ArsenalPitch in p.pitching.arsenal:
			a.movement = down.call(a.movement, hard)
			a.command = down.call(a.command, soft)
			a.velo_avg -= hard * 0.2
			a.velo_max -= hard * 0.2
	return amount


## Whether a man of this age retires this winter.
static func retires(age: int, regular: bool, rng: Rng) -> bool:
	if age >= RETIRE_ALL:
		return true
	if age < RETIRE_FROM:
		return false
	var chance := RETIRE_PER_YEAR * (age - 32) * (REGULAR_HOLDS if regular else 1.0)
	return rng.chance(chance)


## Whether a man was one of his club's regulars this season (they hold on longer).
static func regular(season: Season, p: Player) -> bool:
	if p.is_pitcher():
		var l: PitchingLine = season.book.pitching.get(p.id)
		return l != null and l.outs >= season.games_per_team
	var b: BattingLine = season.book.batting.get(p.id)
	return b != null and b.pa >= 2 * season.games_per_team


## The winter after `season`: the oldest retire (a foreign player's place goes to a new foreign
## player, the others' to drafted rookies in the second team), everyone left a year older and
## the old a little worse, the first teams filled back up, and the computer clubs bring up
## the second-team men who are now better. Returns what happened, for the report.
static func winter(season: Season) -> Winter:
	var w := Winter.new()
	w.year = season.season_year + 1
	var rng := season.rng.fork(hash("winter:%d" % w.year))
	var names := RosterIO.load_names()
	var team_ids: Array = season.teams.keys()
	team_ids.sort()
	# The season's ten biggest risers, for the report.
	var risers: Array = []
	for team_id: String in team_ids:
		for p: Player in (season.teams[team_id] as Team).players:
			if season.grown.has(p.id):
				risers.append([team_id, p.id, float(season.grown[p.id])])
	risers.sort_custom(func(a: Array, b: Array) -> bool: return float(a[2]) > float(b[2]))
	w.risers = risers.slice(0, 10)
	# The retirements: a foreign player's place goes to a new foreign player signed at once; a
	# local man's to a rookie from the draft (below).
	var places: Dictionary[String, Array] = {}
	var numbers_of: Dictionary[String, Dictionary] = {}
	for team_id: String in team_ids:
		var team: Team = season.teams[team_id]
		var d := maxi(season.division_of(team_id), 0)
		var mean := LeagueGenerator.DIVISION_MEANS[mini(d, LeagueGenerator.DIVISION_MEANS.size() - 1)]
		var gen := LeagueGenerator.new(names, season.catalog, hash("draft:%d:%s" % [w.year, team_id]))
		var leaving: Array[Player] = []
		for p: Player in team.players:
			# (A career's own player retires when the person says so.)
			if p.id == season.career_player:
				continue
			if retires(w.year - p.born, regular(season, p), rng):
				leaving.append(p)
		var numbers: Dictionary[int, bool] = {}
		for p: Player in team.players:
			numbers[p.number] = true
		numbers_of[team_id] = numbers
		places[team_id] = []
		for p: Player in leaving:
			var was_first := team.is_registered(p.id)
			w.retired.append([team_id, p.name, w.year - p.born, RosterMoves.kind_of(p)])
			take_off(season, team, p)
			var role := role_of(p)
			if p.origin != &"":
				var newcomer := gen.player(role, mean, p.origin)
				newcomer.born += w.year - 2026
				newcomer.potential = 0.0
				newcomer.id = "r%d_%s_%d" % [w.year, team_id, w.rookies.size()]
				newcomer.number = _free_number(newcomer, numbers, rng)
				team.players.append(newcomer)
				if was_first and not team.registered.is_empty():
					team.registered.append(newcomer.id)
				w.rookies.append([team_id, newcomer.id])
			else:
				(places[team_id] as Array).append(role)
	_draft(season, w, places, numbers_of, names, rng)
	for team_id: String in team_ids:
		var team: Team = season.teams[team_id]
		for p: Player in team.players:
			decline(p, w.year - p.born, float(season.decline_scales.get(p.id, 1.0)))
		RosterMoves.refill(season, team)
		if team_id != season.my_team or season.career_player != "":
			for m: RosterMoves.Move in RosterMoves.advice(season, team, true):
				if season.career_player != "" and ((m.up != null and m.up.id == season.career_player) or (m.down != null and m.down.id == season.career_player)):
					continue
				RosterMoves.apply(season, team, m)
	season.grown.clear()
	return w


## The rookie draft (the user, 2026-11-23: the league's rookies through a draft, as the career's
## own player comes in): a class of the year's prospects, as many as there are local places to
## fill, picked round by round in the reverse order of the season's table (the worst club
## first; a lower division after a higher one's clubs), each club taking the best it sees —
## its scouts are not exact — and a man for a place it has to fill over a slightly better one.
## Each pick comes in as a second-team rookie, aged 19 to 22, with room to grow.
static func _draft(season: Season, w: Winter, places: Dictionary[String, Array], numbers_of: Dictionary[String, Dictionary], names: NameTable, rng: Rng) -> void:
	var gen := LeagueGenerator.new(names, season.catalog, hash("draft class:%d" % w.year))
	var pool: Array[Player] = []
	for team_id: String in places:
		var d := maxi(season.division_of(team_id), 0)
		var mean := LeagueGenerator.DIVISION_MEANS[mini(d, LeagueGenerator.DIVISION_MEANS.size() - 1)]
		for role: String in places[team_id]:
			var rookie := gen.player(role, mean - LeagueGenerator.FARM_GAP, &"", true)
			var age := rng.next_int_range(ROOKIE_AGES.x, ROOKIE_AGES.y)
			rookie.born = w.year - age
			rookie.potential = initial_room(age, rng, true)
			pool.append(rookie)
	var value: Dictionary[Player, float] = {}
	for p: Player in pool:
		value[p] = ClubRules.player_ovr(p, season.ovr, season.catalog) + 0.5 * p.potential
	var order := draft_order(season)
	var guard := 0
	while not pool.is_empty() and guard < 1000:
		guard += 1
		for team_id: String in order:
			var needs: Array = places.get(team_id, [])
			if needs.is_empty() or pool.is_empty():
				continue
			var best: Player = null
			var best_score := -INF
			for p: Player in pool:
				var fits := needs.has(role_of(p))
				var score := value[p] + (3.0 if fits else 0.0) + rng.next_normal() * 2.0
				if score > best_score:
					best_score = score
					best = p
			pool.erase(best)
			var filled := needs.find(role_of(best))
			needs.remove_at(filled if filled >= 0 else 0)
			var team: Team = season.teams[team_id]
			best.id = "r%d_%s_%d" % [w.year, team_id, w.rookies.size()]
			best.number = _free_number(best, numbers_of[team_id] as Dictionary[int, bool], rng)
			team.players.append(best)
			w.rookies.append([team_id, best.id])


## The draft's order: the clubs from the bottom of the season's table up, a lower division's
## after a higher one's.
static func draft_order(season: Season) -> PackedStringArray:
	var out := PackedStringArray()
	for d: int in season.divisions.size():
		var ranked := season.standings[d].ranked() if d < season.standings.size() else []
		var ids := PackedStringArray()
		for row: StandingsRow in ranked:
			ids.append(row.team_id)
		for id: String in season.divisions[d]:
			if not ids.has(id):
				ids.append(id)
		ids.reverse()
		out.append_array(ids)
	return out


## The role a man's place is filled with ("SP", "RP", or his positions as the generator names
## them, e.g. "2B/SS").
static func role_of(p: Player) -> String:
	if p.is_pitcher():
		return String(p.role())
	return Position.code(p.primary_position())


## Takes a man off his club for good: the lists, the plans, the player's club's records (a
## trait he had goes back into the bag).
static func take_off(season: Season, team: Team, p: Player) -> void:
	team.players.erase(p)
	var i := team.registered.find(p.id)
	if i >= 0:
		team.registered.remove_at(i)
	team.removed_on.erase(p.id)
	if team.rotation_plan.has(p.id):
		team.rotation_plan.remove_at(team.rotation_plan.find(p.id))
	for entry: Variant in team.batting_plan:
		if str((entry as Array)[0]) == p.id:
			team.batting_plan = []
			break
	var c: Club = season.clubs.get(team.id)
	if c != null:
		if c.traits.has(p.id):
			c.bag.append(c.traits[p.id])
			c.traits.erase(p.id)
		c.training.erase(p.id)
		c.homegrown.erase(p.id)


static func _free_number(p: Player, taken: Dictionary[int, bool], rng: Rng) -> int:
	for attempt: int in 100:
		var n := rng.next_int_range(11, 69) if p.is_pitcher() else rng.next_int_range(1, 66)
		if not taken.has(n):
			taken[n] = true
			return n
	for n: int in range(1, 100):
		if not taken.has(n):
			taken[n] = true
			return n
	return 99


## What a club's scouts make of a man's room, as stars (0 to 5): his room seen through an
## error that shrinks as the scouting improves (level 1 to 3), the same for him every time.
static func stars(p: Player, scout_level: int = 1) -> int:
	var room := maxf(p.potential, 0.0)
	var noise := Rng.new(hash("stars:" + p.id)).next_normal() * 2.5 / clampf(scout_level, 1.0, 3.0)
	var seen := room + noise
	for i: int in STAR_STEPS.size():
		if seen < STAR_STEPS[i]:
			return i
	return STAR_STEPS.size()


## Room (as seen) where each star begins.
const STAR_STEPS: Array[float] = [1.0, 3.0, 6.0, 9.0, 12.0]


static func stars_text(n: int) -> String:
	return "★".repeat(n) + "☆".repeat(5 - n)
