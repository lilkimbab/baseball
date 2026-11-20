class_name Postseason
extends RefCounted
## A division's postseason (docs/02 section 4.1, docs/13 S7-7): the four best clubs of the
## regular season play down a ladder. Fourth plays third (best of three), the winner plays
## second (best of five), and that winner plays first for the title (best of seven). Extra
## innings go to the fifteenth (the KBO postseason limit; docs/12 section 10 lists it as to be
## confirmed). The real KBO's five-club format comes with the real roster packs (S17).

const ROUND_WINS: Array[int] = [2, 3, 4]
const ROUND_NAMES: Array[String] = ["준플레이오프", "플레이오프", "결승"]
const EXTRA_INNING_LIMIT := 15
## Days off between rounds.
const REST_BETWEEN := 1

## Seeds 1 to 4.
var seeds := PackedStringArray()
var rounds: Array[PlayoffSeries] = []
var current := 0
## The day the next game may be played (rest between rounds).
var ready_day := 0


static func from_standings(table: Standings, first_day: int) -> Postseason:
	var p := Postseason.new()
	var order := table.ranked()
	for i: int in mini(4, order.size()):
		p.seeds.append(order[i].team_id)
	p.ready_day = first_day
	if p.seeds.size() == 4:
		p.rounds.append(PlayoffSeries.make(p.seeds[2], p.seeds[3], ROUND_WINS[0]))
	return p


## The rules for postseason games: as the regular season, longer extra innings.
static func rules(regular: RuleSet) -> RuleSet:
	var r := RuleSet.new()
	r.innings = regular.innings
	r.designated_hitter = regular.designated_hitter
	r.extra_inning_limit = EXTRA_INNING_LIMIT
	return r


func finished() -> bool:
	return rounds.size() == ROUND_WINS.size() and rounds[-1].finished()


func series() -> PlayoffSeries:
	return rounds[current] if current < rounds.size() else null


func round_name() -> String:
	return ROUND_NAMES[mini(current, ROUND_NAMES.size() - 1)]


## Today's game, if one is due; null on a rest day or when it is all over.
func game_on(day: int) -> ScheduledGame:
	if finished() or day < ready_day or rounds.is_empty():
		return null
	return series().next_game(day, current)


func record(game: ScheduledGame, day: int) -> void:
	var s := series()
	s.record(game)
	if not s.finished():
		return
	if current + 1 >= ROUND_WINS.size():
		return
	# The winner moves up a rung to play the next seed.
	var next_seed := seeds[1 - current]
	rounds.append(PlayoffSeries.make(next_seed, s.winner(), ROUND_WINS[current + 1]))
	current += 1
	ready_day = day + 1 + REST_BETWEEN


func champion() -> String:
	return rounds[-1].winner() if finished() else ""


func runner_up() -> String:
	return rounds[-1].loser() if finished() else ""
