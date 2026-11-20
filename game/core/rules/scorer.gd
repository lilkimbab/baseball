class_name Scorer
extends RefCounted
## Keeps the official record of a game from its events: batting and pitching lines, runs
## batted in, earned runs, errors, and the winning, losing, saving and holding pitchers
## (docs/12 section 5.3).

## Facts about one pitcher's time on the mound, for saves and holds.
class Appearance:
	extends RefCounted
	var team := 0
	var lead_at_entry := 0
	## He came in to protect a lead of three or less, or with the tying run on base, at bat
	## or on deck.
	var save_situation := false
	var tying_run_close := false
	var lead_at_exit := 0
	var left := false
	## His team lost the lead while he pitched.
	var relinquished := false

var book := StatBook.new()

var _appearances: Dictionary[String, Appearance] = {}
## The last time a team took the lead: which team, its pitcher of record, the pitcher charged
## with the go-ahead run, and every pitcher's outs at that moment.
var _go_ahead_team := -1
var _go_ahead_pitcher := ""
var _go_ahead_loser := ""
var _outs_at_go_ahead: Dictionary[String, int] = {}


## Records who starts: the nine in each order and the two starting pitchers.
func start(state: GameState) -> void:
	for t: int in 2:
		var team := state.teams[t]
		for slot: LineupSlot in team.lineup:
			_appear_batter(t, slot.player_id)
		_appear_pitcher(state, t, team.pitcher_id)
		book.pitch(team.pitcher_id).starts = 1


func record(state: GameState, event: GameEvent, out: FlowOutcome) -> void:
	var batting := out.batting_before
	var fielding := 1 - batting
	match event.kind:
		GameEvent.Kind.SUBSTITUTION:
			_substitution(state, event)
			return
		GameEvent.Kind.PITCH:
			book.pitch(out.pitcher_id).pitches += 1
			return
		GameEvent.Kind.PLATE_APPEARANCE:
			_plate_appearance(event, out, batting, fielding)
		GameEvent.Kind.STEAL:
			for i: int in event.moves.size():
				var id := out.runner_ids[i]
				if id == "" or out.applied[i] == 0:
					continue
				if event.moves[i].is_out():
					book.bat(id).caught_stealing += 1
				elif event.moves[i].to > event.moves[i].from:
					book.bat(id).stolen_bases += 1
		GameEvent.Kind.WILD_PITCH:
			book.pitch(out.pitcher_id).wild_pitches += 1

	book.pitch(out.pitcher_id).outs += out.outs_made
	if event.result == PaResult.Kind.REACHED_ON_ERROR or _has_error(event):
		book.errors[fielding] += 1
	for run: ScoredRun in out.scored:
		book.bat(run.runner.player_id).runs += 1
		var charged := book.pitch(run.runner.responsible_pitcher_id)
		charged.runs += 1
		if run.earned:
			charged.earned_runs += 1
	if out.half_over:
		book.left_on_base[batting] += out.left_on_base
	_follow_lead(state, out)


func _plate_appearance(event: GameEvent, out: FlowOutcome, batting: int, fielding: int) -> void:
	var b := book.bat(out.charged_batter_id)
	var p := book.pitch(out.charged_pitcher_id)
	var result := event.result
	b.pa += 1
	p.batters_faced += 1
	book.pitch(out.pitcher_id).pitches += event.pitches
	if PaResult.is_at_bat(result):
		b.ab += 1
	match result:
		PaResult.Kind.WALK:
			b.walks += 1
			p.walks += 1
		PaResult.Kind.INTENTIONAL_WALK:
			b.intentional_walks += 1
			p.intentional_walks += 1
		PaResult.Kind.HIT_BY_PITCH:
			b.hit_by_pitch += 1
			p.hit_by_pitch += 1
		PaResult.Kind.STRIKEOUT, PaResult.Kind.DROPPED_THIRD_STRIKE:
			b.strikeouts += 1
			p.strikeouts += 1
		PaResult.Kind.SAC_BUNT:
			b.sac_bunts += 1
		PaResult.Kind.SAC_FLY:
			b.sac_flies += 1
		PaResult.Kind.REACHED_ON_ERROR:
			b.reached_on_error += 1
		PaResult.Kind.DOUBLE_PLAY:
			b.double_plays += 1
			book.double_plays[fielding] += 1
		PaResult.Kind.TRIPLE_PLAY:
			book.double_plays[fielding] += 1
	if PaResult.is_hit(result):
		b.hits += 1
		p.hits += 1
		book.hits[batting] += 1
		match out.credited_bases:
			2:
				b.doubles += 1
			3:
				b.triples += 1
			4:
				b.home_runs += 1
				p.home_runs += 1
	if PaResult.is_walk(result) or result == PaResult.Kind.HIT_BY_PITCH:
		book.bases_on_balls[batting] += 1
	# Runs batted in always go to the batter who finished the plate appearance.
	var finisher := book.bat(out.batter_id)
	for run: ScoredRun in out.scored:
		if run.rbi:
			finisher.rbi += 1


func _has_error(event: GameEvent) -> bool:
	for m: RunnerMove in event.moves:
		if m.on_error:
			return true
	return false


func _substitution(state: GameState, event: GameEvent) -> void:
	if event.change == GameEvent.Change.PITCHER:
		var leaving := event.out_id
		if _appearances.has(leaving):
			_appearances[leaving].left = true
			_appearances[leaving].lead_at_exit = state.lead_of(event.team)
		_appear_pitcher(state, event.team, event.in_id)
	elif event.change != GameEvent.Change.POSITION:
		_appear_batter(event.team, event.in_id)


func _appear_batter(team: int, id: String) -> void:
	if not book.batters[team].has(id):
		book.batters[team].append(id)
		book.bat(id).games = 1


func _appear_pitcher(state: GameState, team: int, id: String) -> void:
	if book.pitchers[team].has(id):
		return
	book.pitchers[team].append(id)
	book.pitch(id).games = 1
	var a := Appearance.new()
	a.team = team
	a.lead_at_entry = state.lead_of(team)
	# The tying run is on base, at bat or on deck.
	a.tying_run_close = a.lead_at_entry > 0 and a.lead_at_entry <= state.runners_on() + 2
	a.save_situation = a.lead_at_entry > 0 and (a.lead_at_entry <= 3 or a.tying_run_close)
	_appearances[id] = a


## Watches the score for lead changes and for relief pitchers losing a lead.
func _follow_lead(state: GameState, out: FlowOutcome) -> void:
	var batting := out.batting_before
	var score := out.score_before.duplicate()
	for run: ScoredRun in out.scored:
		var before := score[batting] - score[1 - batting]
		score[batting] += 1
		if before == 0:
			# This run puts the batting team ahead.
			_go_ahead_team = batting
			_go_ahead_pitcher = state.teams[batting].pitcher_id
			_go_ahead_loser = run.runner.responsible_pitcher_id
			_outs_at_go_ahead.clear()
			for id: String in book.pitching:
				_outs_at_go_ahead[id] = book.pitching[id].outs
	var fielding := 1 - batting
	var on_mound := state.teams[fielding].pitcher_id
	if _appearances.has(on_mound):
		var a := _appearances[on_mound]
		if a.lead_at_entry > 0 and state.lead_of(fielding) <= 0:
			a.relinquished = true


## Settles the decisions once the game is over.
func finish(state: GameState) -> void:
	for t: int in 2:
		var last := state.teams[t].pitcher_id
		if _appearances.has(last) and not _appearances[last].left:
			_appearances[last].lead_at_exit = state.lead_of(t)
	var w := state.winner
	if w >= 0 and _go_ahead_team == w:
		var team := state.teams[w]
		var winner := _go_ahead_pitcher
		var needed := state.rules.starter_win_innings() * 3
		if winner == team.starter_id and book.pitch(winner).outs < needed:
			# A starter who did not go far enough cannot win: the win goes to the reliever
			# who got the most outs after the lead was taken.
			var best := -1
			for id: String in book.pitchers[w]:
				if id == team.starter_id:
					continue
				var gained := book.pitch(id).outs - int(_outs_at_go_ahead.get(id, 0))
				if gained > best:
					best = gained
					winner = id
		book.winner_id = winner
		book.loser_id = _go_ahead_loser
		book.pitch(winner).wins += 1
		if _go_ahead_loser != "":
			book.pitch(_go_ahead_loser).losses += 1
		var finisher := team.pitcher_id
		if finisher != winner and _earns_save(finisher):
			book.save_id = finisher
			book.pitch(finisher).saves += 1
	for t: int in 2:
		var team := state.teams[t]
		for id: String in book.pitchers[t]:
			if id == team.starter_id or id == book.winner_id or id == book.save_id:
				continue
			if t == w and id == team.pitcher_id:
				continue
			var a := _appearances[id]
			if a.save_situation and book.pitch(id).outs >= 1 and not a.relinquished and a.lead_at_exit > 0:
				book.hold_ids.append(id)
				book.pitch(id).holds += 1


func _earns_save(id: String) -> bool:
	if not _appearances.has(id):
		return false
	var a := _appearances[id]
	var outs := book.pitch(id).outs
	if a.relinquished or outs < 1 or a.lead_at_entry <= 0:
		return false
	return (a.lead_at_entry <= 3 and outs >= 3) or a.tying_run_close or outs >= 9
