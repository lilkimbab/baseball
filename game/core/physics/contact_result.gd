class_name ContactResult
extends RefCounted
## Outcome of a swing meeting (or missing) the ball.

var made_contact := false
var velocity := Vector3.ZERO
var spin := Vector3.ZERO


func exit_speed_kmh() -> float:
	return velocity.length() * 3.6


## Launch angle in degrees above horizontal.
func launch_deg() -> float:
	return rad_to_deg(atan2(velocity.z, Vector2(velocity.x, velocity.y).length()))


## Horizontal direction in degrees: 0 = dead centre, + = toward the first-base side.
func spray_deg() -> float:
	return rad_to_deg(atan2(velocity.x, velocity.y))


## Spin rate in rpm.
func spin_rpm() -> float:
	return spin.length() * 60.0 / TAU
