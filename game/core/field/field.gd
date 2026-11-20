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
