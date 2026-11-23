class_name Milestones
extends RefCounted
## The commemorative balls of a career (the user, 2026-11-23: "a first hit, a first home run, a
## first win, 100 hits … like achievements"). A KBO club keeps the ball of a player's first-team
## milestone and hands it to him, the date and the opponent written on it; here each is kept on
## the career (CareerPlayer.milestones), shown as a ceremony with the ball
## (Ceremony.Kind.MILESTONE), told by the caster the moment it happens (CareerMatch), and put on
## the career's shelf. First-team regular-season numbers only.

## Each: id, name, the line's field (BattingLine for a hitter, PitchingLine for a pitcher), how
## many, a pitcher's.
const LIST: Array = [
	["hit_1", "데뷔 첫 안타", "hits", 1, false],
	["hr_1", "데뷔 첫 홈런", "home_runs", 1, false],
	["rbi_1", "데뷔 첫 타점", "rbi", 1, false],
	["sb_1", "데뷔 첫 도루", "stolen_bases", 1, false],
	["hit_100", "통산 100안타", "hits", 100, false],
	["hit_500", "통산 500안타", "hits", 500, false],
	["hit_1000", "통산 1000안타", "hits", 1000, false],
	["hit_1500", "통산 1500안타", "hits", 1500, false],
	["hit_2000", "통산 2000안타", "hits", 2000, false],
	["hr_50", "통산 50홈런", "home_runs", 50, false],
	["hr_100", "통산 100홈런", "home_runs", 100, false],
	["hr_200", "통산 200홈런", "home_runs", 200, false],
	["hr_300", "통산 300홈런", "home_runs", 300, false],
	["hr_400", "통산 400홈런", "home_runs", 400, false],
	["rbi_500", "통산 500타점", "rbi", 500, false],
	["rbi_1000", "통산 1000타점", "rbi", 1000, false],
	["sb_100", "통산 100도루", "stolen_bases", 100, false],
	["win_1", "데뷔 첫 승", "wins", 1, true],
	["k_1", "데뷔 첫 탈삼진", "strikeouts", 1, true],
	["sv_1", "데뷔 첫 세이브", "saves", 1, true],
	["hld_1", "데뷔 첫 홀드", "holds", 1, true],
	["win_50", "통산 50승", "wins", 50, true],
	["win_100", "통산 100승", "wins", 100, true],
	["win_150", "통산 150승", "wins", 150, true],
	["k_100", "통산 100탈삼진", "strikeouts", 100, true],
	["k_500", "통산 500탈삼진", "strikeouts", 500, true],
	["k_1000", "통산 1000탈삼진", "strikeouts", 1000, true],
	["k_1500", "통산 1500탈삼진", "strikeouts", 1500, true],
	["k_2000", "통산 2000탈삼진", "strikeouts", 2000, true],
	["sv_100", "통산 100세이브", "saves", 100, true],
	["sv_200", "통산 200세이브", "saves", 200, true],
	["hld_100", "통산 100홀드", "holds", 100, true],
]


## A milestone's count in a career's totals ([BattingLine, PitchingLine]).
static func value(totals: Array, stat: String) -> int:
	var bat: BattingLine = totals[0] if totals.size() > 0 else null
	var pitch: PitchingLine = totals[1] if totals.size() > 1 else null
	if bat != null and stat in ["hits", "home_runs", "rbi", "stolen_bases"]:
		return int(bat.get(stat))
	if pitch != null and stat in ["wins", "strikeouts", "saves", "holds"]:
		return int(pitch.get(stat))
	return 0


## The milestones reached between two totals, in the list's order.
static func crossed(before: Array, after: Array, pitcher: bool) -> Array:
	var out: Array = []
	for m: Array in LIST:
		if bool(m[4]) != pitcher:
			continue
		if value(before, str(m[2])) < int(m[3]) and value(after, str(m[2])) >= int(m[3]):
			out.append(m)
	return out


static func name_of(id: String) -> String:
	for m: Array in LIST:
		if str(m[0]) == id:
			return str(m[1])
	return id


## Totals with one game's line added on (the game in progress, for the caster).
static func with_game(totals: Array, bat: BattingLine, pitch: PitchingLine) -> Array:
	var b := BattingLine.new()
	var p := PitchingLine.new()
	if totals.size() > 1:
		b.add(totals[0])
		p.add(totals[1])
	if bat != null:
		b.add(bat)
	if pitch != null:
		p.add(pitch)
	return [b, p]


## The milestones still ahead, the nearest first (by how much of the way is done): each
## [milestone, count so far]. For the shelf's "next" balls.
static func ahead(totals: Array, pitcher: bool, count: int = 2) -> Array:
	var open: Array = []
	for m: Array in LIST:
		if bool(m[4]) != pitcher:
			continue
		var have := value(totals, str(m[2]))
		if have < int(m[3]):
			open.append([m, have])
	open.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[1]) / float(a[0][3]) > float(b[1]) / float(b[0][3]))
	return open.slice(0, count)
