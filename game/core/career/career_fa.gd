class_name CareerFA
extends RefCounted
## The career player's free agency, as the KBO runs it and as career modes let a player live it
## (the user, 2026-11-23: "properly, looking at other games if need be"):
##
## - The clock (KBO): eight seasons with three in four of their days on the first team, then a
##   free agent; after a deal, NEXT_FA more. A free agent files or not (not filing, he signs for
##   a year and may file next winter).
## - Before it: a club that values him offers a deal of several years first (비FA 다년계약, as
##   KBO clubs now lock their stars up), a little cheaper for the security; taking it puts free
##   agency off until it ends.
## - The offers: his own club and the clubs that need a man of his place and have room under the
##   salary cap (FreeAgency), the better he is the more of them. Each is a KBO deal — years,
##   signing bonus, salary, an option for a season well played — and says what he would be
##   there (as NBA 2K's free agency weighs the money against the minutes): the regular, one
##   fighting for the place, or behind a better man.
## - Talks (as OOTP's and Football Manager's): asking more, RAISE at a time and ASKS times a
##   club; each club has a limit it will not tell, and pushed past it may say that was its last
##   word or walk away. An agent (EA FC's Player Career has one at the table) gets more out of
##   every club and tells how far each can still go, for AGENT_FEE of the deal.
## - Signed: the salary fixed for the years, the bonus paid at once, the option paid each winter
##   it is met; moving as an A or B grade man, his old club takes a compensation player from his
##   new one.
## Money in 10,000 won.

const RAISE := 0.08
const ASKS := 2
const WALK := 0.3
const AGENT_FEE := 0.03
const AGENT_ROOM := 0.08
## An option: this share of the annual value a year, paid when the season meets its line.
const OPTION_SHARE := 0.1


# --- The clock ---


static func need_seasons(c: CareerPlayer) -> int:
	return c.fa_years if c.fa_count == 0 else FreeAgency.NEXT_FA


## Seasons counted since the clock last started (each with three in four of its days on the
## first team).
static func seasons_counted(c: CareerPlayer, season_days: int) -> int:
	var n := 0
	for i: int in range(mini(c.fa_since, c.first_days.size()), c.first_days.size()):
		if float(c.first_days[i]) / maxi(season_days, 1) >= CareerContract.FA_DAYS_SHARE:
			n += 1
	return n


static func ready(c: CareerPlayer, season_days: int) -> bool:
	return c.contract_years <= 0 and seasons_counted(c, season_days) >= need_seasons(c)


static func age(cs: CareerSeason) -> int:
	return cs.season.season_year + 1 - cs.career.player.born


## What the market makes of him: his standing in the league (FreeAgency), his last season a
## little, and his popularity (a draw at the gate is worth a bit more).
static func asking(cs: CareerSeason) -> int:
	var z := FreeAgency.standing(cs.career.player, cs.season)
	var perf := CareerContract.performance(cs)
	var form := lerpf(0.9, 1.15, clampf((perf - 0.4) / 1.6, 0.0, 1.0))
	var fans := 1.0 + clampf(cs.career.popularity, 0.0, 300.0) / 3000.0
	return roundi(FreeAgency.market_value(z, age(cs)) * form * fans / 100.0) * 100


# --- Before free agency: a deal of several years ---


## His club's offer a winter before he would be a free agent, if it values him: [years, bonus,
## annual], or [].
static func extension_offer(cs: CareerSeason) -> Array:
	var c := cs.career
	if c.contract_years > 0 or c.fa_count > 0:
		return []
	if seasons_counted(c, cs.season.total_days()) != need_seasons(c) - 1:
		return []
	var z := FreeAgency.standing(c.player, cs.season)
	if z < 0.8:
		return []
	var years := clampi(FreeAgency.market_years(z, age(cs)) + 1, 3, 6)
	return FreeAgency.terms(roundi(asking(cs) * 0.88 / 100.0) * 100, years)


static func accept_extension(cs: CareerSeason) -> void:
	var deal := cs.extension
	if deal.is_empty():
		return
	_take(cs, deal, [], "비FA 다년")
	cs.log.append("%d년 비FA 다년계약: %s" % [cs.season.season_year, FreeAgency.deal_text(deal)])
	cs.career.deals.append([cs.season.season_year + 1, "비FA 다년계약 · %s" % FreeAgency.deal_text(deal)])
	CareerLegacy.note(cs.career, cs.season.season_year + 1, "deal", "비FA 다년계약", FreeAgency.deal_text(deal), cs.career.team_id)
	cs.cue(&"contract", "%d 비FA 다년계약" % (cs.season.season_year + 1), "%s 다년계약" % cs.season.teams[cs.career.team_id].name, PackedStringArray([FreeAgency.deal_text(deal)]))
	cs.extension = []


# --- The market ---


## Files for free agency: the offers come in.
static func declare(cs: CareerSeason, rng: Rng) -> void:
	cs.fa_state = "declared"
	cs.fa_offers = market(cs, rng)
	cs.log.append("%d년 겨울: FA 신청 (%s등급) · 제안 %d건" % [cs.season.season_year, cs.fa_grade, cs.fa_offers.size()])


## Does not file: a year's deal at the salary set this winter, free agency again next winter.
static func stay(cs: CareerSeason) -> void:
	cs.fa_state = "stayed"
	cs.log.append("%d년 겨울: FA 미신청, 1년 재계약 (연봉 %s 원)" % [cs.season.season_year, FreeAgency.money(cs.career.salary)])


static func hire_agent(cs: CareerSeason) -> void:
	if cs.agent:
		return
	cs.agent = true
	for o: Dictionary in cs.fa_offers:
		o["limit"] = roundi(int(o["limit"]) * (1.0 + AGENT_ROOM))


## The offers: each {club, years, bonus, annual, option, role, need, limit, asks, status, rank}.
static func market(cs: CareerSeason, rng: Rng) -> Array:
	var c := cs.career
	var s := cs.season
	var z := FreeAgency.standing(c.player, s)
	var ask := asking(cs)
	var years := FreeAgency.market_years(z, age(cs))
	var mine: Array = []
	var others: Array = []
	for id: String in s.divisions[0]:
		var team: Team = s.teams[id]
		var own := id == c.team_id
		var gain := FreeAgency.need(s, team, c.player)
		var room := FreeAgency.room(team, c.player.id if own else "")
		if not own and (gain <= 0.0 or room < ask * 0.7):
			continue
		var aav := float(ask) * ((0.95 + rng.next_float() * 0.08) if own else (0.9 + 0.03 * clampf(gain, 0.0, 5.0) + rng.next_float() * 0.1))
		aav = minf(aav, maxf(float(room), FreeAgency.MINIMUM))
		var flex := (0.12 + clampf(c.popularity, 0.0, 300.0) / 1500.0) if own else (0.05 + 0.03 * clampf(gain, 0.0, 5.0))
		if cs.agent:
			flex += AGENT_ROOM
		var y := clampi(years + (rng.next_int(3) - 1 if rng.chance(0.3) else 0), 1, 6)
		var deal := FreeAgency.terms(roundi(aav / 100.0) * 100, y)
		var offer := {"club": id, "years": int(deal[0]), "bonus": int(deal[1]), "annual": int(deal[2]),
			"option": option_for(c, aav) if z >= 0.3 else [], "role": role_text(gain), "need": gain,
			"limit": roundi(minf(aav * (1.0 + flex), maxf(float(room), aav)) / 100.0) * 100, "asks": ASKS, "status": "",
			"rank": s.standings[0].rank_of(id) if not s.standings.is_empty() else 0}
		if own:
			mine.append(offer)
		else:
			others.append(offer)
	others.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["need"]) > float(b["need"]))
	var wanted := clampi(roundi(1.0 + 1.5 * z), 0, 6)
	var out: Array = mine + others.slice(0, wanted)
	if out.is_empty():
		var deal := FreeAgency.terms(maxi(roundi(ask * 0.8 / 100.0) * 100, FreeAgency.MINIMUM), 1)
		out.append({"club": c.team_id, "years": 1, "bonus": int(deal[1]), "annual": int(deal[2]), "option": [], "role": role_text(0.0), "need": 0.0, "limit": int(deal[2]), "asks": 0, "status": "", "rank": 0})
	return out


## The clubs the papers would call interested before he files: those that need a man of his
## place and have the room for him (as `market` asks), the keenest first.
static func interested(cs: CareerSeason) -> Array[String]:
	var c := cs.career
	var s := cs.season
	var ask := asking(cs)
	var keen: Array = []
	for id: String in s.divisions[0]:
		if id == c.team_id:
			continue
		var team: Team = s.teams[id]
		var gain := FreeAgency.need(s, team, c.player)
		if gain > 0.0 and FreeAgency.room(team) >= ask * 0.7:
			keen.append([id, gain])
	keen.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	var out: Array[String] = []
	for k: Array in keen.slice(0, clampi(roundi(1.0 + 1.5 * FreeAgency.standing(c.player, s)), 0, 6)):
		out.append(str(k[0]))
	return out


static func deal_of(o: Dictionary) -> Array:
	return [int(o["years"]), int(o["bonus"]), int(o["annual"])]


static func value_of(o: Dictionary) -> int:
	return roundi(float(FreeAgency.total_of(deal_of(o))) / int(o["years"]))


## Asks a club for more. What it says.
static func ask_more(cs: CareerSeason, index: int, rng: Rng) -> String:
	if index < 0 or index >= cs.fa_offers.size():
		return ""
	var o: Dictionary = cs.fa_offers[index]
	var club: Team = cs.season.teams[str(o["club"])]
	if str(o["status"]) != "" or int(o["asks"]) <= 0:
		return "%s 측과는 더 이상 협상할 수 없습니다." % club.name
	o["asks"] = int(o["asks"]) - 1
	var want := roundi(value_of(o) * (1.0 + RAISE) / 100.0) * 100
	if want <= int(o["limit"]):
		var deal := FreeAgency.terms(want, int(o["years"]))
		o["bonus"] = int(deal[1])
		o["annual"] = int(deal[2])
		if not (o["option"] as Array).is_empty():
			o["option"] = option_for(cs.career, want)
		return "%s에서 수정 제안이 왔습니다: %s" % [club.name, FreeAgency.deal_text(deal_of(o))]
	if rng.chance(WALK):
		o["status"] = "withdrawn"
		return "%s 측이 협상 테이블을 떠났습니다." % club.name
	o["asks"] = 0
	o["status"] = "final"
	return "%s 측은 지금 조건이 최종 제안이라는 입장입니다." % club.name


## How far a club can still go, as his agent reads it ("" without one).
static func room_word(cs: CareerSeason, o: Dictionary) -> String:
	if not cs.agent or str(o["status"]) != "":
		return ""
	var left := float(o["limit"]) / maxf(value_of(o), 1.0) - 1.0
	if left >= 0.12:
		return "협상 여지 큼"
	if left >= 0.05:
		return "협상 여지 있음"
	return "협상 여지 거의 없음"


## What he would be at a club: the regular, one fighting for the place, or behind a better man.
static func role_text(gain: float) -> String:
	if gain >= 2.0:
		return "주전 보장"
	if gain >= -1.0:
		return "주전 경쟁"
	return "백업 역할"


# --- Options ---


## An option for a season well played: [money a year, kind] — a hitter's qualifying plate
## appearances with an OPS of .850, a starter's qualifying innings with an ERA of 3.50, a
## reliever's 55 games (by a 144-game season) with an ERA of 3.20.
static func option_for(c: CareerPlayer, aav: float) -> Array:
	var kind := "hitter"
	if c.is_pitcher():
		kind = "starter" if c.player.role() == &"SP" else "reliever"
	return [maxi(roundi(aav * OPTION_SHARE / 100.0) * 100, 1000), kind]


static func option_text(option: Array) -> String:
	if option.is_empty():
		return ""
	var line := {"hitter": "규정타석·OPS .850", "starter": "규정이닝·평균자책점 3.50", "reliever": "55경기·평균자책점 3.20"}
	return "옵션: %s 달성 시 연 %s 원" % [str(line.get(str(option[1]), "")), FreeAgency.money(int(option[0]))]


static func option_met(cs: CareerSeason, option: Array) -> bool:
	if option.is_empty():
		return false
	var id := cs.career.player.id
	var games := maxi(cs.season.games_per_team, 1)
	match str(option[1]):
		"hitter":
			var b: BattingLine = cs.season.book.batting.get(id)
			return b != null and b.pa >= roundi(games * 3.1) and b.ops() >= 0.85
		"starter":
			var q: PitchingLine = cs.season.book.pitching.get(id)
			return q != null and q.outs >= games * 3 and q.era() <= 3.5
		_:
			var q: PitchingLine = cs.season.book.pitching.get(id)
			return q != null and q.games >= roundi(55.0 * games / 144.0) and q.era() <= 3.2
	return false


# --- Signing ---


## Signs with a club's offer (the next season begins with it: CareerSession.next_season). The
## agent's fee comes off the bonus. Returns the offer, or {} if there is none for that club.
static func sign(cs: CareerSeason, club_id: String) -> Dictionary:
	for o: Dictionary in cs.fa_offers:
		if str(o["club"]) == club_id and str(o["status"]) != "withdrawn":
			var deal := deal_of(o)
			_take(cs, deal, o["option"], "FA")
			var c := cs.career
			c.fa_count += 1
			c.fa_since = c.first_days.size()
			c.free_agent_done = true
			var club: Team = cs.season.teams[club_id]
			var what := "FA %s" % ("잔류" if club_id == c.team_id else "이적")
			c.deals.append([cs.season.season_year + 1, "%s · %s %s" % [what, club.name, FreeAgency.deal_text(deal)]])
			CareerLegacy.note(c, cs.season.season_year + 1, "deal", "%s · %s" % [what, club.name], FreeAgency.deal_text(deal), club_id)
			if cs.agent:
				var fee := roundi(FreeAgency.total_of(deal) * AGENT_FEE / 100.0) * 100
				c.money -= fee
				cs.log.append("에이전트 수수료 %s 원 지급" % FreeAgency.money(fee))
			return o
	return {}


static func _take(cs: CareerSeason, deal: Array, option: Array, kind: String) -> void:
	var c := cs.career
	c.contract_years = int(deal[0])
	c.contract_length = int(deal[0])
	c.contract_bonus = int(deal[1])
	c.contract_total = FreeAgency.total_of(deal)
	c.contract_option = option.duplicate()
	c.contract_kind = kind
	c.salary = int(deal[2])
	c.best_salary = maxi(c.best_salary, c.salary)
	c.player.salary = roundi(float(c.contract_total) / c.contract_years / 100.0) * 100
	c.money += int(deal[1])
	c.earned += int(deal[1])


## His deal in a line for the screens: "FA 4년 계약 2년째 · 4년 총액 80억 (…)", or the year's.
static func contract_line(c: CareerPlayer) -> String:
	if c.contract_years > 0:
		return "%s %d년 계약 · %d년 남음 · 총액 %s 원" % [c.contract_kind, c.contract_length, c.contract_years, FreeAgency.money(c.contract_total)]
	return "1년 계약 · 연봉 %s 원" % FreeAgency.money(c.salary)
