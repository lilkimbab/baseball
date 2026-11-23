class_name Schedule
extends RefCounted
## A division's regular season: every club meets each of the other nine the
## same number of times, half at home and half away, in series of three games (two where the
## numbers do not divide by three), six game days a week with Monday off, as in the KBO.
##
## Season lengths are 36, 72 and 144 games (4, 8 and 16 meetings per pair); a season of the
## past may have an odd number of meetings (eight clubs, 133 games: 19), the last one a single
## game. With 8 meetings at
## each park the series are 3, 3 and 2 games; with 4 or 2, two-game series. The KBO also plays
## its two-game series late in the season, so they come last here too.
##
## Built by the circle method: one club stays put and the others rotate, giving nine rounds
## in which everybody plays once. Each "cycle" of nine rounds is one series against every
## other club; the home side flips from one cycle to the next.

const LENGTHS: Array[int] = [36, 72, 144]
## The empty place in a circle of an odd number of clubs.
const BYE := "_bye"
const GAME_DAYS_PER_WEEK := 6

var team_ids := PackedStringArray()
## In calendar order.
var games: Array[ScheduledGame] = []
## Calendar days in the season, from opening day to the last game.
var days := 0


static func make(ids: PackedStringArray, games_per_team: int, rng: Rng) -> Schedule:
	var s := Schedule.new()
	s.team_ids = ids
	var n := ids.size()
	if n < 2:
		push_error("Schedule: needs two clubs at least, got %d" % n)
		return s
	# An odd number (a high-school league): one more place in the circle, a bye; the games
	# against it are not played.
	if n % 2 != 0:
		var with_bye := ids.duplicate()
		with_bye.append(BYE)
		var full := make(with_bye, games_per_team, rng)
		s.games = full.games.filter(func(g: ScheduledGame) -> bool: return not g.involves(BYE))
		s.days = full.days
		return s
	var meetings := games_per_team / (n - 1)
	var cycles := series_lengths(meetings / 2)
	# Shuffle the clubs into the circle so each season is different.
	var order := Array(ids)
	for i: int in range(n - 1, 0, -1):
		var j := rng.next_int(i + 1)
		var tmp: String = order[i]
		order[i] = order[j]
		order[j] = tmp
	var rounds := _rounds(PackedStringArray(order))
	var game_day := 0
	var series_index := 0
	var last_round := -1
	for c: int in cycles.size() * 2:
		var length := cycles[c / 2]
		var flip := c % 2 == 1
		var round_order := _shuffled(rounds.size(), rng)
		# The same two clubs do not meet in back-to-back series.
		if round_order.size() > 1 and round_order[0] == last_round:
			var swap := round_order[0]
			round_order[0] = round_order[1]
			round_order[1] = swap
		for r: int in round_order:
			for pair: PackedStringArray in rounds[r]:
				var home := pair[1] if flip else pair[0]
				var away := pair[0] if flip else pair[1]
				for k: int in length:
					s.games.append(ScheduledGame.make(calendar_day(game_day + k), away, home, series_index, k + 1))
				series_index += 1
			game_day += length
			last_round = r
	# An odd number of meetings (19 in a 133-game season of eight clubs): one more game for
	# each pair, at one park or the other in turn.
	if meetings % 2 == 1:
		for r: int in rounds.size():
			for i: int in rounds[r].size():
				var pair: PackedStringArray = rounds[r][i]
				var at_first := (r + i) % 2 == 0
				s.games.append(ScheduledGame.make(calendar_day(game_day), pair[0] if not at_first else pair[1], pair[1] if not at_first else pair[0], series_index, 1))
				series_index += 1
			game_day += 1
	s.games.sort_custom(func(x: ScheduledGame, y: ScheduledGame) -> bool: return x.day < y.day or (x.day == y.day and x.series < y.series))
	s.days = calendar_day(game_day - 1) + 1
	return s


## Series lengths at one park for `per_park` meetings there: threes where they fit, the rest
## in twos (8 → 3, 3, 2; 4 → 2, 2; 2 → 2).
static func series_lengths(per_park: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var threes := per_park / 3
	while threes >= 0:
		var rest := per_park - threes * 3
		if rest % 2 == 0:
			for i: int in threes:
				out.append(3)
			for i: int in rest / 2:
				out.append(2)
			return out
		threes -= 1
	out.append(per_park)
	return out


## Calendar day of a game day: six game days, then Monday off.
static func calendar_day(game_day: int) -> int:
	return game_day + game_day / GAME_DAYS_PER_WEEK


static func is_off_day(day: int) -> bool:
	return day % (GAME_DAYS_PER_WEEK + 1) == GAME_DAYS_PER_WEEK


## The circle method: n − 1 rounds of n / 2 pairs; within a round each club plays once. The
## first club of a pair is the home side of the first cycle; it alternates by round, so a club
## rarely has two series at the same park in a row.
static func _rounds(order: PackedStringArray) -> Array[Array]:
	var n := order.size()
	var circle := order.duplicate()
	var out: Array[Array] = []
	for r: int in n - 1:
		var pairs: Array[PackedStringArray] = []
		for i: int in n / 2:
			var a := circle[i]
			var b := circle[n - 1 - i]
			var a_home := (r + i) % 2 == 0
			pairs.append(PackedStringArray([a, b]) if a_home else PackedStringArray([b, a]))
		out.append(pairs)
		# Keep the first club, turn the rest one place.
		var last := circle[n - 1]
		for i: int in range(n - 1, 1, -1):
			circle[i] = circle[i - 1]
		circle[1] = last
	return out


static func _shuffled(count: int, rng: Rng) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i: int in count:
		out.append(i)
	for i: int in range(count - 1, 0, -1):
		var j := rng.next_int(i + 1)
		var tmp := out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


func games_on(day: int) -> Array[ScheduledGame]:
	var out: Array[ScheduledGame] = []
	for g: ScheduledGame in games:
		if g.day == day:
			out.append(g)
		elif g.day > day:
			break
	return out


func games_of(team_id: String) -> Array[ScheduledGame]:
	var out: Array[ScheduledGame] = []
	for g: ScheduledGame in games:
		if g.involves(team_id):
			out.append(g)
	return out


## The next game for a club not played yet, or null when its season is over.
func next_game_of(team_id: String) -> ScheduledGame:
	for g: ScheduledGame in games:
		if not g.played and g.involves(team_id):
			return g
	return null


func finished() -> bool:
	for g: ScheduledGame in games:
		if not g.played:
			return false
	return true
