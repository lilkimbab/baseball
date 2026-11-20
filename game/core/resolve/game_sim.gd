class_name GameSim
extends RefCounted
## Plays one game with a resolver: asks it for events, applies them with GameFlow and records
## them with the Scorer, until the game is over. Also writes a line of play-by-play per
## event.

const MAX_EVENTS := 2000

var state: GameState
var scorer: Scorer
var resolver: Resolver
var manager: AiManager
## One line per event, in Korean, for the play-by-play.
var log := PackedStringArray()
var keep_log := false


## A game between two clubs with the stat resolver. The starters come from each rotation
## unless given.
static func create(away: Team, home: Team, rules: RuleSet, env: LeagueEnv, catalog: Dictionary[StringName, PitchType], ovr: Overall, rng: Rng, away_starter: Player = null, home_starter: Player = null, physical: bool = false) -> GameSim:
	var manager := AiManager.new(env, catalog, ovr)
	var a_start := away_starter if away_starter != null else away.next_starter()
	var h_start := home_starter if home_starter != null else home.next_starter()
	return with_lineups(manager.make_lineup(away, rules, a_start.id), manager.make_lineup(home, rules, h_start.id), rules, env, catalog, manager, rng, physical)


## A game between two line-ups already made (a season sets them: who rests, who starts).
static func with_lineups(away: TeamInGame, home: TeamInGame, rules: RuleSet, env: LeagueEnv, catalog: Dictionary[StringName, PitchType], manager: AiManager, rng: Rng, physical: bool = false) -> GameSim:
	var sim := GameSim.new()
	sim.manager = manager
	sim.state = GameState.new()
	sim.state.rules = rules
	sim.state.teams = [away, home]
	if physical:
		sim.resolver = PhysicalResolver.new(env, catalog, sim.manager, rng)
	else:
		sim.resolver = StatResolver.new(env, catalog, sim.manager, rng)
	sim.scorer = Scorer.new()
	GameFlow.start(sim.state)
	sim.scorer.start(sim.state)
	sim.manager.start_game(sim.state)
	return sim


func play() -> void:
	var guard := 0
	while not state.over and guard < MAX_EVENTS:
		step()
		guard += 1
	if not state.over:
		push_error("GameSim: the game did not finish in %d events" % MAX_EVENTS)
	scorer.finish(state)


## Plays one event. Returns false once the game is over.
func step() -> bool:
	if state.over:
		return false
	var event := resolver.next_event(state)
	var inning := state.inning
	var top := state.top
	var outs := state.outs
	var bases := _bases_text()
	var batter := state.batter_id()
	var out := GameFlow.apply(state, event)
	scorer.record(state, event, out)
	manager.note_change(state, event)
	# Single pitches (the physical resolver) are not lines of their own in the play-by-play.
	if keep_log and event.kind != GameEvent.Kind.PITCH:
		log.append(_describe(event, out, inning, top, outs, bases, batter))
	return not state.over


func _bases_text() -> String:
	var names: Array[String] = []
	for base: int in [1, 2, 3]:
		if not state.base_empty(base):
			names.append(str(base))
	return "주자 없음" if names.is_empty() else "%s루" % "·".join(names)


func _describe(event: GameEvent, out: FlowOutcome, inning: int, top: bool, outs: int, bases: String, batter_id: String) -> String:
	var team := state.teams[out.batting_before]
	var where := "%d회%s %d사 %s" % [inning, "초" if top else "말", outs, bases]
	var text := ""
	match event.kind:
		GameEvent.Kind.SUBSTITUTION:
			var t := state.teams[event.team]
			var who := t.player(event.in_id)
			var gone := t.player(event.out_id)
			match event.change:
				GameEvent.Change.PITCHER:
					text = "%s 투수 교체: %s → %s" % [t.short_name, gone.name if gone != null else event.out_id, who.name]
				GameEvent.Change.PINCH_HITTER:
					text = "%s 대타: %s (%s 대신)" % [t.short_name, who.name, gone.name]
				GameEvent.Change.PINCH_RUNNER:
					text = "%s 대주자: %s (%s 대신)" % [t.short_name, who.name, gone.name]
				GameEvent.Change.DEFENSE:
					text = "%s 수비 교체: %s (%s 대신 %s)" % [t.short_name, who.name, gone.name, Position.name_of(event.position)]
				GameEvent.Change.POSITION:
					text = "%s %s, %s로" % [t.short_name, who.name, Position.name_of(event.position)]
			return text
		GameEvent.Kind.STEAL:
			var runner := team.player(out.runner_ids[0])
			text = "%s %s" % [runner.name if runner != null else "주자", "도루 성공" if not event.moves[0].is_out() else "도루 실패"]
		GameEvent.Kind.PICKOFF:
			text = "견제사"
		GameEvent.Kind.WILD_PITCH:
			text = "폭투, 주자 진루"
		GameEvent.Kind.PASSED_BALL:
			text = "포일, 주자 진루"
		GameEvent.Kind.PLATE_APPEARANCE:
			var batter := team.player(batter_id)
			text = "%s: %s" % [batter.name if batter != null else batter_id, play_text(event, out)]
	var runs := out.scored.size()
	if runs > 0:
		text += ", %d점" % runs
	text += ". %d-%d" % [state.score[0], state.score[1]]
	if out.walk_off:
		text += " 끝내기"
	return "%s  %s" % [where, text]


## The result written the way a broadcaster or scorebook would: "유격수 땅볼", "좌중간 2루타".
static func play_text(event: GameEvent, out: FlowOutcome) -> String:
	var where := Position.name_of(event.direction - 1 as Position.Kind) if event.direction >= 1 and event.direction <= 9 else ""
	match event.result:
		PaResult.Kind.SINGLE, PaResult.Kind.DOUBLE, PaResult.Kind.TRIPLE, PaResult.Kind.HOME_RUN:
			var bases := out.credited_bases
			var hit := PaResult.text(PaResult.hit_of_bases(bases))
			return "%s %s" % [_field_side(event.direction, bases), hit] if where != "" else hit
		PaResult.Kind.GROUND_OUT:
			return "%s 땅볼" % where
		PaResult.Kind.FLY_OUT:
			return "%s 뜬공" % where
		PaResult.Kind.LINE_OUT:
			return "%s 직선타" % where + (" 병살" if out.outs_made >= 2 else "")
		PaResult.Kind.POP_OUT:
			return "%s 뜬공" % where
		PaResult.Kind.DOUBLE_PLAY:
			return "%s 땅볼 병살 (%s)" % [where, event.fielders]
		PaResult.Kind.FIELDERS_CHOICE:
			return "%s 앞 땅볼, 야수 선택" % where if event.result == PaResult.Kind.FIELDERS_CHOICE and where != "투수" else "야수 선택"
		PaResult.Kind.SAC_FLY:
			return "%s 희생 플라이" % where
		PaResult.Kind.REACHED_ON_ERROR:
			return "%s 실책으로 출루" % where
	return PaResult.text(event.result)


## "좌전 안타", "좌익수 쪽 2루타", "좌월 홈런", "내야 안타".
static func _field_side(direction: int, bases: int) -> String:
	if direction < 7:
		return "내야"
	var side: String = ["좌", "중", "우"][direction - 7]
	if bases == 1:
		return side + "전"
	if bases == 4:
		return side + "월"
	return ["좌익수", "중견수", "우익수"][direction - 7] + " 쪽"
