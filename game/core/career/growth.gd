class_name Growth
extends RefCounted
## Growth points: earned in four fields — batting, fielding, running,
## pitching — only by playing in that field, and spent only on that field's ratings. The next
## point of a rating costs base × (1 + (value − 40) / 20)², a fifth less for the type's
## strengths.


## Points from a game's lines: what the player did at bat, on the bases, in the field (balls he
## handled and errors) and on the mound. Returns field → points.
static func from_game(bat: BattingLine, pitch: PitchingLine, chances: int, errors: int, rules: CareerRules) -> Dictionary[String, float]:
	var out: Dictionary[String, float] = {"batting": 0.0, "fielding": 0.0, "running": 0.0, "pitching": 0.0}
	if bat != null and bat.pa > 0:
		var b: Dictionary = rules.gp["batting"]
		out["batting"] = bat.singles() * float(b.get("single", 0)) + bat.doubles * float(b.get("double", 0)) \
			+ bat.triples * float(b.get("triple", 0)) + bat.home_runs * float(b.get("home_run", 0)) \
			+ (bat.walks + bat.hit_by_pitch) * float(b.get("walk", 0)) + bat.rbi * float(b.get("rbi", 0)) \
			+ bat.pa * float(b.get("plate_appearance", 0))
		var r: Dictionary = rules.gp["running"]
		var on_base := bat.hits + bat.walks + bat.intentional_walks + bat.hit_by_pitch
		out["running"] = bat.stolen_bases * float(r.get("stolen_base", 0)) + bat.runs * float(r.get("run", 0)) + on_base * float(r.get("times_on_base", 0))
	var f: Dictionary = rules.gp["fielding"]
	# Capped: a first baseman's routine putouts would otherwise grow his fielding three times
	# as fast as anyone's.
	out["fielding"] = minf(chances * float(f.get("chance", 0)) + errors * float(f.get("error", 0)), float(f.get("max_per_game", INF)))
	if pitch != null and pitch.outs > 0:
		var p: Dictionary = rules.gp["pitching"]
		var innings := pitch.outs / 3
		var scoreless := maxi(innings - pitch.runs, 0)
		out["pitching"] = pitch.outs * float(p.get("out", 0)) + pitch.strikeouts * float(p.get("strikeout", 0)) \
			+ scoreless * float(p.get("scoreless_inning", 0)) + pitch.wins * float(p.get("win", 0)) \
			+ pitch.saves * float(p.get("save", 0)) + pitch.holds * float(p.get("hold", 0))
	return out


static func add(c: CareerPlayer, points: Dictionary[String, float]) -> void:
	for field: String in points:
		c.gp[field] = float(c.gp.get(field, 0.0)) + points[field]


## Current value of a rating as growth sees it (a pitcher's velocity on the same scale: 140
## km/h is 40, each km/h two points).
static func value(p: Player, rating: String) -> float:
	match rating:
		"contact":
			return p.batting.contact()
		"power":
			return p.batting.power()
		"eye":
			return p.batting.eye
		"speed":
			return p.batting.speed
		"baserunning":
			return p.batting.baserunning
		"range":
			return p.fielding.range
		"hands":
			return p.fielding.hands
		"arm":
			return p.fielding.arm
		"accuracy":
			return p.fielding.accuracy
		"control":
			return p.pitching.control if p.pitching != null else 0.0
		"stamina":
			return p.pitching.stamina if p.pitching != null else 0.0
		"velocity":
			return 40.0 + (p.pitching.fastball_speed() - 140.0) * 2.0 if p.pitching != null else 0.0
		"movement":
			return p.pitching.arsenal[0].movement if p.pitching != null and not p.pitching.arsenal.is_empty() else 0.0
		"command":
			return p.pitching.arsenal[0].command if p.pitching != null and not p.pitching.arsenal.is_empty() else 0.0
	return 0.0


## Past 99 (RatingScale.NATURAL) each point costs twice as much again every BEYOND_DOUBLING
## points: the way to 130 is there for a career really worked at, and long.
const BEYOND_DOUBLING := 10.0


static func cost(c: CareerPlayer, rating: String, rules: CareerRules) -> float:
	var v := value(c.player, rating)
	var price := rules.cost_base * pow(1.0 + (v - 40.0) / 20.0, 2.0)
	if v >= RatingScale.NATURAL:
		price *= pow(2.0, (v - RatingScale.NATURAL + 1.0) / BEYOND_DOUBLING)
	var type := rules.type_by_id(c.type_id)
	if type != null and (type.strengths.has(rating) or (rating == "movement" and type.strengths.has("stuff"))):
		price *= 1.0 - rules.type_discount
	return maxf(price, 1.0)


## Spends the field's points on one point of the rating. False if he has too few points, the
## rating is not his (a hitter's pitching) or it is at the top.
static func raise(c: CareerPlayer, rating: String, rules: CareerRules) -> bool:
	var field := rules.field_of(rating)
	if field == "" or (field == "pitching") != c.is_pitcher():
		return false
	if value(c.player, rating) >= RatingScale.MAX:
		return false
	var price := cost(c, rating, rules)
	if float(c.gp.get(field, 0.0)) < price:
		return false
	c.gp[field] = float(c.gp[field]) - price
	if rating == "stamina":
		c.player.pitching.stamina = minf(c.player.pitching.stamina + 1.0, RatingScale.MAX)
	elif rating == "velocity":
		Training.grow(c.player, PackedStringArray(["velocity"]), 2.5, RatingScale.MAX)
	else:
		# The person raises one rating where the engine keeps two (the user: "not too many
		# ratings"): 주력 is speed and base-running sense, 제구 the control of every pitch.
		var keys := PackedStringArray([rating])
		if rating == "speed":
			keys.append("baserunning")
		elif rating == "control":
			keys.append("command")
		Training.grow(c.player, keys, 1.0, RatingScale.MAX)
	return true
