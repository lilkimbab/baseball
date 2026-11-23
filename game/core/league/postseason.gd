class_name Postseason
extends RefCounted
## A league's postseason: a ladder. The lowest two
## seeds play the first round, the winner goes up a rung to the next seed, and so on to the
## final against the first seed. What the rounds are is a format:
##
## - KBO (the real league since 2015, and the game's top division): five clubs — the wild
##   card (와일드카드 결정전: fifth at fourth, fourth a win up, so one win or a tie sends it on
##   and the fifth must win twice), 준플레이오프 and 플레이오프 (best of five), 한국시리즈 (best
##   of seven).
## - The ladder of four (the lower divisions, and the KBO of 1989 to 2014 with each year's
##   own lengths): 준플레이오프, 플레이오프 and the final.
##
## A season of the past gives its own rounds (SeasonPack.postseason). Extra innings go to the
## fifteenth (the KBO postseason limit).

const EXTRA_INNING_LIMIT := 15
## Days off between rounds.
const REST_BETWEEN := 1


## One round: its name, the wins it takes, and wins the higher seed starts with (the wild
## card's one; with a head start a tie also counts for the higher seed).
class Round:
	var name := ""
	var wins := 2
	var head_start := 0

	static func make(n: String, w: int, start: int = 0) -> Round:
		var r := Round.new()
		r.name = n
		r.wins = w
		r.head_start = start
		return r


## The rounds, first to last. The seeds are one more than the rounds.
var format: Array[Round] = []
var seeds := PackedStringArray()
var rounds: Array[PlayoffSeries] = []
var current := 0
## The day the next game may be played (rest between rounds).
var ready_day := 0


## The real KBO's five-club postseason.
static func kbo() -> Array[Round]:
	return [Round.make("와일드카드 결정전", 2, 1), Round.make("준플레이오프", 3), Round.make("플레이오프", 3), Round.make("한국시리즈", 4)]


## Four clubs: best of three, five and seven.
static func ladder(final_name: String = "챔피언 결정전") -> Array[Round]:
	return [Round.make("준플레이오프", 2), Round.make("플레이오프", 3), Round.make(final_name, 4)]


## Rounds from a list of {"name", "wins", "head_start"} (a season pack, a save).
static func format_from(list: Array) -> Array[Round]:
	var out: Array[Round] = []
	for entry: Dictionary in list:
		out.append(Round.make(str(entry.get("name", "")), int(entry.get("wins", 2)), int(entry.get("head_start", 0))))
	return out


static func format_to(rounds_list: Array[Round]) -> Array:
	var out: Array = []
	for r: Round in rounds_list:
		out.append({"name": r.name, "wins": r.wins, "head_start": r.head_start})
	return out


static func from_standings(table: Standings, first_day: int, rounds_format: Array[Round] = []) -> Postseason:
	var p := Postseason.new()
	p.format = rounds_format.duplicate() if not rounds_format.is_empty() else ladder()
	var order := table.ranked()
	# A league too small for the format plays its last rounds only.
	while p.format.size() + 1 > order.size() and p.format.size() > 1:
		p.format.pop_front()
	for i: int in mini(p.format.size() + 1, order.size()):
		p.seeds.append(order[i].team_id)
	p.ready_day = first_day
	if p.seeds.size() == p.format.size() + 1:
		p.rounds.append(p._series(0, p.seeds[p.seeds.size() - 2], p.seeds[p.seeds.size() - 1]))
	return p


func _series(index: int, high: String, low: String) -> PlayoffSeries:
	var r := format[index]
	var s := PlayoffSeries.make(high, low, r.wins)
	s.high_wins = r.head_start
	s.head_start = r.head_start
	return s


## The rules for postseason games: as the regular season, longer extra innings.
static func rules(regular: RuleSet) -> RuleSet:
	var r := RuleSet.new()
	r.innings = regular.innings
	r.designated_hitter = regular.designated_hitter
	r.extra_inning_limit = EXTRA_INNING_LIMIT
	return r


func finished() -> bool:
	return not format.is_empty() and rounds.size() == format.size() and rounds[-1].finished()


func series() -> PlayoffSeries:
	return rounds[current] if current < rounds.size() else null


func round_name(index: int = -1) -> String:
	var i := current if index < 0 else index
	return format[clampi(i, 0, format.size() - 1)].name if not format.is_empty() else ""


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
	if current + 1 >= format.size():
		return
	# The winner moves up a rung to play the next seed.
	var next_seed := seeds[seeds.size() - 3 - current]
	rounds.append(_series(current + 1, next_seed, s.winner()))
	current += 1
	ready_day = day + 1 + REST_BETWEEN


func champion() -> String:
	return rounds[-1].winner() if finished() else ""


func runner_up() -> String:
	return rounds[-1].loser() if finished() else ""
