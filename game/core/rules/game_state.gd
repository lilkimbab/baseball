class_name GameState
extends RefCounted
## Everything about a game in progress that the rules need. Changed only by GameFlow.

const AWAY := 0
const HOME := 1

var rules := RuleSet.new()
## Index 0 is the visiting team (bats first), 1 the home team.
var teams: Array[TeamInGame] = []
var inning := 1
## True in the top half (visitors batting).
var top := true
var outs := 0
var balls := 0
var strikes := 0
## Runners on first, second and third; null where a base is empty.
var bases: Array[BaseRunner] = [null, null, null]
var score := PackedInt32Array([0, 0])
## Runs per inning, per team.
var line: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
## Next batter's place in the order, per team.
var order := PackedInt32Array([0, 0])
## Pitches thrown and batters faced per pitcher.
var pitch_counts: Dictionary[String, int] = {}
var batters_faced: Dictionary[String, int] = {}
## Outs that would have been made this half-inning but for errors. Runs that score once
## outs + phantom_outs reaches three are not earned.
var phantom_outs := 0
## The batter and pitcher who started the current count, when either was replaced during it
## ("" otherwise). Official scoring charges some results to them (docs/12 section 5.3).
var count_batter_id := ""
var count_pitcher_id := ""
## Balls and strikes when the pitcher was replaced during the count.
var count_at_relief := Vector2i(-1, -1)
var over := false
## 0 visitors won, 1 home won, -1 a tie. Meaningful once over.
var winner := -1


func batting() -> int:
	return AWAY if top else HOME


func fielding() -> int:
	return HOME if top else AWAY


func batting_team() -> TeamInGame:
	return teams[batting()]


func fielding_team() -> TeamInGame:
	return teams[fielding()]


func batter_id() -> String:
	return batting_team().batter_at(order[batting()])


func pitcher_id() -> String:
	return fielding_team().pitcher_id


func runner_on(base: int) -> BaseRunner:
	return bases[base - 1]


func runners_on() -> int:
	var n := 0
	for r: BaseRunner in bases:
		if r != null:
			n += 1
	return n


func base_empty(base: int) -> bool:
	return bases[base - 1] == null


## The home team's lead over the visitors (negative when behind).
func home_lead() -> int:
	return score[HOME] - score[AWAY]


## Lead of one team over the other.
func lead_of(team: int) -> int:
	return score[team] - score[1 - team]


func in_extra_innings() -> bool:
	return inning > rules.innings


## A copy that can be played forward without touching this one (for AI look-ahead).
func duplicate_state() -> GameState:
	var s := GameState.new()
	s.rules = rules
	for t: TeamInGame in teams:
		s.teams.append(t.copy())
	s.inning = inning
	s.top = top
	s.outs = outs
	s.balls = balls
	s.strikes = strikes
	s.bases = [null, null, null]
	for i: int in 3:
		if bases[i] != null:
			s.bases[i] = bases[i].copy()
	s.score = score.duplicate()
	s.line = [line[0].duplicate(), line[1].duplicate()]
	s.order = order.duplicate()
	s.pitch_counts = pitch_counts.duplicate()
	s.batters_faced = batters_faced.duplicate()
	s.phantom_outs = phantom_outs
	s.count_batter_id = count_batter_id
	s.count_pitcher_id = count_pitcher_id
	s.count_at_relief = count_at_relief
	s.over = over
	s.winner = winner
	return s
