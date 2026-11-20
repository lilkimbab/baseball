class_name PitchingLine
extends RefCounted
## A pitcher's counting stats (one game or a season).

var games := 0
var starts := 0
var outs := 0
var batters_faced := 0
var pitches := 0
var hits := 0
var home_runs := 0
var walks := 0
var intentional_walks := 0
var hit_by_pitch := 0
var strikeouts := 0
var runs := 0
var earned_runs := 0
var wins := 0
var losses := 0
var saves := 0
var holds := 0
var wild_pitches := 0


func add(other: PitchingLine) -> void:
	games += other.games
	starts += other.starts
	outs += other.outs
	batters_faced += other.batters_faced
	pitches += other.pitches
	hits += other.hits
	home_runs += other.home_runs
	walks += other.walks
	intentional_walks += other.intentional_walks
	hit_by_pitch += other.hit_by_pitch
	strikeouts += other.strikeouts
	runs += other.runs
	earned_runs += other.earned_runs
	wins += other.wins
	losses += other.losses
	saves += other.saves
	holds += other.holds
	wild_pitches += other.wild_pitches


## Earned runs per nine innings.
func era() -> float:
	return earned_runs * 27.0 / outs if outs > 0 else 0.0


## Walks plus hits per inning.
func whip() -> float:
	return (walks + intentional_walks + hits) * 3.0 / outs if outs > 0 else 0.0


## Innings as written in a box score: 5⅔ is five innings and two outs.
func innings_text() -> String:
	var whole := outs / 3
	var part := outs % 3
	if part == 0:
		return str(whole)
	var fraction := "⅓" if part == 1 else "⅔"
	return fraction if whole == 0 else "%d%s" % [whole, fraction]


## Innings as a number with the outs written as tenths (5.2 = five and two thirds), the way
## record tables list them.
func innings_decimal() -> float:
	return (outs / 3) + (outs % 3) * 0.1
