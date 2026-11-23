class_name CareerLegacy
extends RefCounted
## A career's story and its end (the user, 2026-11-23: "after retiring — a look back, the
## ceremony, the settling up"). As NBA 2K's MyCAREER closes with a jersey retired and MLB The
## Show's with the Hall of Fame, and as KBO clubs see their stars off:
##
## - The moments kept as they happen (`note`): the draft, the first call-up, milestones, titles,
##   all-star selections, championships, deals, trades. The farewell begins with them as a
##   flashback (CareerFlashback), the best of them in order.
## - The farewell tour (KBO, 이승엽 2017): a veteran announces his last season; each club he
##   visits on the road gives him a gift (`tour_gift`).
## - The settling up (`settle`): his grade from his career (its numbers against the hall of
##   fame's marks, his honours), a reward in the shop's points by it, and his number retired by
##   his last club when he spent long there and was one of its greats (rare, as the KBO's are).

const KIND_NAMES := {"draft": "드래프트", "debut": "첫 1군", "milestone": "기념구", "title": "타이틀", "all_star": "올스타", "deal": "계약", "champion": "우승", "trade": "이적", "tour": "은퇴 투어"}
## The flashback's length at most, and its order of preference when there are more.
const FLASHBACK_MOST := 10
const PRIORITY := {"draft": 0, "debut": 1, "champion": 2, "title": 3, "deal": 4, "all_star": 5, "milestone": 6, "trade": 7, "tour": 8}
## Grades by score (the career against the marks; 1.0 is a hall of famer's numbers): name, the
## shop's points paid once.
const GRADES: Array = [[2.0, "레전드", 5000], [1.3, "프랜차이즈 스타", 3000], [0.8, "올스타급 선수", 1800], [0.45, "주전 선수", 1000], [0.0, "저니맨", 500]]
## A number retired: this many seasons with his last club, and a hall of famer or a franchise
## star.
const RETIRE_SEASONS := 10
## What the clubs give on a farewell tour.
const GIFTS: Array = ["등번호 기념 액자", "구단 엠블럼 순금 메달", "선수단 사인 배트", "지역 특산 도자기", "감사패와 꽃다발", "기념 현판", "고향 풍경화", "기념 유니폼 액자", "응원단 영상 편지"]


static func note(c: CareerPlayer, year: int, kind: String, title: String, line: String, club_id: String) -> void:
	c.moments.append([year, kind, title, line, club_id])


## The flashback's moments: the best FLASHBACK_MOST, in the order they happened (a career from
## before they were kept: its debut, clubs and commemorative balls).
static func flashback(c: CareerPlayer) -> Array:
	var all: Array = c.moments.duplicate(true)
	if all.is_empty():
		if not c.seasons.is_empty():
			all.append([int(c.seasons[0][0]), "debut", "프로 데뷔", str(c.seasons[0][1]), c.team_id])
		for m: Variant in c.milestones:
			var row: Array = m
			all.append([int(row[1]), "milestone", Milestones.name_of(str(row[0])), "vs %s" % str(row[3]), c.team_id])
	var ranked := all.duplicate()
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return int(PRIORITY.get(str(a[1]), 9)) < int(PRIORITY.get(str(b[1]), 9)))
	var kept := ranked.slice(0, FLASHBACK_MOST)
	kept.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]) if int(a[0]) != int(b[0]) else all.find(a) < all.find(b))
	return kept


## The clubs he played for: [name, first year, last year], in order.
static func clubs(c: CareerPlayer) -> Array:
	var out: Array = []
	for row: Variant in c.seasons:
		var r: Array = row
		if out.is_empty() or str((out[-1] as Array)[0]) != str(r[1]):
			out.append([str(r[1]), int(r[0]), int(r[0])])
		else:
			(out[-1] as Array)[2] = int(r[0])
	return out


## Seasons with the club he ends with.
static func seasons_with_last_club(c: CareerPlayer, club_name: String) -> int:
	var n := 0
	for row: Variant in c.seasons:
		if str((row as Array)[1]) == club_name:
			n += 1
	return n


## His career against a hall of famer's numbers (1.0), with his honours on top.
static func score(c: CareerPlayer, bat: BattingLine, pitch: PitchingLine, games: int, in_hall: bool) -> float:
	var k := HallOfFame.scale(c, games)
	var base := 0.0
	if c.is_pitcher():
		base = maxf(maxf(pitch.wins / (150.0 * k), pitch.saves / (250.0 * k)), pitch.strikeouts / (2000.0 * k))
	else:
		base = maxf(bat.hits / (2000.0 * k), bat.home_runs / (300.0 * k))
	base += 0.3 * clampf(c.pro_years / 15.0, 0.0, 1.0)
	base += 0.12 * c.titles_won.size() + 0.06 * c.all_stars + 0.08 * c.championships.size()
	if in_hall:
		base += 0.4
	return base


static func grade_of(value: float) -> Array:
	for g: Array in GRADES:
		if value >= float(g[0]):
			return g
	return GRADES[-1]


## The settling up at his retirement (once): his grade and its reward (paid by CareerSession),
## his number retired.
static func settle(cs: CareerSeason, bat: BattingLine, pitch: PitchingLine, in_hall: bool) -> void:
	var c := cs.career
	if c.legacy_grade != "":
		return
	var value := score(c, bat, pitch, cs.pro_games, in_hall)
	var g := grade_of(value)
	c.legacy_grade = str(g[1])
	c.legacy_reward = int(g[2])
	var club: Team = cs.season.teams.get(c.team_id)
	c.number_retired = club != null and seasons_with_last_club(c, club.name) >= RETIRE_SEASONS and (in_hall or value >= 1.3)


## A farewell tour's gift from the club he visits (once a club): what it gave, or "".
static func tour_gift(cs: CareerSeason, club_id: String) -> String:
	var c := cs.career
	if not c.final_season or club_id == c.team_id or club_id == "":
		return ""
	for g: Variant in c.tour_gifts:
		if str((g as Array)[0]) == club_id:
			return ""
	var gift: String = GIFTS[absi(hash(club_id + c.player.id)) % GIFTS.size()]
	c.tour_gifts.append([club_id, gift])
	c.popularity += 3.0
	var club: Team = cs.season.teams.get(club_id)
	cs.log.append("%d일: 은퇴 투어 · %s에서 '%s'을(를) 전달했습니다" % [cs.season.day + 1, club.name if club != null else club_id, gift])
	return gift


## Should his club suggest he retire this winter (from 35: past 38, or his play gone)?
static func should_retire(cs: CareerSeason) -> bool:
	var c := cs.career
	var age := cs.season.season_year + 1 - c.player.born
	if c.final_season or age < 35:
		return false
	return age >= 38 or CareerContract.performance(cs) < 0.75 or CareerContract.first_share(cs) < 0.35


## Announces the farewell tour: next season is his last.
static func announce(cs: CareerSeason) -> void:
	var c := cs.career
	c.final_season = true
	cs.log.append("%d년 겨울: 은퇴 투어 발표. %d 시즌이 마지막입니다" % [cs.season.season_year, cs.season.season_year + 1])
	note(c, cs.season.season_year + 1, "tour", "은퇴 투어", "마지막 시즌을 발표했습니다", c.team_id)


## The line under "THANK YOU" at his farewell, as KBO clubs write it: his number retired, or
## "영원한 ○○맨" for a man long with one club, or his years.
static func slogan(c: CareerPlayer, club: Team) -> String:
	if c.number_retired:
		return "등번호 %d 영구결번" % c.player.number
	if club != null and seasons_with_last_club(c, club.name) >= 8:
		var nickname := club.name.substr(club.short_name.length()).strip_edges() if club.name.begins_with(club.short_name) else club.name
		return "영원한 %s맨" % nickname
	return "프로 %d시즌의 마지막 인사" % c.pro_years
