class_name RuleSet
extends RefCounted
## Rules a game is played under. Defaults are the KBO's for 2026 (docs/12 section 5).

var innings := 9
## Last inning played before a tie is called. 0 = play until someone wins.
var extra_inning_limit := 11
var designated_hitter := true
## An intentional walk is given without pitches.
var auto_intentional_walk := true
## Automatic strike zone: top and bottom as a share of the batter's height, and how far it
## reaches past each side of the plate (m).
var zone_top_ratio := 0.5575
var zone_bottom_ratio := 0.2704
var zone_side_margin := 0.02
## Seconds: pitch clock with the bases empty and with runners on, between batters, by which
## the batter must be ready, and between innings or for a pitching change.
var pitch_clock_empty := 18
var pitch_clock_runners := 23
var between_batters := 33
var batter_ready := 8
var inning_break := 130
var batter_timeouts := 2
## Players dressed for a game and registered for the club.
var active_roster := 28
var registered_roster := 29
## Foreign players a club may register, and Asia-quota players besides them (KBO 2026).
var foreign_players := 3
var asia_quota := 1


static func kbo_2026() -> RuleSet:
	return RuleSet.new()


## A shortened game (3 or 6 innings) under otherwise the same rules. Extra innings stay two
## beyond the regulation length, as in the full game.
static func short_game(innings_count: int) -> RuleSet:
	var rules := RuleSet.new()
	rules.innings = innings_count
	rules.extra_inning_limit = innings_count + 2
	return rules


## Innings a starting pitcher must pitch to be the winning pitcher: five in a nine-inning
## game, in proportion in a shorter one.
func starter_win_innings() -> int:
	return maxi(roundi(innings * 5.0 / 9.0), 1)
