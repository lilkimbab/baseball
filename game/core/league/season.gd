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
## The second teams' league (docs/08 R6); null where there is none (the career mode, which
## plays its own player's second-team games, and batch simulations).
var farm: FarmLeague
## A career's own player (CareerSeason): his club is managed by the computer like the others,
## but he is moved up and down only by his manager's judgement. "" outside a career.
var career_player := ""
## A high-school league (SchoolLeague): its own playoff, no all-star game.
var school := false
## The league's all-star break (LeagueAllStar): who was picked, the derby, the game, what it
## paid. Empty until it comes.
var all_star := {}
## Each game's line of the men the person follows (GameLog): player id → entries.
var game_logs: Dictionary = {}
## Rating points each player has grown this season (Development), for the winter's report.
var grown: Dictionary[String, float] = {}
## Players who played in a first-team game today (for growth); emptied when the day ends.
var played_today: Dictionary[String, bool] = {}
## The winter before this season (who retired, the rookies, who grew most), for the screens.
var last_winter: Development.Winter
## A season of the past being played again (docs/08 R7), and the scenario taken, if any.
var history: SeasonPack
var scenario_id := ""
## A player who plays whenever he is on the first team (the career player): he starts at his
## position, a starter takes his turn, a closer closes and a reliever sets up.
## The difficulty of the game about to be recorded when the person played it on screen (−1:
## simulated); set by the scene, used once (Season.record).
var played_level := -1
## Games the manager played on screen, by difficulty (Difficulty.Level).
var level_games := PackedInt32Array([0, 0, 0, 0])
## The difficulty the league is played at: how strong the other clubs are (Difficulty.league_form).
var difficulty: int = Difficulty.Level.PRO
## Days played at each difficulty (the season's reward is by their average).
var level_days := PackedInt32Array([0, 0, 0, 0])
## How much of the manager's games he played himself (the season's reward is by it): the sum of
## each game's share (1 played wholly, 0 left to the computer) and how many games.
var involvement_sum := 0.0
var involvement_games := 0
## The share of the game about to be recorded he played himself (−1: simulated); set by the
## scene, used once (Season.record).
var played_share := -1.0
## The season's reward has been paid (one season, then a new one: docs/08 R8-1).
var rewarded := false
## Who is hurt and for how long (Injuries; none in a season of the past, played as it was).
var injuries := Injuries.new()
## Today's news of the manager's club: [player id, days, cause] hurt, and the ids healed.
var hurt_today: Array = []
## What the manager should hear about his club since he last looked (an injury and who took
## the place). Not saved: told once.
var news := PackedStringArray()
var healed_today := PackedStringArray()
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
	# Players from a pack (or an old save) get their room to grow.
	Development.give_rooms(clubs, s.season_year)
	for d: int in clubs.size() / per_division:
		var ids := PackedStringArray()
		for i: int in per_division:
			ids.append(clubs[d * per_division + i].id)
		s.divisions.append(ids)
		s.schedules.append(Schedule.make(ids, games, s.rng.fork(1000 + d)))
		s.standings.append(Standings.of(ids))
		s.standings[-1].count_ties_as_losses(rule_set.ties_as_losses)
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
		manager.use_bullpen_plan(teams[side])
	var game_rules := rules_for(game)
	var a := lineup_for(game.away, game.day, manager, game_rules)
	var h := lineup_for(game.home, game.day, manager, game_rules)
	var sim := GameSim.with_lineups(a, h, game_rules, env, catalog, manager, rng.fork(hash("%d:%s" % [game.day, game.home])), physical)
	if sim.resolver is StatResolver and history != null:
		(sim.resolver as StatResolver).park = history.park_of(game.home)
	return sim


## A game's injuries (Injuries): drawn for both sides. Every club fills the first-team place at
## once with the best second-team man of the kind it is short of, as a real club does the same
## day; the manager's club too (an empty place played a club short all season: its winning
## share fell by a third), and he is told who went down and who came up (news) — he may change
## it as he likes.
func _note_injuries(game: ScheduledGame, game_book: StatBook, state: GameState = null) -> void:
	if history != null or my_team == "":
		return
	var hurt := injuries.note_game(self, game_book, rng.fork(hash("hurt:%d:%s" % [day, game.home])), state)
	for h: Array in hurt:
		var team: Team = teams[str(h[0])]
		var before := team.registered.duplicate()
		RosterMoves.refill(self, team)
		if team.id != my_team:
			continue
		hurt_today.append([h[1], h[2], h[3]])
		if career_player != "":
			continue
		var who := team.player(str(h[1]))
		var called := ""
		for id: String in team.registered:
			if not before.has(id):
				called = team.player(id).name
		news.append("부상: %s (%s · %d일)%s" % [who.name if who != null else "", Injuries.CAUSES.get(str(h[3]), "부상"), int(h[2]), " → %s 1군 등록" % called if called != "" else ""])
		while news.size() > 6:
			news.remove_at(0)


## Pitchers' overalls for the bullpen roles, worked out once a day (play_day empties it):
## ratings change over a season, and a cache kept from the first day, which a saved game
## does not carry, gave a season continued and the same season loaded different closers.
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
	# The manager's own order goes with the squad (anyone not in it today is replaced).
	view.batting_plan = team.batting_plan
	view.rotation_plan = team.rotation_plan
	var managed: Club = clubs.get(team.id)
	var actives: Array[ClubRules.ColorDef] = []
	if managed != null:
		actives = TeamColors.active(team, managed, club_rules, ovr, catalog)
	# Relievers in order of rest, so a manager's "anybody else" is the freshest arm.
	var first := team.first_team()
	first.sort_custom(func(a: Player, b: Player) -> bool: return usage.rest_days(a.id, on_day) > usage.rest_days(b.id, on_day))
	for p: Player in first:
		# The injured are out (a club whose every man counts as registered keeps them listed).
		if injuries.is_out(p.id):
			continue
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
		# The league's strength by the difficulty, for every club but the manager's.
		if my_team != "" and team.id != my_team:
			factor += Difficulty.league_form(difficulty)
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


## The day's growth (Development): every player of a club that played today, faster for
## those who played (first team or second).
func _develop_day() -> void:
	var playing: Dictionary[String, bool] = {}
	for g: ScheduledGame in games_today():
		if g.played and postseason_of(g) == null:
			playing[g.away] = true
			playing[g.home] = true
	for team_id: String in playing:
		for p: Player in (teams[team_id] as Team).players:
			if p.potential <= 0.0:
				continue
			var played := played_today.has(p.id) or (farm != null and farm.played_today.has(p.id))
			var gain := Development.grow_day(p, season_year - p.born, played, games_per_team)
			if gain > 0.0:
				grown[p.id] = float(grown.get(p.id, 0.0)) + gain
	played_today.clear()
	if farm != null:
		farm.played_today.clear()


## Today's scouting candidates for the player's club.
func refresh_candidates(report: int = 0) -> void:
	if club == null or club_rules == null:
		return
	if _names == null:
		_names = RosterIO.load_names()
	var key := "scout:%d:%d" % [season_year, day] + (":%d" % report if report > 0 else "")
	var gen := LeagueGenerator.new(_names, catalog, hash(key))
	club.candidates = Scouting.candidates(gen, division_of(club.team_id), club.scout_level, club_rules)
	# Every day's generator numbers its men from one: tell the days (and reports) apart, or
	# two men signed on different days would share an id.
	for p: Player in club.candidates:
		p.id = "s%d_%d_%d_%s" % [season_year, day, report, p.id.trim_prefix("s")]
	# A second report the same day is new names, not a second signing.
	if report == 0:
		club.signed_today = false
		club.reported_today = false


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
			if p.is_pitcher() and not injuries.is_out(p.id) and (chosen == null or usage.rest_days(p.id, on_day) > usage.rest_days(chosen.id, on_day)):
				chosen = p
	else:
		for k: int in rotation.size():
			var p := rotation[(team.rotation_index + k) % rotation.size()]
			if usage.can_start(p.id, on_day) and not injuries.is_out(p.id):
				chosen = p
				team.rotation_index = (team.rotation_index + k + 1) % rotation.size()
				break
		if chosen == null:
			for p: Player in rotation:
				if not injuries.is_out(p.id) and (chosen == null or usage.rest_days(p.id, on_day) > usage.rest_days(chosen.id, on_day)):
					chosen = p
		if chosen == null:
			chosen = rotation[0]
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
		if sitting.get(p.id, -1) >= on_day or injuries.is_out(p.id):
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
	_note_injuries(game, game_book, state)
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
		played_today[id] = true
		if playoff == null:
			_note_recent(id, line, game.day)
	for side: String in [game.away, game.home]:
		for p: Player in (teams[side] as Team).first_team():
			if not p.is_pitcher():
				streak[p.id] = int(streak.get(p.id, 0)) + 1 if played.has(p.id) else 0
	if club != null and game.involves(club.team_id):
		# A game the manager played on screen pays by its difficulty (Difficulty.REWARDS).
		var share := Difficulty.reward(played_level, "club") if played_level >= 0 else 1.0
		club.earn(signi(game.runs_of(club.team_id) - game.runs_against(club.team_id)), playoff != null, club_rules, share)
		if played_level >= 0:
			level_games[clampi(played_level, 0, 3)] += 1
		played_level = -1
		involvement_sum += maxf(played_share, 0.0)
		involvement_games += 1
		played_share = -1.0
	for id: String in game_book.pitching:
		var line: PitchingLine = game_book.pitching[id]
		target.pitch(id).add(line)
		usage.note(id, game.day, line.pitches)
		played_today[id] = true
	# The followed men's lines of this game (GameLog): his club's, or a career's own player.
	var followed := _followed(game)
	if not followed.is_empty():
		GameLog.note(game_logs, followed, game, game_book, "고교" if school else ("PS" if playoff != null else "1군"))


## The men whose games are kept (GameLog) in a game: the person's club's when he manages one,
## the career's own player when there is one; id → his side.
func _followed(game: ScheduledGame) -> Dictionary:
	var out := {}
	if career_player != "":
		for side: String in [game.away, game.home]:
			if (teams[side] as Team).player(career_player) != null:
				out[career_player] = side
		return out
	if my_team != "" and game.involves(my_team) and history == null:
		for p: Player in (teams[my_team] as Team).players:
			out[p.id] = my_team
	return out


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
	_overall_cache.clear()
	if farm != null:
		farm.play_day(self, games_today())
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
	_develop_day()
	hurt_today.clear()
	healed_today = injuries.heal_day()
	if phase != Phase.OVER and my_team != "":
		level_days[clampi(difficulty, 0, 3)] += 1
	day += 1
	_overnight()
	# The clubs' call-ups and send-downs, with or without a second teams' league (ratings and
	# first-team form when there is none).
	if phase == Phase.REGULAR and my_team != "" and (farm != null or history == null) and day % RosterMoves.EVERY_DAYS == 0:
		RosterMoves.weekly(self)
	if phase == Phase.REGULAR and regular_season_over():
		phase = Phase.POSTSEASON
		postseasons.clear()
		for d: int in divisions.size():
			postseasons.append(Postseason.from_standings(standings[d], day + Postseason.REST_BETWEEN, postseason_format(d)))
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


## A division's postseason: a season of the past as that year had it; the top division the
## KBO's five clubs from the wild card to the 한국시리즈; the divisions under it a ladder of four.
func postseason_format(d: int) -> Array[Postseason.Round]:
	if history != null:
		return history.postseason_format()
	if school:
		return SchoolLeague.playoff()
	return Postseason.kbo() if d == 0 else Postseason.ladder()


## The difficulty the season was managed at, for what asks for a harder game (an achievement
## for a title won at 올스타 or harder): the hardest level at which, or harder, seven in ten of
## at least ten games played on screen were played. 0 (any) otherwise.
func managed_level() -> int:
	var total := 0
	for n: int in level_games:
		total += n
	if total < 10:
		return 0
	for level: int in [3, 2, 1]:
		var at_least := 0
		for l: int in range(level, 4):
			at_least += level_games[l]
		if float(at_least) >= 0.7 * total:
			return level
	return 0


## A division's postseason champion ("" until it is decided).
func champion_of(d: int) -> String:
	if d < 0 or d >= postseasons.size() or not postseasons[d].finished():
		return ""
	return postseasons[d].champion()


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
