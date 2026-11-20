class_name StrikeZone
extends RefCounted
## Automatic strike zone scaled to the batter's height (docs/04, section 6).

const TOP_RATIO := 0.5575
const BOTTOM_RATIO := 0.2704
const SIDE_MARGIN := 0.02
const MID_PLANE_Y := Field.PLATE_FRONT_Y * 0.5

var top := 1.0
var bottom := 0.5
var half_width := (Field.PLATE_WIDTH + 2.0 * SIDE_MARGIN) * 0.5


static func for_batter(height_m: float) -> StrikeZone:
	var zone := StrikeZone.new()
	zone.top = height_m * TOP_RATIO
	zone.bottom = height_m * BOTTOM_RATIO
	return zone


func center() -> Vector3:
	return Vector3(0.0, Field.PLATE_FRONT_Y, (top + bottom) * 0.5)


func height() -> float:
	return top - bottom


## True if a ball centre at (x, z) is inside the zone. margin widens the zone on every side.
func contains(x: float, z: float, margin: float = 0.0) -> bool:
	return absf(x) <= half_width + margin and z >= bottom - margin and z <= top + margin


## A pitch is a strike if it is inside the zone at both the front and the middle of the plate.
func is_strike(pitch: PitchFlight) -> bool:
	var front := pitch.plate_pos
	if not contains(front.x, front.z):
		return false
	var mid := front
	if absf(pitch.plate_vel.y) > 1e-6:
		mid += pitch.plate_vel * ((MID_PLANE_Y - Field.PLATE_FRONT_Y) / pitch.plate_vel.y)
	return contains(mid.x, mid.z)


## Point in the zone for a 0..1 position: u across (0 = third-base edge), v up (0 = bottom).
func point(u: float, v: float) -> Vector3:
	return Vector3(lerpf(-half_width, half_width, u), Field.PLATE_FRONT_Y, lerpf(bottom, top, v))
