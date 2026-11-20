class_name Season
extends RefCounted
## A season of the manager league (docs/13 S7-3 to S7-5): every division's schedule, played a
## day at a time. The player's own game is handed out to be played on screen; the others are
## worked out at once by the stat resolver.
##
## Before each game the club's manager sets who can play:
## - the next starter in the rotation who has had his rest (PitcherUsage);
## - relievers who pitched the two days before, or a lot yesterday, sit; one who pitched
##   yesterday plays below his best;
## - regulars get a day off now and then (one or two a month, catchers more), and a regular in
##   a slump (low OPS over his last 20 games) sits for a few games;
## - only the first team (1군 엔트리) dresses.

const RECENT_GAMES := 20
## A day off for a regular, per game (about one or two a month; catchers more) (A).
const REST_DAY_CHANCE := 0.045
const CATCHER_REST_CHANCE := 0.11
## A regular with an OPS under SLUMP_OPS over his last 20 games, once he has SLUMP_MIN_PA plate
## appearances in them, sits for SLUMP_DAYS days (A).
const SLUMP_OPS := 0.560
const SLUMP_MIN_PA := 60
const SLUMP_DAYS := 5
## A regular hitting under COLD_AVG for the season, after COLD_MIN_PA plate appearances,
## sits this share of games (A).
const COLD_AVG := 0.215
const COLD_MIN_PA := 150
const COLD_REST_CHANCE := 0.35
## Chance a reliever who pitched yesterday is kept out of today's game (A).
const TIRED_HELD_OUT := 0.6

var rules: RuleSet
var env: LeagueEnv
var catalog: Dictionary[StringName, PitchType]
var ovr: Overall
var rng: Rng
var teams: Dictionary[String, Team] = {}
## Club ids per division, top division first.
var divisions: Array[PackedStringArray] = []
var schedules: Array[Schedule] = []
var standings: Array[Standings] = []
var games_per_team := 144
## Calendar day, 0 = opening day.
var day := 0
## Season totals per player.
var book := StatBook.new()
var usage := PitcherUsage.new()
## Per hitter: his lines from his last RECENT_GAMES games, oldest first.
var recent: Dictionary[String, Array] = {}
## Hitters sitting out a slump, until (and including) this day.
var sitting: Dictionary[String, int] = {}
## The club the player manages ("" for none).
var my_team := ""
## Decided once per game and club: "day:team" → starter id, and who has the day off.
var _starters: Dictionary[String, String] = {}
var _resting: Dictionary[String, Dictionary] = {}


static func create(clubs: Array[Team], per_division: int, games: int, seed_value: int, rule_set: RuleSet, league: LeagueEnv, pitch_catalog: Dictionary[StringName, PitchType], overall: Overall) -> Season:
	var s := Season.new()
	s.rules = rule_set
	s.env = league
	s.catalog = pitch_catalog
	s.ovr = overall
	s.rng = Rng.new(seed_value)
	s.games_per_team = games
	for t: Team in clubs:
		s.teams[t.id] = t
	for d: int in clubs.size() / per_division:
		var ids := PackedStringArray()
		for i: int in per_division:
			ids.append(clubs[d * per_division + i].id)
		s.divisions.append(ids)
		s.schedules.append(Schedule.make(ids, games, s.rng.fork(1000 + d)))
		s.standings.append(Standings.of(ids))
	return s


func total_days() -> int:
	return schedules[0].days if not schedules.is_empty() else 0


func finished() -> bool:
	for s: Schedule in schedules:
		if not s.finished():
			return false
	return true


func division_of(team_id: String) -> int:
	for d: int in divisions.size():
		if divisions[d].has(team_id):
			return d
	return -1


func games_today() -> Array[ScheduledGame]:
	var out: Array[ScheduledGame] = []
	for s: Schedule in schedules:
		out.append_array(s.games_on(day))
	return out


## The player's game today, or null (an off day, or no club).
func my_game_today() -> ScheduledGame:
	if my_team == "":
		return null
	for g: ScheduledGame in games_today():
		if g.involves(my_team):
			return g
	return null


# --- Before a game ---


## A game ready to play with the stat resolver (or the physical one): today's line-ups.
func prepare(game: ScheduledGame, physical: bool = false) -> GameSim:
	var manager := AiManager.new(env, catalog, ovr)
	var a := lineup_for(game.away, game.day, manager)
	var h := lineup_for(game.home, game.day, manager)
	return GameSim.with_lineups(a, h, rules, env, catalog, manager, rng.fork(hash("%d:%s" % [game.day, game.home])), physical)


## A club's line-up for the day, made by its manager.
func lineup_for(team_id: String, on_day: int, manager: AiManager) -> TeamInGame:
	var team: Team = teams[team_id]
	var starter := starter_for(team, on_day)
	return manager.make_lineup(squad_for(team, on_day, starter.id), rules, starter.id, resting(team, on_day))


## The first team as it can play today: the starter, the relievers who may pitch (a tired one
## with lowered ratings), and the position players. Starters between starts stay out.
func squad_for(team: Team, on_day: int, starter_id: String) -> Team:
	var view := Team.new()
	view.id = team.id
	view.name = team.name
	view.short_name = team.short_name
	view.stadium = team.stadium
	view.primary = team.primary
	view.secondary = team.secondary
	view.accent = team.accent
	view.steal_style = team.steal_style
	view.bunt_style = team.bunt_style
	# Relievers in order of rest, so a manager's "anybody else" is the freshest arm.
	var first := team.first_team()
	first.sort_custom(func(a: Player, b: Player) -> bool: return usage.rest_days(a.id, on_day) > usage.rest_days(b.id, on_day))
	for p: Player in first:
		if p.is_pitcher() and p.id != starter_id:
			if p.role() == &"SP":
				continue
			match usage.reliever_status(p.id, on_day):
				PitcherUsage.Status.REST:
					continue
				PitcherUsage.Status.TIRED:
					# Managers keep a reliever who pitched yesterday out about half the time.
					if rng.chance(TIRED_HELD_OUT):
						continue
					view.players.append(p.with_form(PitcherUsage.TIRED_FORM))
					continue
		view.players.append(p)
	return view


## The day's starter: the next one in the rotation who has had his rest, otherwise the one
## who has rested longest.
func starter_for(team: Team, on_day: int) -> Player:
	var key := "%d:%s" % [on_day, team.id]
	if _starters.has(key):
		return team.player(_starters[key])
	var rotation := team.rotation()
	var chosen: Player = null
	if rotation.is_empty():
		for p: Player in team.first_team():
			if p.is_pitcher() and (chosen == null or usage.rest_days(p.id, on_day) > usage.rest_days(chosen.id, on_day)):
				chosen = p
	else:
		for k: int in rotation.size():
			var p := rotation[(team.rotation_index + k) % rotation.size()]
			if usage.can_start(p.id, on_day):
				chosen = p
				team.rotation_index = (team.rotation_index + k + 1) % rotation.size()
				break
		if chosen == null:
			for p: Player in rotation:
				if chosen == null or usage.rest_days(p.id, on_day) > usage.rest_days(chosen.id, on_day):
					chosen = p
	_starters[key] = chosen.id
	return chosen


## Position players who start on the bench today: a day off or a slump.
func resting(team: Team, on_day: int) -> Dictionary[String, bool]:
	var key := "%d:%s" % [on_day, team.id]
	if _resting.has(key):
		var cached: Dictionary[String, bool] = {}
		cached.assign(_resting[key])
		return cached
	var out: Dictionary[String, bool] = {}
	for p: Player in team.first_team():
		if p.is_pitcher():
			continue
		if sitting.get(p.id, -1) >= on_day:
			out[p.id] = true
			continue
		var chance := CATCHER_REST_CHANCE if p.primary_position() == Position.Kind.C else REST_DAY_CHANCE
		# A regular who has hit poorly all season loses starts to the bench.
		var season_line: BattingLine = book.batting.get(p.id)
		if season_line != null and season_line.pa >= COLD_MIN_PA and season_line.average() < COLD_AVG:
			chance = COLD_REST_CHANCE
		if rng.chance(chance):
			out[p.id] = true
	_resting[key] = out
	return out


# --- After a game ---


func record(game: ScheduledGame, state: GameState, game_book: StatBook) -> void:
	game.finish(state.score[0], state.score[1], state.inning)
	var d := division_of(game.home)
	if d >= 0:
		standings[d].record(game)
	for id: String in game_book.batting:
		var line: BattingLine = game_book.batting[id]
		book.bat(id).add(line)
		_note_recent(id, line, game.day)
	for id: String in game_book.pitching:
		var line: PitchingLine = game_book.pitching[id]
		book.pitch(id).add(line)
		usage.note(id, game.day, line.pitches)


func _note_recent(id: String, line: BattingLine, on_day: int) -> void:
	if not recent.has(id):
		recent[id] = []
	var list: Array = recent[id]
	list.append(line)
	while list.size() > RECENT_GAMES:
		list.pop_front()
	var total := BattingLine.new()
	for l: BattingLine in list:
		total.add(l)
	if total.pa >= SLUMP_MIN_PA and total.ops() < SLUMP_OPS:
		sitting[id] = on_day + SLUMP_DAYS
		# He starts afresh when he comes back.
		list.clear()


## A hitter's line over his last games.
func recent_line(id: String) -> BattingLine:
	var total := BattingLine.new()
	for l: BattingLine in recent.get(id, []):
		total.add(l)
	return total


# --- Days ---


## Plays today's games with the stat resolver, all but the player's own, which is returned
## (null if he has none today or `include_mine` is set).
func play_day(include_mine: bool = false) -> ScheduledGame:
	var mine: ScheduledGame = null
	for g: ScheduledGame in games_today():
		if g.played:
			continue
		if not include_mine and my_team != "" and g.involves(my_team):
			mine = g
			continue
		var sim := prepare(g)
		sim.play()
		record(g, sim.state, sim.scorer.book)
	return mine


## To the next day.
func advance() -> void:
	day += 1


## Plays out the rest of the regular season, the player's games included.
func play_to_end() -> void:
	while day < total_days():
		play_day(true)
		advance()


## Plate appearances needed to qualify for the batting title: 3.1 per team game.
func qualifying_pa() -> int:
	return int(floorf(games_per_team * 3.1))


## Innings (in outs) needed for the ERA title: one per team game.
func qualifying_outs() -> int:
	return games_per_team * 3
