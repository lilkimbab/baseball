class_name PuppetPose
extends RefCounted
## A body pose given by where things are rather than by joint angles: pelvis position and
## heading, how the spine leans, and targets for hands and feet. Coordinates are in the
## puppet's own space: +X right, +Y up, -Z forward (the way it faces).

var hips := Vector3(0.0, 0.93, 0.0)
## Heading of the pelvis in radians about +Y; positive turns to the puppet's left.
var hips_yaw := 0.0
## Extra rotation of the shoulders relative to the pelvis.
var twist := 0.0
## Forward lean of the spine in radians.
var lean := 0.0
var r_hand := Vector3(0.25, 0.9, -0.1)
var l_hand := Vector3(-0.25, 0.9, -0.1)
var r_foot := Vector3(0.12, 0.08, 0.0)
var l_foot := Vector3(-0.12, 0.08, 0.0)
## Direction of the bat from the hands. Zero length = no bat in this pose.
var bat_dir := Vector3.ZERO


## Builds a position from (right, up, forward) which reads more naturally than -Z forward.
static func at(right: float, up: float, forward: float) -> Vector3:
	return Vector3(right, up, -forward)


func blend(to: PuppetPose, t: float) -> PuppetPose:
	var out := PuppetPose.new()
	out.hips = hips.lerp(to.hips, t)
	out.hips_yaw = lerpf(hips_yaw, to.hips_yaw, t)
	out.twist = lerpf(twist, to.twist, t)
	out.lean = lerpf(lean, to.lean, t)
	out.r_hand = r_hand.lerp(to.r_hand, t)
	out.l_hand = l_hand.lerp(to.l_hand, t)
	out.r_foot = r_foot.lerp(to.r_foot, t)
	out.l_foot = l_foot.lerp(to.l_foot, t)
	out.bat_dir = bat_dir.lerp(to.bat_dir, t)
	return out
