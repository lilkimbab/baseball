class_name Field
extends RefCounted
## Field coordinate system and regulation dimensions.
##
## Field coords (used everywhere inside core/): +x = first-base side (catcher's right),
## +y = from home plate toward centre field, +z = up. Origin = rear apex of home plate
## at ground level. SI units. Convert to engine world space only at the scene boundary.

const BASE_DISTANCE := 27.432
const BASE_DIAGONAL := 19.397
const RUBBER_Y := 18.44
const MOUND_CENTER_Y := 17.98
const MOUND_RADIUS := 2.743
const MOUND_HEIGHT := 0.254
## The level top of the mound: from 6 inches in front of the rubber to behind it, 5 feet wide.
const MOUND_TOP_FRONT := 0.152
const MOUND_TOP_BACK := 0.61
const MOUND_TOP_HALF_WIDTH := 0.76
const PLATE_WIDTH := 0.4318
## Home plate is a pentagon: 17 in across the front, square sides 8.5 in deep, then two 12 in
## edges meeting at the rear apex. Corners from the apex round by the third-base side.
const PLATE_OUTLINE: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(-0.2159, 0.2159), Vector2(-0.2159, 0.4318), Vector2(0.2159, 0.4318), Vector2(0.2159, 0.2159),
]
## Bases are 18 in square (KBO since 2024, MLB since 2023) and 3 to 5 in thick.
const BASE_SIZE := 0.4572
const BASE_THICKNESS := 0.09
## Chalk lines are 3 in wide.
const LINE_WIDTH := 0.0762
const PLATE_FRONT_Y := 0.4318
const INFIELD_ARC_RADIUS := 28.96

const FIRST_BASE := Vector3(BASE_DIAGONAL, BASE_DIAGONAL, 0.0)
const SECOND_BASE := Vector3(0.0, 2.0 * BASE_DIAGONAL, 0.0)
const THIRD_BASE := Vector3(-BASE_DIAGONAL, BASE_DIAGONAL, 0.0)
const HOME := Vector3.ZERO


static func to_world(f: Vector3) -> Vector3:
	return Vector3(f.x, f.z, -f.y)


static func to_field(w: Vector3) -> Vector3:
	return Vector3(w.x, -w.z, w.y)


## Azimuth of a field position seen from home: 0 = dead centre, + = right-field side. Radians.
static func azimuth(f: Vector3) -> float:
	return atan2(f.x, f.y)


static func is_fair(f: Vector3) -> bool:
	return f.y >= absf(f.x)


## Height of the ground at (x, y): zero everywhere except the mound, which is level on top
## and falls 1 in 12 toward the plate, meeting the field at the edge of its circle.
static func ground_height(x: float, y: float) -> float:
	var to_edge := MOUND_RADIUS - Vector2(x, y - MOUND_CENTER_Y).length()
	if to_edge <= 0.0:
		return 0.0
	var dx := maxf(absf(x) - MOUND_TOP_HALF_WIDTH, 0.0)
	var dy := maxf(maxf(RUBBER_Y - MOUND_TOP_FRONT - y, y - RUBBER_Y - MOUND_TOP_BACK), 0.0)
	return MOUND_HEIGHT * to_edge / (to_edge + Vector2(dx, dy).length())


## Centre of a base bag. First and third lie wholly inside the diamond with two edges on the
## lines; second is centred on its point.
static func base_centre(base: int) -> Vector3:
	var inset := BASE_SIZE * 0.5 * sqrt(2.0)
	match base:
		1:
			return FIRST_BASE + Vector3(-inset, 0.0, 0.0)
		2:
			return SECOND_BASE
		3:
			return THIRD_BASE + Vector3(inset, 0.0, 0.0)
	return Vector3.ZERO
