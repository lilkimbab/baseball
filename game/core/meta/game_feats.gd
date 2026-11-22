class_name GameFeats
extends RefCounted
## What a game the person played counts toward the achievements (AchievementBook keys):
## his side's wins, hits, home runs, steals and strikeouts, and the feats — a walk-off, a
## comeback from five down, a grand slam, three home runs or the cycle by one man, ten
## strikeouts, a shutout, a no-hitter, a perfect game (the last three over nine innings or
## more). Followed event by event (note) for what the box score does not keep.
## In a career only his own lines count (`only`): his hits, his home runs; a no-hitter only
## if he pitched every out.

## His side (0 away, 1 home).
var side := 1
## A career's player: only his lines count ("" for the whole side).
var only := ""
var worst_deficit := 0
var grand_slams := 0
var walk_off := false


static func for_side(team: int, player_id: String = "") -> GameFeats:
	var f := GameFeats.new()
	f.side = team
	f.only = player_id
	return f


## After each event of the game.
func note(state: GameState, e: GameEvent, out: FlowOutcome) -> void:
	if side < 0 or out == null:
		return
	worst_deficit = maxi(worst_deficit, state.score[1 - side] - state.score[side])
	if e.kind == GameEvent.Kind.PLATE_APPEARANCE and e.result == PaResult.Kind.HOME_RUN and out.batting_before == side \
			and out.scored.size() >= 4 and (only == "" or out.batter_id == only):
		grand_slams += 1
	if state.over and side == 1 and out.batting_before == 1 and out.score_before[1] <= out.score_before[0] and state.score[1] > state.score[0]:
		walk_off = true


## The game over: key -> how many.
func counts(state: GameState, book: StatBook) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	var mine := state.score[side]
	var theirs := state.score[1 - side]
	var won := mine > theirs
	out["games"] = 1
	out["wins"] = 1 if won else 0
	var bat: BattingLine = book.batting.get(only) if only != "" else book.team_batting(side)
	if bat != null:
		out["hits"] = bat.hits
		out["home_runs"] = bat.home_runs
		out["steals"] = bat.stolen_bases
	var team_pitch := book.team_pitching(side)
	var pitch: PitchingLine = book.pitching.get(only) if only != "" else team_pitch
	if pitch != null:
		out["strikeouts"] = pitch.strikeouts
		out["k10"] = 1 if pitch.strikeouts >= 10 else 0
	if won:
		out["blowout"] = 1 if mine - theirs >= 10 else 0
		out["comeback"] = 1 if worst_deficit >= 5 else 0
		out["walk_off"] = 1 if walk_off else 0
	out["grand_slam"] = grand_slams
	for id: String in book.batting:
		if (only != "" and id != only) or state.teams[side].player(id) == null:
			continue
		var line: BattingLine = book.batting[id]
		if line.home_runs >= 3:
			out["three_hr"] = 1
		if line.singles() > 0 and line.doubles > 0 and line.triples > 0 and line.home_runs > 0:
			out["cycle"] = 1
	# Nine innings or more, and in a career only a game he pitched from first out to last.
	var whole := state.rules.innings >= 9 and state.inning >= 9 and (only == "" or (pitch != null and pitch.outs > 0 and pitch.outs >= team_pitch.outs))
	if won and whole:
		var against := book.team_batting(1 - side)
		out["shutout"] = 1 if theirs == 0 else 0
		out["no_hitter"] = 1 if against.hits == 0 else 0
		out["perfect"] = 1 if against.hits == 0 and against.pa <= team_pitch.outs else 0
	return out
