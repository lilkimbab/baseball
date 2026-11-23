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

## Half-width of the timing window in seconds at average contact (docs/04: easy 0.090,
## normal 0.065, hard 0.045, real 0.030).
var timing_window := 0.065
## How much of an aiming error on screen becomes a bat-ball offset (docs/04: 0.035-0.10).
var aim_scale := 0.05
## A person's small errors are forgiven and large ones count in full (SwingModel.error_scale);
## off, the whole error is scaled by aim_scale (the computer batter, whose error is its read).
var aim_forgiving := true
## With aim_forgiving off: the share of the error across the plate that moves the contact
## point along the bat (the computer batter's misread puts balls off the end or the handle).
var aim_across := 1.0
## Random spread of the bat's angle at contact (degrees, one sd): the computer batter's
## natural variation; a person's, by his difficulty (Difficulty).
var yaw_spread := 0.0
## A person's aiming error smaller than this (m) is mostly forgiven (SwingModel.error_scale).
var aim_forgiven := 0.06
## The timing window and the spread of the barrel on the ball, as shares of the usual, and the
## miss of a pitch let go by hand, as a share of PitchDuel.player_scatter: the person's
## difficulty (Difficulty).
var timing_scale := 1.0
var barrel_scale := 1.0
var hand_scatter := 1.0
## The pitcher's feel for the seam-shifted wake: how much of a pitch type's push his sinker,
## changeup or splitter gets (PitchType.ssw_accel), from his movement rating.
var ssw_scale := 1.0
## Pitcher's release point for a right-hander; mirrored for a left-hander.
var release_point := Vector3(-0.55, 16.76, 1.80)
## Rules the pitch is called under (the strike zone's size).
var rules := RuleSet.kbo_2026()
## The batter's body for a hit by pitch: a standing cylinder this far from the middle of the
## plate (to the third-base side for a right-handed batter), from the ankles to the shoulders.
var body_offset := 0.72
var body_radius := 0.22
var body_ankle := 0.12
var body_shoulder_share := 0.80
## Chance the batter gets out of the way of a pitch that would hit him (the computer batter;
## a person dodges with the controls).
var dodge := 0.0


func release() -> Vector3:
	return Vector3(-release_point.x, release_point.y, release_point.z) if throws_left else release_point
