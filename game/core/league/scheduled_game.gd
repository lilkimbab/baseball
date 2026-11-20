class_name ScheduledGame
extends RefCounted
## One game on the season calendar, and its score once it has been played.

## Calendar day from opening day (0), off days included.
var day := 0
var away := ""
var home := ""
## Which series of the season this game belongs to, and its place in the series (1, 2, 3).
var series := 0
var game_in_series := 1
var played := false
var away_score := 0
var home_score := 0
## Innings played (more than nine for extra innings).
var innings := 9


static func make(on_day: int, away_id: String, home_id: String, series_index: int, number: int) -> ScheduledGame:
	var g := ScheduledGame.new()
	g.day = on_day
	g.away = away_id
	g.home = home_id
	g.series = series_index
	g.game_in_series = number
	return g


func involves(team_id: String) -> bool:
	return away == team_id or home == team_id


func opponent_of(team_id: String) -> String:
	return home if away == team_id else away


## Records the final score.
func finish(away_runs: int, home_runs: int, innings_played: int = 9) -> void:
	played = true
	away_score = away_runs
	home_score = home_runs
	innings = innings_played


func is_tie() -> bool:
	return played and away_score == home_score


## The winner's team id, or "" for a tie or a game not played yet.
func winner() -> String:
	if not played or away_score == home_score:
		return ""
	return away if away_score > home_score else home


func loser() -> String:
	if not played or away_score == home_score:
		return ""
	return home if away_score > home_score else away


func runs_of(team_id: String) -> int:
	return away_score if team_id == away else home_score


func runs_against(team_id: String) -> int:
	return home_score if team_id == away else away_score
