class_name Injuries
extends RefCounted
## Injuries (the user, 2026-11-23: a reckless dive or a pitch that hits a man can hurt him, and
## he is out until he is healed). As the KBO's injured list (since 2020, KBO League rules 14-3):
## an injured man comes off the first-team entry with his days still counted, and may come
## back as soon as he is healed, without the ten days a man sent down waits.
##
## How often (a club of the KBO puts a man on the list a dozen times a season or so): a
## position player who plays a game, WEAR_HITTER; a pitcher who pitches, WEAR_PITCHER; a man
## hit by a pitch, HBP (a pitch at the head, HEAD); a dive in the field made on screen, DIVE (one
## at a ball he had little chance of, RECKLESS_DIVE). How long: mostly a week or two, sometimes
## a month or more (days_for).

const WEAR_HITTER := 0.0012
const WEAR_PITCHER := 0.0016
const HBP := 0.04
const HEAD := 0.3
const DIVE := 0.004
const RECKLESS_DIVE := 0.03

const CAUSES := {"wear": "근육 부상", "hbp": "몸에 맞는 공", "head": "머리에 맞은 공", "dive": "다이빙 중 부상"}

## Player id -> [days left, cause].
var out: Dictionary[String, Array] = {}


static func days_for(rng: Rng, cause: String) -> int:
	var roll := rng.next_float()
	var days := 0
	if roll < 0.6:
		days = rng.next_int_range(3, 10)
	elif roll < 0.9:
		days = rng.next_int_range(11, 25)
	else:
		days = rng.next_int_range(26, 60)
	if cause == "head":
		days = maxi(days, 7)
	return days


func is_out(player_id: String) -> bool:
	return out.has(player_id)


func days_left(player_id: String) -> int:
	return int(out[player_id][0]) if out.has(player_id) else 0


func cause_of(player_id: String) -> String:
	return str(CAUSES.get(str(out[player_id][1]), "부상")) if out.has(player_id) else ""


## Hurts a man for `days`: off the first-team entry (the injured list: no wait to come back).
func injure(team: Team, p: Player, days: int, cause: String) -> void:
	if p == null or days <= 0:
		return
	out[p.id] = [maxi(days, days_left(p.id)), cause]
	if not team.registered.is_empty() and team.registered.has(p.id):
		team.registered.remove_at(team.registered.find(p.id))
		team.removed_on.erase(p.id)


## A game's draws: each man who played, his wear; each man hit by a pitch, the pitch. Returns
## [team id, player id, days, cause] of each hurt.
func note_game(season: Season, book: StatBook, rng: Rng) -> Array:
	var hurt: Array = []
	for side: String in [season_team_of(season, book, 0), season_team_of(season, book, 1)]:
		if side == "":
			continue
		var team: Team = season.teams[side]
		for p: Player in team.players:
			if out.has(p.id):
				continue
			var cause := ""
			var bat: BattingLine = book.batting.get(p.id)
			var pitch: PitchingLine = book.pitching.get(p.id)
			if bat != null and bat.hit_by_pitch > 0 and rng.chance(1.0 - pow(1.0 - HBP, bat.hit_by_pitch)):
				cause = "hbp"
			elif bat != null and bat.pa > 0 and not p.is_pitcher() and rng.chance(WEAR_HITTER):
				cause = "wear"
			elif pitch != null and pitch.outs > 0 and rng.chance(WEAR_PITCHER):
				cause = "wear"
			if cause != "":
				var days := days_for(rng, cause)
				injure(team, p, days, cause)
				hurt.append([side, p.id, days, cause])
	return hurt


## The club ids of a game's two sides, found from the men in its book.
static func season_team_of(season: Season, book: StatBook, side: int) -> String:
	for id: String in book.batters[side]:
		for team_id: String in season.teams:
			if (season.teams[team_id] as Team).player(id) != null:
				return team_id
	return ""


## A day goes by: the injured heal a day; returns the ids healed today.
func heal_day() -> PackedStringArray:
	var healed := PackedStringArray()
	for id: String in out.keys():
		out[id][0] = int(out[id][0]) - 1
		if int(out[id][0]) <= 0:
			out.erase(id)
			healed.append(id)
	return healed


func to_dict() -> Dictionary:
	return {"out": out.duplicate(true)}


func load_dict(d: Dictionary) -> void:
	out.clear()
	var stored: Dictionary = d.get("out", {})
	for id: String in stored:
		var entry: Array = stored[id]
		out[id] = [int(entry[0]), str(entry[1])]
