class_name PlayoffSeries
extends RefCounted
## One round of the postseason: first to `wins_needed` wins. A tie (the game reached the
## extra-inning limit level) does not count, and the series goes on.

var high := ""
var low := ""
var wins_needed := 2
var high_wins := 0
var low_wins := 0
var games: Array[ScheduledGame] = []


static func make(higher_seed: String, lower_seed: String, need: int) -> PlayoffSeries:
	var s := PlayoffSeries.new()
	s.high = higher_seed
	s.low = lower_seed
	s.wins_needed = need
	return s


## Best of 2n − 1.
func length() -> int:
	return wins_needed * 2 - 1


func finished() -> bool:
	return high_wins >= wins_needed or low_wins >= wins_needed


func winner() -> String:
	if high_wins >= wins_needed:
		return high
	if low_wins >= wins_needed:
		return low
	return ""


func loser() -> String:
	var w := winner()
	if w == "":
		return ""
	return low if w == high else high


## Which club is at home in game n (1-based): a best-of-three all at the higher seed (as the
## KBO's and MLB's wild-card rounds), a best-of-five 2-2-1 and a best-of-seven 2-3-2 (as the
## KBO's playoffs and Korean Series). Games after a tie keep the last pattern's host.
func host_of(n: int) -> String:
	var pattern: Array[bool] = []
	match wins_needed:
		2:
			pattern = [true, true, true]
		3:
			pattern = [true, true, false, false, true]
		4:
			pattern = [true, true, false, false, false, true, true]
		_:
			for i: int in length():
				pattern.append(i % 2 == 0)
	var at_high: bool = pattern[mini(n - 1, pattern.size() - 1)]
	return high if at_high else low


## The game on `day`: one not played yet, or a new one; null once the series is over or
## today's game has been played (one a day).
func next_game(day: int, series_index: int) -> ScheduledGame:
	for g: ScheduledGame in games:
		if not g.played:
			return g
	if finished() or (not games.is_empty() and games[-1].day >= day):
		return null
	var n := games.size() + 1
	var home := host_of(n)
	var g := ScheduledGame.make(day, low if home == high else high, home, series_index, n)
	games.append(g)
	return g


func record(game: ScheduledGame) -> void:
	var w := game.winner()
	if w == high:
		high_wins += 1
	elif w == low:
		low_wins += 1


## "3승 1패" from the higher seed's side, for the bracket.
func score_text() -> String:
	return "%d - %d" % [high_wins, low_wins]
