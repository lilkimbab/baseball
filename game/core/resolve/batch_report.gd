class_name BatchReport
extends RefCounted
## League totals from a batch of simulated games, compared with the targets of a league
## environment. Used by tools/sim_batch.gd and by the tests.

var games := 0
var batting := BattingLine.new()
var pitching := PitchingLine.new()
var runs := 0
var errors := 0
var double_plays := 0
var steal_attempts := 0
var steals := 0
var pickoffs := 0
var wild_pitches := 0
var passed_balls := 0
var ties := 0
var home_wins := 0
var decided := 0
var extra_innings := 0
var plate_appearances := 0
var starter_outs := 0
var saves := 0
var failures := 0
## Pitch-by-pitch counts when the games were played with the physical resolver.
var tally: PitchTally
var _rows := PackedStringArray()


static func run(teams: Array[Team], game_count: int, rules: RuleSet, env: LeagueEnv, catalog: Dictionary[StringName, PitchType], ovr: Overall, rng: Rng, physical: bool = false) -> BatchReport:
	var r := BatchReport.new()
	if physical:
		r.tally = PitchTally.new()
	for g: int in game_count:
		var away := teams[g % teams.size()]
		var home := teams[(g + 1 + (g / teams.size()) % (teams.size() - 1)) % teams.size()]
		var sim := GameSim.create(away, home, rules, env, catalog, ovr, rng.fork(g), null, null, physical)
		if physical:
			(sim.resolver as PhysicalResolver).tally = r.tally
		var counter := EventCounter.new()
		var guard := 0
		while not sim.state.over and guard < GameSim.MAX_EVENTS:
			var event := sim.resolver.next_event(sim.state)
			var out := GameFlow.apply(sim.state, event)
			sim.scorer.record(sim.state, event, out)
			sim.manager.note_change(sim.state, event)
			counter.count(event)
			guard += 1
		sim.scorer.finish(sim.state)
		r._add(sim, counter)
	return r


## Adds another batch's totals to this one.
func merge(other: BatchReport) -> void:
	games += other.games
	batting.add(other.batting)
	pitching.add(other.pitching)
	runs += other.runs
	errors += other.errors
	double_plays += other.double_plays
	steal_attempts += other.steal_attempts
	steals += other.steals
	pickoffs += other.pickoffs
	wild_pitches += other.wild_pitches
	passed_balls += other.passed_balls
	ties += other.ties
	home_wins += other.home_wins
	decided += other.decided
	extra_innings += other.extra_innings
	starter_outs += other.starter_outs
	saves += other.saves
	if other.tally != null:
		if tally == null:
			tally = PitchTally.new()
		tally.merge(other.tally)


func _add(sim: GameSim, counter: EventCounter) -> void:
	games += 1
	var book := sim.scorer.book
	for t: int in 2:
		batting.add(book.team_batting(t))
		pitching.add(book.team_pitching(t))
		errors += book.errors[t]
		double_plays += book.double_plays[t]
		starter_outs += book.pitch(sim.state.teams[t].starter_id).outs
	runs += sim.state.score[0] + sim.state.score[1]
	steal_attempts += counter.steal_attempts
	steals += counter.steals
	pickoffs += counter.pickoffs
	wild_pitches += counter.wild_pitches
	passed_balls += counter.passed_balls
	if sim.state.winner < 0:
		ties += 1
	else:
		decided += 1
		if sim.state.winner == GameState.HOME:
			home_wins += 1
	if sim.state.inning > sim.state.rules.innings:
		extra_innings += 1
	if book.save_id != "":
		saves += 1


func text(env: LeagueEnv) -> String:
	_rows.clear()
	failures = 0
	var team_games := games * 2.0
	var pa := float(batting.pa)
	_rows.append("%d경기, 타석 %d (경기당 %.1f)" % [games, batting.pa, pa / games])
	_rows.append("%-22s %9s %9s %9s" % ["항목", "시뮬", "목표", "허용"])
	_check("타율", batting.average(), env.targets.get("avg", 0.0), 0.008, "%.3f")
	_check("득점/팀·경기", runs / team_games, env.targets.get("runs_per_team_game", 0.0), 0.25, "%.2f")
	_check("평균자책점", pitching.era(), env.targets.get("era", 0.0), 0.30, "%.2f")
	_check("비자책점 비율", 1.0 - float(pitching.earned_runs) / maxi(pitching.runs, 1), 1.0 - 6115.0 / 6813.0, 0.025, "%.3f")
	_check("삼진/타석", (batting.strikeouts) / pa, env.rates[LeagueEnv.Outcome.K], 0.010, "%.3f")
	_check("볼넷/타석", (batting.walks + batting.intentional_walks) / pa, env.rates[LeagueEnv.Outcome.BB], 0.007, "%.3f")
	_rows.append("%-22s %9.3f" % ["  고의사구/팀·경기", batting.intentional_walks / team_games])
	_check("사구/타석", batting.hit_by_pitch / pa, env.rates[LeagueEnv.Outcome.HBP], 0.003, "%.4f")
	_check("홈런/타석", batting.home_runs / pa, env.rates[LeagueEnv.Outcome.HR], 0.003, "%.4f")
	_check("2루타/타석", batting.doubles / pa, env.rates[LeagueEnv.Outcome.DOUBLE], 0.004, "%.4f")
	_check("안타/타석", batting.hits / pa, env.rates[LeagueEnv.Outcome.SINGLE] + env.rates[LeagueEnv.Outcome.DOUBLE] + env.rates[LeagueEnv.Outcome.TRIPLE] + env.rates[LeagueEnv.Outcome.HR], 0.006, "%.3f")
	_check("실책/팀·경기", errors / team_games, env.targets.get("errors_per_team_game", 0.0), 0.067, "%.3f")
	_check("병살/팀·경기", double_plays / team_games, env.targets.get("double_plays_per_team_game", 0.0), 0.084, "%.3f")
	_check("도루시도/팀·경기", steal_attempts / team_games, env.targets.get("steal_attempts_per_team_game", 0.0), 0.084, "%.3f")
	_check("도루성공률", float(steals) / maxi(steal_attempts, 1), env.targets.get("steal_success", 0.0), 0.04, "%.3f")
	_check("폭투/팀·경기", wild_pitches / team_games, env.targets.get("wild_pitches_per_team_game", 0.0), 0.06, "%.3f")
	_check("포일/팀·경기", passed_balls / team_games, env.targets.get("passed_balls_per_team_game", 0.0), 0.015, "%.3f")
	_check("견제사/팀·경기", pickoffs / team_games, env.targets.get("pickoffs_per_team_game", 0.0), 0.012, "%.3f")
	_check("무승부 비율", float(ties) / games, 0.031, 0.015, "%.3f")
	_check("홈 승률", float(home_wins) / maxi(decided, 1), 0.530, 0.025, "%.3f")
	_check("타석/경기(양팀)", pa / games, 77.0, 5.0, "%.1f")
	_check("투구수/팀·경기", pitching.pitches / team_games, 145.0, 10.0, "%.1f")
	_rows.append("%-22s %9s" % ["출루율", BattingLine.rate_text(batting.on_base())])
	_rows.append("%-22s %9s" % ["장타율", BattingLine.rate_text(batting.slugging())])
	_rows.append("%-22s %9s" % ["인플레이 타율", BattingLine.rate_text(batting.babip())])
	_rows.append("%-22s %9.2f" % ["선발 이닝/경기", starter_outs / team_games / 3.0])
	_rows.append("%-22s %9.3f" % ["연장 비율", float(extra_innings) / games])
	_rows.append("%-22s %9.3f" % ["세이브/경기", float(saves) / games])
	if tally != null:
		_rows.append("")
		_rows.append(tally.text())
		failures += tally.failures
	return "\n".join(_rows)


func _check(label: String, value: float, target: float, tolerance: float, format: String) -> void:
	var bad := absf(value - target) > tolerance
	if bad:
		failures += 1
	_rows.append("%-22s %9s %9s %9s %s" % [label, format % value, format % target, "±" + (format % tolerance), "!!" if bad else ""])


## Counts running plays, which the box score does not keep per team.
class EventCounter:
	extends RefCounted
	var steal_attempts := 0
	var steals := 0
	var pickoffs := 0
	var wild_pitches := 0
	var passed_balls := 0

	func count(event: GameEvent) -> void:
		match event.kind:
			GameEvent.Kind.STEAL:
				steal_attempts += 1
				if not event.moves[0].is_out():
					steals += 1
			GameEvent.Kind.PICKOFF:
				pickoffs += 1
			GameEvent.Kind.WILD_PITCH:
				wild_pitches += 1
			GameEvent.Kind.PASSED_BALL:
				passed_balls += 1
