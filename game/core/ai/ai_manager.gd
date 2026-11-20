class_name AiManager
extends RefCounted
## The computer manager: line-ups, pitching changes, pinch hitters and runners, bunts and
## intentional walks (docs/13 S4-10). Limits come from the "manager" section of
## data/league_env.json.

var env: LeagueEnv
var catalog: Dictionary[StringName, PitchType]
var overall: Overall
## A team whose manager is the player (0 away, 1 home, -1 none): the computer makes only the
## changes the rules force on it (a pinch hitter taking the field), not its pitching changes
## or pinch hitters.
var manual_team := -1

## Bullpen roles per team, decided when the game starts: closer first, then set-up men.
var _closer: Array[String] = ["", ""]
var _setup: Array[PackedStringArray] = [PackedStringArray(), PackedStringArray()]
## Runs and inning at the moment each pitcher came in, to judge how his outing is going.
var _entry_runs: Dictionary[String, int] = {}
var _entry_inning: Dictionary[String, int] = {}


func _init(league: LeagueEnv, pitch_catalog: Dictionary[StringName, PitchType], ovr: Overall) -> void:
	env = league
	catalog = pitch_catalog
	overall = ovr


# --- Line-ups ---


## Builds a team for one game: the best fielder at each position, the best remaining hitter
## as designated hitter, and a batting order by the usual roles. Players in `rest` start on
## the bench (a day off, a slump) unless nobody else can play the position.
func make_lineup(team: Team, rules: RuleSet, starter_id: String, rest: Dictionary[String, bool] = {}) -> TeamInGame:
	var t := TeamInGame.new()
	t.team_id = team.id
	t.name = team.name
	t.short_name = team.short_name
	t.steal_style = team.steal_style
	t.bunt_style = team.bunt_style
	var squad := team.first_team()
	for p: Player in squad:
		t.players[p.id] = p
	if team.player(starter_id) != null:
		t.players[starter_id] = team.player(starter_id)
	var hitters: Array[Player] = []
	for p: Player in squad:
		if not p.is_pitcher():
			hitters.append(p)
	var chosen: Dictionary[Position.Kind, Player] = {}
	var used: Dictionary[String, bool] = {}
	# Hardest positions first, so a shortstop is not used up at second base.
	var order: Array[Position.Kind] = [Position.Kind.C, Position.Kind.SS, Position.Kind.CF, Position.Kind.B2, Position.Kind.B3, Position.Kind.RF, Position.Kind.LF, Position.Kind.B1]
	for kind: Position.Kind in order:
		var best: Player = null
		var best_value := -1.0
		for p: Player in hitters:
			if used.has(p.id) or p.aptitude(kind) <= 0.0:
				continue
			if Position.needs_right_hand(kind) and p.throws == &"L":
				continue
			var v := overall.batter(p, kind) * (0.6 + 0.4 * p.aptitude(kind)) - (1000.0 if rest.has(p.id) else 0.0)
			if v > best_value or best == null:
				best_value = v
				best = p
		if best != null:
			chosen[kind] = best
			used[best.id] = true
	if rules.designated_hitter:
		var best_dh: Player = null
		var best_value := -1.0
		for p: Player in hitters:
			var v := overall.batter(p, Position.Kind.DH) - (1000.0 if rest.has(p.id) else 0.0)
			if not used.has(p.id) and (v > best_value or best_dh == null):
				best_value = v
				best_dh = p
		if best_dh != null:
			chosen[Position.Kind.DH] = best_dh
			used[best_dh.id] = true
	else:
		chosen[Position.Kind.P] = team.player(starter_id)
	t.dh_active = rules.designated_hitter
	for kind: Position.Kind in _batting_order(chosen):
		t.lineup.append(LineupSlot.make(chosen[kind].id, kind))
	t.pitcher_id = starter_id
	for p: Player in squad:
		if used.has(p.id) or p.id == starter_id:
			continue
		if p.is_pitcher():
			if p.role() == &"RP":
				t.bullpen.append(p.id)
		else:
			t.bench.append(p.id)
	return t


## Batting order: a high on-base hitter leads off, the best contact hitter second, the best
## all-round hitter third, the most power fourth, then the rest by overall.
func _batting_order(chosen: Dictionary[Position.Kind, Player]) -> Array[Position.Kind]:
	var pool: Array[Position.Kind] = chosen.keys()
	var pick := func(score: Callable) -> Position.Kind:
		var best: Position.Kind = pool[0]
		var best_value := -INF
		for kind: Position.Kind in pool:
			var v: float = score.call(chosen[kind])
			if v > best_value:
				best_value = v
				best = kind
		pool.erase(best)
		return best
	var out: Array[Position.Kind] = []
	if pool.has(Position.Kind.P):
		pool.erase(Position.Kind.P)
	out.append(pick.call(func(p: Player) -> float: return p.batting.eye * 0.4 + p.batting.contact() * 0.3 + p.batting.speed * 0.3))
	out.append(pick.call(func(p: Player) -> float: return p.batting.contact() * 0.6 + p.batting.eye * 0.2 + p.batting.speed * 0.2))
	var third: Position.Kind = pick.call(func(p: Player) -> float: return p.batting.contact() * 0.5 + p.batting.power() * 0.5)
	var fourth: Position.Kind = pick.call(func(p: Player) -> float: return p.batting.power())
	out.append(third)
	out.append(fourth)
	while not pool.is_empty():
		out.append(pick.call(func(p: Player) -> float: return p.batting.contact() * 0.5 + p.batting.power() * 0.4 + p.batting.eye * 0.1))
	if chosen.has(Position.Kind.P):
		out.append(Position.Kind.P)
	return out


## Notes the bullpen roles once the line-ups are set.
func start_game(state: GameState) -> void:
	for t: int in 2:
		var team := state.teams[t]
		var relievers: Array[String] = team.bullpen.duplicate()
		relievers.sort_custom(func(a: String, b: String) -> bool:
			return Overall.pitcher(team.player(a), catalog) > Overall.pitcher(team.player(b), catalog))
		_closer[t] = relievers[0] if relievers.size() > 0 else ""
		_setup[t] = PackedStringArray(relievers.slice(1, 3))
		_note_entry(state, team.pitcher_id)


# --- Decisions during the game ---


## The next substitution the managers want before the coming plate appearance, or null.
func next_change(state: GameState) -> GameEvent:
	var defence := state.fielding()
	var fix := _fill_positions(state, defence)
	if fix != null:
		return fix
	if defence != manual_team:
		var pitching := _pitching_change(state, defence)
		if pitching != null:
			return pitching
	if state.batting() == manual_team:
		return null
	return _offensive_change(state, state.batting())


## Pinch hitters and runners keep their places on defence if they can play the position they
## took over; otherwise a bench player who can comes in.
func _fill_positions(state: GameState, t: int) -> GameEvent:
	var team := state.teams[t]
	for slot: LineupSlot in team.lineup:
		if slot.position != Position.Kind.PH and slot.position != Position.Kind.PR:
			continue
		var wanted := slot.replaced_position
		if wanted == Position.Kind.P:
			var reliever := _pick_reliever(state, t)
			return GameEvent.substitution(t, GameEvent.Change.PITCHER, team.pitcher_id, reliever, Position.Kind.P)
		var p := team.player(slot.player_id)
		if wanted == Position.Kind.DH or (p.aptitude(wanted) >= 0.5 and not (Position.needs_right_hand(wanted) and p.throws == &"L")):
			return GameEvent.substitution(t, GameEvent.Change.POSITION, slot.player_id, slot.player_id, wanted)
		var sub := _best_bench(team, wanted)
		if sub != "":
			return GameEvent.substitution(t, GameEvent.Change.DEFENSE, slot.player_id, sub, wanted)
		return GameEvent.substitution(t, GameEvent.Change.POSITION, slot.player_id, slot.player_id, wanted)
	return null


func _pitching_change(state: GameState, t: int) -> GameEvent:
	var team := state.teams[t]
	var current := team.pitcher_id
	var p := team.player(current)
	var pitches: int = state.pitch_counts.get(current, 0)
	var is_starter := current == team.starter_id
	var limit := p.pitching.starter_limit() if is_starter else p.pitching.reliever_limit()
	var runs_in_outing := state.score[1 - t] - int(_entry_runs.get(current, 0))
	var start_of_half := state.outs == 0 and state.runners_on() == 0 and state.balls == 0 and state.strikes == 0
	var lead := state.lead_of(t)
	var change := false
	if pitches >= limit:
		change = true
	elif is_starter:
		var hook_inning := int(env.value("starter_hook_inning", 5))
		if state.inning <= hook_inning and runs_in_outing >= int(env.value("starter_runs_early_hook", 5)):
			change = true
		elif start_of_half and state.inning >= state.rules.innings - 1 and _closer_wanted(state, t) and _closer[t] != "" and team.bullpen.has(_closer[t]):
			change = true
		elif start_of_half and pitches >= limit * 0.85:
			change = true
	else:
		if runs_in_outing >= int(env.value("reliever_runs_hook", 3)) and team.bullpen.size() > 0:
			change = true
		elif start_of_half and _entry_inning.get(current, state.inning) < state.inning:
			# Relievers work an inning at a time, except in a blow-out.
			change = absi(lead) <= 4 or pitches >= limit * 0.6
		elif start_of_half and _closer_wanted(state, t) and current != _closer[t] and team.bullpen.has(_closer[t]):
			change = true
	if not change:
		return null
	var reliever := _pick_reliever(state, t)
	if reliever == "" or reliever == current:
		return null
	return GameEvent.substitution(t, GameEvent.Change.PITCHER, current, reliever, Position.Kind.P)


func _closer_wanted(state: GameState, t: int) -> bool:
	var lead := state.lead_of(t)
	return state.inning >= state.rules.innings and lead > 0 and lead <= int(env.value("save_lead", 3))


## Chooses who comes in: the closer for a save, set-up men late in close games, anyone else
## otherwise (the freshest of the rest).
func _pick_reliever(state: GameState, t: int) -> String:
	var team := state.teams[t]
	var lead := state.lead_of(t)
	var available: Array[String] = []
	for id: String in team.bullpen:
		if not team.removed.has(id):
			available.append(id)
	if available.is_empty():
		return ""
	if _closer_wanted(state, t) and available.has(_closer[t]):
		return _closer[t]
	if state.inning >= state.rules.innings - 2 and lead >= -1 and lead <= 3:
		for id: String in _setup[t]:
			if available.has(id):
				return id
	var fallback := ""
	for id: String in available:
		if id == _closer[t] or _setup[t].has(id):
			continue
		return id
	fallback = available[0]
	return fallback


func _offensive_change(state: GameState, t: int) -> GameEvent:
	var team := state.teams[t]
	var late := state.inning >= int(env.value("pinch_run_from_inning", 8))
	var close := absi(state.lead_of(t)) <= 1
	# Pinch runner for a slow runner who represents an important run.
	if late and close:
		for base: int in [2, 1, 3]:
			var r := state.runner_on(base)
			if r == null:
				continue
			var runner := team.player(r.player_id)
			if runner == null or runner.batting.speed >= env.value("pinch_run_speed_below", 40.0):
				continue
			var fast := ""
			for id: String in team.bench:
				var b := team.player(id)
				if b.batting.speed >= env.value("pinch_run_speed_bench", 70.0):
					fast = id
					break
			if fast != "":
				return GameEvent.substitution(t, GameEvent.Change.PINCH_RUNNER, r.player_id, fast, Position.Kind.PR)
	# Pinch hitter late in a close game with a runner in scoring position.
	if state.inning >= int(env.value("pinch_hit_from_inning", 7)) and absi(state.lead_of(t)) <= int(env.value("pinch_hit_margin", 2)) and (state.runner_on(2) != null or state.runner_on(3) != null):
		var batter_id := state.batter_id()
		var slot := team.slot_of(batter_id)
		var current := team.player(batter_id)
		var position := team.lineup[slot].position
		var pitcher := state.fielding_team().player(state.pitcher_id())
		var current_value := _hitting_value(current, pitcher)
		var best := ""
		var best_value := current_value + env.value("pinch_hit_gap", 10.0)
		for id: String in team.bench:
			var b := team.player(id)
			# Keep the last catcher: nobody else can catch.
			if position == Position.Kind.C and not _bench_has_catcher(team, id):
				continue
			var v := _hitting_value(b, pitcher)
			if v > best_value:
				best_value = v
				best = id
		if best != "" and position != Position.Kind.C:
			return GameEvent.substitution(t, GameEvent.Change.PINCH_HITTER, batter_id, best, Position.Kind.PH)
	return null


func _bench_has_catcher(team: TeamInGame, other_than: String) -> bool:
	for id: String in team.bench:
		if id != other_than and team.player(id).aptitude(Position.Kind.C) > 0.0:
			return true
	return false


func _hitting_value(p: Player, pitcher: Player) -> float:
	var throws := pitcher.throws if pitcher != null else &"R"
	return p.batting.contact_vs(throws) * 0.45 + p.batting.power_vs(throws) * 0.40 + p.batting.eye * 0.15


func _best_bench(team: TeamInGame, kind: Position.Kind) -> String:
	var best := ""
	var best_value := 0.0
	for id: String in team.bench:
		var p := team.player(id)
		if Position.needs_right_hand(kind) and p.throws == &"L":
			continue
		var v := p.aptitude(kind) * p.fielding.overall()
		if v > best_value:
			best_value = v
			best = id
	return best


## Walk the batter on purpose: first base open, a big gap between him and the next batter,
## and the walk does not put the winning or tying run on base late in the game.
func wants_intentional_walk(state: GameState) -> bool:
	if not state.base_empty(1) or state.base_empty(2):
		return false
	if state.inning < int(env.value("intentional_walk_from_inning", 6)) or state.outs == 0:
		return false
	var team := state.batting_team()
	var pitcher := state.fielding_team().player(state.pitcher_id())
	var now := _hitting_value(team.player(state.batter_id()), pitcher)
	var next := _hitting_value(team.player(team.batter_at(state.order[state.batting()] + 1)), pitcher)
	if now - next < env.value("intentional_walk_gap", 15.0):
		return false
	var late := state.inning >= state.rules.innings - 1
	if late and state.lead_of(state.fielding()) <= 1:
		return false
	return true


## Sacrifice bunt: late in a one-run game with a runner on first (or first and second), no
## one out, and a weak hitter up.
func wants_bunt(state: GameState) -> bool:
	if state.outs != 0 or state.base_empty(1) or not state.base_empty(3):
		return false
	if state.inning < int(env.value("bunt_from_inning", 7)):
		return false
	var lead := state.lead_of(state.batting())
	if lead < -1 or lead > 0:
		return false
	var team := state.batting_team()
	var batter := team.player(state.batter_id())
	return batter.batting.contact() < env.value("bunt_contact_below", 45.0) * team.bunt_style


## Called by the game loop after each substitution, so the manager knows when a pitcher came in.
func note_change(state: GameState, event: GameEvent) -> void:
	if event.kind == GameEvent.Kind.SUBSTITUTION and event.change == GameEvent.Change.PITCHER:
		_note_entry(state, event.in_id)


func _note_entry(state: GameState, id: String) -> void:
	_entry_inning[id] = state.inning
	var t := 0 if state.teams[0].pitcher_id == id else 1
	_entry_runs[id] = state.score[1 - t]
