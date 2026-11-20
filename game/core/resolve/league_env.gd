class_name LeagueEnv
extends RefCounted
## League averages and the tables the stat resolver draws from (data/league_env.json).

## Outcomes of a plate appearance, in the order the resolver works with them.
enum Outcome { K, BB, HBP, SINGLE, DOUBLE, TRIPLE, HR, OUT }
const OUTCOME_KEYS: Array[String] = ["K", "BB", "HBP", "1B", "2B", "3B", "HR", "OUT"]

var name := ""
var label := ""
## League rate per plate appearance for each Outcome (OUT is what is left over).
var rates := PackedFloat64Array()
## Rating coefficients: outcome key -> rating name -> k.
var batter_k: Dictionary[String, Dictionary] = {}
var pitcher_k: Dictionary[String, Dictionary] = {}
var defence_hits := -0.05
var clutch := 0.04
## Multipliers by outcome key, for a batter facing a pitcher who throws with the same hand
## he bats from, and for the opposite hand.
var same_hand: Dictionary[String, float] = {}
var opposite_hand: Dictionary[String, float] = {}
## Effect of a tired pitcher on each outcome at full fatigue (proportional change).
var fatigue: Dictionary[String, float] = {}
## Batted-ball outs: ground, fly, line, popup shares.
var out_types := PackedFloat64Array([0.45, 0.30, 0.12, 0.13])
## Everything else, by key: probabilities for in-play situations, running, manager limits.
var values: Dictionary[String, float] = {}
var targets: Dictionary[String, float] = {}
var pitches_per_pa: Dictionary[String, float] = {}
var home_hits := 1.0
## Correction applied to the league rates when outcomes are drawn (by outcome key).
var calibration: Dictionary[String, float] = {}


func rate(outcome: Outcome) -> float:
	return rates[outcome]


func value(key: String, fallback: float = 0.0) -> float:
	return values.get(key, fallback)


## Rate of an outcome for a player: the league rate scaled by his ratings.
func scaled(outcome_key: String, table: Dictionary[String, Dictionary], ratings: Dictionary[String, float]) -> float:
	var outcome := OUTCOME_KEYS.find(outcome_key)
	var base := rates[outcome]
	if not table.has(outcome_key):
		return base
	var exponent := 0.0
	var ks: Dictionary = table[outcome_key]
	for rating: String in ks:
		var k: float = ks[rating]
		exponent += k * (float(ratings.get(rating, 50.0)) - 50.0) / 15.0
	return base * exp(exponent)
