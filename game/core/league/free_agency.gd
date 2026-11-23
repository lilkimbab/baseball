class_name FreeAgency
extends RefCounted
## Contracts and free agency as the KBO has them (the user, 2026-11-23: "the computer's players
## move as free agents too — grades, compensation players and the salary cap"). Every local
## player has a contract (Player.salary, contract_years, service, fa_count): signed year by year
## until his seasons on the first team reach FIRST_FA, then a free agent who hears offers from
## the clubs; a deal of several years with a signing bonus, and NEXT_FA seasons later a free
## agent again. Each winter (offseason): the seasons are counted, the deals run down, the men
## signed year by year are paid again by how good they are, and the free agents go to market.
##
## The market (resolve): the most valued first; each club bids when he would be an upgrade where
## it needs one and its payroll has room under the salary cap; his own club too, and he goes
## where the deal is best (a little loyalty to his own). A club that loses an A or B grade free
## agent takes a compensation player from the one that signed him, outside its protected men.
## Foreign players are signed year by year and are never free agents (and, as in the KBO, not
## counted under the cap). Money is in 10,000 won, as everywhere in the game.
##
## The numbers marked A are assumptions measured against recent KBO deals (tools: balance in
## tests/core/league/test_free_agency.gd).

const MINIMUM := 3000
## The salary cap (the KBO's 경쟁균형세 line, by year: 137억 1,165만 in 2025, then 5% more each
## year to 2028), on the annual values of a club's CAP_PLAYERS best-paid local men. A club over
## it pays OVER_TAX of what is over; the computer's clubs keep under it.
const CAPS := {2025: 1371165, 2026: 1439723, 2027: 1511709, 2028: 1587294}
const CAP := 1439723
const OVER_TAX := 0.3
const CAP_PLAYERS := 40
## Seasons for free agency: the first time (from high school; seven from college, not made), and
## again after a deal.
const FIRST_FA := 8
const NEXT_FA := 4
## Grades as the KBO sets them, by last salary's rank in his club and in the league (the men in
## a free agent's deal left out of the ranking): A — his club's top CLUB_A and the league's top
## GRADE_A; B — his club's top CLUB_B or the league's top GRADE_B; C — the rest, and every new
## free agent of VETERAN_C or older, and a third free agency. The club that loses an A or B man
## takes a player outside the signing club's PROTECT men and COMPENSATION times his last salary;
## a C man brings money only.
const CLUB_A := 3
const CLUB_B := 10
const GRADE_A := 30
const GRADE_B := 60
const VETERAN_C := 35
const PROTECT := {"A": 20, "B": 25}
const COMPENSATION := {"A": 2.0, "B": 1.0, "C": 1.5}
## The most outside free agents one club signs in a winter.
const SIGN_MOST := 2
## What staying with his own club is worth to a free agent, against the money (A: about half of
## the KBO's free agents re-sign).
const LOYALTY := 1.15


# --- What a man is worth ---


## Where a man stands among the league's first-team local men, in standard deviations of their
## overalls (a pack of the past or a stronger fictional league is priced alike: by standing, not
## by the number). Kept per season until `forget`.
static var _refs: Dictionary = {}


static func standing(p: Player, season: Season) -> float:
	var key := season.get_instance_id()
	if not _refs.has(key):
		var sum := 0.0
		var squares := 0.0
		var n := 0
		for id: String in season.teams:
			var team: Team = season.teams[id]
			for q: Player in team.players:
				if q.origin == &"" and team.is_registered(q.id):
					var v := ClubRules.player_ovr(q, season.ovr, season.catalog)
					sum += v
					squares += v * v
					n += 1
		var mean := sum / maxf(n, 1.0)
		_refs[key] = Vector2(mean, sqrt(maxf(squares / maxf(n, 1.0) - mean * mean, 1.0)))
	var ref: Vector2 = _refs[key]
	return (ClubRules.player_ovr(p, season.ovr, season.catalog) - ref.x) / ref.y


static func forget(season: Season) -> void:
	_refs.erase(season.get_instance_id())


## A free agent's annual value by his standing (A, measured against recent KBO deals: a regular
## half a deviation up about 2억 3,000만 a year, one and a half up about 8억, the league's very
## best 25억 at most — 4년 100억 with the bonus; less from 32 on).
static func market_value(z: float, age: int) -> int:
	var v := 3000.0 * exp(2.0 + 1.25 * z)
	if age >= 32:
		v *= maxf(1.0 - 0.09 * float(age - 31), 0.35)
	return clampi(roundi(v / 100.0) * 100, MINIMUM, 250000)


## How many years a club offers him: four for the best, fewer for the rest and the old; six for a
## young star.
static func market_years(z: float, age: int) -> int:
	var y := 1
	if z >= 1.8:
		y = 4
	elif z >= 1.0:
		y = 3
	elif z >= 0.3:
		y = 2
	if z >= 2.4 and age <= 29:
		y = 6
	if age >= 35:
		y = 1
	elif age >= 33:
		y = mini(y, 2)
	return y


## A deal as it is announced: [years, signing bonus, annual salary], the bonus a bigger share of
## a bigger deal.
static func terms(aav: int, years: int) -> Array:
	years = maxi(years, 1)
	var total := aav * years
	var share := clampf(0.2 + 0.05 * years, 0.2, 0.45) if aav >= 10000 else 0.15
	var bonus := roundi(total * share / 1000.0) * 1000
	var annual := maxi(roundi(float(total - bonus) / years / 100.0) * 100, MINIMUM)
	return [years, bonus, annual]


static func total_of(deal: Array) -> int:
	return int(deal[1]) + int(deal[2]) * int(deal[0])


## "4년 총액 80억 원 (계약금 30억 · 연봉 12억 5,000만)".
static func deal_text(deal: Array) -> String:
	return "%d년 총액 %s 원 (계약금 %s · 연봉 %s)" % [int(deal[0]), money(total_of(deal)), money(int(deal[1])), money(int(deal[2]))]


## Money without the "원": "80억", "12억 5,000만", "3,000만".
static func money(man: int) -> String:
	var eok := man / 10000
	var rest := man % 10000
	var r := _grouped(rest)
	if eok > 0 and rest > 0:
		return "%s억 %s만" % [_grouped(eok), r]
	if eok > 0:
		return "%s억" % _grouped(eok)
	return "%s만" % r


static func _grouped(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


## A man signed year by year before free agency: a share of what he would be worth on the market,
## more with each season counted — half of it by the eighth (A: the KBO's young stars before
## free agency earn a third to a half of what they sign for after it).
static func reserve_salary(z: float, service: int) -> int:
	var share := clampf(0.15 + 0.05 * float(service), 0.15, 0.55)
	return maxi(MINIMUM, roundi(market_value(z, 27) * share / 100.0) * 100)


static func shown_of(p: Player, season: Season) -> float:
	return RatingScale.shown(ClubRules.player_ovr(p, season.ovr, season.catalog))


# --- Contracts ---


## Every man without a contract (from a roster pack) gets one fitting his age and play: how many
## seasons he would have counted (a bench man fewer), what free agency he has been through, the
## deal he is in.
static func ensure(season: Season) -> void:
	forget(season)
	for id: String in season.teams:
		for p: Player in (season.teams[id] as Team).players:
			if p.salary <= 0:
				_first_contract(p, season)


static func _first_contract(p: Player, season: Season) -> void:
	var age := season.season_year - p.born
	var z := standing(p, season)
	var jitter := absi(hash(p.id + ":contract")) % 3 - 1
	if p.origin != &"":
		p.salary = maxi(market_value(z, age), 30000)
		return
	var quality := clampf(0.85 + 0.2 * z, 0.5, 1.0)
	var seasons := clampi(roundi(float(age - 20) * quality) + jitter, 0, 18)
	if seasons <= FIRST_FA:
		p.fa_count = 0
		p.service = seasons
	else:
		var after := seasons - FIRST_FA
		p.fa_count = 1 + (after - 1) / NEXT_FA
		p.service = after - NEXT_FA * (p.fa_count - 1)
	p.contract_years = 0
	if p.fa_count > 0:
		var years := market_years(z, age - p.service)
		p.contract_years = maxi(years - p.service, 0)
		p.salary = market_value(z, age - p.service) if p.contract_years > 0 else roundi(market_value(z, age) * 0.9 / 100.0) * 100
	else:
		p.salary = reserve_salary(z, p.service)
	p.salary = maxi(p.salary, MINIMUM)


## A free agent this winter: a local man out of contract with his seasons counted.
static func eligible(p: Player) -> bool:
	return p.origin == &"" and p.contract_years <= 0 and p.service >= (FIRST_FA if p.fa_count == 0 else NEXT_FA)


## What a club pays its CAP_PLAYERS best-paid local men (the cap's measure).
static func payroll(team: Team, leaving: String = "") -> int:
	var pays: Array[int] = []
	for p: Player in team.players:
		if p.origin == &"" and p.id != leaving:
			pays.append(p.salary)
	pays.sort()
	pays.reverse()
	var sum := 0
	for i: int in mini(pays.size(), CAP_PLAYERS):
		sum += pays[i]
	return sum


static func room(team: Team, leaving: String = "") -> int:
	return CAP - payroll(team, leaving)


## The season gone counted for each man (a season on the first team, or one he played much of:
## as the KBO's 145 registered days), the deals a year shorter, and the men signed year by year
## paid again (not the career's own man: CareerContract).
static func count_season(season: Season, skip_id: String = "") -> void:
	var share := clampf(float(season.games_per_team) / 144.0, 0.1, 1.0)
	for id: String in season.teams:
		var team: Team = season.teams[id]
		for p: Player in team.players:
			if p.id == skip_id or p.origin != &"":
				continue
			var bat: BattingLine = season.book.batting.get(p.id)
			var pitch: PitchingLine = season.book.pitching.get(p.id)
			var pa := bat.pa if bat != null else 0
			var outs := pitch.outs if pitch != null else 0
			var played := pa >= roundi(150 * share) or outs >= roundi(120 * share) or (team.is_registered(p.id) and (pa >= roundi(30 * share) or outs >= roundi(30 * share)))
			if played:
				p.service += 1
			if p.contract_years > 0:
				p.contract_years -= 1
				continue
			if eligible(p):
				continue
			var z := standing(p, season)
			var target := reserve_salary(z, p.service) if p.fa_count == 0 else roundi(market_value(z, season.season_year + 1 - p.born) * 0.9)
			var next := lerpf(float(p.salary), float(target), 0.6)
			p.salary = maxi(MINIMUM, roundi(clampf(next, p.salary * 0.75, p.salary * 2.5) / 100.0) * 100)


## The grade of each free agent (A, B or C).
static func grades(season: Season, free_agents: Array[Player]) -> Dictionary:
	var ranked := func(men: Array[Player]) -> Array[int]:
		var pays: Array[int] = []
		for q: Player in men:
			# (The men in a free agent's deal are not ranked.)
			if q.origin == &"" and not (q.fa_count > 0 and q.contract_years > 0):
				pays.append(q.salary)
		pays.sort()
		pays.reverse()
		return pays
	var everyone: Array[Player] = []
	for id: String in season.teams:
		everyone.append_array((season.teams[id] as Team).players)
	var league: Array[int] = ranked.call(everyone)
	var out := {}
	for p: Player in free_agents:
		var club: Team = season.teams.get(club_of(season, p))
		var own: Array[int] = ranked.call(club.players if club != null else [p] as Array[Player])
		var in_league := league.find(p.salary) + 1
		var in_club := own.find(p.salary) + 1
		var g := "C"
		if in_club <= CLUB_A and in_league <= GRADE_A:
			g = "A"
		elif in_club <= CLUB_B or in_league <= GRADE_B:
			g = "B"
		if (p.fa_count == 0 and season.season_year + 1 - p.born >= VETERAN_C) or p.fa_count >= 2:
			g = "C"
		out[p.id] = g
	return out


# --- The market ---


## A signing of the winter.
class Signing:
	var player: Player
	var from := ""
	var to := ""
	var grade := "C"
	var deal: Array = []
	## What the club he left got from the one that signed him: a player ("" none) and money
	## (COMPENSATION times his last salary).
	var compensation := ""
	var compensation_money := 0


## The winter's market: the season counted (count_season), the free agents to market, each to
## the club with the best deal. `skip_id`: the career's own man (CareerContract has his).
## `bids` (player id → [years, bonus, annual]) are a person's club's offers (`human_club`, which
## makes no other).
static func offseason(season: Season, rng: Rng, skip_id: String = "", human_club: String = "", bids: Dictionary = {}) -> Array[Signing]:
	ensure(season)
	forget(season)
	count_season(season, skip_id)
	return resolve(season, market(season, skip_id), rng, skip_id, human_club, bids)


## The free agents who go to market (a man worth no more than he is paid stays where he is).
static func market(season: Season, skip_id: String = "") -> Array[Player]:
	var out: Array[Player] = []
	for id: String in season.teams:
		for p: Player in (season.teams[id] as Team).players:
			if p.id == skip_id or not eligible(p):
				continue
			var age := season.season_year + 1 - p.born
			var z := standing(p, season)
			# (As in the KBO, a man files when the market pays him clearly more, or he is wanted;
			# one who does not keeps his right for another winter.)
			if age >= 38 or (market_value(z, age) < p.salary * 1.3 and z < 0.4):
				continue
			out.append(p)
	out.sort_custom(func(a: Player, b: Player) -> bool: return standing(a, season) > standing(b, season))
	return out


static func club_of(season: Season, p: Player) -> String:
	for id: String in season.teams:
		if (season.teams[id] as Team).players.has(p):
			return id
	return ""


## How much better he would make a club where he plays (his overall against the man he would
## replace: the fifth starter, the sixth reliever, the third outfielder, the regular elsewhere).
static func need(season: Season, team: Team, p: Player) -> float:
	var mine := ClubRules.player_ovr(p, season.ovr, season.catalog)
	var same: Array[float] = []
	for q: Player in team.players:
		if q == p or q.is_pitcher() != p.is_pitcher():
			continue
		if p.is_pitcher():
			if q.role() == p.role():
				same.append(ClubRules.player_ovr(q, season.ovr, season.catalog))
		elif (p.primary_position() in Position.OUTFIELD and q.primary_position() in Position.OUTFIELD) or q.primary_position() == p.primary_position():
			same.append(ClubRules.player_ovr(q, season.ovr, season.catalog))
	same.sort()
	same.reverse()
	var slot := 1
	if p.is_pitcher():
		slot = 5 if p.role() == &"SP" else 6
	elif p.primary_position() in Position.OUTFIELD:
		slot = 3
	if same.size() < slot:
		return mine - 40.0
	return mine - same[slot - 1]


static func resolve(season: Season, free_agents: Array[Player], rng: Rng, skip_id: String = "", human_club: String = "", bids: Dictionary = {}) -> Array[Signing]:
	var graded := grades(season, free_agents)
	var signed_by: Dictionary = {}
	var moved: Array[String] = []
	var out: Array[Signing] = []
	for p: Player in free_agents:
		var from := club_of(season, p)
		var age := season.season_year + 1 - p.born
		var z := standing(p, season)
		var ask := market_value(z, age)
		var years := market_years(z, age)
		var offers: Array = []
		for id: String in season.teams:
			var team: Team = season.teams[id]
			var own := id == from
			if id == human_club:
				if bids.has(p.id):
					offers.append([id, bids[p.id]])
				continue
			if not own and int(signed_by.get(id, 0)) >= SIGN_MOST:
				continue
			var gain := need(season, team, p)
			# His own club wants back a man it plays (or a star); another one where he is an upgrade.
			var keen := (gain > -3.0 or z >= 1.0) if own else gain > 1.5
			if not keen:
				continue
			var space := room(team, p.id if own else "")
			var aav := float(ask) * (0.9 + 0.03 * clampf(gain, 0.0, 5.0) + rng.next_float() * 0.1)
			if own:
				aav = float(ask) * (1.0 + rng.next_float() * 0.15)
			if space < aav * 0.9:
				continue
			aav = minf(aav, float(space))
			var y := clampi(years + (rng.next_int(3) - 1 if rng.chance(0.25) else 0), 1, mini(years + 1, 6 if age <= 29 else (4 if age <= 32 else 2)))
			offers.append([id, terms(roundi(aav / 100.0) * 100, y)])
		var best: Array = []
		var best_value := -1.0
		for o: Array in offers:
			# (Most stay: a club he knows, a town he lives in.)
			var value := float(total_of(o[1])) * (LOYALTY if str(o[0]) == from else 1.0) * (1.0 + rng.next_float() * 0.06)
			if value > best_value:
				best_value = value
				best = o
		var s := Signing.new()
		s.player = p
		s.from = from
		s.grade = str(graded.get(p.id, "C"))
		if best.is_empty():
			# Nobody bid: his own club keeps him a year for less.
			s.to = from
			s.deal = terms(roundi(ask * 0.7 / 100.0) * 100, 1)
		else:
			s.to = str(best[0])
			s.deal = best[1]
		_sign(season, s, skip_id, moved, rng)
		if s.to != s.from:
			signed_by[s.to] = int(signed_by.get(s.to, 0)) + 1
		out.append(s)
	return out


## The deal made: he moves (a free number found), his contract set, and an A or B grade free
## agent's old club takes its compensation player.
static func _sign(season: Season, s: Signing, skip_id: String, moved: Array[String], rng: Rng) -> void:
	var p := s.player
	var last := p.salary
	p.salary = roundi(float(total_of(s.deal)) / int(s.deal[0]) / 100.0) * 100
	p.contract_years = int(s.deal[0])
	p.fa_count += 1
	p.service = 0
	if s.to == s.from:
		return
	_move(season, p, s.from, s.to, rng)
	moved.append(p.id)
	s.compensation_money = roundi(last * float(COMPENSATION[s.grade]) / 100.0) * 100
	s.compensation = compensate(season, s.grade, s.from, s.to, skip_id, moved, rng)


## The compensation player an A or B free agent's old club takes from the club that signed him:
## the best man outside its protected ones (not a foreign player, a free agent signed this
## winter, or a rookie just drafted). His name, or "".
static func compensate(season: Season, grade: String, from: String, to: String, skip_id: String, moved: Array[String], rng: Rng) -> String:
	if not PROTECT.has(grade):
		return ""
	var signing: Team = season.teams[to]
	var men: Array[Player] = []
	for q: Player in signing.players:
		var rookie := q.service == 0 and season.season_year + 1 - q.born <= 20
		if q.origin == &"" and q.id != skip_id and not moved.has(q.id) and not rookie:
			men.append(q)
	men.sort_custom(func(a: Player, b: Player) -> bool: return ClubRules.player_ovr(a, season.ovr, season.catalog) > ClubRules.player_ovr(b, season.ovr, season.catalog))
	var protected_count: int = PROTECT[grade]
	if men.size() <= protected_count:
		return ""
	var pick := men[protected_count]
	_move(season, pick, to, from, rng)
	moved.append(pick.id)
	return pick.name


static func _move(season: Season, p: Player, from: String, to: String, rng: Rng) -> void:
	var a: Team = season.teams[from]
	var b: Team = season.teams[to]
	a.players.erase(p)
	a.registered.erase(p.id)
	var taken: Dictionary = {}
	for q: Player in b.players:
		taken[q.number] = true
	if taken.has(p.number):
		var n := 1 + rng.next_int(98)
		var guard := 0
		while taken.has(n) and guard < 200:
			n = 1 + rng.next_int(98)
			guard += 1
		p.number = n
	b.players.append(p)


## A signing as a line of the winter's news.
static func news(season: Season, s: Signing) -> String:
	var to: Team = season.teams[s.to]
	if s.to == s.from:
		return "FA 잔류: %s (%s등급) %s %s" % [s.player.name, s.grade, to.name, deal_text(s.deal)]
	var from: Team = season.teams[s.from]
	var line := "FA 이적: %s (%s등급) %s → %s %s" % [s.player.name, s.grade, from.name, to.name, deal_text(s.deal)]
	if s.compensation != "":
		line += " · 보상선수 %s, 보상금 %s 원" % [s.compensation, money(s.compensation_money)]
	elif s.compensation_money > 0:
		line += " · 보상금 %s 원" % money(s.compensation_money)
	return line
