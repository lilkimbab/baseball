class_name CareerEvents
extends RefCounted
## What happens to a pro career in the season besides the games (docs/08 R8-3; the user, 2026-
## 11-23): a long stay in the second team brings a talk with the club (a cut in pay coming); a
## trade to another club before the deadline (Trade.deadline; never in his first season); a
## pitcher picks up a new pitch by himself after a fine outing now and then ("suddenly learned
## it"). Each told once in his log; a trade and a new pitch are the cutscenes' cue later.

## Of a regular season's days: so many in the second team for the talk.
const LONG_STAY_SHARE := 0.4
## A week's chance of a trade (from his second season), more for a regular who is not a star.
const TRADE_WEEKLY := 0.012
const TRADE_WEEKLY_REGULAR := 0.025
## A pitcher's chance, after a game rated this high, to pick up a pitch by himself.
const PICK_UP_RATING := 8.0
const PICK_UP_CHANCE := 0.05


## Once a day, after the night (CareerSeason._after_day).
static func day(cs: CareerSeason) -> void:
	if cs.season.school or cs.season.phase != Season.Phase.REGULAR:
		return
	var days := maxi(cs.season.total_days(), 1)
	if not cs.career.first_team and float(cs.futures_days) / days >= LONG_STAY_SHARE and not cs.events_seen.has("long_stay"):
		cs.events_seen.append("long_stay")
		cs.log.append("%d일: 구단 면담 — 2군 생활이 길어지고 있습니다. 이대로면 연봉 삭감이 예상됩니다." % (cs.season.day + 1))
	if cs.season.day % 7 == 0 and cs.career.pro_years >= 1 and Trade.open(cs.season):
		var regular := cs.career.first_team and CareerContract.performance(cs) < 1.4
		var rng := Rng.new(hash("trade:%s:%d:%d" % [cs.career.player.id, cs.season.season_year, cs.season.day]))
		if rng.chance(TRADE_WEEKLY_REGULAR if regular else TRADE_WEEKLY):
			trade(cs, rng)


## A trade: to another club, for one of its men of his kind, as near to him as can be.
static func trade(cs: CareerSeason, rng: Rng) -> String:
	var s := cs.season
	var c := cs.career
	var from: Team = s.teams[c.team_id]
	var others: Array = s.teams.keys().filter(func(id: String) -> bool: return id != c.team_id)
	if others.is_empty():
		return ""
	var to: Team = s.teams[others[rng.next_int(others.size())]]
	var kind := RosterMoves.kind_of(c.player)
	var mine := ClubRules.player_ovr(c.player, s.ovr, s.catalog)
	var back: Player = null
	for p: Player in to.players:
		if RosterMoves.kind_of(p) != kind or p.is_foreign() or s.injuries.is_out(p.id):
			continue
		if back == null or absf(ClubRules.player_ovr(p, s.ovr, s.catalog) - mine) < absf(ClubRules.player_ovr(back, s.ovr, s.catalog) - mine):
			back = p
	var was_first := c.first_team
	from.players.erase(c.player)
	from.registered.erase(c.player.id)
	to.players.append(c.player)
	if back != null:
		var back_first := to.registered.has(back.id)
		to.players.erase(back)
		to.registered.erase(back.id)
		from.players.append(back)
		if back_first:
			from.registered.append(back.id)
	if was_first:
		to.registered.append(c.player.id)
		RosterMoves.trim(s, to, s.rules.registered_roster)
		if not to.registered.has(c.player.id):
			to.registered.append(c.player.id)
	RosterMoves.refill(s, from)
	c.team_id = to.id
	s.my_team = to.id
	var line := "%d일: 트레이드 — %s에서 %s로%s" % [s.day + 1, from.name, to.name, " (상대: %s)" % back.name if back != null else ""]
	cs.log.append(line)
	cs.events_seen.append("trade:%d" % s.season_year)
	cs.cue(&"trade", "%d년 트레이드" % s.season_year, "%s 이적" % to.name, PackedStringArray(["%s → %s" % [from.name, to.name]] + (["맞트레이드: %s" % back.name] if back != null else [])), from.id)
	return line


## After one of his games: a pitcher who pitched very well may pick up a new pitch by himself.
## Returns what he learned ("" none).
static func after_game(cs: CareerSeason, report: CareerSeason.Report) -> String:
	var c := cs.career
	if not c.is_pitcher() or report.rating < PICK_UP_RATING:
		return ""
	var can := PitchEvolution.learnable(c, cs.rules)
	if can.is_empty():
		return ""
	var rng := Rng.new(hash("pick_up:%s:%d:%d" % [c.player.id, cs.season.season_year, cs.season.day]))
	if not rng.chance(PICK_UP_CHANCE):
		return ""
	var id := can[rng.next_int(can.size())]
	if not PitchEvolution.learn(c, id, cs.rules, cs.season.catalog, true):
		return ""
	var t: PitchType = cs.season.catalog.get(id)
	var name := t.label if t != null else String(id)
	cs.log.append("%d일: 새 구종 습득 — 던지다 보니 %s의 감을 잡았습니다" % [cs.season.day + 1, name])
	return "새 구종: %s" % name
