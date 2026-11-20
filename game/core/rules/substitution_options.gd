class_name SubstitutionOptions
extends RefCounted
## Who a manager can send in now, and the substitution events for it (docs/13 S5-11). A
## player who has left the game cannot come back, and a change is only offered if the team
## is still legal after it.


## Relievers who have not pitched today and are not out of the game.
static func relievers(team: TeamInGame) -> Array[String]:
	var out: Array[String] = []
	for id: String in team.bullpen:
		if team.is_available(id) and not team.pitchers_used.has(id) and id != team.pitcher_id:
			out.append(id)
	return out


## Position players on the bench who can still come in.
static func bench(team: TeamInGame) -> Array[String]:
	var out: Array[String] = []
	for id: String in team.bench:
		if team.is_available(id) and team.slot_of(id) < 0:
			out.append(id)
	return out


static func pitcher_change(state: GameState, team_index: int, in_id: String) -> GameEvent:
	var team := state.teams[team_index]
	return GameEvent.substitution(team_index, GameEvent.Change.PITCHER, team.pitcher_id, in_id, Position.Kind.P)


static func pinch_hitter(state: GameState, in_id: String) -> GameEvent:
	return GameEvent.substitution(state.batting(), GameEvent.Change.PINCH_HITTER, state.batter_id(), in_id, Position.Kind.PH)


static func pinch_runner(state: GameState, base: int, in_id: String) -> GameEvent:
	var on := state.runner_on(base)
	return GameEvent.substitution(state.batting(), GameEvent.Change.PINCH_RUNNER, on.player_id if on != null else "", in_id, Position.Kind.PR)


static func defensive_change(team_index: int, out_id: String, in_id: String, at: Position.Kind) -> GameEvent:
	return GameEvent.substitution(team_index, GameEvent.Change.DEFENSE, out_id, in_id, at)


## Problems the change would cause, tried on a copy of the game. Empty when it is allowed.
static func check(state: GameState, event: GameEvent) -> PackedStringArray:
	var team := state.teams[event.team]
	if event.out_id == "":
		return PackedStringArray(["교체할 선수가 없다"])
	if event.change == GameEvent.Change.PITCHER:
		if not relievers(team).has(event.in_id):
			return PackedStringArray(["%s 선수는 등판할 수 없다" % event.in_id])
	elif not bench(team).has(event.in_id):
		return PackedStringArray(["%s 선수는 들어갈 수 없다" % event.in_id])
	var trial := state.duplicate_state()
	GameFlow.apply(trial, event)
	var batting_side := event.change == GameEvent.Change.PINCH_HITTER or event.change == GameEvent.Change.PINCH_RUNNER
	return trial.teams[event.team].validate(not batting_side)
