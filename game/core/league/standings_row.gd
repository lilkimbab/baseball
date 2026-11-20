class_name StandingsRow
extends RefCounted
## One club's line in the standings.

var team_id := ""
var wins := 0
var losses := 0
var ties := 0
var runs_for := 0
var runs_against := 0
var home := Vector3i.ZERO
var away := Vector3i.ZERO
## Wins (+) or losses (−) in a row; a tie ends a run.
var streak := 0
## The last ten results, oldest first: 1 win, 0 tie, −1 loss.
var last_ten := PackedInt32Array()
## Against each opponent: wins, losses, ties.
var head_to_head: Dictionary[String, Vector3i] = {}


func games() -> int:
	return wins + losses + ties


## KBO winning percentage: ties do not count.
func pct() -> float:
	var decided := wins + losses
	return float(wins) / decided if decided > 0 else 0.0


func run_difference() -> int:
	return runs_for - runs_against


func against(team: String) -> Vector3i:
	return head_to_head.get(team, Vector3i.ZERO)


func add(result: int, opponent: String, at_home: bool, scored: int, allowed: int) -> void:
	var v := Vector3i(1, 0, 0) if result > 0 else (Vector3i(0, 1, 0) if result < 0 else Vector3i(0, 0, 1))
	wins += v.x
	losses += v.y
	ties += v.z
	runs_for += scored
	runs_against += allowed
	if at_home:
		home += v
	else:
		away += v
	head_to_head[opponent] = against(opponent) + v
	if result == 0:
		streak = 0
	elif signi(streak) == result:
		streak += result
	else:
		streak = result
	last_ten.append(result)
	if last_ten.size() > 10:
		last_ten.remove_at(0)


## "3연승", "2연패", or "" after a tie or before the first game.
func streak_text() -> String:
	if streak > 0:
		return "%d연승" % streak
	if streak < 0:
		return "%d연패" % -streak
	return ""


## "6승 1무 3패" over the last ten.
func last_ten_text() -> String:
	var w := 0
	var l := 0
	var t := 0
	for r: int in last_ten:
		if r > 0:
			w += 1
		elif r < 0:
			l += 1
		else:
			t += 1
	return "%d승 %d무 %d패" % [w, t, l] if t > 0 else "%d승 %d패" % [w, l]


## ".587" the scorebook way.
func pct_text() -> String:
	return BattingLine.rate_text(pct())
