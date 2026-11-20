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
## this ERA over this many outs (starter, reliever); or anyone within this many overall points of
## the weakest first-teamer in his place after a few games.
const CALL_UP_OPS := 0.78
const CALL_UP_PA := 30
const CALL_UP_ERA := 3.6
const CALL_UP_OUTS_SP := 30
const CALL_UP_OUTS_RP := 15
const CALL_UP_GAP := 2.0
const CALL_UP_MIN_GAMES := 5
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


var season: Season
var career: CareerPlayer
var rules: CareerRules
var futures: Dictionary[String, Team] = {}
## Second-team lines (only the career player's matter), and his games there.
var futures_book := StatBook.new()
var futures_games := 0
var _futures_day := -1
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


# --- His game ---


## Today's game for him, ready to play: the first-team game with the season's line-ups, or a
## second-team game between the two clubs' second teams.
func prepare(physical: bool) -> GameSim:
	var g := club_game()
	if career.first_team:
		season.featured = career.player.id
		return season.prepare(g, physical)
	var away := _futures_team(g.away)
	var home := _futures_team(g.home)
	var r := RuleSet.kbo_2026()
	return GameSim.create(away, home, r, season.env, season.catalog, season.ovr, season.rng.fork(hash("f%d:%s" % [season.day, g.home])), null, null, physical)


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
	var my_team := 0 if club_game().away == career.team_id else 1
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
func finish(state: GameState, book: StatBook, chances: int, errors: int, scene_gp: Dictionary[String, float] = {}, clutch: int = 0, pitches_seen: Dictionary[StringName, int] = {}) -> Report:
	var report := Report.new()
	report.played = true
	report.first_team = career.first_team
	var g := club_game()
	var id := career.player.id
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
	Growth.add(career, gp)
	report.gp = gp
	career.popularity += (1.0 if career.first_team else 0.3) * (1.0 + clutch + (1.0 if report.goal_met else 0.0))
	report.line = _line_text(bat, pitch)
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
	if futures_games < CALL_UP_MIN_GAMES:
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
