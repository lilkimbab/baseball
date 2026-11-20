class_name LeagueGenerator
extends RefCounted
## Makes up a fictional league: clubs and 28-man rosters with ratings, bodies, handedness and
## pitch mixes in realistic proportions (docs/13 S4-11). Same seed, same league.

## Average talent per division, top division first.
const DIVISION_MEANS: Array[float] = [56.0, 50.0, 44.0]
const TEAM_SPREAD := 11.0
const ABILITY_SPREAD := 9.0
## Roster shape: starters, relievers, catchers, infielders by main position, outfielders.
## Players marked "+" are regulars; the rest are back-ups. A rating of 50 means the average of
## the players who actually play, so back-ups are made weaker than regulars.
const ROSTER: Array[String] = [
	"+SP", "+SP", "+SP", "+SP", "+SP",
	"+RP", "+RP", "+RP", "+RP", "RP", "RP", "RP", "RP",
	"+C", "C",
	"+1B", "+2B", "+3B", "+SS", "2B/SS", "3B/1B", "SS/3B",
	"+LF", "+CF", "+RF", "CF/LF", "RF/1B", "+1B/DH",
]
## How much weaker a back-up is than a regular (rating points, A).
const BACKUP_GAP := 8.0
## Talent offsets so that a club made around 50 averages 50 where it counts: over the plate
## appearances its hitters take and the batters its pitchers face. Managers play their best
## hitters, so hitters are drawn a little lower; pitching is spread over the whole staff,
## so pitchers a little higher. Measured with tools (see docs/13 S4-12).
const HITTER_OFFSET := -4.0
const PITCHER_OFFSET := 2.5
## Breaking and off-speed pitches by how often pitchers have them (A).
const SECONDARY: Array[StringName] = [&"slider", &"changeup", &"curve", &"splitter", &"cutter", &"sweeper", &"two_seam"]
const SECONDARY_WEIGHTS: Array[float] = [0.85, 0.55, 0.45, 0.35, 0.25, 0.12, 0.2]

var names: NameTable
var catalog: Dictionary[StringName, PitchType]
var rng: Rng
var _player_serial := 0


func _init(name_table: NameTable, pitch_catalog: Dictionary[StringName, PitchType], seed_value: int) -> void:
	names = name_table
	catalog = pitch_catalog
	rng = Rng.new(seed_value)


## Three divisions of ten clubs.
func league(divisions: int = 3, per_division: int = 10) -> Array[Team]:
	var teams: Array[Team] = []
	var city_order := _shuffled(names.city_names.size())
	var nick_order := _shuffled(names.nicknames.size())
	for d: int in divisions:
		for i: int in per_division:
			var index := d * per_division + i
			teams.append(team(index, DIVISION_MEANS[mini(d, DIVISION_MEANS.size() - 1)], city_order[index % city_order.size()], nick_order[index % nick_order.size()]))
	return teams


## One club with talent around `mean`.
func team(index: int, mean: float, city: int = -1, nickname: int = -1) -> Team:
	var t := Team.new()
	var c := city if city >= 0 else index % names.city_names.size()
	var n := nickname if nickname >= 0 else index % names.nicknames.size()
	t.id = "t%02d" % (index + 1)
	t.name = "%s %s" % [names.city_names[c], names.nicknames[n]]
	t.short_name = names.city_names[c]
	t.stadium = "park_%02d" % (index + 1)
	var palette := names.colors[(index * 7) % names.colors.size()]
	t.primary = palette[0]
	t.secondary = palette[1]
	t.accent = palette[2]
	# Managers differ a lot in how often they run: real clubs range from 31 to 214 attempts.
	t.steal_style = clampf(exp(rng.next_normal() * 0.5), 0.25, 2.2)
	t.bunt_style = clampf(exp(rng.next_normal() * 0.3), 0.5, 1.8)
	var numbers: Dictionary[int, bool] = {}
	for entry: String in ROSTER:
		var regular := entry.begins_with("+")
		var role := entry.trim_prefix("+")
		var p := player(role, mean + rng.next_normal() * 3.0 - (0.0 if regular else BACKUP_GAP))
		p.number = _number(p, numbers)
		t.players.append(p)
	return t


func player(role: String, team_mean: float) -> Player:
	_player_serial += 1
	var p := Player.new()
	p.id = "p%05d" % _player_serial
	p.name = names.person(rng)
	var talent := team_mean + rng.next_normal() * TEAM_SPREAD
	var age := clampi(roundi(27.5 + rng.next_normal() * 4.0), 19, 38)
	p.born = 2026 - age
	# Players peak at 27 to 30.
	var age_factor := -0.6 * maxf(24.0 - age, 0.0) - 0.8 * maxf(age - 31.0, 0.0)
	talent += age_factor
	var parts := role.split("/")
	var main := parts[0]
	if main == "SP" or main == "RP":
		_pitcher(p, main, talent + PITCHER_OFFSET)
	else:
		_hitter(p, parts, talent + HITTER_OFFSET)
	return p


func _ability(talent: float, shift: float = 0.0) -> float:
	return clampf(talent + shift + rng.next_normal() * ABILITY_SPREAD, 20.0, 99.0)


func _hitter(p: Player, parts: PackedStringArray, talent: float) -> void:
	var main := parts[0]
	var shifts := {"C": [0.0, 0.0, -10.0, 6.0], "1B": [6.0, 0.0, -6.0, -4.0], "DH": [7.0, 2.0, -8.0, -8.0], "SS": [-3.0, 0.0, 4.0, 8.0], "CF": [-2.0, 0.0, 6.0, 8.0], "2B": [-3.0, 2.0, 3.0, 4.0], "3B": [3.0, 0.0, -2.0, 2.0]}
	var s: Array = shifts.get(main, [0.0, 0.0, 0.0, 0.0])
	var power_shift: float = s[0]
	var contact_shift: float = s[1]
	var speed_shift: float = s[2]
	var field_shift: float = s[3]
	var contact := _ability(talent, contact_shift)
	var power := _ability(talent, power_shift)
	# The usual edge against opposite-handed pitchers is applied by the league environment;
	# here each hitter only gets his own small difference between the two.
	p.batting.contact_r = clampf(contact + rng.next_normal() * 3.0, 20.0, 99.0)
	p.batting.contact_l = clampf(contact + rng.next_normal() * 3.0, 20.0, 99.0)
	p.batting.power_r = clampf(power + rng.next_normal() * 3.0, 20.0, 99.0)
	p.batting.power_l = clampf(power + rng.next_normal() * 3.0, 20.0, 99.0)
	p.batting.eye = _ability(talent)
	p.batting.speed = _ability(talent - 2.0, speed_shift)
	p.batting.baserunning = clampf(p.batting.speed * 0.6 + _ability(talent) * 0.4, 20.0, 99.0)
	p.batting.bunt = _ability(talent - 4.0, speed_shift * 0.5)
	p.batting.clutch = _ability(50.0)
	p.fielding.range = _ability(talent, field_shift + (6.0 if main == "SS" or main == "CF" else 0.0))
	p.fielding.hands = _ability(talent, field_shift)
	p.fielding.arm = _ability(talent, 6.0 if main == "C" or main == "3B" or main == "RF" else 0.0)
	p.fielding.accuracy = _ability(talent)
	for i: int in parts.size():
		var code := parts[i]
		if code == "DH":
			continue
		p.positions[code] = 100.0 if i == 0 else roundf(clampf(70.0 + rng.next_normal() * 10.0, 40.0, 95.0))
	_body(p, main)
	_hands(p, main)


func _pitcher(p: Player, role: String, talent: float) -> void:
	var r := PitchingRatings.new()
	p.pitching = r
	p.positions[role] = 100.0
	r.control = _ability(talent)
	r.composure = _ability(talent)
	r.hold = _ability(50.0)
	r.fielding = _ability(45.0)
	r.stamina = _ability(talent, 12.0 if role == "SP" else -12.0)
	# Fastball: league average 144 km/h, a standard deviation of 3.5 (A); better pitchers throw
	# a little harder, relievers a little harder still.
	var fastball := ArsenalPitch.new()
	fastball.type = &"four_seam" if rng.chance(0.85) else &"two_seam"
	fastball.velo_avg = clampf(144.0 + rng.next_normal() * 3.5 + (talent - 50.0) * 0.08 + (1.0 if role == "RP" else 0.0), 130.0, 158.0)
	fastball.velo_max = fastball.velo_avg + 4.0 + absf(rng.next_normal()) * 1.5
	fastball.movement = _ability(talent)
	fastball.command = _ability(talent)
	r.arsenal.append(fastball)
	var count := 2 + (1 if role == "SP" else 0) + (1 if rng.chance(0.45) else 0) + (1 if role == "SP" and rng.chance(0.3) else 0)
	var weights := PackedFloat64Array(SECONDARY_WEIGHTS)
	for i: int in count - 1:
		var pick := rng.pick_weighted(weights)
		weights[pick] = 0.0
		var type := SECONDARY[pick]
		if type == fastball.type:
			continue
		var pitch := ArsenalPitch.new()
		pitch.type = type
		var reference: float = catalog[type].speed_kmh if catalog.has(type) else 132.0
		pitch.velo_avg = clampf(reference + (fastball.velo_avg - 145.0) * 0.8 + rng.next_normal() * 2.0, 100.0, 152.0)
		pitch.velo_max = pitch.velo_avg + 3.0 + absf(rng.next_normal())
		pitch.movement = _ability(talent)
		pitch.command = _ability(talent - 3.0)
		r.arsenal.append(pitch)
	# Usage: the fastball about half, the rest falling off.
	var total := 0.0
	for i: int in r.arsenal.size():
		r.arsenal[i].usage = (0.48 + rng.next_normal() * 0.06) if i == 0 else 0.52 / pow(1.6, i - 1)
		total += r.arsenal[i].usage
	for pitch: ArsenalPitch in r.arsenal:
		pitch.usage /= total
	p.batting.contact_r = 20.0
	p.batting.contact_l = 20.0
	p.batting.power_r = 20.0
	p.batting.power_l = 20.0
	p.batting.eye = 20.0
	p.batting.speed = _ability(35.0)
	p.fielding.range = r.fielding
	p.fielding.hands = r.fielding
	p.fielding.arm = clampf(50.0 + (fastball.velo_avg - 144.0) * 3.0, 20.0, 99.0)
	p.fielding.accuracy = r.control
	_body(p, "P")
	p.throws = &"L" if rng.chance(0.28) else &"R"
	p.bats = p.throws if rng.chance(0.85) else (&"R" if p.throws == &"L" else &"L")


## Height and weight by position (A: docs/13 S4-11).
func _body(p: Player, main: String) -> void:
	var mean := {"P": 186.0, "C": 180.0, "1B": 183.0, "DH": 183.0, "LF": 182.0, "CF": 181.0, "RF": 182.0}.get(main, 180.0) as float
	p.height_cm = roundf(clampf(mean + rng.next_normal() * 5.0, 168.0, 200.0))
	var heavy := 5.0 if main == "C" or main == "1B" or main == "DH" else 0.0
	p.weight_kg = roundf(clampf((p.height_cm - 100.0) * 0.95 + 8.0 + heavy + rng.next_normal() * 6.0, 65.0, 125.0))


## Batting and throwing hands. Catchers and middle and third basemen throw right-handed.
func _hands(p: Player, main: String) -> void:
	var roll := rng.next_float()
	p.bats = &"R" if roll < 0.60 else (&"L" if roll < 0.95 else &"S")
	var right_only := main == "C" or main == "2B" or main == "3B" or main == "SS"
	p.throws = &"R" if right_only or p.bats != &"L" or rng.chance(0.5) else &"L"
	if p.throws == &"L":
		for code: String in p.positions.keys():
			if Position.needs_right_hand(Position.from_code(code)):
				p.positions.erase(code)
		if p.positions.is_empty():
			p.positions["1B"] = 100.0


func _number(p: Player, taken: Dictionary[int, bool]) -> int:
	for attempt: int in 100:
		var n := rng.next_int_range(11, 69) if p.is_pitcher() else rng.next_int_range(1, 66)
		if not taken.has(n):
			taken[n] = true
			return n
	for n: int in range(1, 100):
		if not taken.has(n):
			taken[n] = true
			return n
	return 99


func _shuffled(count: int) -> PackedInt32Array:
	var order := PackedInt32Array()
	for i: int in count:
		order.append(i)
	for i: int in range(count - 1, 0, -1):
		var j := rng.next_int(i + 1)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp
	return order
