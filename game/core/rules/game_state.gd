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
## The bullpen (docs/08 R4): how warm each reliever is (0 cold, 1 ready to pitch) by team, who
## is throwing out there now (at most MAX_WARMING a side), and how warm each pitcher was when
## he came into the game (a starter is ready).
var warmth: Array[Dictionary] = [{}, {}]
var warming: Array[PackedStringArray] = [PackedStringArray(), PackedStringArray()]
var entered_warmth: Dictionary[String, float] = {}
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


# --- The bullpen (docs/08 R4) ---

## Pitches thrown in the game while a reliever throws in the bullpen to have him ready (about
## 15, some five minutes), and to have a ready one go cold again once he stops (about 60).
const WARM_PITCHES := 15.0
const COOL_PITCHES := 60.0
const MAX_WARMING := 2
## A reliever coming in gets his warm-up throws on the mound: this much of the way, whatever
## the bullpen did.
const MOUND_WARMUP := 0.25
## A pitcher who came in less than ready is himself by his SETTLE_PITCHES-th pitch.
const SETTLE_PITCHES := 12.0
## Off only to measure what the warm-ups change (tools/sim_batch.gd --no-warmup).
static var warm_ups_matter := true


## Who throws in team t's bullpen from now on (the first MAX_WARMING of `ids`).
func set_warming(t: int, ids: PackedStringArray) -> void:
	var keep := PackedStringArray()
	for id: String in ids:
		if keep.size() < MAX_WARMING and not keep.has(id) and id != teams[t].pitcher_id and not teams[t].removed.has(id):
			keep.append(id)
	warming[t] = keep


## `pitches` more were thrown in the game: those warming get warmer, those who stopped cool.
func warm_up(pitches: int) -> void:
	for t: int in 2:
		var w: Dictionary = warmth[t]
		for id: String in warming[t]:
			w[id] = minf(float(w.get(id, 0.0)) + pitches / WARM_PITCHES, 1.0)
		for id: String in w.keys():
			if not warming[t].has(id):
				w[id] = maxf(float(w[id]) - pitches / COOL_PITCHES, 0.0)


## How warm reliever `id` of team t is now (0-1).
func warmth_of(t: int, id: String) -> float:
	return float(warmth[t].get(id, 0.0))


## Pitcher `id` takes the mound for team t: how warm he is (with his warm-up throws there).
func enters(t: int, id: String) -> void:
	entered_warmth[id] = minf(warmth_of(t, id) + MOUND_WARMUP, 1.0)
	var keep := PackedStringArray()
	for other: String in warming[t]:
		if other != id:
			keep.append(other)
	warming[t] = keep


## How far from ready the pitcher `id` still is on this pitch: 0 a starter or a reliever who
## came in warm, up to 0.75 one who came in cold, going to 0 over his first SETTLE_PITCHES.
func cold(id: String) -> float:
	if not warm_ups_matter or not entered_warmth.has(id):
		return 0.0
	var short := 1.0 - float(entered_warmth[id])
	var settled := clampf(float(pitch_counts.get(id, 0)) / SETTLE_PITCHES, 0.0, 1.0)
	return short * (1.0 - settled)


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
	s.warmth = [warmth[0].duplicate(), warmth[1].duplicate()]
	s.warming = [warming[0].duplicate(), warming[1].duplicate()]
	s.entered_warmth = entered_warmth.duplicate()
	s.batters_faced = batters_faced.duplicate()
	s.phantom_outs = phantom_outs
	s.count_batter_id = count_batter_id
	s.count_pitcher_id = count_pitcher_id
	s.count_at_relief = count_at_relief
	s.over = over
	s.winner = winner
	return s
