class_name Trade
extends RefCounted
## Trades between clubs in the regular season (the user, 2026-11-23: "in the league, call up
## second-team men or trade them myself"). Up to three men a side, until the
## deadline (the KBO's is July 31, about seven tenths of the way through the season). The
## other club weighs what it gives and gets: a man's worth rises steeply with his rating (a
## star is worth several regulars), youth with room to grow adds to it, age past 32 takes from
## it, and a club short at a man's place values him more. It takes a deal that leaves it a
## little better off. Men arriving take the first-team places of those who left, the rest
## join the second team.

const MAX_MEN := 3
const DEADLINE_SHARE := 0.7
## The other club wants at least this much more worth than it gives.
const MARGIN := 1.05


## The last day of the regular season a trade can be made.
static func deadline(season: Season) -> int:
	return int(floor(season.total_days() * DEADLINE_SHARE))


static func open(season: Season) -> bool:
	return season.phase == Season.Phase.REGULAR and season.day <= deadline(season)


## A man's worth to a club.
static func worth(season: Season, team: Team, p: Player) -> float:
	var ovr := ClubRules.player_ovr(p, season.ovr, season.catalog)
	var value := pow(maxf(ovr - 30.0, 1.0), 2.0) / 10.0
	var age := season.season_year - p.born
	if age <= 25 and p.potential > 0.0:
		value *= 1.0 + 0.04 * p.potential
	elif age > 32:
		value *= maxf(1.0 - 0.08 * (age - 32), 0.4)
	# Short at his place: a club with few men there values him more.
	var kind := RosterMoves.kind_of(p)
	var have := 0
	for q: Player in team.players:
		if RosterMoves.kind_of(q) == kind and q.id != p.id:
			have += 1
	var usual := int(RosterMoves.MAKE_UP.get(kind, 4))
	if have < usual:
		value *= 1.2
	return value


## What the other club makes of an offer: {"accepted": bool, "give": its worth of what it
## gives, "get": of what it gets, "reason": words for the screen}.
static func weigh(season: Season, mine: Team, theirs: Team, give_ids: PackedStringArray, get_ids: PackedStringArray) -> Dictionary:
	var out := {"accepted": false, "give": 0.0, "get": 0.0, "reason": ""}
	if not open(season):
		out["reason"] = "트레이드 마감일이 지났습니다."
		return out
	if give_ids.is_empty() or get_ids.is_empty():
		out["reason"] = "주고받을 선수를 한 명 이상 고르세요."
		return out
	if give_ids.size() > MAX_MEN or get_ids.size() > MAX_MEN:
		out["reason"] = "한쪽에 %d명까지입니다." % MAX_MEN
		return out
	var received := 0.0
	for id: String in give_ids:
		var p := mine.player(id)
		if p == null:
			return out
		received += worth(season, theirs, p)
	var given := 0.0
	for id: String in get_ids:
		var p := theirs.player(id)
		if p == null:
			return out
		given += worth(season, theirs, p)
	out["give"] = given
	out["get"] = received
	out["accepted"] = received >= given * MARGIN
	if out["accepted"]:
		out["reason"] = "%s이(가) 트레이드를 받아들였습니다." % theirs.name
	elif received >= given * 0.85:
		out["reason"] = "%s: 조금만 더 얹어 주면 생각해 보겠다고 합니다." % theirs.short_name
	else:
		out["reason"] = "%s: 받아들일 수 없는 제안이라고 합니다." % theirs.short_name
	return out


## Makes the trade (weigh first). Men arriving take the first-team places their club's
## departures left, as many as there are; the rest join the second team.
static func apply(season: Season, a: Team, b: Team, a_ids: PackedStringArray, b_ids: PackedStringArray) -> void:
	var a_places := _leave(season, a, a_ids)
	var b_places := _leave(season, b, b_ids)
	var a_men: Array[Player] = []
	for id: String in a_ids:
		a_men.append(_found(id))
	_arrive(season, b, a_men, b_places)
	var b_men: Array[Player] = []
	for id: String in b_ids:
		b_men.append(_found(id))
	_arrive(season, a, b_men, a_places)
	_moving.clear()


static var _moving: Dictionary[String, Player] = {}


static func _found(id: String) -> Player:
	return _moving.get(id)


## Takes the men off their club; returns how many first-team places they left.
static func _leave(season: Season, team: Team, ids: PackedStringArray) -> int:
	var places := 0
	for id: String in ids:
		var p := team.player(id)
		if p == null:
			continue
		if not team.registered.is_empty() and team.registered.has(id):
			places += 1
		_moving[id] = p
		Development.take_off(season, team, p)
	return places


static func _arrive(season: Season, team: Team, men: Array[Player], places: int) -> void:
	var taken: Dictionary[int, bool] = {}
	for q: Player in team.players:
		taken[q.number] = true
	for p: Player in men:
		if p == null:
			continue
		if taken.has(p.number):
			for n: int in range(1, 100):
				if not taken.has(n):
					p.number = n
					break
		taken[p.number] = true
		team.players.append(p)
		if places > 0 and not team.registered.is_empty():
			team.registered.append(p.id)
			places -= 1
