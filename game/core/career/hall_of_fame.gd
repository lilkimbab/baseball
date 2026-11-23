class_name HallOfFame
extends RefCounted
## The hall of fame of the person's own careers: a retired career player goes
## in when his first-team career meets one of the marks below; the list outlives each career
## (kept beside the profile, user://hall_of_fame.json).
##
## The marks (the KBO has no hall of its own; these are its elite as the KBO's "레전드 40"
## counted them: some twenty men with 2,000 hits, ten with 300 home runs, ten with 150 wins):
## - a hitter: 2,000 hits; or 300 home runs; or 1,500 hits batting .300; or 4,000 plate
##   appearances with an OPS of .850; or five titles,
## - a pitcher: 150 wins; or 250 saves; or 2,000 strikeouts; or 100 wins with an ERA of 3.20;
##   or five titles.
## Counts are of 144-game seasons: a career of shorter seasons needs as much in proportion
## (scale). Who is in, and by what, is kept with his line.

const PATH := "user://hall_of_fame.json"
const MARKS_TEXT := "타자: 2,000안타 · 300홈런 · 1,500안타+타율 .300 · 4,000타석+OPS .850 · 타이틀 5개 / 투수: 150승 · 250세이브 · 2,000탈삼진 · 100승+평균자책점 3.20 · 타이틀 5개 (144경기 시즌 기준, 짧은 시즌은 비례)"


## The share of a 144-game season his seasons were.
static func scale(c: CareerPlayer, games: int) -> float:
	return clampf(float(games) / 144.0, 0.1, 1.0)


## The marks he met (empty: not in). `titles` counted over his winters.
static func marks(c: CareerPlayer, bat: BattingLine, pitch: PitchingLine, titles: int, games: int) -> PackedStringArray:
	var k := scale(c, games)
	var out := PackedStringArray()
	if c.is_pitcher():
		if pitch.wins >= 150 * k:
			out.append("%d승" % pitch.wins)
		if pitch.saves >= 250 * k:
			out.append("%d세이브" % pitch.saves)
		if pitch.strikeouts >= 2000 * k:
			out.append("%d탈삼진" % pitch.strikeouts)
		if pitch.wins >= 100 * k and pitch.outs > 0 and pitch.era() <= 3.2:
			out.append("%d승 · 평균자책점 %.2f" % [pitch.wins, pitch.era()])
	else:
		if bat.hits >= 2000 * k:
			out.append("%d안타" % bat.hits)
		if bat.home_runs >= 300 * k:
			out.append("%d홈런" % bat.home_runs)
		if bat.hits >= 1500 * k and bat.average() >= 0.3:
			out.append("%d안타 · 타율 %s" % [bat.hits, BattingLine.rate_text(bat.average())])
		if bat.pa >= 4000 * k and bat.ops() >= 0.85:
			out.append("OPS %s" % BattingLine.rate_text(bat.ops()))
	if titles >= 5:
		out.append("타이틀 %d개" % titles)
	return out


static func load_list() -> Array:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	return (d as Array) if d is Array else []


## Adds a member (not from a tool's run: Profile.tool_run).
static func add(entry: Dictionary) -> void:
	if Profile.tool_run():
		return
	var list := load_list()
	list.append(entry)
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(list, "\t"))
