class_name LeagueGenerator
extends RefCounted
## Makes up a fictional league: clubs and 28-man rosters with ratings, bodies, handedness and
## pitch mixes in realistic proportions. Same seed, same league.

## Average talent per division, top division first.
const DIVISION_MEANS: Array[float] = [56.0, 50.0, 44.0]
## A player's overall talent varies by this much (sd, rating points) and each ability by this
## much more on its own. Most of the spread is in the separate abilities: real hitters are
## rarely elite at everything, so the abilities are only loosely tied together (about 25%).
const TEAM_SPREAD := 6.5
const ABILITY_SPREAD := 11.5
## Hitting style, also per player: power hitters strike out more and run less (sd of the shift).
const STYLE_SPREAD := 5.0
## Nobody below this makes a professional roster as a hitter: contact and batting eye are
## never lower (a regular with less would hit well under .200).
const HITTING_FLOOR := 32.0
## Roster shape: starters, relievers, catchers, infielders by main position, outfielders.
## Players marked "+" are regulars; the rest are back-ups. A rating of 50 means the average of
## the players who actually play, so back-ups are made weaker than regulars.
const ROSTER: Array[String] = [
	"+SP", "+SP", "+SP", "+SP", "+SP",
	"+RP", "+RP", "+RP", "+RP", "RP", "RP", "RP", "RP",
	"+C", "C",
	"+1B", "+2B", "+3B", "+SS", "2B/SS", "3B/1B", "SS/3B",
	"+LF", "+CF", "+RF", "CF/LF", "RF/1B", "+1B/DH", "RP",
]
## The second team (2군): prospects and fringe players, further below the regulars (A).
const FARM: Array[String] = ["SP", "SP", "RP", "RP", "RP", "RP", "C", "2B/SS", "3B/1B", "CF/RF", "LF/1B"]
const FARM_GAP := 13.0
## Foreign players (A). KBO clubs carry three, usually two starters and a hitter,
## plus one Asia-quota player; most of the league's home run leaders are the foreign hitters.
## Starters get more talent, the hitter more power, the Asia-quota reliever a little more.
const FOREIGN_STARTER := 7.0
const FOREIGN_POWER := 10.0
const ASIA_TALENT := 4.0
## Where the foreign hitter plays.
const FOREIGN_HITTER_SPOTS: Array[String] = ["+1B", "+3B", "+LF", "+RF", "+1B/DH"]
## The local players are drawn this much lower so that a club still averages 50 over the
## plate appearances and batters faced (power over nine regulars, talent over a staff whose
## starters pitch about 60% of the innings). Measured with ./dev sim, see.
const LOCAL_POWER_SHIFT := -1.1
## Power above the knee counts for this share (A: measured with ./dev sim season).
const POWER_KNEE := 76.0
const POWER_ABOVE_KNEE := 0.5
const LOCAL_PITCHER_SHIFT := -1.7
## How much weaker a back-up is than a regular (rating points, A).
const BACKUP_GAP := 8.0
## Talent offsets so that a club made around 50 averages 50 where it counts: over the plate
## appearances its hitters take and the batters its pitchers face. Managers play their best
## hitters, so hitters are drawn a little lower; pitching is spread over the whole staff,
## so pitchers a little higher. Measured with tools (see ).
const HITTER_OFFSET := -4.0
const PITCHER_OFFSET := 2.5
## Breaking and off-speed pitches by how often pitchers have them (A).
## A pitcher's other pitches and how likely each is, as the KBO's (Statiz through 시사IN: the
## fastball about half of all pitches, the slider about a quarter — more for left-handers — two-
## seamers 6-9%, the splitter the least of the main ones; the sweeper up from 0.7% in 2025 to
## 4.3% in 2026; the forkball still common among Korean pitchers; knuckle curves, slurves and
## screwballs rare, a knuckleballer once in a long while).
const SECONDARY: Array[StringName] = [&"slider", &"changeup", &"curve", &"forkball", &"splitter", &"cutter", &"two_seam", &"sinker", &"sweeper",
	&"circle_change", &"knuckle_curve", &"slurve", &"screwball", &"knuckleball"]
const SECONDARY_WEIGHTS: Array[float] = [0.85, 0.5, 0.42, 0.3, 0.15, 0.22, 0.18, 0.1, 0.12, 0.06, 0.05, 0.04, 0.01, 0.003]

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
	t.steal_style = clampf(exp(rng.next_normal() * 0.45), 0.35, 1.9)
	t.bunt_style = clampf(exp(rng.next_normal() * 0.3), 0.5, 1.8)
	var numbers: Dictionary[int, bool] = {}
	# Which first-team places go to foreign players: the first two regular starters, one of
	# the regular corner bats, one regular reliever (the Asia quota).
	var foreign_hitter: String = FOREIGN_HITTER_SPOTS[rng.next_int(FOREIGN_HITTER_SPOTS.size())]
	var asia_reliever := rng.next_int(4)
	var starters := 0
	var relievers := 0
	for entry: String in ROSTER:
		var regular := entry.begins_with("+")
		var role := entry.trim_prefix("+")
		var origin: StringName = &""
		if entry == "+SP":
			starters += 1
			if starters <= 2:
				origin = &"foreign"
		elif entry == "+RP":
			if relievers == asia_reliever:
				origin = &"asia"
			relievers += 1
		elif entry == foreign_hitter:
			origin = &"foreign"
		var p := player(role, mean + rng.next_normal() * 3.0 - (0.0 if regular else BACKUP_GAP), origin)
		p.number = _number(p, numbers)
		t.players.append(p)
		t.registered.append(p.id)
	for entry: String in FARM:
		var p := player(entry, mean + rng.next_normal() * 3.0 - FARM_GAP, &"", true)
		p.number = _number(p, numbers)
		t.players.append(p)
	return t


## One player. `origin` makes him one of the club's foreign players (&"foreign", &"asia");
## `prospect` a young second-team player.
func player(role: String, team_mean: float, origin: StringName = &"", prospect: bool = false) -> Player:
	_player_serial += 1
	var p := Player.new()
	p.id = "p%05d" % _player_serial
	p.origin = origin
	p.name = names.person(rng) if origin == &"" else names.foreigner(rng, origin == &"asia")
	var talent := team_mean + rng.next_normal() * TEAM_SPREAD
	var age := clampi(roundi(27.5 + rng.next_normal() * 4.0), 19, 38)
	if origin != &"":
		age = clampi(roundi(29.5 + rng.next_normal() * 2.5), 24, 36)
	elif prospect:
		age = clampi(roundi(22.5 + rng.next_normal() * 2.5), 19, 33)
	p.born = 2026 - age
	# Players peak at 27 to 30.
	var age_factor := -0.6 * maxf(24.0 - age, 0.0) - 0.8 * maxf(age - 31.0, 0.0)
	talent += age_factor
	var parts := role.split("/")
	var main := parts[0]
	if main == "SP" or main == "RP":
		var bonus := LOCAL_PITCHER_SHIFT
		if origin == &"foreign":
			bonus = FOREIGN_STARTER
		elif origin == &"asia":
			bonus = ASIA_TALENT
		_pitcher(p, main, talent + PITCHER_OFFSET + bonus)
	else:
		_hitter(p, parts, talent + HITTER_OFFSET, FOREIGN_POWER if origin == &"foreign" else LOCAL_POWER_SHIFT)
	return p


func _ability(talent: float, shift: float = 0.0) -> float:
	return clampf(talent + shift + rng.next_normal() * ABILITY_SPREAD, 20.0, 99.0)


func _hitter(p: Player, parts: PackedStringArray, talent: float, power_bonus: float = 0.0) -> void:
	var main := parts[0]
	var shifts := {"C": [0.0, 0.0, -10.0, 6.0], "1B": [6.0, 0.0, -6.0, -4.0], "DH": [7.0, 2.0, -8.0, -8.0], "SS": [-3.0, 0.0, 4.0, 8.0], "CF": [-2.0, 0.0, 6.0, 8.0], "2B": [-3.0, 2.0, 3.0, 4.0], "3B": [3.0, 0.0, -2.0, 2.0]}
	var s: Array = shifts.get(main, [0.0, 0.0, 0.0, 0.0])
	var power_shift: float = s[0]
	var contact_shift: float = s[1]
	var speed_shift: float = s[2]
	var field_shift: float = s[3]
	var style := rng.next_normal() * STYLE_SPREAD
	var contact := _ability(talent, contact_shift - style * 0.8)
	var power := _ability(talent, power_shift + style + power_bonus)
	# Big power is rarer than the other gifts: a KBO season has only a handful of 30-homer
	# hitters, so the top of the scale is pressed together.
	if power > POWER_KNEE:
		power = POWER_KNEE + (power - POWER_KNEE) * POWER_ABOVE_KNEE
	# The usual edge against opposite-handed pitchers is applied by the league environment;
	# here each hitter only gets his own small difference between the two.
	p.batting.contact_r = clampf(contact + rng.next_normal() * 3.0, HITTING_FLOOR, 99.0)
	p.batting.contact_l = clampf(contact + rng.next_normal() * 3.0, HITTING_FLOOR, 99.0)
	p.batting.power_r = clampf(power + rng.next_normal() * 3.0, 20.0, 99.0)
	p.batting.power_l = clampf(power + rng.next_normal() * 3.0, 20.0, 99.0)
	p.batting.eye = maxf(_ability(talent), HITTING_FLOOR)
	p.batting.speed = _ability(talent - 2.0, speed_shift - style * 0.6)
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
	# How hard he is to hit is one trait of the pitcher, shared by all his pitches: averaging
	# separately drawn pitches would make every pitcher look alike.
	var stuff := talent + rng.next_normal() * 11.5
	# Fastball: league average 144 km/h, a standard deviation of 3.5 (A); better pitchers throw
	# a little harder, relievers a little harder still.
	var fastball := ArsenalPitch.new()
	fastball.type = &"four_seam" if rng.chance(0.85) else &"two_seam"
	fastball.velo_avg = clampf(144.0 + rng.next_normal() * 3.0 + (stuff - 50.0) * 0.12 + (1.0 if role == "RP" else 0.0), 130.0, 158.0)
	fastball.velo_max = fastball.velo_avg + 4.0 + absf(rng.next_normal()) * 1.5
	fastball.movement = clampf(stuff + rng.next_normal() * 6.0, 20.0, 99.0)
	fastball.command = _ability(talent)
	r.arsenal.append(fastball)
	# How many pitches (the fastball among them): a reliever two or three, now and then four; a
	# starter three to five, six very rarely (the user: not everyone six; some only three).
	var count := 2 + (1 if role == "SP" else 0) + (1 if rng.chance(0.45) else 0) + (1 if role == "SP" and rng.chance(0.3) else 0) \
		+ (1 if role == "SP" and rng.chance(0.04) else 0)
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
		pitch.movement = clampf(stuff + rng.next_normal() * 6.0, 20.0, 99.0)
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


## Height and weight by position (A: ).
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
