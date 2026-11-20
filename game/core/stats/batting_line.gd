class_name BattingLine
extends RefCounted
## A batter's counting stats (one game or a season).

var games := 0
var pa := 0
var ab := 0
var runs := 0
var hits := 0
var doubles := 0
var triples := 0
var home_runs := 0
var rbi := 0
var walks := 0
var intentional_walks := 0
var hit_by_pitch := 0
var strikeouts := 0
var double_plays := 0
var sac_bunts := 0
var sac_flies := 0
var stolen_bases := 0
var caught_stealing := 0
var reached_on_error := 0


func add(other: BattingLine) -> void:
	games += other.games
	pa += other.pa
	ab += other.ab
	runs += other.runs
	hits += other.hits
	doubles += other.doubles
	triples += other.triples
	home_runs += other.home_runs
	rbi += other.rbi
	walks += other.walks
	intentional_walks += other.intentional_walks
	hit_by_pitch += other.hit_by_pitch
	strikeouts += other.strikeouts
	double_plays += other.double_plays
	sac_bunts += other.sac_bunts
	sac_flies += other.sac_flies
	stolen_bases += other.stolen_bases
	caught_stealing += other.caught_stealing
	reached_on_error += other.reached_on_error


func singles() -> int:
	return hits - doubles - triples - home_runs


func total_bases() -> int:
	return singles() + 2 * doubles + 3 * triples + 4 * home_runs


func average() -> float:
	return float(hits) / ab if ab > 0 else 0.0


func on_base() -> float:
	var chances := ab + walks + hit_by_pitch + sac_flies
	return float(hits + walks + hit_by_pitch) / chances if chances > 0 else 0.0


func slugging() -> float:
	return float(total_bases()) / ab if ab > 0 else 0.0


func ops() -> float:
	return on_base() + slugging()


## Batting average on balls in play.
func babip() -> float:
	var in_play := ab - strikeouts - home_runs + sac_flies
	return float(hits - home_runs) / in_play if in_play > 0 else 0.0


## A rate stat written the way scoreboards write it: ".287".
static func rate_text(value: float) -> String:
	var text := "%.3f" % value
	return text.substr(1) if text.begins_with("0") else text
