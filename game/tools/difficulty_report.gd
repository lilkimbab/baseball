extends SceneTree
## How hard the game is at the plate for a person (the user, 2026-11-22: "is the game's
## difficulty right — judge it from the player's side"). Plays whole games with the physical
## resolver; one club's batters are a model of a person at the controls — he sees where the
## pitch will cross (the arrival ring), swings at what he reads as a strike (and chases some),
## and his swing is off by a person's timing and aiming errors — the other side and every
## pitcher are the computer. Prints his club's line by skill:
##   novice   timing ±60 ms, aim ±8 cm, chases 35%
##   average  timing ±40 ms, aim ±5 cm, chases 20%
##   expert   timing ±25 ms, aim ±3 cm, chases 10%
## (± one standard deviation). The KBO 2025 line for comparison: .262 / .337 / .384, K 19%.
##
##   godot --headless --path game --script res://tools/difficulty_report.gd -- [--games 20] [--level average] [--difficulty pro]

const LEVELS := {
	"novice": [0.060, 0.08, 0.35, 0.80],
	"average": [0.040, 0.05, 0.20, 0.85],
	"expert": [0.025, 0.03, 0.10, 0.90],
}


## A person at the plate (see the top). Pitches are the computer's.
class Person extends Controller:
	var ai: AiController
	var rng: Rng
	var timing := 0.04
	var aim := 0.05
	var chase := 0.2
	var swing_zone := 0.85
	var power_share := 0.3

	## He pitches too: the computer's choice of pitch and spot (a person picks much the same),
	## let go by hand with his timing error on the gauge (DuelScene.gauge_accuracy).
	var pitches := true

	func choose_pitch(state: GameState, duel: PitchDuel) -> PitchDecision:
		var d := ai.choose_pitch(state, duel)
		if pitches and d != null:
			d.by_hand = true
			d.quality = clampf(1.0 - absf(rng.next_normal() * timing) / (1.15 * 0.25), 0.0, 1.0)
		return d

	func react(state: GameState, duel: PitchDuel) -> void:
		var crossing := Vector2(duel.pitch.plate_pos.x, duel.pitch.plate_pos.z)
		var in_zone := duel.zone.contains(crossing.x, crossing.y, 0.0)
		var near := duel.zone.distance_outside(crossing.x, crossing.y) < 0.12
		var want := swing_zone if in_zone else (chase if near else chase * 0.2)
		# Two strikes: he protects.
		if state.strikes == 2:
			want = minf(want + (0.1 if in_zone else 0.1), 1.0)
		if state.balls == 3 and state.strikes < 2 and not in_zone:
			want *= 0.5
		if not rng.chance(want):
			return
		var kind := SwingAttempt.Kind.POWER if rng.chance(power_share if state.strikes < 2 else 0.05) else SwingAttempt.Kind.CONTACT
		var when := duel.ideal_contact_time + rng.next_normal() * timing
		var at := Vector2(duel.ideal_contact_pos.x, duel.ideal_contact_pos.z) + Vector2(rng.next_normal(), rng.next_normal()) * aim
		duel.swing_at(when, kind, at, true)


func _init() -> void:
	var args := CmdArgs.parse(OS.get_cmdline_user_args())
	var games := int(args.get("games", "20"))
	var only := str(args.get("level", ""))
	_difficulty = Difficulty.by_id(str(args.get("difficulty", "pro")))
	print("difficulty: %s" % Difficulty.NAMES[_difficulty])
	print("            (his batting)                                         (batting against his pitching)")
	print("level      games  W-L    R/G   avg / obp / slg     K%    BB%   HR/G   R/G   avg / obp / slg     K%    BB%   HR/G")
	for level: String in LEVELS:
		if only != "" and level != only:
			continue
		_measure(level, games)
	quit()


var _difficulty: int = Difficulty.Level.PRO


func _measure(level: String, games: int) -> void:
	var p: Array = LEVELS[level]
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	var season := Season.create(clubs, 10, 36, 77, RuleSet.kbo_2026(), LeagueEnvIO.load_default(), PitchCatalogIO.load_default(), LeagueEnvIO.load_overall(), ClubIO.load_default())
	var wins := 0
	var losses := 0
	var runs := 0
	var total := BattingLine.new()
	var against := BattingLine.new()
	var runs_against := 0
	var played := 0
	var day := 0
	while played < games and day < 200:
		for g: ScheduledGame in season.schedules[0].games_on(day):
			if played >= games:
				break
			var sim := season.prepare(g, true)
			# The person bats for the home side.
			var person := Person.new()
			person.ai = sim.resolver.controllers[1] as AiController
			person.rng = Rng.new(hash("%s:%d" % [level, played]))
			person.timing = float(p[0])
			person.aim = float(p[1])
			person.chase = float(p[2])
			person.swing_zone = float(p[3])
			sim.resolver.controllers[1] = person
			var physical := sim.resolver as PhysicalResolver
			physical.person_bats = 1
			physical.person_pitches = 1
			physical.difficulty = _difficulty
			sim.play()
			var line := sim.scorer.book.team_batting(1)
			total.add(line)
			against.add(sim.scorer.book.team_batting(0))
			runs += sim.state.score[1]
			runs_against += sim.state.score[0]
			if sim.state.score[1] > sim.state.score[0]:
				wins += 1
			elif sim.state.score[1] < sim.state.score[0]:
				losses += 1
			played += 1
		day += 1
	var g := maxf(played, 1.0)
	print("%-9s  %5d  %2d-%-2d  %4.1f   %s   %4.1f  %s" % [level, played, wins, losses, runs / g, _line(total, g), runs_against / g, _line(against, g)])


func _line(b: BattingLine, games: float) -> String:
	var pa := maxf(float(b.pa), 1.0)
	return "%s / %s / %s   %4.1f  %4.1f  %4.2f" % [BattingLine.rate_text(b.average()), BattingLine.rate_text(b.on_base()), BattingLine.rate_text(b.slugging()),
		100.0 * b.strikeouts / pa, 100.0 * (b.walks + b.intentional_walks) / pa, float(b.home_runs) / games]
