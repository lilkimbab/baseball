class_name RosterMoves
extends RefCounted
## Call-ups and send-downs between the first and second teams (docs/08 R6): every week the
## computer clubs bring up a second-team man who has become better than the weakest first-team
## man of his kind (a starter for a starter, a reliever for a reliever, a catcher for a
## catcher, an infielder for an infielder, an outfielder for an outfielder), counting what each
## has done lately; the player's club gets the same as advice. KBO's rules hold: 29 on the
## first team, ten days before a man sent down can come back, the foreign-player limits.

const EVERY_DAYS := 7
## The second-team man must be this much better (in overall points, form included).
const MARGIN := 2.0
## At most this many moves a club a week.
const MOVES_A_WEEK := 2
## Form: a second-team hitter with this OPS over this many plate appearances, or a pitcher
## with this ERA over this many outs, counts this much better; a first-team man in a slump
## this much worse.
const HOT_OPS := 0.9
const HOT_PA := 40
const HOT_ERA := 2.5
const HOT_OUTS := 30
const COLD_OPS := 0.55
const COLD_PA := 60
const COLD_ERA := 6.5
const COLD_OUTS := 30
const FORM := 2.0


## One move: who goes down, who comes up, and why (for the player's advice).
class Move:
	var down: Player
	var up: Player
	var reason := ""


## The kind a man is swapped within.
static func kind_of(p: Player) -> String:
	if p.is_pitcher():
		return String(p.role())
	var pos := p.primary_position()
	if pos == Position.Kind.C:
		return "C"
	if pos in [Position.Kind.LF, Position.Kind.CF, Position.Kind.RF]:
		return "OF"
	return "IF"


static func _overall(season: Season, p: Player) -> float:
	return Overall.pitcher(p, season.catalog) if p.is_pitcher() else season.ovr.batter(p, p.primary_position())


## What a man is worth for the place: his overall, and his form.
static func worth(season: Season, p: Player, first_team: bool) -> float:
	var value := _overall(season, p)
	if first_team:
		if p.is_pitcher():
			var l: PitchingLine = season.book.pitching.get(p.id)
			if l != null and l.outs >= COLD_OUTS and l.era() > COLD_ERA:
				value -= FORM
		else:
			var b: BattingLine = season.book.batting.get(p.id)
			if b != null and b.pa >= COLD_PA and b.ops() < COLD_OPS:
				value -= FORM
	elif season.farm != null:
		if p.is_pitcher():
			var l := season.farm.pitching(p.id)
			if l.outs >= HOT_OUTS and l.era() <= HOT_ERA:
				value += FORM
		else:
			var b := season.farm.batting(p.id)
			if b.pa >= HOT_PA and b.ops() >= HOT_OPS:
				value += FORM
	return value


## The moves that would make a club better today, best first (at most MOVES_A_WEEK). In the
## winter (`winter`) the ten-day rule does not apply and form does not count.
static func advice(season: Season, team: Team, winter: bool = false) -> Array[Move]:
	var out: Array[Move] = []
	if team.second_team().is_empty():
		return out
	var taken: Dictionary[String, bool] = {}
	var candidates: Array = []
	for kind: String in ["SP", "RP", "C", "IF", "OF"]:
		var first: Array[Player] = []
		var second: Array[Player] = []
		for p: Player in team.players:
			if kind_of(p) != kind:
				continue
			if team.is_registered(p.id):
				first.append(p)
			elif winter or not (team.removed_on.has(p.id) and season.day - team.removed_on[p.id] < Team.RECALL_DAYS):
				second.append(p)
		if first.is_empty() or second.is_empty():
			continue
		var value := func(p: Player, on_first: bool) -> float:
			return _overall(season, p) if winter else worth(season, p, on_first)
		first.sort_custom(func(a: Player, b: Player) -> bool: return value.call(a, true) < value.call(b, true))
		second.sort_custom(func(a: Player, b: Player) -> bool: return value.call(a, false) > value.call(b, false))
		var gain: float = value.call(second[0], false) - value.call(first[0], true)
		if gain > MARGIN and _foreign_ok(team, first[0], second[0], season.rules):
			candidates.append([gain, first[0], second[0]])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for c: Array in candidates:
		if out.size() >= MOVES_A_WEEK:
			break
		var m := Move.new()
		m.down = c[1]
		m.up = c[2]
		m.reason = _reason(season, m.up)
		if taken.has(m.down.id) or taken.has(m.up.id):
			continue
		taken[m.down.id] = true
		taken[m.up.id] = true
		out.append(m)
	return out


## Swapping these two keeps the club within the foreign-player limits.
static func _foreign_ok(team: Team, down: Player, up: Player, rules: RuleSet) -> bool:
	if up.origin == &"" or up.origin == down.origin:
		return true
	var count := 0
	for p: Player in team.first_team():
		if p.origin == up.origin:
			count += 1
	var limit := rules.foreign_players if up.origin == &"foreign" else rules.asia_quota
	return count < limit


static func _reason(season: Season, up: Player) -> String:
	if season.farm == null:
		return "능력치"
	if up.is_pitcher():
		var l := season.farm.pitching(up.id)
		return "2군 평균자책점 %.2f (%s이닝)" % [l.era(), l.innings_text()] if l.outs > 0 else "능력치"
	var b := season.farm.batting(up.id)
	return "2군 OPS %s (%d타석)" % [BattingLine.rate_text(b.ops()), b.pa] if b.pa > 0 else "능력치"


## Makes a move: down to the second team, up to the first.
static func apply(season: Season, team: Team, m: Move) -> bool:
	if not team.unregister(m.down.id, season.day):
		return false
	if not team.register(m.up.id, season.day, season.rules):
		# Should not happen (advice checks the rules); put him back as he was.
		team.registered.append(m.down.id)
		team.removed_on.erase(m.down.id)
		return false
	if team.rotation_plan.has(m.down.id):
		var i := team.rotation_plan.find(m.down.id)
		team.rotation_plan.remove_at(i)
	for entry: Variant in team.batting_plan:
		if str((entry as Array)[0]) == m.down.id:
			team.batting_plan = []
			break
	return true


## The weekly moves of the computer clubs (not the player's).
static func weekly(season: Season) -> void:
	for team_id: String in season.teams:
		if team_id == season.my_team and season.career_player == "":
			continue
		var team: Team = season.teams[team_id]
		for m: Move in advice(season, team):
			if season.career_player != "" and ((m.up != null and m.up.id == season.career_player) or (m.down != null and m.down.id == season.career_player)):
				continue
			apply(season, team, m)


## The first team's usual make-up (as the generator builds it): five starters, nine relievers,
## two catchers, seven infielders, six outfielders.
const MAKE_UP := {"SP": 5, "RP": 9, "C": 2, "IF": 7, "OF": 6}


## Fills the first team back up to the roster size (after the winter's departures) with the
## best second-team men, of the kind it is shortest of.
static func refill(season: Season, team: Team) -> void:
	if team.registered.is_empty():
		return
	var guard := 0
	while team.registered.size() < season.rules.registered_roster and guard < 40:
		guard += 1
		var have := {"SP": 0, "RP": 0, "C": 0, "IF": 0, "OF": 0}
		for p: Player in team.first_team():
			have[kind_of(p)] = int(have[kind_of(p)]) + 1
		var short_kind := ""
		var short_by := -99
		for kind: String in MAKE_UP:
			var gap := int(MAKE_UP[kind]) - int(have[kind])
			if gap > short_by:
				short_by = gap
				short_kind = kind
		var best: Player = null
		for p: Player in team.second_team():
			# (A career's own player goes up only by his manager's judgement: CareerSeason.)
			if p.id == season.career_player or season.injuries.is_out(p.id):
				continue
			if kind_of(p) != short_kind and short_by > 0:
				continue
			if p.origin != &"" and not _foreign_ok(team, p, p, season.rules):
				continue
			if best == null or _overall(season, p) > _overall(season, best):
				best = p
		if best == null and short_by > 0:
			# Nobody of that kind: the best of any.
			for p: Player in team.second_team():
				if p.id == season.career_player or season.injuries.is_out(p.id):
					continue
				if best == null or _overall(season, p) > _overall(season, best):
					best = p
		if best == null:
			return
		team.registered.append(best.id)


## Sends the weakest men down until the first team is no bigger than `size` (a season with a
## smaller roster rule), never below the usual make-up of a kind.
static func trim(season: Season, team: Team, size: int) -> void:
	if team.registered.is_empty():
		return
	var guard := 0
	while team.registered.size() > size and guard < 20:
		guard += 1
		var have := {"SP": 0, "RP": 0, "C": 0, "IF": 0, "OF": 0}
		for p: Player in team.first_team():
			have[kind_of(p)] = int(have[kind_of(p)]) + 1
		var weakest: Player = null
		for p: Player in team.first_team():
			if int(have[kind_of(p)]) <= int(MAKE_UP[kind_of(p)]) - (1 if kind_of(p) == "RP" else 0):
				continue
			if weakest == null or _overall(season, p) < _overall(season, weakest):
				weakest = p
		if weakest == null:
			return
		team.registered.remove_at(team.registered.find(weakest.id))
