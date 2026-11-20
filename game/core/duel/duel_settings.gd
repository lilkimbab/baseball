class_name DuelSettings
extends RefCounted
## Who is pitching to whom, and how forgiving the game is. Ratings are 1-99 with 50 average.

var batter_height := 1.82
var bats_left := false
var throws_left := false

var contact := 55.0
var power := 55.0
var eye := 55.0
var command := 55.0

## Half-width of the timing window in seconds at average contact (docs/05: easy 0.090,
## normal 0.065, hard 0.045, real 0.030).
var timing_window := 0.065
## How much of an aiming error on screen becomes a bat-ball offset (docs/05: 0.035-0.10).
var aim_scale := 0.05
## Pitcher's release point for a right-hander; mirrored for a left-hander.
var release_point := Vector3(-0.55, 16.76, 1.80)


func release() -> Vector3:
	return Vector3(-release_point.x, release_point.y, release_point.z) if throws_left else release_point
