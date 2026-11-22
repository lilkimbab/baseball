class_name Player
extends RefCounted
## One player: who he is, how he plays, and how he looks. Read and written by RosterIO.

var id := ""
var name := ""
var number := 0
var born := 2000
## &"R", &"L" or &"S" (switch hitter).
var bats: StringName = &"R"
## &"R" or &"L".
var throws: StringName = &"R"
var height_cm := 183.0
var weight_kg := 88.0
## Position code ("SS", "SP", ...) -> aptitude 0..100.
var positions: Dictionary[String, float] = {}
var batting := BattingRatings.new()
var fielding := FieldingRatings.new()
## Null for a position player.
var pitching: PitchingRatings
## Form ids for motion: "batting", "pitching".
var forms: Dictionary[String, String] = {}
## &"" for a local player, &"foreign" for one of the club's foreign players, &"asia" for its
## Asia-quota player (docs/13 S7).
var origin: StringName = &""
## Room left to grow, in rating points on his main ratings (docs/08 R6, Development): hidden;
## scouts see it as stars. Below zero: not yet given one (an old pack or save).
var potential := -1.0


func is_pitcher() -> bool:
	return pitching != null


## &"SP", &"RP" or &"" for a position player.
func role() -> StringName:
	if positions.has("SP"):
		return &"SP"
	if positions.has("RP") or is_pitcher():
		return &"RP"
	return &""


## Main position: the one with the highest aptitude.
func primary_position() -> Position.Kind:
	var best := ""
	var best_value := -1.0
	for code: String in positions:
		if positions[code] > best_value:
			best = code
			best_value = positions[code]
	return Position.from_code(best) if best != "" else Position.Kind.DH


## How well he plays a position, 0..1. Anyone can be a designated hitter; nobody untrained
## can catch or pitch.
func aptitude(kind: Position.Kind) -> float:
	if kind == Position.Kind.DH or kind == Position.Kind.PH or kind == Position.Kind.PR:
		return 1.0
	var code := Position.code(kind)
	if kind == Position.Kind.P:
		return 1.0 if is_pitcher() else 0.0
	if positions.has(code):
		return positions[code] / 100.0
	if kind == Position.Kind.C:
		return 0.0
	# Out of position: an outfielder anywhere in the outfield, anyone at first base.
	if kind == Position.Kind.B1:
		return 0.6
	if Position.OUTFIELD.has(kind):
		for other: Position.Kind in Position.OUTFIELD:
			if positions.has(Position.code(other)):
				return 0.7
	return 0.3


## Fielding ratings scaled by how well he knows the position: a player in a position he cannot
## play fields at half strength, a non-catcher catching at 30%.
func fielding_at(kind: Position.Kind) -> float:
	var fit := aptitude(kind)
	if kind == Position.Kind.C and fit <= 0.0:
		fit = 0.3
	return fielding.overall() * lerpf(0.5, 1.0, clampf(fit, 0.0, 1.0))


## The side he bats from against a pitcher: a switch hitter takes the opposite side.
func batting_side(pitcher_throws: StringName) -> StringName:
	if bats == &"S":
		return &"L" if pitcher_throws == &"R" else &"R"
	return bats


func is_foreign() -> bool:
	return origin != &""


## A copy for one game with his ratings scaled by `factor` (1 as he is; 0.94 for a bad day,
## 1.06 for a good one, docs/02 section 5.4) and then moved by `deltas` (rating name → points:
## contact, power, eye, speed, baserunning, clutch, range, hands, arm, accuracy, control,
## composure, stamina, movement, command; velocity in km/h), for traits and team colours.
## Pitch speeds drop or rise far less than the ratings: a tired arm loses a km/h or two, not 6%.
func with_form(factor: float, deltas: Dictionary[String, float] = {}) -> Player:
	var p := Player.new()
	p.id = id
	p.name = name
	p.number = number
	p.born = born
	p.bats = bats
	p.throws = throws
	p.height_cm = height_cm
	p.weight_kg = weight_kg
	p.positions = positions.duplicate()
	p.forms = forms.duplicate()
	p.origin = origin
	p.potential = potential
	var s := func(v: float, key: String) -> float: return clampf(v * factor + float(deltas.get(key, 0.0)), 1.0, 99.0)
	var b := BattingRatings.new()
	b.contact_r = s.call(batting.contact_r, "contact")
	b.contact_l = s.call(batting.contact_l, "contact")
	b.power_r = s.call(batting.power_r, "power")
	b.power_l = s.call(batting.power_l, "power")
	b.eye = s.call(batting.eye, "eye")
	b.speed = s.call(batting.speed, "speed")
	b.baserunning = s.call(batting.baserunning, "baserunning")
	b.bunt = s.call(batting.bunt, "bunt")
	b.clutch = clampf(batting.clutch + float(deltas.get("clutch", 0.0)), 1.0, 99.0)
	p.batting = b
	var f := FieldingRatings.new()
	f.range = s.call(fielding.range, "range")
	f.hands = s.call(fielding.hands, "hands")
	f.arm = s.call(fielding.arm, "arm")
	f.accuracy = s.call(fielding.accuracy, "accuracy")
	p.fielding = f
	if pitching != null:
		var r := PitchingRatings.new()
		r.stamina = clampf(pitching.stamina + float(deltas.get("stamina", 0.0)), 1.0, 99.0)
		r.control = s.call(pitching.control, "control")
		r.composure = clampf(pitching.composure + float(deltas.get("composure", 0.0)), 1.0, 99.0)
		r.hold = pitching.hold
		r.fielding = s.call(pitching.fielding, "fielding")
		var kmh := (factor - 1.0) * 25.0 + float(deltas.get("velocity", 0.0))
		for a: ArsenalPitch in pitching.arsenal:
			var c := ArsenalPitch.new()
			c.type = a.type
			c.velo_avg = a.velo_avg + kmh
			c.velo_max = a.velo_max + kmh
			c.movement = s.call(a.movement, "movement")
			c.command = s.call(a.command, "command")
			c.usage = a.usage
			r.arsenal.append(c)
		p.pitching = r
	return p
