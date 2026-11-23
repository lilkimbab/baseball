class_name GameLog
extends RefCounted
## Each game's line of the players the person follows (queue stage 5: "each player's games"):
## his own club's men in a league season, his own player in a career (both teams). Kept on the
## season (Season.game_logs: player id → entries) and saved with it; the others' games are not
## kept, so a save stays small (a club's 35 men × 144 games is about 60 KB compressed).
##
## An entry: [day, opponent id, at home (1/0), result ("승"·"패"·"무"), kind ("bat"/"pitch"),
## the numbers, where ("1군"·"2군"·"PS"·"고교")]. A hitter's numbers: plate appearances,
## at-bats, hits, doubles, triples, home runs, runs batted in, walks (with hit-by-pitch),
## strikeouts, stolen bases. A pitcher's: outs, hits, runs, earned runs, walks, strikeouts,
## the decision ("승"·"패"·"세"·"홀"·"").

const BAT := ["타석", "타수", "안타", "2루타", "3루타", "홈런", "타점", "볼넷", "삼진", "도루"]
const PITCH := ["아웃", "피안타", "실점", "자책", "볼넷", "탈삼진"]


static func entry_for_bat(day: int, opponent: String, home: bool, result: String, b: BattingLine, where: String) -> Array:
	return [day, opponent, 1 if home else 0, result, "bat", [b.pa, b.ab, b.hits, b.doubles, b.triples, b.home_runs, b.rbi, b.walks + b.hit_by_pitch, b.strikeouts, b.stolen_bases], where]


static func entry_for_pitch(day: int, opponent: String, home: bool, result: String, q: PitchingLine, decision: String, where: String) -> Array:
	return [day, opponent, 1 if home else 0, result, "pitch", [q.outs, q.hits, q.runs, q.earned_runs, q.walks, q.strikeouts, decision], where]


## A game into the logs of the followed men who played in it.
static func note(logs: Dictionary, followed: Dictionary, game: ScheduledGame, book: StatBook, where: String) -> void:
	for id: String in book.batting:
		if not followed.has(id):
			continue
		var side := str(followed[id])
		var line: BattingLine = book.batting[id]
		if line.pa > 0:
			_add(logs, id, entry_for_bat(game.day, _other(game, side), game.home == side, _result(game, side), line, where))
	for id: String in book.pitching:
		if not followed.has(id):
			continue
		var side := str(followed[id])
		var q: PitchingLine = book.pitching[id]
		var decision := "승" if q.wins > 0 else ("패" if q.losses > 0 else ("세" if q.saves > 0 else ("홀" if q.holds > 0 else "")))
		_add(logs, id, entry_for_pitch(game.day, _other(game, side), game.home == side, _result(game, side), q, decision, where))


static func _add(logs: Dictionary, id: String, entry: Array) -> void:
	if not logs.has(id):
		logs[id] = []
	(logs[id] as Array).append(entry)


static func _other(game: ScheduledGame, side: String) -> String:
	return game.home if game.away == side else game.away


static func _result(game: ScheduledGame, side: String) -> String:
	var mine := game.runs_of(side)
	var theirs := game.runs_against(side)
	return "승" if mine > theirs else ("패" if mine < theirs else "무")


## A logged game in a line ("4타수 2안타 1홈런 2타점", "6⅔이닝 1실점 7삼진 승").
static func text(entry: Array) -> String:
	var n: Array = entry[5]
	if str(entry[4]) == "bat":
		var parts := PackedStringArray(["%d타수 %d안타" % [int(n[1]), int(n[2])]])
		if int(n[5]) > 0:
			parts.append("%d홈런" % int(n[5]))
		if int(n[6]) > 0:
			parts.append("%d타점" % int(n[6]))
		if int(n[7]) > 0:
			parts.append("%d볼넷" % int(n[7]))
		if int(n[9]) > 0:
			parts.append("%d도루" % int(n[9]))
		return " ".join(parts)
	var line := PitchingLine.new()
	line.outs = int(n[0])
	var out := "%s이닝 %d실점 %d삼진" % [line.innings_text(), int(n[2]), int(n[5])]
	return out + (" " + str(n[6]) if str(n[6]) != "" else "")
