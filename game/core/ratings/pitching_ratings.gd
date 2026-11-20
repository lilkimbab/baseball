class_name PitchingRatings
extends RefCounted
## A pitcher's ratings, 1..99 with the league average at 50, and the pitches he throws.

## One standard deviation of pitch speed among pitchers of one type (km/h). A pitch this much
## faster than the type's reference speed counts 15 rating points better.
const SPEED_SD := 3.5

var stamina := 50.0
var control := 50.0
## Pitching with runners in scoring position.
var composure := 50.0
## Holding runners: pickoff move and time to the plate.
var hold := 50.0
var fielding := 50.0
var arsenal: Array[ArsenalPitch] = []


## Rating of one pitch's speed against the reference speed of its type.
static func speed_score(pitch: ArsenalPitch, catalog: Dictionary[StringName, PitchType]) -> float:
	var reference := 144.0
	if catalog.has(pitch.type):
		reference = catalog[pitch.type].speed_kmh
	return 50.0 + 15.0 * (pitch.velo_avg - reference) / SPEED_SD


## How hard he is to hit: usage-weighted speed and movement of his pitches.
func stuff(catalog: Dictionary[StringName, PitchType]) -> float:
	var total := 0.0
	var weight := 0.0
	for pitch: ArsenalPitch in arsenal:
		total += pitch.usage * (0.5 * speed_score(pitch, catalog) + 0.5 * pitch.movement)
		weight += pitch.usage
	return total / weight if weight > 0.0 else 50.0


## Average speed of his main fastball, or of his fastest pitch if he has no fastball.
func fastball_speed() -> float:
	var best := 0.0
	for pitch: ArsenalPitch in arsenal:
		if pitch.type == &"four_seam" or pitch.type == &"two_seam":
			return pitch.velo_avg
		best = maxf(best, pitch.velo_avg)
	return best


## Average movement of his breaking and off-speed pitches.
func breaking(catalog: Dictionary[StringName, PitchType]) -> float:
	var total := 0.0
	var count := 0
	for pitch: ArsenalPitch in arsenal:
		var family: StringName = catalog[pitch.type].family if catalog.has(pitch.type) else &"fastball"
		if family != &"fastball":
			total += pitch.movement
			count += 1
	return total / count if count > 0 else 40.0


## Pitches he can throw before he tires, as a starter: 75 to 115.
func starter_limit() -> float:
	return lerpf(75.0, 115.0, stamina / 99.0)


## Pitches he can throw in one outing out of the bullpen: 20 to 45.
func reliever_limit() -> float:
	return lerpf(20.0, 45.0, stamina / 99.0)
