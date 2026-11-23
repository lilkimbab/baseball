class_name CareerContract
extends RefCounted
## A pro career's money and its winters (the user, 2026-11-23: "contract
## money, trades and free agency as the KBO has them; a long stay in the second team brings a
## pay cut or a release").
##
## His salary (10,000 won) starts at the KBO's minimum (3,000만 since 2024) and is set again
## each winter by how much of the season he was on the first team and how he played there
## (renew). Paid through the season, day by day (pay_day). Free agency after FA_YEARS seasons
## counted for it: a season counts when he was on the first team at least FA_DAYS_SHARE of the
## days (the KBO asks 145 registered days of a 144-game season, about three in four). A free
## agent hears offers from several clubs and chooses (the one choice of club a player has).
## Released: two seasons running almost all in the second team (RELEASE_SHARE) from the age
## RELEASE_AGE; another club signs him at the minimum.

const MINIMUM := 3000
## Of a season's days on the first team: for an FA season, and too few (a release warning).
const FA_DAYS_SHARE := 0.75
const RELEASE_SHARE := 0.1
const RELEASE_AGE := 24
## A salary moves by at most this much in a winter (down, up).
const CUT_MOST := 0.25
const RAISE_MOST := 2.5
## FA offers: years and money a year by how good he is.
const FA_OFFERS := 3
## A course of lessons for a new pitch at a pitching academy (10,000 won).
const LESSON_PRICE := 1500
## A title of the season (batting average, home runs, runs batted in, stolen bases; wins, ERA,
## strikeouts, saves): its prize (10,000 won).
const TITLE_PRIZE := 1000


## A new pitch learned with lessons paid for out of his money.
static func lesson(cs: CareerSeason, id: StringName) -> bool:
	var c := cs.career
	if c.money < LESSON_PRICE or not PitchEvolution.learnable(c, cs.rules).has(id):
		return false
	if not PitchEvolution.learn(c, id, cs.rules, cs.season.catalog, true):
		return false
	c.money -= LESSON_PRICE
	cs.log.append("%d일: 구종 레슨 — %s 습득" % [cs.season.day + 1, String(id)])
	return true


## The titles he won this season (the league's leaders among the qualified), as their names.
static func titles(cs: CareerSeason) -> PackedStringArray:
	var s := cs.season
	var id := cs.career.player.id
	var out := PackedStringArray()
	var games := maxi(s.games_per_team, 1)
	if cs.career.is_pitcher():
		var boards := {"다승": func(q: PitchingLine) -> float: return q.wins, "탈삼진": func(q: PitchingLine) -> float: return q.strikeouts, "세이브": func(q: PitchingLine) -> float: return q.saves}
		for title: String in boards:
			if _leads_pitching(s, id, boards[title], 0):
				out.append(title)
		if _leads_pitching(s, id, func(q: PitchingLine) -> float: return -q.era(), games * 3):
			out.append("평균자책점")
	else:
		var boards := {"홈런": func(b: BattingLine) -> float: return b.home_runs, "타점": func(b: BattingLine) -> float: return b.rbi, "도루": func(b: BattingLine) -> float: return b.stolen_bases}
		for title: String in boards:
			if _leads_batting(s, id, boards[title], 0):
				out.append(title)
		if _leads_batting(s, id, func(b: BattingLine) -> float: return b.average(), roundi(games * 3.1)):
			out.append("타율")
	return out


static func _leads_batting(s: Season, id: String, score: Callable, min_pa: int) -> bool:
	var mine: BattingLine = s.book.batting.get(id)
	if mine == null or mine.pa < maxi(min_pa, 1) or float(score.call(mine)) <= 0.0:
		return false
	for other: String in s.book.batting:
		var b: BattingLine = s.book.batting[other]
		if other != id and b.pa >= min_pa and float(score.call(b)) > float(score.call(mine)):
			return false
	return true


static func _leads_pitching(s: Season, id: String, score: Callable, min_outs: int) -> bool:
	var mine: PitchingLine = s.book.pitching.get(id)
	if mine == null or mine.outs < maxi(min_outs, 1):
		return false
	if min_outs == 0 and float(score.call(mine)) <= 0.0:
		return false
	for other: String in s.book.pitching:
		var q: PitchingLine = s.book.pitching[other]
		if other != id and q.outs >= min_outs and float(score.call(q)) > float(score.call(mine)):
			return false
	return true


## His share of this season's regular-season days on the first team.
static func first_share(cs: CareerSeason) -> float:
	var days := maxi(cs.season.total_days(), 1)
	return clampf(float(cs.first_team_days) / days, 0.0, 1.0)


## How he played on the first team this season: 1 average, up to 2 for a star, down to 0.4.
static func performance(cs: CareerSeason) -> float:
	var id := cs.career.player.id
	if cs.career.is_pitcher():
		var q: PitchingLine = cs.season.book.pitching.get(id)
		if q == null or q.outs < 30:
			return 0.8
		return clampf(1.0 + (4.6 - q.era()) / 3.0, 0.4, 2.0)
	var b: BattingLine = cs.season.book.batting.get(id)
	if b == null or b.pa < 60:
		return 0.8
	return clampf(1.0 + (b.ops() - 0.72) / 0.2, 0.4, 2.0)


## Next year's salary (10,000 won, rounded to a million).
static func renewed(c: CareerPlayer, share: float, perf: float) -> int:
	var factor := 0.8 + share * perf * 0.9
	if share < RELEASE_SHARE * 3.0:
		# Mostly in the second team: a cut.
		factor = minf(factor, 0.9)
	factor = clampf(factor, 1.0 - CUT_MOST, RAISE_MOST)
	return maxi(MINIMUM, roundi(c.salary * factor / 100.0) * 100)


## A day of the regular season: a day's pay.
static func pay_day(cs: CareerSeason) -> void:
	var days := maxi(cs.season.total_days(), 1)
	cs.salary_paid += float(cs.career.salary) / days
	var whole := int(cs.salary_paid)
	if whole > 0:
		cs.career.money += whole
		cs.career.earned += whole
		cs.salary_paid -= whole


## The winter's business for him: the season into his record, the FA clock, released or not,
## his new salary. Returns the lines to tell him (and his career log).
static func winter(cs: CareerSeason, rng: Rng) -> PackedStringArray:
	var c := cs.career
	var lines := PackedStringArray()
	var share := first_share(cs)
	var perf := performance(cs)
	var team: Team = cs.season.teams[c.team_id]
	c.pro_years += 1
	c.first_days.append(cs.first_team_days)
	var id := c.player.id
	var empty_bat := BattingLine.new()
	var empty_pitch := PitchingLine.new()
	c.seasons.append([cs.season.season_year, team.name, cs.first_team_days, season_line(cs),
		SaveIO.fields(cs.season.book.batting.get(id, empty_bat)), SaveIO.fields(cs.season.book.pitching.get(id, empty_pitch)),
		SaveIO.fields(cs.futures_book.batting.get(id, empty_bat)), SaveIO.fields(cs.futures_book.pitching.get(id, empty_pitch))])
	# The season's games into his career's log.
	for entry: Variant in cs.season.game_logs.get(id, []):
		c.game_log.append([cs.season.season_year] + (entry as Array))
	var age := cs.season.season_year + 1 - c.player.born
	cs.last_salary = c.salary
	# A deal of several years (CareerFA): a year of it gone, its option paid when the season met
	# its line; the club cannot let him go while it runs.
	var under := c.contract_years > 0
	if under:
		c.contract_years -= 1
		if CareerFA.option_met(cs, c.contract_option):
			var paid := int(c.contract_option[0])
			c.money += paid
			c.earned += paid
			lines.append("옵션 달성: 보너스 %s 원 지급" % FreeAgency.money(paid))
	# Released: two seasons running almost all in the second team.
	var recent := c.first_days.slice(maxi(c.first_days.size() - 2, 0))
	var low := recent.size() == 2 and recent.all(func(d: int) -> bool: return float(d) / maxi(cs.season.total_days(), 1) < RELEASE_SHARE)
	if low and age >= RELEASE_AGE and not under:
		lines.append("방출: %s이(가) 재계약하지 않았습니다." % team.name)
		c.salary = MINIMUM
		c.released = true
		return lines
	# A title's prize, and a title is worth more at the table.
	var won := titles(cs)
	for title: String in won:
		c.money += TITLE_PRIZE
		c.earned += TITLE_PRIZE
		lines.append("%s 타이틀 (상금 %s 원)" % [title, FreeAgency.money(TITLE_PRIZE)])
	if not won.is_empty():
		perf = minf(perf + 0.3 * won.size(), 2.5)
	if c.contract_years > 0:
		lines.append("%s 계약 %d년 남음 · 연봉 %s 원 (계약 기간 동안 고정)" % [c.contract_kind, c.contract_years, FreeAgency.money(c.salary)])
		return lines
	if under:
		lines.append("%s 계약이 만료되어 올겨울부터 매년 연봉 협상을 합니다." % c.contract_kind)
		c.contract_kind = ""
		c.contract_option = []
	var before := c.salary
	c.salary = renewed(c, share, perf)
	c.best_salary = maxi(c.best_salary, c.salary)
	if c.salary > before:
		lines.append("연봉 인상: %s → %s 원" % [FreeAgency.money(before), FreeAgency.money(c.salary)])
	elif c.salary < before:
		lines.append("연봉 삭감: %s → %s 원%s" % [FreeAgency.money(before), FreeAgency.money(c.salary), " (2군에 오래 있었습니다)" if share < RELEASE_SHARE * 3.0 else ""])
	else:
		lines.append("연봉 동결: %s 원" % FreeAgency.money(c.salary))
	if CareerFA.ready(c, cs.season.total_days()):
		lines.append("FA 자격을 취득했습니다%s." % ("" if c.fa_count == 0 else " (%d번째)" % (c.fa_count + 1)))
	return lines


## Seasons counted for free agency since the clock last started (CareerFA).
static func fa_seasons(c: CareerPlayer, season_days: int) -> int:
	return CareerFA.seasons_counted(c, season_days)


static func fa_ready(c: CareerPlayer, season_days: int) -> bool:
	return CareerFA.ready(c, season_days)


## His first-team totals over the seasons gone (and the one on, if given): batting, pitching.
static func totals(c: CareerPlayer, current: CareerSeason = null) -> Array:
	var bat := BattingLine.new()
	var pitch := PitchingLine.new()
	for row: Array in c.seasons:
		if row.size() >= 6:
			var b := BattingLine.new()
			SaveIO.fill(b, row[4])
			bat.add(b)
			var q := PitchingLine.new()
			SaveIO.fill(q, row[5])
			pitch.add(q)
	if current != null and not current.season.school:
		var id := c.player.id
		if current.season.book.batting.has(id):
			bat.add(current.season.book.batting[id])
		if current.season.book.pitching.has(id):
			pitch.add(current.season.book.pitching[id])
	return [bat, pitch]


## His season in a line for the record (first team, or the second team's).
static func season_line(cs: CareerSeason) -> String:
	var id := cs.career.player.id
	var book: StatBook = cs.season.book
	var where := "1군"
	if cs.first_team_days == 0:
		book = cs.futures_book
		where = "2군"
	if cs.career.is_pitcher():
		var q: PitchingLine = book.pitching.get(id)
		return "%s %s이닝 평균자책점 %.2f" % [where, q.innings_text(), q.era()] if q != null and q.outs > 0 else "%s 기록 없음" % where
	var b: BattingLine = book.batting.get(id)
	return "%s %d타석 타율 %s 홈런 %d OPS %s" % [where, b.pa, BattingLine.rate_text(b.average()), b.home_runs, BattingLine.rate_text(b.ops())] if b != null and b.pa > 0 else "%s 기록 없음" % where
