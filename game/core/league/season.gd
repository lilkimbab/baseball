class_name Season
extends RefCounted
## A season of the manager league (docs/13 S7-3 to S7-8): every division's schedule, played a
## day at a time, then each division's postseason, then promotion and relegation. The
## player's own game is handed out to be played on screen; the others are worked out at once
## by the stat resolver.
##
## Before each game the club's manager sets who can play:
## - the next starter in the rotation who has had his rest (PitcherUsage);
## - relievers who pitched the two days before, or a lot yesterday, sit; one who pitched
##   yesterday plays below his best;
## - regulars get a day off now and then (one or two a month, catchers more), and a regular in
##   a slump (low OPS over his last 20 games) sits for a few games;
## - only the first team (1군 엔트리) dresses;
## - everyone plays at today's condition (최악 to 최상, ratings −6% to +6%), and the player's
##   club with its traits and team colours (docs/13 S7-9).

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
const COLD_AVG := 0.225
const COLD_MIN_PA := 150
const COLD_REST_CHANCE := 0.4
## Chance a reliever who pitched yesterday is kept out of today's game (A).
const TIRED_HELD_OUT := 0.6

enum Phase { REGULAR, POSTSEASON, OVER }

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
var phase := Phase.REGULAR
## Season totals per player (regular season), and the postseason's apart, as the KBO keeps them.
var book := StatBook.new()
var postseason_book := StatBook.new()
var postseasons: Array[Postseason] = []
var usage := PitcherUsage.new()
## Per hitter: his lines from his last RECENT_GAMES games, oldest first.
var recent: Dictionary[String, Array] = {}
## Hitters sitting out a slump, until (and including) this day.
var sitting: Dictionary[String, int] = {}
## The club the player manages ("" for none), and its management.
var my_team := ""
var club: Club
var club_rules: ClubRules
## Clubs under management (the player's): team colours, traits and training count for them
## only. The computer's clubs are not managed this way, so the league stays as calibrated.
var clubs: Dictionary[String, Club] = {}
## Condition per player: index into ClubRules.condition_levels (2 = 보통). Games played in a
## row by each position player (a long run makes a bad day more likely).
var condition: Dictionary[String, int] = {}
var streak: Dictionary[String, int] = {}
var season_year := 2026
## A player who plays whenever he is on the first team (the career player): he starts at his
## position, a starter takes his turn, a closer closes and a reliever sets up.
var featured := ""
var featured_role := ""
## Decided once per game and club: "day:team" → starter id, and who has the day off.
var _starters: Dictionary[String, String] = {}
var _names: NameTable
var _resting: Dictionary[String, Dictionary] = {}


static func create(clubs: Array[Team], per_division: int, games: int, seed_value: int, rule_set: RuleSet, league: LeagueEnv, pitch_catalog: Dictionary[StringName, PitchType], overall: Overall, management: ClubRules = null) -> Season:
	var s := Season.new()
	s.club_rules = management
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


## The regular season is over.
func regular_season_over() -> bool:
	for s: Schedule in schedules:
		if not s.finished():
			return false
	return true


## Everything is over, postseason included.
func finished() -> bool:
	return phase == Phase.OVER


func division_of(team_id: String) -> int:
	for d: int in divisions.size():
		if divisions[d].has(team_id):
			return d
	return -1


func games_today() -> Array[ScheduledGame]:
	var out: Array[ScheduledGame] = []
	if phase == Phase.REGULAR:
		for s: Schedule in schedules:
			out.append_array(s.games_on(day))
	elif phase == Phase.POSTSEASON:
		for p: Postseason in postseasons:
			var g := p.game_on(day)
			if g != null:
				out.append(g)
	return out


## The postseason a game belongs to, or null for a regular-season game.
func postseason_of(game: ScheduledGame) -> Postseason:
	if phase != Phase.POSTSEASON:
		return null
	for p: Postseason in postseasons:
		var s := p.series()
		if s != null and s.games.has(game):
			return p
	return null


func rules_for(game: ScheduledGame) -> RuleSet:
	return Postseason.rules(rules) if postseason_of(game) != null else rules


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
	for side: String in [game.away, game.home]:
		var best_relief := 0.0
		for p: Player in (teams[side] as Team).first_team():
			if p.is_pitcher():
				manager.role_overall[p.id] = _pitcher_overall(p)
				if p.role() == &"RP" and p.id != featured:
					best_relief = maxf(best_relief, manager.role_overall[p.id])
		if featured != "" and manager.role_overall.has(featured):
			manager.role_overall[featured] = best_relief + (1.0 if featured_role == "CL" else -0.01)
	var game_rules := rules_for(game)
	var a := lineup_for(game.away, game.day, manager, game_rules)
	var h := lineup_for(game.home, game.day, manager, game_rules)
	return GameSim.with_lineups(a, h, game_rules, env, catalog, manager, rng.fork(hash("%d:%s" % [game.day, game.home])), physical)


var _overall_cache: Dictionary[String, float] = {}


func _pitcher_overall(p: Player) -> float:
	if not _overall_cache.has(p.id):
		_overall_cache[p.id] = Overall.pitcher(p, catalog)
	return _overall_cache[p.id]


## A club's line-up for the day, made by its manager.
func lineup_for(team_id: String, on_day: int, manager: AiManager, game_rules: RuleSet = null) -> TeamInGame:
	var team: Team = teams[team_id]
	var starter := starter_for(team, on_day)
	var rest := resting(team, on_day)
	var must: Dictionary[String, bool] = {}
	if featured != "" and team.player(featured) != null and team.is_registered(featured):
		must[featured] = true
		rest.erase(featured)
	return manager.make_lineup(squad_for(team, on_day, starter.id), game_rules if game_rules != null else rules, starter.id, rest, must)


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
	var managed: Club = clubs.get(team.id)
	var actives: Array[ClubRules.ColorDef] = []
	if managed != null:
		actives = TeamColors.active(team, managed, club_rules, ovr, catalog)
	# Relievers in order of rest, so a manager's "anybody else" is the freshest arm.
	var first := team.first_team()
	first.sort_custom(func(a: Player, b: Player) -> bool: return usage.rest_days(a.id, on_day) > usage.rest_days(b.id, on_day))
	for p: Player in first:
		var factor := 1.0
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
					factor = PitcherUsage.TIRED_FORM
		factor += condition_effect(p.id)
		var deltas: Dictionary[String, float] = {}
		if managed != null:
			deltas = managed.trait_deltas(p, club_rules)
			var colour := TeamColors.deltas(p, actives, team, managed, club_rules, ovr, catalog)
			for key: String in colour:
				deltas[key] = float(deltas.get(key, 0.0)) + colour[key]
		view.players.append(p if is_equal_approx(factor, 1.0) and deltas.is_empty() else p.with_form(factor, deltas))
	return view


## Today's condition as a rating change (−0.06 to +0.06); 0 without club rules.
func condition_effect(id: String) -> float:
	if club_rules == null:
		return 0.0
	return club_rules.condition_effect[int(condition.get(id, ClubRules.NORMAL))]


func condition_name(id: String) -> String:
	if club_rules == null:
		return "보통"
	return club_rules.condition_levels[int(condition.get(id, ClubRules.NORMAL))]


## Overnight: condition drifts (back toward 보통 more often than away from it; a position
## player in a long run of games more likely down), the player's club trains, and new
## scouting candidates arrive.
func _overnight() -> void:
	if club_rules == null:
		return
	for t: Team in teams.values():
		for p: Player in t.first_team():
			var level := int(condition.get(p.id, ClubRules.NORMAL))
			var drop := club_rules.streak_drop if int(streak.get(p.id, 0)) >= club_rules.streak_games else 0.0
			if rng.chance(drop):
				level -= 1
			elif rng.chance(club_rules.condition_change):
				if level != ClubRules.NORMAL and rng.chance(club_rules.toward_normal):
					level += 1 if level < ClubRules.NORMAL else -1
				else:
					level += 1 if rng.chance(0.5) else -1
			condition[p.id] = clampi(level, 0, club_rules.condition_levels.size() - 1)
	if club == null:
		return
	var team: Team = teams[club.team_id]
	var actives := TeamColors.active(team, club, club_rules, ovr, catalog)
	club.train(team, func(p: Player) -> int: return season_year - p.born, club_rules, ovr, catalog, TeamColors.training_boost(actives))
	refresh_candidates()


## Today's scouting candidates for the player's club.
func refresh_candidates() -> void:
	if club == null or club_rules == null:
		return
	if _names == null:
		_names = RosterIO.load_names()
	var gen := LeagueGenerator.new(_names, catalog, hash("scout:%d:%d" % [season_year, day]))
	club.candidates = Scouting.candidates(gen, division_of(club.team_id), club.scout_level, club_rules)
	club.signed_today = false


## The player takes charge of a club: its management starts.
func manage(team_id: String) -> void:
	my_team = team_id
	if club_rules != null:
		club = Club.for_team(teams[team_id])
		clubs[team_id] = club
		refresh_candidates()


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
	var playoff := postseason_of(game)
	var target := book
	if playoff != null:
		target = postseason_book
		playoff.record(game, day)
	else:
		var d := division_of(game.home)
		if d >= 0:
			standings[d].record(game)
	var played: Dictionary[String, bool] = {}
	for id: String in game_book.batting:
		var line: BattingLine = game_book.batting[id]
		target.bat(id).add(line)
		played[id] = true
		if playoff == null:
			_note_recent(id, line, game.day)
	for side: String in [game.away, game.home]:
		for p: Player in (teams[side] as Team).first_team():
			if not p.is_pitcher():
				streak[p.id] = int(streak.get(p.id, 0)) + 1 if played.has(p.id) else 0
	if club != null and game.involves(club.team_id):
		club.earn(signi(game.runs_of(club.team_id) - game.runs_against(club.team_id)), playoff != null, club_rules)
	for id: String in game_book.pitching:
		var line: PitchingLine = game_book.pitching[id]
		target.pitch(id).add(line)
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


## To the next day. The day after the last regular-season game the postseason begins; when
## every division has its champion the season is over.
func advance() -> void:
	day += 1
	_overnight()
	if phase == Phase.REGULAR and regular_season_over():
		phase = Phase.POSTSEASON
		postseasons.clear()
		for d: int in divisions.size():
			postseasons.append(Postseason.from_standings(standings[d], day + Postseason.REST_BETWEEN))
	elif phase == Phase.POSTSEASON:
		var done := true
		for p: Postseason in postseasons:
			if not p.finished():
				done = false
		if done:
			phase = Phase.OVER


## Plays out the rest of the season, postseason included, the player's games too.
func play_to_end() -> void:
	var guard := 0
	while phase != Phase.OVER and guard < 1000:
		play_day(true)
		advance()
		guard += 1


## Plays out the regular season only.
func play_regular_season() -> void:
	while phase == Phase.REGULAR:
		play_day(true)
		advance()


# --- After the season ---


## Clubs going up and down (docs/02 section 4.1): each division's postseason champion and
## runner-up go up, its bottom two of the regular season go down. Per division: [up, down].
func movements() -> Array[Array]:
	var out: Array[Array] = []
	for d: int in divisions.size():
		var up := PackedStringArray()
		var down := PackedStringArray()
		if d > 0 and d < postseasons.size() and postseasons[d].finished():
			up.append(postseasons[d].champion())
			up.append(postseasons[d].runner_up())
		if d < divisions.size() - 1:
			var order := standings[d].ranked()
			for i: int in 2:
				down.append(order[order.size() - 1 - i].team_id)
		out.append([up, down])
	return out


## Next season's divisions after the movements.
func next_divisions() -> Array[PackedStringArray]:
	var moves := movements()
	var out: Array[PackedStringArray] = []
	for d: int in divisions.size():
		var ids := PackedStringArray()
		var up: PackedStringArray = moves[d][0]
		var down: PackedStringArray = moves[d][1]
		for id: String in divisions[d]:
			if not up.has(id) and not down.has(id):
				ids.append(id)
		if d + 1 < divisions.size():
			ids.append_array(moves[d + 1][0])
		if d > 0:
			ids.append_array(moves[d - 1][1])
		out.append(ids)
	return out


## Plate appearances needed to qualify for the batting title: 3.1 per team game.
func qualifying_pa() -> int:
	return int(floorf(games_per_team * 3.1))


## Innings (in outs) needed for the ERA title: one per team game.
func qualifying_outs() -> int:
	return games_per_team * 3
