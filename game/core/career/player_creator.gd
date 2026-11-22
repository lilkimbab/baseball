class_name PlayerCreator
extends RefCounted
## Makes the career player from the choices on the creation screen (docs/02 section 6.1):
## name, number, hands, body and looks, position and type. He starts at second-team level:
## every rating at the base, his type's strengths higher and its weak side lower.


class Spec:
	var name := "신인"
	var number := 1
	var bats: StringName = &"R"
	var throws: StringName = &"R"
	var position := "SS"
	var type_id := "all_round"
	var body_id := "standard"
	var skin := ""
	var hair := ""
	var beard := ""


static func create(spec: Spec, rules: CareerRules, catalog: Dictionary[StringName, PitchType]) -> CareerPlayer:
	var c := CareerPlayer.new()
	var p := Player.new()
	p.id = "career_%s" % spec.name.md5_text().substr(0, 8)
	p.name = spec.name
	p.number = spec.number
	p.born = 2026 - 20
	# He grows by his own points (CareerRules), not by the league's development.
	p.potential = 0.0
	p.bats = spec.bats
	p.throws = spec.throws
	var body := rules.body_by_id(spec.body_id)
	p.height_cm = body.height
	p.weight_kg = body.weight
	var type := rules.type_by_id(spec.type_id)
	if type == null:
		type = rules.types_for(spec.position)[0]
	var v := func(key: String) -> float:
		var value := rules.base + type.all
		if type.strengths.has(key):
			value += rules.strength
		if type.weak.has(key):
			value += rules.weakness
		return clampf(value, 20.0, 99.0)
	if CareerRules.is_pitching_position(spec.position):
		_pitcher(p, spec, type, v, catalog)
	else:
		_hitter(p, spec, v)
	c.player = p
	c.position = spec.position
	c.type_id = type.id
	c.appearance = {"body": body.id, "skin": spec.skin, "hair": spec.hair, "beard": spec.beard}
	return c


static func _hitter(p: Player, spec: Spec, v: Callable) -> void:
	p.positions[spec.position] = 100.0
	var contact: float = v.call("contact")
	var power: float = v.call("power")
	p.batting.contact_r = contact
	p.batting.contact_l = contact
	p.batting.power_r = power
	p.batting.power_l = power
	p.batting.eye = v.call("eye")
	p.batting.speed = v.call("speed")
	# One running rating for the person (주력): his base-running sense goes with his speed.
	p.batting.baserunning = v.call("speed")
	p.batting.bunt = contact - 5.0
	p.batting.clutch = 50.0
	p.fielding.range = v.call("range")
	p.fielding.hands = v.call("hands")
	p.fielding.arm = v.call("arm") + (4.0 if spec.position == "C" or spec.position == "RF" or spec.position == "3B" else 0.0)
	p.fielding.accuracy = v.call("accuracy")


static func _pitcher(p: Player, spec: Spec, type: CareerRules.PlayerType, v: Callable, catalog: Dictionary[StringName, PitchType]) -> void:
	var role := "SP" if spec.position == "SP" else "RP"
	p.positions[role] = 100.0
	var r := PitchingRatings.new()
	p.pitching = r
	r.control = v.call("control")
	r.composure = 45.0
	r.hold = 45.0
	r.fielding = 45.0
	r.stamina = clampf(float(v.call("stamina")) + (12.0 if role == "SP" else -12.0), 20.0, 99.0)
	var movement: float = v.call("movement")
	if type.strengths.has("stuff"):
		movement += 6.0
	# One control rating for the person (제구): his pitches' command goes with it.
	var command: float = v.call("control")
	var fastball_speed := type.velocity
	for i: int in type.pitches.size():
		var id := type.pitches[i]
		var a := ArsenalPitch.new()
		a.type = id
		if i == 0:
			a.velo_avg = fastball_speed
		else:
			var reference: float = catalog[id].speed_kmh if catalog.has(id) else 130.0
			a.velo_avg = reference + (fastball_speed - 145.0) * 0.8
		a.velo_max = a.velo_avg + 4.0
		a.movement = movement
		a.command = command - (0.0 if i == 0 else 3.0)
		a.usage = 0.5 if i == 0 else 0.5 / (type.pitches.size() - 1)
		r.arsenal.append(a)
	p.batting.contact_r = 20.0
	p.batting.contact_l = 20.0
	p.batting.power_r = 20.0
	p.batting.power_l = 20.0
	p.batting.eye = 20.0
	p.batting.speed = 35.0
	p.fielding.range = r.fielding
	p.fielding.hands = r.fielding
	p.fielding.arm = clampf(50.0 + (fastball_speed - 144.0) * 3.0, 20.0, 99.0)
	p.fielding.accuracy = r.control
