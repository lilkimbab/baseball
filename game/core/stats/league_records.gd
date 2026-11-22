class_name LeagueRecords
extends RefCounted
## The records room of a division (docs/08 R5): the leaders in each of the KBO's batting and
## pitching categories, and the clubs' batting and pitching side by side. Rates (an average,
## an ERA) count only for men who qualify as the KBO has it, against the games their club has
## played so far: 3.1 plate appearances a game for a hitter, an inning a game for a pitcher.

## One category: its name, how a line gives its value, how the value is written, whether it
## needs the qualifying amount, and whether lower is better.
class Category:
	var name := ""
	var pitching := false
	var value: Callable
	var text: Callable
	var qualified := false
	var lower_better := false

	func _init(n: String, p: bool, v: Callable, t: Callable, q: bool = false, low: bool = false) -> void:
		name = n
		pitching = p
		value = v
		text = t
		qualified = q
		lower_better = low


## A place on a leader board.
class Entry:
	var player_id := ""
	var team_id := ""
	var value := 0.0
	var text := ""


static func batting_categories() -> Array[Category]:
	var rate := func(v: float) -> String: return BattingLine.rate_text(v)
	var count := func(v: float) -> String: return str(roundi(v))
	return [
		Category.new("타율", false, func(l: BattingLine) -> float: return l.average(), rate, true),
		Category.new("홈런", false, func(l: BattingLine) -> float: return l.home_runs, count),
		Category.new("타점", false, func(l: BattingLine) -> float: return l.rbi, count),
		Category.new("안타", false, func(l: BattingLine) -> float: return l.hits, count),
		Category.new("득점", false, func(l: BattingLine) -> float: return l.runs, count),
		Category.new("도루", false, func(l: BattingLine) -> float: return l.stolen_bases, count),
		Category.new("출루율", false, func(l: BattingLine) -> float: return l.on_base(), rate, true),
		Category.new("장타율", false, func(l: BattingLine) -> float: return l.slugging(), rate, true),
		Category.new("OPS", false, func(l: BattingLine) -> float: return l.ops(), rate, true),
	]


static func pitching_categories() -> Array[Category]:
	var count := func(v: float) -> String: return str(roundi(v))
	return [
		Category.new("평균자책점", true, func(l: PitchingLine) -> float: return l.era(), func(v: float) -> String: return "%.2f" % v, true, true),
		Category.new("다승", true, func(l: PitchingLine) -> float: return l.wins, count),
		Category.new("세이브", true, func(l: PitchingLine) -> float: return l.saves, count),
		Category.new("홀드", true, func(l: PitchingLine) -> float: return l.holds, count),
		Category.new("탈삼진", true, func(l: PitchingLine) -> float: return l.strikeouts, count),
		Category.new("WHIP", true, func(l: PitchingLine) -> float: return l.whip(), func(v: float) -> String: return "%.2f" % v, true, true),
		Category.new("이닝", true, func(l: PitchingLine) -> float: return l.outs / 3.0, func(v: float) -> String:
			var outs := roundi(v * 3.0)
			return "%d%s" % [outs / 3, ["", "⅓", "⅔"][outs % 3]]),
	]


## Games a club has played so far (the regular season).
static func games_played(season: Season, team_id: String) -> int:
	var d := season.division_of(team_id)
	if d < 0:
		return 0
	return season.standings[d].row(team_id).games()


static func qualifying_pa(season: Season, team_id: String) -> int:
	return int(floorf(games_played(season, team_id) * 3.1))


static func qualifying_outs(season: Season, team_id: String) -> int:
	return games_played(season, team_id) * 3


## The first `count` of a division in a category, best first. Men with nothing in the
## category (no plate appearance, no out, no home run on the home-run board) are not on it.
static func leaders(season: Season, division: int, category: Category, count: int = 10) -> Array[Entry]:
	var out: Array[Entry] = []
	for team_id: String in season.divisions[division]:
		var team: Team = season.teams[team_id]
		var need_pa := qualifying_pa(season, team_id)
		var need_outs := qualifying_outs(season, team_id)
		for p: Player in team.players:
			var line: Variant = season.book.pitching.get(p.id) if category.pitching else season.book.batting.get(p.id)
			if line == null:
				continue
			if category.pitching:
				var pl := line as PitchingLine
				if pl.outs == 0 or (category.qualified and pl.outs < maxi(need_outs, 1)):
					continue
			else:
				var bl := line as BattingLine
				if bl.pa == 0 or (category.qualified and bl.pa < maxi(need_pa, 1)):
					continue
			var e := Entry.new()
			e.player_id = p.id
			e.team_id = team_id
			e.value = category.value.call(line)
			# A count of nothing (no home run yet) is no place on its board.
			if not category.qualified and e.value <= 0.0:
				continue
			out.append(e)
	out.sort_custom(func(a: Entry, b: Entry) -> bool:
		if not is_equal_approx(a.value, b.value):
			return a.value < b.value if category.lower_better else a.value > b.value
		return a.player_id < b.player_id)
	if out.size() > count:
		out.resize(count)
	for e: Entry in out:
		e.text = category.text.call(e.value)
	return out


## Each club of a division with its batting and pitching added up: [team id, BattingLine,
## PitchingLine], in the order of the table.
static func clubs(season: Season, division: int) -> Array:
	var rows: Array = []
	for standing: StandingsRow in season.standings[division].ranked():
		var team_id := standing.team_id
		var team: Team = season.teams[team_id]
		var bat := BattingLine.new()
		var pitch := PitchingLine.new()
		for p: Player in team.players:
			if season.book.batting.has(p.id):
				bat.add(season.book.batting[p.id])
			if season.book.pitching.has(p.id):
				pitch.add(season.book.pitching[p.id])
		rows.append([team_id, bat, pitch])
	return rows
