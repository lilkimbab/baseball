class_name RulesFixture
extends RefCounted
## Games set up for rules tests: two made-up clubs, line-ups chosen by the computer manager.

static var _catalog: Dictionary[StringName, PitchType] = {}
static var _env: LeagueEnv
static var _ovr: Overall


static func catalog() -> Dictionary[StringName, PitchType]:
	if _catalog.is_empty():
		_catalog = PitchCatalogIO.load_default()
	return _catalog


static func env() -> LeagueEnv:
	if _env == null:
		_env = LeagueEnvIO.load_default()
	return _env


static func overall() -> Overall:
	if _ovr == null:
		_ovr = LeagueEnvIO.load_overall()
	return _ovr


static func teams(seed_value: int = 1) -> Array[Team]:
	var gen := LeagueGenerator.new(RosterIO.load_names(), catalog(), seed_value)
	return [gen.team(0, 50.0), gen.team(1, 50.0)]


static func manager() -> AiManager:
	return AiManager.new(env(), catalog(), overall())


## A game ready for the first pitch.
static func game(rules: RuleSet = null, seed_value: int = 1) -> GameState:
	var r := rules if rules != null else RuleSet.kbo_2026()
	var t := teams(seed_value)
	var ai := manager()
	var state := GameState.new()
	state.rules = r
	state.teams = [ai.make_lineup(t[0], r, t[0].rotation()[0].id), ai.make_lineup(t[1], r, t[1].rotation()[0].id)]
	GameFlow.start(state)
	return state


## Puts runners on the given bases (1..3), let on by the current pitcher.
static func put_runners(state: GameState, bases: Array[int]) -> void:
	var team := state.batting_team()
	var used := 1
	for base: int in bases:
		var id := team.batter_at(state.order[state.batting()] + used)
		state.bases[base - 1] = BaseRunner.make(id, state.pitcher_id())
		used += 1


static func pa(result: PaResult.Kind, moves: Array[RunnerMove]) -> GameEvent:
	return GameEvent.plate_appearance(result, moves, 4)


static func move(from: int, to: int, out: RunnerMove.OutKind = RunnerMove.OutKind.NONE, error: bool = false) -> RunnerMove:
	return RunnerMove.make(from, to, out, error)


## Ends the current half-inning with three quick outs.
static func three_outs(state: GameState, scorer: Scorer = null) -> void:
	var guard := 0
	var top := state.top
	while state.top == top and not state.over and guard < 5:
		var e := pa(PaResult.Kind.STRIKEOUT, [move(0, -1, RunnerMove.OutKind.STRIKEOUT)] as Array[RunnerMove])
		var out := GameFlow.apply(state, e)
		if scorer != null:
			scorer.record(state, e, out)
		guard += 1
