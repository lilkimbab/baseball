class_name StrikeZone
extends RefCounted
## Automatic strike zone scaled to the batter's height, as the KBO's ABS calls it (2026 rules,
## docs/12 section 5): the top is 55.75% of the batter's height and the bottom 27.04%, the
## width is the plate plus 2 cm on each side, width is judged at the middle of the plate, and
## height at both the middle and the back of the plate.

const TOP_RATIO := 0.5575
const BOTTOM_RATIO := 0.2704
const SIDE_MARGIN := 0.02
const MID_PLANE_Y := Field.PLATE_FRONT_Y * 0.5

var top := 1.0
var bottom := 0.5
var half_width := (Field.PLATE_WIDTH + 2.0 * SIDE_MARGIN) * 0.5


## The zone for a batter of this height, under these rules (KBO 2026 when none are given).
static func for_batter(height_m: float, rules: RuleSet = null) -> StrikeZone:
	var zone := StrikeZone.new()
	zone.top = height_m * (rules.zone_top_ratio if rules != null else TOP_RATIO)
	zone.bottom = height_m * (rules.zone_bottom_ratio if rules != null else BOTTOM_RATIO)
	if rules != null:
		zone.half_width = Field.PLATE_WIDTH * 0.5 + rules.zone_side_margin
	return zone


func center() -> Vector3:
	return Vector3(0.0, Field.PLATE_FRONT_Y, (top + bottom) * 0.5)


func height() -> float:
	return top - bottom


## True if a ball centre at (x, z) is inside the zone. margin widens the zone on every side.
func contains(x: float, z: float, margin: float = 0.0) -> bool:
	return absf(x) <= half_width + margin and z >= bottom - margin and z <= top + margin


## How far outside the zone a ball centre at (x, z) is, in metres; zero inside it.
func distance_outside(x: float, z: float) -> float:
	var across := maxf(absf(x) - half_width, 0.0)
	var up := maxf(maxf(z - top, bottom - z), 0.0)
	return Vector2(across, up).length()


## A pitch is a strike if it is within the zone's width at the middle of the plate, and within
## its height both there and at the back of the plate (the apex, where y = 0).
func is_strike(pitch: PitchFlight) -> bool:
	var mid := crossing(pitch, MID_PLANE_Y)
	var back := crossing(pitch, 0.0)
	return absf(mid.x) <= half_width and mid.z >= bottom and mid.z <= top and back.z >= bottom and back.z <= top


## Where the pitch is as it crosses the plane at distance y from the apex of the plate, carried
## on in a straight line from the front of the plate.
static func crossing(pitch: PitchFlight, y: float) -> Vector3:
	if absf(pitch.plate_vel.y) < 1e-6:
		return pitch.plate_pos
	return pitch.plate_pos + pitch.plate_vel * ((y - Field.PLATE_FRONT_Y) / pitch.plate_vel.y)


## Point in the zone for a 0..1 position: u across (0 = third-base edge), v up (0 = bottom).
func point(u: float, v: float) -> Vector3:
	return Vector3(lerpf(-half_width, half_width, u), Field.PLATE_FRONT_Y, lerpf(bottom, top, v))
