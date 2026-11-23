class_name GameGoal
extends RefCounted
## The goal for a whole game: two hits, an extra-base hit, six innings with
## two runs or fewer, no runs in relief. Set by the player's type (or pitching role) in
## data/career.ko.json; worth CareerRules.game_goal_gp in the field it belongs to.

var what := "hits"
var count := 1
var field := "batting"


static func for_player(c: CareerPlayer, rules: CareerRules) -> GameGoal:
	var g := GameGoal.new()
	var key := c.position if c.is_pitcher() else c.type_id
	var row: Array = rules.game_goals.get(key, ["times_on_base", 1])
	g.what = str(row[0])
	g.count = int(row[1])
	g.field = "pitching" if c.is_pitcher() else ("running" if g.what == "runs_or_steals" else "batting")
	return g


func label() -> String:
	match what:
		"hits":
			return "안타 %d개" % count
		"extra_bases":
			return "장타 %d개" % count
		"runs_or_steals":
			return "득점과 도루 합해 %d개" % count
		"times_on_base":
			return "출루 %d번" % count
		"quality_start":
			return "6이닝 2실점 이하"
		"scoreless":
			return "실점 없이 마치기"
	return what


func achieved(bat: BattingLine, pitch: PitchingLine) -> bool:
	match what:
		"hits":
			return bat != null and bat.hits >= count
		"extra_bases":
			return bat != null and bat.doubles + bat.triples + bat.home_runs >= count
		"runs_or_steals":
			return bat != null and bat.runs + bat.stolen_bases >= count
		"times_on_base":
			return bat != null and bat.hits + bat.walks + bat.intentional_walks + bat.hit_by_pitch >= count
		"quality_start":
			return pitch != null and pitch.outs >= 18 and pitch.runs <= 2
		"scoreless":
			return pitch != null and pitch.outs > 0 and pitch.runs == 0
	return false
