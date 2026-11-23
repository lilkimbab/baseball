class_name SeasonAwards
extends RefCounted
## The end-of-season awards of one division: MVP, the
## pitching award, rookie of the year, the best at each position (as the KBO's Golden Glove:
## pitcher, catcher, the four infield places, three outfielders and a designated hitter), and
## the title holders (KBO's individual titles).
##
## Value is wins above replacement, simply (A): hitters from weighted on-base average against
## the division's (FanGraphs' linear weights), plus a position adjustment and the replacement
## level, ten runs a win; pitchers from runs saved against a replacement-level ERA (league ERA
## × 1.28 for starters, × 1.12 for relievers) over their innings.

const WEIGHTS := {"bb": 0.69, "hbp": 0.72, "1b": 0.89, "2b": 1.27, "3b": 1.62, "hr": 2.10}
const WOBA_SCALE := 1.25
const RUNS_PER_WIN := 10.0
## Runs per 600 plate appearances.
const REPLACEMENT_RUNS := 20.0
const POSITION_RUNS := {"C": 12.5, "SS": 7.5, "2B": 2.5, "3B": 2.5, "CF": 2.5, "LF": -7.5, "RF": -7.5, "1B": -12.5, "DH": -17.5}
const STARTER_REPLACEMENT := 1.28
const RELIEVER_REPLACEMENT := 1.12
const ROOKIE_AGE := 23
const BATTING_TITLES: Array[String] = ["타율", "홈런", "타점", "안타", "득점", "도루", "출루율", "장타율"]
const PITCHING_TITLES: Array[String] = ["다승", "평균자책점", "탈삼진", "세이브", "홀드", "승률"]


class Award:
	var title := ""
	var player_id := ""
	var team_id := ""
	var value := 0.0
	var text := ""


var mvp: Award
var pitcher: Award
var rookie: Award
## Position code ("P", "C", "1B", ..., "OF", "DH") → award; the outfield has three.
var best: Array[Award] = []
var titles: Array[Award] = []

var _season: Season
var _team_of: Dictionary[String, String] = {}
var _players: Dictionary[String, Player] = {}
var _lg_woba := 0.32
var _lg_era := 4.3
var _year := 2026


static func for_division(season: Season, d: int, year: int = 2026) -> SeasonAwards:
	var a := SeasonAwards.new()
	a._season = season
	a._year = year
	for id: String in season.divisions[d]:
		for p: Player in season.teams[id].players:
			a._team_of[p.id] = id
			a._players[p.id] = p
	a._league_rates()
	a._decide()
	return a


static func woba(b: BattingLine) -> float:
	var den := b.ab + b.walks + b.sac_flies + b.hit_by_pitch
	if den <= 0:
		return 0.0
	var num: float = WEIGHTS["bb"] * b.walks + WEIGHTS["hbp"] * b.hit_by_pitch + WEIGHTS["1b"] * b.singles() \
		+ WEIGHTS["2b"] * b.doubles + WEIGHTS["3b"] * b.triples + WEIGHTS["hr"] * b.home_runs
	return num / den


func batting_war(id: String) -> float:
	var b: BattingLine = _season.book.batting.get(id)
	var p: Player = _players.get(id)
	if b == null or p == null or b.pa == 0:
		return 0.0
	var runs := (woba(b) - _lg_woba) / WOBA_SCALE * b.pa
	var code := Position.code(p.primary_position())
	runs += float(POSITION_RUNS.get(code, 0.0)) * b.pa / 600.0
	runs += REPLACEMENT_RUNS * b.pa / 600.0
	return runs / RUNS_PER_WIN


func pitching_war(id: String) -> float:
	var line: PitchingLine = _season.book.pitching.get(id)
	if line == null or line.outs == 0:
		return 0.0
	var starter := line.starts * 2 >= line.games
	var replacement := _lg_era * (STARTER_REPLACEMENT if starter else RELIEVER_REPLACEMENT)
	return (replacement - line.era()) * (line.outs / 3.0) / 9.0 / RUNS_PER_WIN


func war(id: String) -> float:
	var p: Player = _players.get(id)
	if p != null and p.is_pitcher():
		return pitching_war(id)
	return batting_war(id)


func _league_rates() -> void:
	var bat := BattingLine.new()
	var pit := PitchingLine.new()
	for id: String in _season.book.batting:
		if _team_of.has(id):
			bat.add(_season.book.batting[id])
	for id: String in _season.book.pitching:
		if _team_of.has(id):
			pit.add(_season.book.pitching[id])
	_lg_woba = woba(bat)
	_lg_era = pit.era() if pit.outs > 0 else 4.3


func _award(title: String, id: String, value: float, text: String) -> Award:
	var a := Award.new()
	a.title = title
	a.player_id = id
	a.team_id = _team_of.get(id, "")
	a.value = value
	a.text = text
	return a


func _name(id: String) -> String:
	var p: Player = _players.get(id)
	return p.name if p != null else id


## One line for the awards screen: "MVP  권시영 (라온)  타율 .370 · 50홈런 · 155타점".
func line(a: Award) -> String:
	var team: Team = _season.teams.get(a.team_id)
	return "%s  %s (%s)  %s" % [a.title, _name(a.player_id), team.short_name if team != null else "", a.text]


func _summary(id: String) -> String:
	var p: Player = _players.get(id)
	if p != null and p.is_pitcher():
		var l: PitchingLine = _season.book.pitching[id]
		if l.saves >= 10:
			return "%d세이브 · 평균자책점 %.2f" % [l.saves, l.era()]
		if l.holds >= 10:
			return "%d홀드 · 평균자책점 %.2f" % [l.holds, l.era()]
		return "%d승 %d패 · 평균자책점 %.2f · %d탈삼진" % [l.wins, l.losses, l.era(), l.strikeouts]
	var b: BattingLine = _season.book.batting[id]
	return "타율 %s · %d홈런 · %d타점" % [BattingLine.rate_text(b.average()), b.home_runs, b.rbi]


func _decide() -> void:
	var hitters: Array[String] = []
	var pitchers: Array[String] = []
	for id: String in _season.book.batting:
		if _team_of.has(id) and not _players[id].is_pitcher():
			hitters.append(id)
	for id: String in _season.book.pitching:
		if _team_of.has(id):
			pitchers.append(id)
	var by_war := func(a: String, b: String) -> bool: return war(a) > war(b)
	var everyone: Array[String] = hitters.duplicate()
	everyone.append_array(pitchers)
	everyone.sort_custom(by_war)
	if not everyone.is_empty():
		mvp = _award("MVP", everyone[0], war(everyone[0]), _summary(everyone[0]))
	pitchers.sort_custom(by_war)
	if not pitchers.is_empty():
		pitcher = _award("투수상", pitchers[0], war(pitchers[0]), _summary(pitchers[0]))
	for id: String in everyone:
		if _year - _players[id].born <= ROOKIE_AGE:
			rookie = _award("신인상", id, war(id), _summary(id))
			break
	_best_at_positions(hitters, pitchers)
	_titles(hitters, pitchers)


func _best_at_positions(hitters: Array[String], pitchers: Array[String]) -> void:
	var enough := _season.qualifying_pa() / 2
	var taken: Dictionary[String, bool] = {}
	if not pitchers.is_empty():
		best.append(_award("베스트 투수", pitchers[0], war(pitchers[0]), _summary(pitchers[0])))
	var order: Array[String] = hitters.duplicate()
	order.sort_custom(func(a: String, b: String) -> bool: return batting_war(a) > batting_war(b))
	var places: Array[String] = ["C", "1B", "2B", "3B", "SS"]
	for code: String in places:
		for id: String in order:
			if taken.has(id) or _season.book.batting[id].pa < enough:
				continue
			if Position.code(_players[id].primary_position()) == code:
				taken[id] = true
				best.append(_award("베스트 " + Position.name_of(Position.from_code(code)), id, batting_war(id), _summary(id)))
				break
	var outfield := 0
	for id: String in order:
		if outfield >= 3:
			break
		if taken.has(id) or _season.book.batting[id].pa < enough:
			continue
		if Position.OUTFIELD.has(_players[id].primary_position()):
			taken[id] = true
			outfield += 1
			best.append(_award("베스트 외야수", id, batting_war(id), _summary(id)))
	for id: String in order:
		if not taken.has(id) and _season.book.batting[id].pa >= enough:
			best.append(_award("베스트 지명타자", id, batting_war(id), _summary(id)))
			break


func _titles(hitters: Array[String], pitchers: Array[String]) -> void:
	var qualified: Array[String] = []
	for id: String in hitters:
		if _season.book.batting[id].pa >= _season.qualifying_pa():
			qualified.append(id)
	var bat := func(id: String) -> BattingLine: return _season.book.batting[id]
	var top := func(pool: Array[String], key: Callable) -> String:
		var bestid := ""
		var best_value := -INF
		for id: String in pool:
			var v: float = key.call(id)
			if v > best_value:
				best_value = v
				bestid = id
		return bestid
	var add := func(title: String, id: String, text: String) -> void:
		if id != "":
			titles.append(_award(title, id, 0.0, text))
	var id := ""
	id = top.call(qualified, func(x: String) -> float: return (bat.call(x) as BattingLine).average())
	add.call("타율", id, BattingLine.rate_text((bat.call(id) as BattingLine).average()) if id != "" else "")
	id = top.call(hitters, func(x: String) -> float: return (bat.call(x) as BattingLine).home_runs)
	add.call("홈런", id, "%d개" % (bat.call(id) as BattingLine).home_runs if id != "" else "")
	id = top.call(hitters, func(x: String) -> float: return (bat.call(x) as BattingLine).rbi)
	add.call("타점", id, "%d개" % (bat.call(id) as BattingLine).rbi if id != "" else "")
	id = top.call(hitters, func(x: String) -> float: return (bat.call(x) as BattingLine).hits)
	add.call("안타", id, "%d개" % (bat.call(id) as BattingLine).hits if id != "" else "")
	id = top.call(hitters, func(x: String) -> float: return (bat.call(x) as BattingLine).runs)
	add.call("득점", id, "%d개" % (bat.call(id) as BattingLine).runs if id != "" else "")
	id = top.call(hitters, func(x: String) -> float: return (bat.call(x) as BattingLine).stolen_bases)
	add.call("도루", id, "%d개" % (bat.call(id) as BattingLine).stolen_bases if id != "" else "")
	id = top.call(qualified, func(x: String) -> float: return (bat.call(x) as BattingLine).on_base())
	add.call("출루율", id, BattingLine.rate_text((bat.call(id) as BattingLine).on_base()) if id != "" else "")
	id = top.call(qualified, func(x: String) -> float: return (bat.call(x) as BattingLine).slugging())
	add.call("장타율", id, BattingLine.rate_text((bat.call(id) as BattingLine).slugging()) if id != "" else "")
	var pit := func(x: String) -> PitchingLine: return _season.book.pitching[x]
	var q_p: Array[String] = []
	var deciders: Array[String] = []
	for x: String in pitchers:
		var l: PitchingLine = pit.call(x)
		if l.outs >= _season.qualifying_outs():
			q_p.append(x)
		# KBO: ten wins for the winning-percentage title, in proportion in a shorter season.
		if l.wins >= ceili(10.0 * _season.games_per_team / 144.0):
			deciders.append(x)
	id = top.call(pitchers, func(x: String) -> float: return (pit.call(x) as PitchingLine).wins)
	add.call("다승", id, "%d승" % (pit.call(id) as PitchingLine).wins if id != "" else "")
	id = top.call(q_p, func(x: String) -> float: return -(pit.call(x) as PitchingLine).era())
	add.call("평균자책점", id, "%.2f" % (pit.call(id) as PitchingLine).era() if id != "" else "")
	id = top.call(pitchers, func(x: String) -> float: return (pit.call(x) as PitchingLine).strikeouts)
	add.call("탈삼진", id, "%d개" % (pit.call(id) as PitchingLine).strikeouts if id != "" else "")
	id = top.call(pitchers, func(x: String) -> float: return (pit.call(x) as PitchingLine).saves)
	add.call("세이브", id, "%d개" % (pit.call(id) as PitchingLine).saves if id != "" else "")
	id = top.call(pitchers, func(x: String) -> float: return (pit.call(x) as PitchingLine).holds)
	add.call("홀드", id, "%d개" % (pit.call(id) as PitchingLine).holds if id != "" else "")
	id = top.call(deciders, func(x: String) -> float:
		var l: PitchingLine = pit.call(x)
		return float(l.wins) / maxi(l.wins + l.losses, 1))
	if id != "":
		var l: PitchingLine = pit.call(id)
		add.call("승률", id, BattingLine.rate_text(float(l.wins) / maxi(l.wins + l.losses, 1)))
