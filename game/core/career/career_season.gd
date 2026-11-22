class_name CareerSeason
extends RefCounted
## A career player's season (docs/02 section 6.4, docs/13 S8-3): the league season around him,
## his second-team games until he is called up, his first-team games after, and what each game
## earns him.
##
## The second team plays the same days as the first, against the same club's second team.
## Second teams are short of players, so each gets fillers made at second-team level (A). A
## rookie is called up when his second-team numbers or his ratings are good enough for the
## first team (CALL_UP_*), and sent back down if he is overmatched there.

const FILLER_ROLES: Array[String] = ["SP", "SP", "SP", "RP", "RP", "RP", "C", "1B", "2B", "SS", "3B", "LF", "CF", "RF"]
## Second-team talent below the division's first teams (as LeagueGenerator.FARM_GAP).
const FARM_GAP := 13.0
## Call-up: a hitter with this OPS over this many second-team plate appearances; a pitcher with
## this ERA over this many outs (starter, reliever); or anyone at least as good as the weakest
## first-teamer in his place after this many games. (Measured with tools/balance_report.gd: at
## 30 PA, .780 and five games a rookie was up on the fourth day, and the second team meant
## nothing; now a month or so, sooner for a hot start.)
const CALL_UP_OPS := 0.85
const CALL_UP_PA := 60
const CALL_UP_ERA := 3.0
const CALL_UP_OUTS_SP := 45
const CALL_UP_OUTS_RP := 24
const CALL_UP_GAP := 0.0
const CALL_UP_MIN_GAMES := 20
## Sent down: OPS under this over this many first-team plate appearances, or ERA over this
## over this many outs.
const DOWN_OPS := 0.45
const DOWN_PA := 60
const DOWN_ERA := 7.5
const DOWN_OUTS := 45


class Report:
	var played := false
	var first_team := false
	var gp: Dictionary[String, float] = {}
	var goal := ""
	var goal_met := false
	var called_up := false
	var sent_down := false
	var line := ""
	var evolved := PackedStringArray()
	var rating := 0.0
	var medal := 0
	var reward := ""


var season: Season
var career: CareerPlayer
var rules: CareerRules
var futures: Dictionary[String, Team] = {}
## Second-team lines (only the career player's matter), and his games there.
var futures_book := StatBook.new()
var futures_games := 0
var _futures_day := -1
## The all-star break: held once at mid-season. Who was picked, whether the career player's
## all-star game and derby turn are still to come, the derby's home runs.
var all_star_done := false
var all_star_selected: Array[String] = []
var all_star_today := false
var derby: Dictionary[String, int] = {}
var derby_waiting := false
## "all_star" while the all-star game is the game being played.
var special := ""
static var _names: NameTable
## Popularity from games.
var log := PackedStringArray()


static func start(league: Season, c: CareerPlayer, career_rules: CareerRules) -> CareerSeason:
	var cs := CareerSeason.new()
	cs.season = league
	cs.career = c
	cs.rules = career_rules
	league.my_team = c.team_id
	cs.start_day()
	return cs


## The first-team games of the day are played: all of them while he is in the second team,
## all but his club's once he is up (that one is his to play).
func start_day() -> void:
	season.featured = career.player.id if career.first_team else ""
	season.featured_role = career.position
	season.play_day(not career.first_team)


## His club's game today (first team), or null on an off day or after the season.
func club_game() -> ScheduledGame:
	for g: ScheduledGame in season.games_today():
		if g.involves(career.team_id):
			return g
	return null


## Whether he has a game still to play today: his club's first-team game once he is up, a
## second-team game on his club's game days before that (the regular season only).
func has_game() -> bool:
	var g := club_game()
	if g == null:
		return false
	if career.first_team:
		return not g.played
	return season.phase == Season.Phase.REGULAR and _futures_day != season.day


func next_day() -> void:
	season.advance()
	start_day()
	_check_all_star()


## Mid-season: the all-star picks and the derby. The career player's part waits for him; the
## rest is settled at once.
func _check_all_star() -> void:
	var share := float(rules.all_star.get("at_share", 0.5))
	if all_star_done or season.phase != Season.Phase.REGULAR or season.day < int(season.total_days() * share):
		return
	all_star_done = true
	var d := season.division_of(career.team_id)
	all_star_selected = AllStar.select(season, d, career, int(rules.all_star.get("players", 22)))
	var me := career.player.id
	if all_star_selected.has(me):
		all_star_today = true
		career.popularity += 5.0
		log.append("%d일: 올스타 선정" % (season.day + 1))
	var field := AllStar.derby_field(season, d, career, all_star_selected, int(rules.all_star.get("derby", 8)))
	var outs := int(rules.all_star.get("derby_outs", 10))
	var rng := Rng.new(hash("derby:%d" % season.season_year))
	for id: String in field:
		if id == me:
			derby_waiting = true
			continue
		var p := _find(id)
		derby[id] = AllStar.derby_swings(p.batting.power() if p != null else 50.0, outs, rng)
	if not derby_waiting:
		_derby_winner()


func _find(id: String) -> Player:
	for t: Team in season.teams.values():
		var p := t.player(id)
		if p != null:
			return p
	return null


func _derby_winner() -> String:
	var best := ""
	for id: String in derby:
		if best == "" or derby[id] > derby[best]:
			best = id
	if best != "":
		var p := _find(best)
		log.append("홈런 더비 우승: %s (%d개)" % [p.name if p != null else best, derby[best]])
		if best == career.player.id:
			career.popularity += 8.0
			career.points += 80
	return best


## The career player's derby turn is over (played on screen or at once).
func finish_derby(home_runs: int) -> String:
	derby[career.player.id] = home_runs
	derby_waiting = false
	return _derby_winner()


func quick_derby() -> String:
	var outs := int(rules.all_star.get("derby_outs", 10))
	return finish_derby(AllStar.derby_swings(career.player.batting.power(), outs, Rng.new(hash("mine:%d" % season.season_year))))


## Which side he is on in a game being played.
func my_side(state: GameState) -> int:
	if special == "all_star":
		return 0 if state.teams[0].players.has(career.player.id) else 1
	return 0 if club_game().away == career.team_id else 1


# --- His game ---


## Today's game for him, ready to play: the first-team game with the season's line-ups, or a
## second-team game between the two clubs' second teams.
func prepare(physical: bool) -> GameSim:
	if special == "all_star":
		var d := season.division_of(career.team_id)
		var sides := AllStar.teams(season, d, all_star_selected, career)
		return GameSim.create(sides[0], sides[1], RuleSet.kbo_2026(), season.env, season.catalog, season.ovr, season.rng.fork(hash("allstar:%d" % season.season_year)), null, null, physical)
	var g := club_game()
	if career.first_team:
		season.featured = career.player.id
		return season.prepare(g, physical)
	var away := _futures_team(g.away)
	var home := _futures_team(g.home)
	var r := RuleSet.kbo_2026()
	# He plays: a second team's manager has filler players who may be better than a rookie
	# (a catcher's career never got a game); his career is about him playing.
	var manager := AiManager.new(season.env, season.catalog, season.ovr)
	var must: Dictionary[String, bool] = {}
	var none: Dictionary[String, bool] = {}
	if not career.is_pitcher():
		must[career.player.id] = true
	var lineups: Array[TeamInGame] = []
	for side: Team in [away, home]:
		var his := side.player(career.player.id) != null
		var starter := side.next_starter()
		if career.position == "SP" and his and futures_games % 5 == 0:
			starter = career.player
		lineups.append(manager.make_lineup(side, r, starter.id, none, must if his else none))
	return GameSim.with_lineups(lineups[0], lineups[1], r, season.env, season.catalog, manager, season.rng.fork(hash("f%d:%s" % [season.day, g.home])), physical)


func _futures_team(team_id: String) -> Team:
	if futures.has(team_id):
		return futures[team_id]
	var team: Team = season.teams[team_id]
	var view := Team.new()
	view.id = team_id
	view.name = team.name + " 2군"
	view.short_name = team.short_name
	view.stadium = team.stadium
	view.primary = team.primary
	view.secondary = team.secondary
	view.accent = team.accent
	for p: Player in team.second_team():
		view.players.append(p)
	var d := season.division_of(team_id)
	var mean := LeagueGenerator.DIVISION_MEANS[mini(d, LeagueGenerator.DIVISION_MEANS.size() - 1)] - FARM_GAP
	if _names == null:
		_names = RosterIO.load_names()
	var gen := LeagueGenerator.new(_names, season.catalog, hash("futures:" + team_id))
	for i: int in FILLER_ROLES.size():
		var p := gen.player(FILLER_ROLES[i], mean)
		p.id = "f_%s_%d" % [team_id, i]
		view.players.append(p)
	futures[team_id] = view
	return view


## Plays his game at once (when he does not play it on screen). Returns what it earned.
func quick() -> Report:
	var sim := prepare(false)
	var chances := 0
	var errors := 0
	var my_team := my_side(sim.state)
	var guard := 0
	while not sim.state.over and guard < GameSim.MAX_EVENTS:
		var fielding := sim.state.fielding()
		var e := sim.resolver.next_event(sim.state)
		var out := GameFlow.apply(sim.state, e)
		sim.scorer.record(sim.state, e, out)
		sim.manager.note_change(sim.state, e)
		if fielding == my_team:
			var c := fielding_credit(e)
			chances += c.x
			errors += c.y
		guard += 1
	sim.scorer.finish(sim.state)
	return finish(sim.state, sim.scorer.book, chances, errors)


## Chances (balls he handled) and errors for him in an event, from the scorebook string.
func fielding_credit(e: GameEvent) -> Vector2i:
	if career.is_pitcher() and e.kind == GameEvent.Kind.PLATE_APPEARANCE and e.fielders.begins_with("1"):
		return Vector2i(1, 0)
	var number := str(career.player.primary_position() + 1)
	var credit := Vector2i.ZERO
	if e.fielders == "":
		return credit
	for part: String in e.fielders.split("-"):
		if part == number:
			credit.x = 1
		elif part == "E" + number:
			credit.y = 1
	return credit


## The game is over: into the books (the season's, or the second team's), growth points for
## his lines and his game goal, popularity, and a call-up or a trip down.
func finish(state: GameState, book: StatBook, chances: int, errors: int, scene_gp: Dictionary[String, float] = {}, clutch: int = 0, pitches_seen: Dictionary[StringName, int] = {}, level: int = -1) -> Report:
	var report := Report.new()
	report.played = true
	report.first_team = career.first_team
	var id := career.player.id
	if special == "all_star":
		return _finish_all_star(state, book, report)
	var g := club_game()
	if career.first_team:
		season.record(g, state, book)
	else:
		futures_games += 1
		_futures_day = season.day
		if book.batting.has(id):
			futures_book.bat(id).add(book.batting[id])
		if book.pitching.has(id):
			futures_book.pitch(id).add(book.pitching[id])
	var bat: BattingLine = book.batting.get(id)
	var pitch: PitchingLine = book.pitching.get(id)
	var gp := Growth.from_game(bat, pitch, chances, errors, rules)
	for field: String in scene_gp:
		gp[field] = float(gp.get(field, 0.0)) + scene_gp[field]
	var goal := GameGoal.for_player(career, rules)
	report.goal = goal.label()
	report.goal_met = goal.achieved(bat, pitch)
	if report.goal_met:
		gp[goal.field] = float(gp.get(goal.field, 0.0)) + rules.game_goal_gp
	# Played on screen: by its difficulty (Difficulty.REWARDS); simulated: 프로's at most.
	var gp_share := Difficulty.reward(level if level >= 0 else Difficulty.Level.PRO, "gp", level >= 0)
	for field: String in gp:
		gp[field] = float(gp[field]) * gp_share
	Growth.add(career, gp)
	report.gp = gp
	career.popularity += (1.0 if career.first_team else 0.3) * (1.0 + clutch + (1.0 if report.goal_met else 0.0))
	report.line = _line_text(bat, pitch)
	if (bat != null and bat.pa > 0) or (pitch != null and pitch.outs > 0):
		report.rating = GameRating.rate(bat, pitch, chances, errors, report.goal_met, clutch, rules)
		report.medal = GameRating.medal(report.rating, rules)
		var before := career.points
		report.reward = GameRating.open_box(career, report.medal, rules, Rng.new(hash("box:%d:%d" % [season.season_year, season.day])))
		# A box's points by the difficulty too.
		if career.points > before and level >= 0:
			career.points = before + roundi((career.points - before) * Difficulty.reward(level, "points"))
		career.ratings.append(report.rating)
	if pitch != null:
		PitchEvolution.note_game(career, pitch.pitches, pitches_seen)
	report.evolved = PitchEvolution.check(career, rules, season.catalog)
	for change: String in report.evolved:
		log.append("%d일: 구종 진화 %s" % [season.day + 1, change])
	if not career.first_team and ready_for_call_up():
		call_up()
		report.called_up = career.first_team
	elif career.first_team and overmatched():
		send_down()
		report.sent_down = true
	return report


## The all-star game counts for nothing in the season; it brings popularity, a few growth
## points, and for its MVP a prize.
func _finish_all_star(state: GameState, book: StatBook, report: Report) -> Report:
	special = ""
	all_star_today = false
	var id := career.player.id
	var bat: BattingLine = book.batting.get(id)
	var pitch: PitchingLine = book.pitching.get(id)
	var gp := Growth.from_game(bat, pitch, 0, 0, rules)
	Growth.add(career, gp)
	report.gp = gp
	report.goal = "올스타전"
	report.line = _line_text(bat, pitch)
	career.popularity += 3.0
	var mvp := GameMvp.pick(state, book)
	if mvp == id:
		career.popularity += 10.0
		career.points += 100
		report.reward = "올스타전 MVP: 포인트 +100"
	log.append("올스타전 %s %d : %d %s%s" % [AllStar.TEAM_NAMES[0], state.score[0], state.score[1], AllStar.TEAM_NAMES[1], "  (MVP)" if mvp == id else ""])
	return report


## Plays the all-star game at once.
func quick_all_star() -> Report:
	special = "all_star"
	return quick()


func _line_text(bat: BattingLine, pitch: PitchingLine) -> String:
	if pitch != null and pitch.outs > 0:
		return "%s이닝 %d실점 %d탈삼진" % [pitch.innings_text(), pitch.runs, pitch.strikeouts]
	if bat != null and bat.pa > 0:
		return BottomBar.today_batting(bat)
	return "출전하지 않음"


# --- Up and down ---


func ready_for_call_up() -> bool:
	var id := career.player.id
	var team: Team = season.teams[career.team_id]
	# Ten days after being sent down (KBO), whatever his numbers.
	if team.removed_on.has(id) and season.day - team.removed_on[id] < Team.RECALL_DAYS:
		return false
	if career.is_pitcher():
		var p: PitchingLine = futures_book.pitching.get(id)
		var need := CALL_UP_OUTS_SP if career.position == "SP" else CALL_UP_OUTS_RP
		if p != null and p.outs >= need and p.era() <= CALL_UP_ERA:
			return true
	else:
		var b: BattingLine = futures_book.batting.get(id)
		if b != null and b.pa >= CALL_UP_PA and b.ops() >= CALL_UP_OPS:
			return true
	# A month or so of a 144-game season; a short season's share of it.
	if futures_games < mini(CALL_UP_MIN_GAMES, season.games_per_team / 4):
		return false
	var weakest := weakest_in_place()
	return weakest != null and _ovr(career.player) >= _ovr(weakest) - CALL_UP_GAP


## The weakest first-teamer in his place: same pitching role, or same main position.
func weakest_in_place() -> Player:
	var team: Team = season.teams[career.team_id]
	var worst: Player = null
	for p: Player in team.first_team():
		if p.id == career.player.id:
			continue
		var same := p.role() == career.player.role() if career.is_pitcher() else (not p.is_pitcher() and p.primary_position() == career.player.primary_position())
		if same and (worst == null or _ovr(p) < _ovr(worst)):
			worst = p
	return worst


func _ovr(p: Player) -> float:
	return ClubRules.player_ovr(p, season.ovr, season.catalog)


func call_up() -> void:
	var team: Team = season.teams[career.team_id]
	var out := weakest_in_place()
	if out != null:
		team.unregister(out.id, season.day)
	if team.registration_problem(career.player.id, season.day, season.rules) != "":
		# Full for another reason: the weakest of the whole first team goes down.
		var worst: Player = null
		for p: Player in team.first_team():
			if worst == null or _ovr(p) < _ovr(worst):
				worst = p
		team.unregister(worst.id, season.day)
	if not team.register(career.player.id, season.day, season.rules):
		return
	career.first_team = true
	log.append("%d일: 1군 등록" % (season.day + 1))


func overmatched() -> bool:
	var id := career.player.id
	if career.is_pitcher():
		var p: PitchingLine = season.book.pitching.get(id)
		return p != null and p.outs >= DOWN_OUTS and p.era() > DOWN_ERA
	var b: BattingLine = season.book.batting.get(id)
	return b != null and b.pa >= DOWN_PA and b.ops() < DOWN_OPS


func send_down() -> void:
	var team: Team = season.teams[career.team_id]
	team.unregister(career.player.id, season.day)
	career.first_team = false
	season.featured = ""
	# He earns his way back with new numbers.
	futures_book = StatBook.new()
	futures_games = 0
	log.append("%d일: 2군으로" % (season.day + 1))
