class_name TeamColors
extends RefCounted
## Team colours (docs/02 section 5.5): a first team built a certain way gets a bonus for the
## whole club. Limits keep one combination from ruling the game: at most rules.color_limit
## colours at once (the first ones in the table that are met), and no rating goes up by more
## than rules.color_cap however many colours add to it.

## What "all ratings" means for a bonus.
const ALL: Array[String] = ["contact", "power", "eye", "speed", "range", "hands", "control", "movement", "command"]


## The colours a club has now, in table order, at most color_limit. For a stepped colour
## (franchise) the bonus is scaled to the step reached.
static func active(team: Team, club: Club, rules: ClubRules, ovr: Overall, catalog: Dictionary[StringName, PitchType]) -> Array[ClubRules.ColorDef]:
	var out: Array[ClubRules.ColorDef] = []
	for c: ClubRules.ColorDef in rules.colors:
		if out.size() >= rules.color_limit:
			break
		if level(c, team, club, rules, ovr, catalog) > 0:
			out.append(c)
	return out


## 0 when not met, otherwise 1 (or the step reached, for a stepped colour).
static func level(c: ClubRules.ColorDef, team: Team, club: Club, rules: ClubRules, ovr: Overall, catalog: Dictionary[StringName, PitchType]) -> int:
	var first := team.first_team()
	var n := 0
	match c.need_kind:
		&"homegrown", &"developed":
			for p: Player in first:
				var set: Dictionary[String, bool] = club.homegrown if c.need_kind == &"homegrown" else club.developed
				if set.has(p.id):
					n += 1
			if not c.steps.is_empty():
				var reached := 0
				for i: int in c.steps.size():
					if n >= c.steps[i]:
						reached = i + 1
				return reached
		&"starter", &"reliever":
			var role: StringName = &"SP" if c.need_kind == &"starter" else &"RP"
			for p: Player in first:
				if p.role() == role and rules.grade_rank(rules.grade_of(Overall.pitcher(p, catalog)).name) <= rules.grade_rank(c.grade_at_least):
					n += 1
		_:
			for p: Player in first:
				if not p.is_pitcher() and _rating(p, c.rating) >= c.at_least:
					n += 1
	return 1 if n >= c.count else 0


static func _rating(p: Player, key: String) -> float:
	match key:
		"speed":
			return p.batting.speed
		"power":
			return p.batting.power()
		"contact":
			return p.batting.contact()
		"range":
			return p.fielding.range
	return 0.0


## The rating changes the active colours give one player: no rating goes up by more than the
## cap however many colours add to it.
static func deltas(p: Player, actives: Array[ClubRules.ColorDef], team: Team, club: Club, rules: ClubRules, ovr: Overall, catalog: Dictionary[StringName, PitchType]) -> Dictionary[String, float]:
	var out: Dictionary[String, float] = {}
	for c: ClubRules.ColorDef in actives:
		var applies := false
		match c.to:
			&"all":
				applies = true
			&"batter":
				applies = not p.is_pitcher()
			&"starter":
				applies = p.role() == &"SP"
			&"reliever":
				applies = p.role() == &"RP"
		if not applies:
			continue
		var scale := float(level(c, team, club, rules, ovr, catalog))
		for key: String in c.bonus:
			if key == "training":
				continue
			var keys: Array[String] = []
			if key == "all":
				keys.assign(ALL)
			else:
				keys.append(key)
			for k: String in keys:
				out[k] = minf(float(out.get(k, 0.0)) + c.bonus[key] * scale, rules.color_cap)
	return out


## Extra training speed from the colours (development).
static func training_boost(actives: Array[ClubRules.ColorDef]) -> float:
	var boost := 0.0
	for c: ClubRules.ColorDef in actives:
		boost += float(c.bonus.get("training", 0.0))
	return boost
