class_name Draft
extends RefCounted
## The KBO's draft of new players (신인 드래프트; docs/08 R8-3), the day a high-school career
## becomes a pro one. Since 2023 one draft for the whole country: ten clubs, eleven rounds, each
## round in the same order, the weakest club of the last season first (here: the clubs by their
## strength, weakest first). Clubs cannot be chosen: he goes where he is picked.
##
## The pool: the third-year students of his league with this year's numbers, and the rest of
## the country's prospects (high-school and college) made up around them. Each club takes the
## best man left by its scouts' reckoning: his ability now, what he may become, how his season
## went, and the scouts' error (SCOUT_ERROR). Not picked in the eleven rounds, he is offered a
## contract as a developmental player (육성선수) by a club.
##
## The bonus (계약금, in 10,000 won) by round, as clubs paid in 2024 and 2025: the first pick
## of the first round about 5억, the rest of the first round 2억 to 3억, the second round about
## 1억, then down to the 3,000만 of the late rounds (BONUS).

const ROUNDS := 11
## Prospects from the rest of the country, besides his league's third-year students.
const OTHERS := 150
## How far off a club's reckoning of a prospect is (points).
const SCOUT_ERROR := 4.0
## His season's weight: so many points for an OPS of .300 above his league's, or an ERA two
## runs below it.
const SEASON_WEIGHT := 6.0
## Bonus by round (10,000 won); the first pick of all.
const BONUS: Array[int] = [25000, 11000, 8000, 6500, 5500, 4500, 4000, 3500, 3000, 3000, 3000]
const FIRST_PICK_BONUS := 50000
const DEVELOPMENTAL_BONUS := 1000
## Where the country's other prospects come from (a third are from college).
const COLLEGE_SHARE := 0.3


class Pick:
	var round := 0
	## 1..10 within the round.
	var number := 0
	## 1..110 overall.
	var overall := 0
	var team_id := ""
	var name := ""
	var school := ""
	var position := ""
	var value := 0.0
	var mine := false
	var bonus := 0


class Prospect:
	var name := ""
	var school := ""
	var position := ""
	var value := 0.0
	var mine := false


var picks: Array[Pick] = []
## His pick (null: not drafted).
var his: Pick
## Not drafted: the club offering a developmental contract.
var developmental_team := ""
var order: PackedStringArray = []
var year := 0


## The draft of the year his high-school season ends (`school_season`), for the league's clubs.
static func run(c: CareerPlayer, school_season: Season, clubs: Array[Team], seed_value: int) -> Draft:
	var d := Draft.new()
	d.year = school_season.season_year
	var rng := Rng.new(seed_value)
	# The order: the weakest club first, every round the same.
	var ranked := clubs.duplicate()
	ranked.sort_custom(func(a: Team, b: Team) -> bool: return _strength(a, school_season) < _strength(b, school_season))
	for t: Team in ranked:
		d.order.append(t.id)
	var pool := _pool(c, school_season, rng)
	var overall := 0
	for r: int in ROUNDS:
		for i: int in d.order.size():
			if pool.is_empty():
				break
			# Each club's own reckoning of the best man left: the scouts' error club by club.
			var best := 0
			var best_seen := -INF
			for k: int in mini(pool.size(), 12):
				var seen := (pool[k] as Prospect).value + rng.next_normal() * SCOUT_ERROR * 0.5
				if seen > best_seen:
					best_seen = seen
					best = k
			var chosen: Prospect = pool[best]
			pool.remove_at(best)
			overall += 1
			var p := Pick.new()
			p.round = r + 1
			p.number = i + 1
			p.overall = overall
			p.team_id = d.order[i]
			p.name = chosen.name
			p.school = chosen.school
			p.position = chosen.position
			p.value = chosen.value
			p.mine = chosen.mine
			p.bonus = FIRST_PICK_BONUS if overall == 1 else BONUS[r]
			# Within a round the earlier picks are paid a little more.
			if overall > 1:
				p.bonus = roundi(p.bonus * lerpf(1.15, 0.9, float(i) / maxf(d.order.size() - 1, 1.0)) / 100.0) * 100
			d.picks.append(p)
			if p.mine:
				d.his = p
	if d.his == null and not d.order.is_empty():
		d.developmental_team = d.order[rng.next_int(d.order.size())]
	return d


## The bonus he signs for (10,000 won).
func bonus() -> int:
	return his.bonus if his != null else DEVELOPMENTAL_BONUS


## The club he goes to.
func team_id() -> String:
	return his.team_id if his != null else developmental_team


static func _strength(t: Team, s: Season) -> float:
	var total := 0.0
	var n := 0
	for p: Player in t.first_team():
		total += ClubRules.player_ovr(p, s.ovr, s.catalog)
		n += 1
	return total / maxf(n, 1.0)


## Everyone up for the draft, best first by the clubs' common reckoning.
static func _pool(c: CareerPlayer, s: Season, rng: Rng) -> Array:
	var pool: Array = []
	var league := _league_rates(s)
	for team_id: String in s.teams:
		var team: Team = s.teams[team_id]
		for p: Player in team.players:
			if s.season_year - p.born < 18:
				continue
			var pr := Prospect.new()
			pr.name = p.name
			pr.school = team.name
			pr.position = String(p.role()) if p.is_pitcher() else Position.code(p.primary_position())
			pr.mine = p.id == c.player.id
			pr.value = value_of(p, s, league) + rng.next_normal() * SCOUT_ERROR
			pool.append(pr)
	# The rest of the country.
	var names := RosterIO.load_names()
	var gen := LeagueGenerator.new(names, s.catalog, hash("draft_pool:%d" % s.season_year))
	var others := SchoolLeague.schools().filter(func(e: Dictionary) -> bool: return not s.teams.has(str(e["id"])))
	var talent := float(SchoolLeague.data().get("talent", 37.0))
	for i: int in OTHERS:
		var college := rng.chance(COLLEGE_SHARE)
		var roles: Array[String] = ["SP", "RP", "C", "1B", "2B", "SS", "3B", "LF", "CF", "RF"]
		var role := roles[rng.next_int(roles.size())]
		var p := gen.player(role, talent + (6.0 if college else 0.0) + rng.next_normal() * 3.0)
		p.born = s.season_year - (22 if college else 18)
		p.potential = Development.initial_room(22 if college else 18, rng, true)
		var pr := Prospect.new()
		pr.name = p.name
		pr.school = "대학 졸업 예정" if college or others.is_empty() else str((others[rng.next_int(others.size())] as Dictionary)["name"])
		pr.position = role
		pr.value = ClubRules.player_ovr(p, s.ovr, s.catalog) + p.potential * 0.8 + rng.next_normal() * SCOUT_ERROR
		pool.append(pr)
	pool.sort_custom(func(a: Prospect, b: Prospect) -> bool: return a.value > b.value)
	return pool


## How the clubs rate one of his league's students: his ability now, what he may become (a
## career player grows by his own points: a drafted student's room), and how his season went.
static func value_of(p: Player, s: Season, league: Vector2) -> float:
	var room := p.potential if p.potential >= 0.0 and not p.id.begins_with("career_") else Development.initial_room(18, Rng.new(1), true)
	var v := ClubRules.player_ovr(p, s.ovr, s.catalog) + room * 0.8
	var bat: BattingLine = s.book.batting.get(p.id)
	var pitch: PitchingLine = s.book.pitching.get(p.id)
	if p.is_pitcher() and pitch != null and pitch.outs >= 15:
		v += clampf((league.y - pitch.era()) / 2.0, -1.0, 1.5) * SEASON_WEIGHT
	elif not p.is_pitcher() and bat != null and bat.pa >= 20:
		v += clampf((bat.ops() - league.x) / 0.3, -1.0, 1.5) * SEASON_WEIGHT
	return v


## The league's OPS and ERA this season.
static func _league_rates(s: Season) -> Vector2:
	var bat := BattingLine.new()
	var pitch := PitchingLine.new()
	for id: String in s.book.batting:
		bat.add(s.book.batting[id])
	for id: String in s.book.pitching:
		pitch.add(s.book.pitching[id])
	# Too few games to tell (before the season, or a test's few lines): a high-school league's
	# usual rates.
	return Vector2(bat.ops() if bat.pa >= 300 else 0.7, pitch.era() if pitch.outs >= 300 else 4.5)


## Money as the KBO's papers write it: 10,000 won units into 억 and 만.
static func money_text(man: int) -> String:
	var eok := man / 10000
	var rest := man % 10000
	if eok > 0 and rest > 0:
		return "%d억 %d만 원" % [eok, rest]
	if eok > 0:
		return "%d억 원" % eok
	return "%d만 원" % man


func to_dict() -> Dictionary:
	var list: Array = []
	for p: Pick in picks:
		list.append({"round": p.round, "number": p.number, "overall": p.overall, "team": p.team_id, "name": p.name, "school": p.school, "position": p.position, "mine": p.mine, "bonus": p.bonus})
	return {"year": year, "order": Array(order), "picks": list, "developmental": developmental_team}
