class_name PitchFlight
extends RefCounted
## A pitch from release to the front of home plate.

var release_pos := Vector3.ZERO
var release_vel := Vector3.ZERO
var spin := Vector3.ZERO
## The seam-shifted wake's push through the flight (m/s², PitchModel.ssw_vector).
var ssw := Vector3.ZERO
## Seconds from release to the front edge of the plate.
var flight_time := 0.0
## Ball centre where it crosses the front edge of the plate.
var plate_pos := Vector3.ZERO
var plate_vel := Vector3.ZERO
## How far spin moved the ball compared with the same throw without spin, measured at the
## plate: x = toward first base, y = up (metres). Only worked out when asked for.
var movement := Vector2.ZERO
## When and where the ball crosses the batter's contact plane (in front of the plate), if a
## plane was given.
var contact_time := 0.0
var contact_pos := Vector3.ZERO


func release_speed_kmh() -> float:
	return release_vel.length() * 3.6


func plate_speed_kmh() -> float:
	return plate_vel.length() * 3.6
