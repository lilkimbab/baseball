class_name GameRating
extends RefCounted
## The game rating and its reward (docs/02 section 6.3): 0 to 10 from what the player did,
## with his game goal and clutch scenes counting; bronze, silver or gold by the rating; and a
## reward box for the medal holding points, growth points or a piece of gear (gear adds a point
## to one rating, once per piece).

const MEDALS: Array[String] = ["", "동", "은", "금"]


static func rate(bat: BattingLine, pitch: PitchingLine, chances: int, errors: int, goal_met: bool, clutch: int, rules: CareerRules) -> float:
	var r := rules.rating
	var score := float(r.get("base", 5.5))
	if bat != null and bat.pa > 0:
		var w: Dictionary = r.get("batting", {})
		score += bat.hits * float(w.get("hit", 0.0)) + (bat.doubles + bat.triples) * float(w.get("extra_base", 0.0)) \
			+ bat.home_runs * (float(w.get("home_run", 0.0)) + float(w.get("extra_base", 0.0))) \
			+ (bat.walks + bat.intentional_walks + bat.hit_by_pitch) * float(w.get("walk", 0.0)) \
			+ bat.rbi * float(w.get("rbi", 0.0)) + bat.runs * float(w.get("run", 0.0)) \
			+ bat.stolen_bases * float(w.get("stolen_base", 0.0)) + (bat.ab - bat.hits) * float(w.get("out", 0.0)) \
			+ bat.strikeouts * float(w.get("strikeout", 0.0))
	var f: Dictionary = r.get("fielding", {})
	score += chances * float(f.get("chance", 0.0)) + errors * float(f.get("error", 0.0))
	if pitch != null and pitch.outs > 0:
		var p: Dictionary = r.get("pitching", {})
		score += pitch.outs * float(p.get("out", 0.0)) + pitch.strikeouts * float(p.get("strikeout", 0.0)) \
			+ (pitch.walks + pitch.hit_by_pitch) * float(p.get("walk", 0.0)) + pitch.hits * float(p.get("hit", 0.0)) \
			+ pitch.runs * float(p.get("run", 0.0)) + pitch.wins * float(p.get("win", 0.0)) \
			+ pitch.saves * float(p.get("save", 0.0)) + pitch.holds * float(p.get("hold", 0.0))
	if goal_met:
		score += float(r.get("goal", 0.0))
	score += clutch * float(r.get("clutch", 0.0))
	return clampf(snappedf(score, 0.1), 0.0, 10.0)


## 0 none, 1 bronze, 2 silver, 3 gold.
static func medal(rating: float, rules: CareerRules) -> int:
	var m := 0
	for i: int in rules.medals.size():
		if rating >= rules.medals[i]:
			m = i + 1
	return m


## Opens the reward box for a medal. Returns what was in it.
static func open_box(c: CareerPlayer, medal_level: int, rules: CareerRules, rng: Rng) -> String:
	if medal_level <= 0:
		return ""
	var i := medal_level - 1
	var roll := rng.next_int(3)
	if roll == 2 and not rules.gear.is_empty():
		var g: Dictionary = rules.gear[rng.next_int(rules.gear.size())]
		var name := str(g.get("name", ""))
		var rating := str(g.get("rating", ""))
		if not c.gear.has(name) and (rules.field_of(rating) == "pitching") == c.is_pitcher():
			c.gear[name] = rating
			Training.grow(c.player, PackedStringArray([rating]), float(g.get("amount", 1)))
			return "장비: %s" % name
		roll = 0
	if roll == 1:
		var fields: Array[String] = []
		if c.is_pitcher():
			fields.append("pitching")
		else:
			fields.append_array(["batting", "fielding", "running"])
		var field: String = fields[rng.next_int(fields.size())]
		var amount := float(rules.reward_gp[mini(i, rules.reward_gp.size() - 1)])
		c.gp[field] = float(c.gp.get(field, 0.0)) + amount
		return "성장 포인트: %s +%d" % [{"batting": "타격", "fielding": "수비", "running": "주루", "pitching": "투구"}[field], roundi(amount)]
	var points := rules.reward_points[mini(i, rules.reward_points.size() - 1)]
	c.points += points
	return "포인트 +%d" % points
