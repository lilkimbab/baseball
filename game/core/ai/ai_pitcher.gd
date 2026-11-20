class_name AiPitcher
extends RefCounted
## The computer pitcher (docs/03 section 8.1, docs/13 S5-8): picks a pitch from his own
## arsenal by the count, and a target either on the edges of the zone or just off it where a
## batter might chase. Behind in the count he comes in with fastballs; ahead he expands.
## The share of pitches that end up in the zone comes out of these targets plus his command.

## Chance of aiming inside the zone, by balls and strikes.
const ZONE_INTENT := [
	[0.66, 0.55, 0.27],
	[0.66, 0.59, 0.41],
	[0.73, 0.67, 0.55],
	[0.94, 0.90, 0.82],
]
## Fastballs are thrown this much more often when behind, breaking balls when ahead.
const BEHIND_FASTBALL := 1.8
const AHEAD_BREAKING := 1.5
## Chance of picking one of the batter's weak spots for a pitch in the zone.
const WEAK_SPOT_AIM := 0.4
## How far off the zone a chase pitch is aimed: away from the batter (m), in on his hands
## (m, less: a miss there hits him), and up or down (m).
const CHASE_ACROSS := 0.18
const CHASE_INSIDE := 0.15
const CHASE_UP_DOWN := 0.22
## How well a pitch is executed (0..1; PitchDuel turns it and the command rating into the
## size of the miss): a base, plus more for a pitch he commands, with some spread.
const QUALITY_BASE := 0.76
const QUALITY_BY_COMMAND := 0.30
const QUALITY_SPREAD := 0.08


## One pitch of a pitcher's arsenal, as he throws it.
class Option:
	extends RefCounted
	var type: PitchType
	var usage := 0.0
	var command := 50.0


## What he threw last, to avoid a third identical pitch in a row.
class Memory:
	extends RefCounted
	var types: Array[StringName] = []
	var cells := PackedInt32Array()

	func note(type: StringName, cell: int) -> void:
		types.append(type)
		cells.append(cell)
		if types.size() > 2:
			types.remove_at(0)
			cells.remove_at(0)

	func would_repeat_twice(type: StringName, cell: int) -> bool:
		return types.size() == 2 and types[0] == type and types[1] == type and cells[0] == cell and cells[1] == cell


## His pitches as PitchTypes: the catalogue's shape at his own speed and movement.
static func options_for(pitcher: Player, catalog: Dictionary[StringName, PitchType]) -> Array[Option]:
	var out: Array[Option] = []
	if pitcher == null or pitcher.pitching == null:
		return out
	for a: ArsenalPitch in pitcher.pitching.arsenal:
		if not catalog.has(a.type):
			continue
		var base := catalog[a.type]
		var t := PitchType.new()
		t.id = base.id
		t.label = base.label
		t.family = base.family
		t.speed_kmh = a.velo_avg
		t.spin_rpm = base.spin_rpm * lerpf(0.85, 1.15, clampf(a.movement / 99.0, 0.0, 1.0))
		t.efficiency = base.efficiency
		t.tilt_deg = base.tilt_deg
		var o := Option.new()
		o.type = t
		o.usage = a.usage
		o.command = a.command
		out.append(o)
	return out


## The pitch for this count. `weak` lists the batter's weak cells (0..8, row by row from the
## top, first column on the third-base side).
static func decide(options: Array[Option], zone: StrikeZone, balls: int, strikes: int, bats_left: bool,
		weak: PackedInt32Array, memory: Memory, rng: Rng) -> PitchDecision:
	var weights := PackedFloat64Array()
	var behind := balls >= 2 and balls > strikes
	var ahead := strikes == 2 and balls <= 1
	for o: Option in options:
		var w := o.usage
		if behind and o.type.family == &"fastball":
			w *= BEHIND_FASTBALL
		elif ahead and o.type.family != &"fastball":
			w *= AHEAD_BREAKING
		weights.append(w)
	var pick := options[rng.pick_weighted(weights)]
	var in_zone := rng.chance(ZONE_INTENT[mini(balls, 3)][mini(strikes, 2)])
	var target := _zone_target(zone, weak, balls, rng) if in_zone else _chase_target(zone, pick.type.family, bats_left, rng)
	var cell := cell_of(zone, target)
	if memory != null and memory.would_repeat_twice(pick.type.id, cell):
		# Never the same pitch to the same spot three times running.
		target = _chase_target(zone, pick.type.family, bats_left, rng) if in_zone else _zone_target(zone, weak, balls, rng)
		cell = cell_of(zone, target)
	if memory != null:
		memory.note(pick.type.id, cell)
	var choice := PitchDecision.new()
	choice.type = pick.type
	choice.target = target
	choice.quality = clampf(QUALITY_BASE + QUALITY_BY_COMMAND * pick.command / 99.0 + rng.next_normal() * QUALITY_SPREAD, 0.0, 1.0)
	choice.effort = rng.next_range(0.97, 1.0)
	return choice


## The simple pitcher for practice mode: a catalogue pitch, mostly on the edges of the zone.
static func choose(catalog: Dictionary[StringName, PitchType], zone: StrikeZone, rng: Rng) -> PitchDecision:
	var ids: Array[StringName] = [&"four_seam", &"slider", &"changeup", &"curve", &"two_seam"]
	var weights := PackedFloat64Array([0.46, 0.20, 0.14, 0.10, 0.10])
	var choice := PitchDecision.new()
	choice.type = catalog[ids[rng.pick_weighted(weights)]]
	choice.target = _zone_target(zone, PackedInt32Array(), 0, rng) if rng.chance(0.6) else _chase_target(zone, choice.type.family, false, rng)
	choice.quality = rng.next_range(0.55, 1.0)
	choice.effort = rng.next_range(0.97, 1.0)
	return choice


## On the edges of the zone (or over the plate with three balls), sometimes at a weak spot.
static func _zone_target(zone: StrikeZone, weak: PackedInt32Array, balls: int, rng: Rng) -> Vector3:
	if not weak.is_empty() and rng.chance(WEAK_SPOT_AIM):
		var cell := weak[rng.next_int(weak.size())]
		var u := (float(cell % 3) + rng.next_range(0.2, 0.8)) / 3.0
		var v := 1.0 - (float(cell / 3) + rng.next_range(0.2, 0.8)) / 3.0
		return zone.point(u, v)
	if balls >= 3:
		return zone.point(rng.next_range(0.25, 0.75), rng.next_range(0.25, 0.75))
	return zone.point(lerpf(0.18, 0.82, _edge(rng)), lerpf(0.18, 0.82, _edge(rng)))


## Just off the zone where this kind of pitch gets chased: fastballs up or on the corners,
## breaking balls down and away, change-ups down.
static func _chase_target(zone: StrikeZone, family: StringName, bats_left: bool, rng: Rng) -> Vector3:
	var c := zone.center()
	var half := zone.half_width
	var away := -1.0 if bats_left else 1.0
	var x := c.x
	var z := c.z
	match family:
		&"fastball":
			if rng.chance(0.55):
				x = c.x + rng.next_range(-half, half)
				z = zone.top + rng.next_range(0.04, CHASE_UP_DOWN)
			elif rng.chance(0.65):
				x = c.x + away * (half + rng.next_range(0.03, CHASE_ACROSS))
				z = rng.next_range(zone.bottom + 0.1, zone.top - 0.1)
			else:
				x = c.x - away * (half + rng.next_range(0.0, CHASE_INSIDE))
				z = rng.next_range(zone.bottom + 0.1, zone.top - 0.1)
		&"breaking":
			x = c.x + away * (half + rng.next_range(-0.05, CHASE_ACROSS))
			z = zone.bottom - rng.next_range(0.04, CHASE_UP_DOWN)
		_:
			x = c.x + rng.next_range(-half, half)
			z = zone.bottom - rng.next_range(0.05, CHASE_UP_DOWN)
	return Vector3(x, c.y, z)


## Which of the nine cells of the zone a point is in (0..8), or -1 outside.
static func cell_of(zone: StrikeZone, p: Vector3) -> int:
	var u := (p.x - (zone.center().x - zone.half_width)) / (2.0 * zone.half_width)
	var v := (p.z - zone.bottom) / maxf(zone.top - zone.bottom, 0.01)
	if u < 0.0 or u >= 1.0 or v < 0.0 or v >= 1.0:
		return -1
	return int((1.0 - v) * 3.0) * 3 + int(u * 3.0)


## A position across the zone that favours the edges over the middle.
static func _edge(rng: Rng) -> float:
	var x := rng.next_float()
	return 0.5 + 0.5 * signf(x - 0.5) * sqrt(absf(2.0 * x - 1.0))
