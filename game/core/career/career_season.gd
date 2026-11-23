class_name CareerSeason
extends RefCounted
## A career player's season: the league season around him,
## his second-team games until he is called up, his first-team games after, and what each game
## earns him.
##
## In a league of the KBO's ten clubs his second team plays in the futures
## league (FarmLeague: twelve teams, north and south, on its own calendar). In an older league
## of three divisions the second team plays the same days as the first, against the same
## club's second team, made up with fillers at second-team level (A).
##
## Up and down are his manager's judgement on how he is playing (the user, 2026-11-23: "sent
## down when he slumps or needs a rest, not too strictly; called up again when he plays well
## in the second team"), not on his ratings: called up after a good run in his recent second-
## team games (CALL_UP_*), not every time at once; sent down after a poor run in his recent
## first-team games (DOWN_*).

const FILLER_ROLES: Array[String] = ["SP", "SP", "SP", "RP", "RP", "RP", "C", "1B", "2B", "SS", "3B", "LF", "CF", "RF"]
## Second-team talent below the division's first teams (as LeagueGenerator.FARM_GAP).
const FARM_GAP := 13.0
## Call-up: a hitter with this OPS over this many second-team plate appearances; a pitcher with
## this ERA over this many outs (starter, reliever); or anyone at least as good as the weakest
## first-teamer in his place after this many games. (Measured with tools/balance_report.gd: at
## 30 PA, .780 and five games a rookie was up on the fourth day, and the second team meant
## nothing; now a month or so, sooner for a hot start.)
## Called up: over his last RECENT second-team games a hitter with this OPS in at least this
## many plate appearances, a pitcher with this ERA in at least this many outs (starter,
## reliever); then on each such day the call comes with CALL_CHANCE (a manager waits for the
## right moment), and never in the first CALL_UP_MIN_GAMES second-team games of a season.
const RECENT := 12
const CALL_UP_OPS := 0.8
const CALL_UP_PA := 30
const CALL_UP_ERA := 3.5
const CALL_UP_OUTS_SP := 27
const CALL_UP_OUTS_RP := 12
const CALL_CHANCE := 0.5
const CALL_UP_MIN_GAMES := 8
## Sent down: over his last RECENT first-team games OPS under this in at least this many
## plate appearances, or ERA over this in at least this many outs.
const DOWN_OPS := 0.48
const DOWN_PA := 35
const DOWN_ERA := 7.0
const DOWN_OUTS := 18


class Report:
	var played := false
	var first_team := false
	## A postseason game (its numbers are not in the regular season's book).
	var postseason := false
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
## His last RECENT games' lines, second team and first team ([pa, ab, hits, doubles, triples,
## home runs, walks, hbp, sac flies] for a hitter; [outs, earned runs] for a pitcher).
var recent_futures: Array = []
var recent_first: Array = []
## Days in a row in the second team this season (the long stays: CareerEvents).
var futures_days := 0
## The length of his pro seasons (chosen when he was made; a high-school season is its own).
var pro_games := 144
## Regular-season days on the first team this season (CareerContract), the salary owed but not
## yet a whole unit, and the events told once (CareerEvents).
var first_team_days := 0
var salary_paid := 0.0
var events_seen := PackedStringArray()
## The winter after this season (CareerSession.start_winter): what he was told, free agency's
## offers ([club id, years, money a year]) and, released, the club that signs him.
var winter_lines := PackedStringArray()
var fa_offers: Array = []
var release_team := ""
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
## The cutscenes waiting to be shown (Ceremony): [kind, heading, big line, more
## lines, the club he left (a trade)], kinds &"draft", &"contract", &"award", &"champion",
## &"trade", &"call_up". Shown by the career's screen and gone; not saved (a scene missed by
## quitting is not owed).
var cues: Array = []


func cue(kind: StringName, heading: String, big: String, more: PackedStringArray = PackedStringArray(), from_id: String = "") -> void:
	cues.append([kind, heading, big, more, from_id])


static func start(league: Season, c: CareerPlayer, career_rules: CareerRules) -> CareerSeason:
	var cs := CareerSeason.new()
	cs.season = league
	cs.career = c
	cs.rules = career_rules
	league.my_team = c.team_id
	league.career_player = c.player.id
	cs.start_day()
	return cs


## His second team plays in the futures league on its own calendar.
func farm_mode() -> bool:
	return season.farm != null and season.farm.schedule != null


## The first-team games of the day are played: all of them while he is in the second team,
## all but his club's once he is up (that one is his to play).
func start_day() -> void:
	season.featured = career.player.id if career.first_team else ""
	season.featured_role = career.position
	if season.farm != null:
		season.farm.held = career.team_id if farm_mode() and not career.first_team else ""
	season.play_day(not career.first_team)


## His game today: his club's first-team game once he is up; before that his second team's in
## the futures league (or, in an older league, his club's first-team game, whose opponent his
## second team plays). Null on an off day or after the season.
func club_game() -> ScheduledGame:
	if farm_mode() and not career.first_team:
		return season.farm.game_of(season, career.team_id)
	for g: ScheduledGame in season.games_today():
		if g.involves(career.team_id):
			return g
	return null


## A side of today's game as a club (for the screens): a first team, a second team, or one of
## the futures league's own teams.
func side_team(team_id: String) -> Team:
	if farm_mode() and not career.first_team:
		return season.farm.team_of(season, team_id)
	return season.teams.get(team_id)


## Whether he has a game still to play today: his club's first-team game once he is up, a
## second-team game on his club's game days before that (the regular season only).
func has_game() -> bool:
	var g := club_game()
	if g == null or season.injuries.is_out(career.player.id):
		return false
	if career.first_team:
		return not g.played
	return season.phase == Season.Phase.REGULAR and _futures_day != season.day


func next_day() -> void:
	season.advance()
	_after_day()
	start_day()
	_check_all_star()


## Overnight for him: hurt (Injuries: on the injured list, off the first team; back to the
## second team to play his way back when he is healed), and another day in the second team.
func _after_day() -> void:
	var id := career.player.id
	if season.school:
		# A school has no second team: out while hurt, back in the side when healed.
		var team: Team = season.teams[career.team_id]
		if not season.injuries.is_out(id) and not team.registered.has(id):
			team.registered.append(id)
		return
	if season.injuries.is_out(id):
		if career.first_team:
			career.first_team = false
			season.featured = ""
			recent_first.clear()
			log.append("%d일: 부상자 명단 (%s, %d일)" % [season.day + 1, season.injuries.cause_of(id), season.injuries.days_left(id)])
	elif season.healed_today.has(id):
		log.append("%d일: 부상 회복, 2군에서 재활" % (season.day + 1))
		recent_futures.clear()
	if season.phase == Season.Phase.REGULAR:
		if career.first_team:
			first_team_days += 1
		else:
			futures_days += 1
		CareerContract.pay_day(self)
	CareerEvents.day(self)

## Mid-season: the all-star picks and the derby. The career player's part waits for him; the
## rest is settled at once.
func _check_all_star() -> void:
	var share := float(rules.all_star.get("at_share", 0.5))
	if season.school or all_star_done or season.phase != Season.Phase.REGULAR or season.day < int(season.total_days() * share):
		return
	all_star_done = true
	var d := season.division_of(career.team_id)
	all_star_selected = AllStar.select(season, d, career, int(rules.all_star.get("players", 22)))
	var me := career.player.id
	# The fans' vote announced (AllStarVote), whether he is in it or not.
	var board := AllStar.board(season, d, all_star_selected, career)
	var said := "아쉽게도 이번 올스타에는 뽑히지 못했습니다"
	if all_star_selected.has(me):
		said = "올스타 선정! 감독 추천으로 합류합니다"
		for line: String in board:
			var f := line.split("|")
			if f.size() >= 6 and f[5] == "1":
				said = "올스타 선정! %s %s 부문 · %s표" % [AllStar.TEAM_NAMES[int(f[0])].substr(0, 2), f[1], AllStarVote._thousands(int(f[4]))]
	cue(&"all_star_vote", "%d 올스타 팬 투표 최종 결과" % season.season_year, said, board)
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
	var away := season.farm.futures_team(season, g.away) if farm_mode() else _futures_team(g.away)
	var home := season.farm.futures_team(season, g.home) if farm_mode() else _futures_team(g.home)
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
	report.postseason = season.phase == Season.Phase.POSTSEASON
	var id := career.player.id
	if special == "all_star":
		return _finish_all_star(state, book, report)
	var g := club_game()
	# His first-team totals before this game, for the milestones it reaches (Milestones).
	var totals_before := CareerContract.totals(career, self) if career.first_team and not report.postseason else []
	if career.first_team:
		season.record(g, state, book)
		if not totals_before.is_empty():
			_milestones(totals_before, g)
	else:
		futures_games += 1
		_futures_day = season.day
		if farm_mode():
			season.farm.record_game(g, state, book)
		# His second-team game into his log (GameLog).
		var played := ScheduledGame.new()
		played.day = season.day
		played.away = g.away
		played.home = g.home
		played.finish(state.score[0], state.score[1], state.inning)
		var side := g.away if my_side(state) == 0 else g.home
		GameLog.note(season.game_logs, {id: side}, played, book, "2군")
		if book.batting.has(id):
			futures_book.bat(id).add(book.batting[id])
		if book.pitching.has(id):
			futures_book.pitch(id).add(book.pitching[id])
	var bat: BattingLine = book.batting.get(id)
	var pitch: PitchingLine = book.pitching.get(id)
	_note_recent(recent_first if career.first_team else recent_futures, bat, pitch)
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
	var picked_up := CareerEvents.after_game(self, report)
	if picked_up != "":
		report.evolved.append(picked_up)
	for change: String in report.evolved:
		log.append("%d일: 구종 진화 %s" % [season.day + 1, change])
	if season.school:
		pass
	elif not career.first_team and ready_for_call_up() and Rng.new(hash("call:%d:%d:%s" % [season.season_year, season.day, id])).chance(CALL_CHANCE):
		call_up()
		report.called_up = career.first_team
	elif career.first_team and season.phase == Season.Phase.REGULAR and overmatched():
		send_down()
		report.sent_down = true
	return report


## The milestones this game reached: kept on the career, a ceremony with the ball for each.
func _milestones(before: Array, g: ScheduledGame) -> void:
	var after := CareerContract.totals(career, self)
	var other := g.home if g.away == career.team_id else g.away
	var vs: Team = season.teams.get(other)
	var vs_name := vs.name if vs != null else ""
	for m: Array in Milestones.crossed(before, after, career.is_pitcher()):
		career.milestones.append([str(m[0]), season.season_year, season.day + 1, vs_name])
		cue(&"milestone", "%d년 %d일차 · vs %s" % [season.season_year, season.day + 1, vs_name], str(m[1]), PackedStringArray(["기념구"]))
		log.append("%s 달성! 기념구를 챙겼습니다" % str(m[1]))


## A game's line into his last RECENT.
static func _note_recent(into: Array, bat: BattingLine, pitch: PitchingLine) -> void:
	if pitch != null and pitch.outs + pitch.batters_faced > 0:
		into.append([pitch.outs, pitch.earned_runs])
	elif bat != null and bat.pa > 0:
		into.append([bat.pa, bat.ab, bat.hits, bat.doubles, bat.triples, bat.home_runs, bat.walks, bat.hit_by_pitch, bat.sac_flies])
	else:
		return
	while into.size() > RECENT:
		into.remove_at(0)


## A hitter's recent games as one line.
static func recent_batting(lines: Array) -> BattingLine:
	var b := BattingLine.new()
	for l: Array in lines:
		if l.size() < 9:
			continue
		b.pa += int(l[0])
		b.ab += int(l[1])
		b.hits += int(l[2])
		b.doubles += int(l[3])
		b.triples += int(l[4])
		b.home_runs += int(l[5])
		b.walks += int(l[6])
		b.hit_by_pitch += int(l[7])
		b.sac_flies += int(l[8])
	return b


## A pitcher's recent games as one line.
static func recent_pitching(lines: Array) -> PitchingLine:
	var q := PitchingLine.new()
	for l: Array in lines:
		if l.size() != 2:
			continue
		q.outs += int(l[0])
		q.earned_runs += int(l[1])
	return q


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
	# Ten days after being sent down (KBO), whatever his numbers; and hurt, not at all.
	if team.removed_on.has(id) and season.day - team.removed_on[id] < Team.RECALL_DAYS:
		return false
	if season.injuries.is_out(id):
		return false
	# A few games first (fewer in a short season).
	if futures_games < mini(CALL_UP_MIN_GAMES, maxi(season.games_per_team / 12, 3)):
		return false
	if career.is_pitcher():
		var q := recent_pitching(recent_futures)
		var need := CALL_UP_OUTS_SP if career.position == "SP" else CALL_UP_OUTS_RP
		return q.outs >= need and q.era() <= CALL_UP_ERA
	var b := recent_batting(recent_futures)
	return b.pa >= CALL_UP_PA and b.ops() >= CALL_UP_OPS


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
	recent_first.clear()
	futures_days = 0
	log.append("%d일: 1군 등록" % (season.day + 1))
	var first := not events_seen.has("first_call_up")
	if first:
		events_seen.append("first_call_up")
	cue(&"call_up", "%d년 %s" % [season.season_year, team.name], "첫 1군 등록" if first else "1군 등록", PackedStringArray(["%d일 · 퓨처스에서 올라왔습니다" % (season.day + 1)]))


func overmatched() -> bool:
	if career.is_pitcher():
		var q := recent_pitching(recent_first)
		return q.outs >= DOWN_OUTS and q.era() > DOWN_ERA
	var b := recent_batting(recent_first)
	return b.pa >= DOWN_PA and b.ops() < DOWN_OPS


func send_down() -> void:
	var team: Team = season.teams[career.team_id]
	team.unregister(career.player.id, season.day)
	career.first_team = false
	season.featured = ""
	# He earns his way back with new numbers.
	recent_futures.clear()
	recent_first.clear()
	log.append("%d일: 2군으로" % (season.day + 1))
