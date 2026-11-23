class_name PitchEvolution
extends RefCounted
## A career pitcher's pitches change: one he has thrown enough, with the
## rating that matters high enough, turns into the next one up — a changeup into a circle
## changeup, a slider into a sweeper or a hard slider, a curve into a power curve, a four-seam
## into a rising fastball. He can also learn new pitches with pitching points, up to six.


## The pitch's speed, movement or command as the rule reads it.
static func reading(p: Player, a: ArsenalPitch, rating: String) -> float:
	match rating:
		"velocity":
			return p.pitching.fastball_speed()
		"movement":
			return a.movement
		"command":
			return a.command
	return 0.0


## Evolutions due now, applied. Returns what changed ("슬라이더 → 스위퍼").
static func check(c: CareerPlayer, rules: CareerRules, catalog: Dictionary[StringName, PitchType]) -> PackedStringArray:
	var out := PackedStringArray()
	if not c.is_pitcher():
		return out
	for a: ArsenalPitch in c.player.pitching.arsenal:
		for e: CareerRules.Evolution in rules.evolutions:
			if a.type != e.from or int(c.pitch_uses.get(a.type, 0)) < e.uses:
				continue
			if reading(c.player, a, e.rating) < e.at_least or _has(c, e.to):
				continue
			var old_label := _label(a.type, catalog)
			var before: PitchType = catalog.get(a.type)
			var after: PitchType = catalog.get(e.to)
			if before != null and after != null:
				a.velo_avg += after.speed_kmh - before.speed_kmh
				a.velo_max += after.speed_kmh - before.speed_kmh
			c.pitch_uses[e.to] = int(c.pitch_uses.get(a.type, 0))
			a.type = e.to
			a.movement = minf(a.movement + 3.0, 99.0)
			out.append("%s → %s" % [old_label, _label(e.to, catalog)])
			break
	return out


static func _has(c: CareerPlayer, id: StringName) -> bool:
	for a: ArsenalPitch in c.player.pitching.arsenal:
		if a.type == id:
			return true
	return false


static func _label(id: StringName, catalog: Dictionary[StringName, PitchType]) -> String:
	var t: PitchType = catalog.get(id)
	return t.label if t != null else String(id)


## Pitches he could learn now: not ones he has, while he has fewer than the most.
static func learnable(c: CareerPlayer, rules: CareerRules) -> Array[StringName]:
	var out: Array[StringName] = []
	if not c.is_pitcher() or c.player.pitching.arsenal.size() >= rules.max_pitches:
		return out
	for id: StringName in rules.learnable:
		if not _has(c, id):
			out.append(id)
	return out


## Learns a pitch with pitching points (or, `free`, picked up by himself: CareerEvents, a lesson
## paid for: CareerContract): it starts a little below his others.
static func learn(c: CareerPlayer, id: StringName, rules: CareerRules, catalog: Dictionary[StringName, PitchType], free: bool = false) -> bool:
	if not learnable(c, rules).has(id) or (not free and float(c.gp.get("pitching", 0.0)) < rules.new_pitch_gp):
		return false
	if not free:
		c.gp["pitching"] = float(c.gp["pitching"]) - rules.new_pitch_gp
	var r := c.player.pitching
	var fastball := r.fastball_speed()
	var a := ArsenalPitch.new()
	a.type = id
	var reference: float = catalog[id].speed_kmh if catalog.has(id) else 130.0
	a.velo_avg = reference + (fastball - 145.0) * 0.8
	a.velo_max = a.velo_avg + 3.0
	a.movement = maxf(r.arsenal[0].movement - 6.0, 20.0)
	a.command = maxf(r.arsenal[0].command - 8.0, 20.0)
	# A new pitch is thrown now and then; the others give up a share.
	a.usage = 0.1
	for other: ArsenalPitch in r.arsenal:
		other.usage *= 0.9
	r.arsenal.append(a)
	return true


## A game's pitches into the use counts: those seen on screen, or his pitch count shared by
## usage when the game was settled at once.
static func note_game(c: CareerPlayer, pitches: int, seen: Dictionary[StringName, int]) -> void:
	if not c.is_pitcher():
		return
	if not seen.is_empty():
		for id: StringName in seen:
			c.pitch_uses[id] = int(c.pitch_uses.get(id, 0)) + seen[id]
		return
	for a: ArsenalPitch in c.player.pitching.arsenal:
		c.pitch_uses[a.type] = int(c.pitch_uses.get(a.type, 0)) + roundi(pitches * a.usage)
