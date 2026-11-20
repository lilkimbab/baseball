class_name StatBook
extends RefCounted
## The record of one game: every batter's and pitcher's line, the line score, errors, men left
## on base, and the pitchers credited with the win, loss, save and holds.

var batting: Dictionary[String, BattingLine] = {}
var pitching: Dictionary[String, PitchingLine] = {}
## Order players appeared, per team, for the box score.
var batters: Array[PackedStringArray] = [PackedStringArray(), PackedStringArray()]
var pitchers: Array[PackedStringArray] = [PackedStringArray(), PackedStringArray()]
var hits := PackedInt32Array([0, 0])
var errors := PackedInt32Array([0, 0])
## Walks and hit batsmen (the B in R H E B).
var bases_on_balls := PackedInt32Array([0, 0])
var left_on_base := PackedInt32Array([0, 0])
## Double plays turned by each team's defence.
var double_plays := PackedInt32Array([0, 0])
var winner_id := ""
var loser_id := ""
var save_id := ""
var hold_ids := PackedStringArray()


func bat(id: String) -> BattingLine:
	if not batting.has(id):
		batting[id] = BattingLine.new()
	return batting[id]


func pitch(id: String) -> PitchingLine:
	if not pitching.has(id):
		pitching[id] = PitchingLine.new()
	return pitching[id]


func team_batting(team: int) -> BattingLine:
	var total := BattingLine.new()
	for id: String in batters[team]:
		total.add(batting[id])
	return total


func team_pitching(team: int) -> PitchingLine:
	var total := PitchingLine.new()
	for id: String in pitchers[team]:
		total.add(pitching[id])
	return total


## The game written out the way a newspaper box score is.
func box_score(state: GameState) -> String:
	var lines := PackedStringArray()
	var innings := maxi(state.line[0].size(), state.line[1].size())
	var header := "      "
	for i: int in innings:
		header += "%3d" % (i + 1)
	header += "     R  H  E  B"
	lines.append(header)
	for t: int in 2:
		var row := "%-6s" % state.teams[t].short_name
		for i: int in innings:
			row += "%3s" % (str(state.line[t][i]) if i < state.line[t].size() else "X")
		row += "  %3d%3d%3d%3d" % [state.score[t], hits[t], errors[t], bases_on_balls[t]]
		lines.append(row)
	for t: int in 2:
		var team := state.teams[t]
		lines.append("")
		lines.append("%s 타자          타수 득점 안타 타점 볼넷 삼진  타율" % team.name)
		for id: String in batters[t]:
			var b := batting[id]
			var p := team.player(id)
			lines.append("  %-14s %4d %4d %4d %4d %4d %4d  %s" % [p.name if p != null else id, b.ab, b.runs, b.hits, b.rbi, b.walks + b.intentional_walks + b.hit_by_pitch, b.strikeouts, BattingLine.rate_text(b.average())])
		lines.append("%s 투수          이닝 타자 투구 안타 실점 자책 볼넷 삼진" % team.name)
		for id: String in pitchers[t]:
			var pl := pitching[id]
			var p := team.player(id)
			var mark := ""
			if id == winner_id:
				mark = " 승"
			elif id == loser_id:
				mark = " 패"
			elif id == save_id:
				mark = " 세"
			elif hold_ids.has(id):
				mark = " 홀"
			lines.append("  %-14s %4s %4d %4d %4d %4d %4d %4d %4d%s" % [p.name if p != null else id, pl.innings_text(), pl.batters_faced, pl.pitches, pl.hits, pl.runs, pl.earned_runs, pl.walks + pl.intentional_walks + pl.hit_by_pitch, pl.strikeouts, mark])
		lines.append("  잔루 %d  병살(수비) %d" % [left_on_base[t], double_plays[t]])
	return "\n".join(lines)
