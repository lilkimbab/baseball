class_name PuppetClips
extends RefCounted
## Key poses for the greybox mannequin: pitching delivery, batting stance and swing, and
## idle poses. Stage S10 replaces these with motion-capture clips; the event times
## (release, contact) are what the game logic synchronises to.

## Seconds from the start of the delivery to the release of the ball.
const PITCH_RELEASE := 1.15
const PITCH_LENGTH := 2.1
## Hand position at release in puppet space; matches the physics release point of a
## right-hander standing on the rubber (docs/04, section 5.1).
const RELEASE_HAND := Vector3(0.55, 1.546, -1.68)
const BAT_LENGTH := 0.85


static func _pose(hips: Vector3, yaw_deg: float, twist_deg: float, lean_deg: float,
		r_hand: Vector3, l_hand: Vector3, r_foot: Vector3, l_foot: Vector3) -> PuppetPose:
	var p := PuppetPose.new()
	p.hips = hips
	p.hips_yaw = deg_to_rad(yaw_deg)
	p.twist = deg_to_rad(twist_deg)
	p.lean = deg_to_rad(lean_deg)
	p.r_hand = r_hand
	p.l_hand = l_hand
	p.r_foot = r_foot
	p.l_foot = l_foot
	return p


static func _sample(times: PackedFloat32Array, poses: Array[PuppetPose], t: float) -> PuppetPose:
	if t <= times[0]:
		return poses[0]
	var last := times.size() - 1
	if t >= times[last]:
		return poses[last]
	var i := 0
	while t > times[i + 1]:
		i += 1
	var f := (t - times[i]) / (times[i + 1] - times[i])
	return poses[i].blend(poses[i + 1], smoothstep(0.0, 1.0, f))


## Right-handed delivery, t in seconds from the start of the motion.
static func pitch(t: float) -> PuppetPose:
	var a := PuppetPose.at
	var times := PackedFloat32Array([0.0, 0.5, 0.88, PITCH_RELEASE, 1.5, PITCH_LENGTH])
	var poses: Array[PuppetPose] = [
		_pose(a.call(0.0, 0.93, 0.0), 0.0, 0.0, 2.0, a.call(0.04, 1.22, 0.22), a.call(-0.02, 1.2, 0.24), a.call(0.12, 0.08, 0.0), a.call(-0.12, 0.08, 0.0)),
		_pose(a.call(0.0, 0.95, -0.02), -80.0, 0.0, 0.0, a.call(0.1, 1.2, 0.12), a.call(0.06, 1.18, 0.16), a.call(0.12, 0.08, 0.0), a.call(0.05, 0.62, 0.22)),
		_pose(a.call(0.0, 0.82, 0.55), -55.0, -25.0, 6.0, a.call(0.42, 1.52, 0.2), a.call(-0.25, 1.15, 1.05), a.call(0.12, 0.1, 0.0), a.call(-0.1, 0.08, 1.35)),
		_pose(a.call(0.06, 0.87, 1.12), 8.0, 25.0, 40.0, RELEASE_HAND, a.call(-0.2, 1.05, 0.95), a.call(0.16, 0.14, 0.3), a.call(-0.1, 0.08, 1.35)),
		_pose(a.call(-0.02, 0.84, 1.08), 35.0, 20.0, 52.0, a.call(-0.25, 0.55, 1.5), a.call(-0.32, 1.0, 0.85), a.call(0.3, 0.3, 0.9), a.call(-0.1, 0.08, 1.35)),
		_pose(a.call(0.02, 0.86, 1.15), 0.0, 0.0, 22.0, a.call(0.22, 0.85, 1.45), a.call(-0.22, 0.85, 1.45), a.call(0.3, 0.08, 1.05), a.call(-0.26, 0.08, 1.25)),
	]
	return _sample(times, poses, t)


## Right-handed batter waiting for the pitch. The plate is in front of him, the pitcher to
## his left.
static func stance() -> PuppetPose:
	var a := PuppetPose.at
	var p := _pose(a.call(0.0, 0.9, 0.0), 0.0, -12.0, 8.0, a.call(0.24, 1.33, 0.1), a.call(0.2, 1.27, 0.12), a.call(0.3, 0.08, 0.0), a.call(-0.3, 0.08, 0.0))
	p.bat_dir = a.call(0.28, 1.0, -0.18).normalized()
	return p


## Swing, with t in seconds relative to contact (negative before). lead = how long before
## contact the swing starts; contact_height = height of the ball at contact.
static func swing(t: float, lead: float, contact_height: float) -> PuppetPose:
	var a := PuppetPose.at
	var hands_up := clampf(contact_height + 0.04, 0.45, 1.25)
	var contact := _pose(a.call(-0.06, 0.88, 0.02), 62.0, 18.0, 12.0, a.call(-0.1, hands_up, 0.42), a.call(-0.14, hands_up - 0.04, 0.4), a.call(0.28, 0.1, 0.02), a.call(-0.42, 0.08, 0.02))
	contact.bat_dir = a.call(-0.12, -0.04, 1.0).normalized()
	var finish := _pose(a.call(-0.08, 0.9, 0.02), 92.0, 30.0, 6.0, a.call(-0.32, 1.38, -0.05), a.call(-0.28, 1.32, -0.02), a.call(0.26, 0.12, 0.02), a.call(-0.42, 0.08, 0.02))
	finish.bat_dir = a.call(0.55, 0.3, -0.75).normalized()
	var times := PackedFloat32Array([-lead, 0.0, 0.2, 0.75, 1.1])
	var poses: Array[PuppetPose] = [stance(), contact, finish, finish, stance()]
	return _sample(times, poses, t)


static func catcher() -> PuppetPose:
	var a := PuppetPose.at
	return _pose(a.call(0.0, 0.46, 0.0), 0.0, 0.0, 24.0, a.call(0.22, 0.55, 0.1), a.call(-0.04, 0.72, 0.5), a.call(0.3, 0.08, 0.12), a.call(-0.3, 0.08, 0.12))


static func fielder_ready() -> PuppetPose:
	var a := PuppetPose.at
	return _pose(a.call(0.0, 0.84, 0.0), 0.0, 0.0, 22.0, a.call(0.24, 0.72, 0.3), a.call(-0.24, 0.72, 0.3), a.call(0.3, 0.08, 0.0), a.call(-0.3, 0.08, 0.0))


## Plate umpire: bent forward with hands on knees, looking over the catcher.
static func umpire() -> PuppetPose:
	var a := PuppetPose.at
	return _pose(a.call(0.0, 0.8, 0.0), 0.0, 0.0, 30.0, a.call(0.2, 0.56, 0.24), a.call(-0.2, 0.56, 0.24), a.call(0.26, 0.08, 0.0), a.call(-0.26, 0.08, 0.0))


## Running, for fielders and runners until stage S12 brings recorded motion: two strides
## blended back and forth. phase advances one stride per unit.
static func run(phase: float) -> PuppetPose:
	var a := PuppetPose.at
	var left := _pose(a.call(0.0, 0.92, 0.05), 0.0, 8.0, 16.0, a.call(0.22, 1.12, 0.3), a.call(-0.22, 0.88, -0.25), a.call(0.12, 0.3, -0.42), a.call(-0.12, 0.1, 0.42))
	var right := _pose(a.call(0.0, 0.92, 0.05), 0.0, -8.0, 16.0, a.call(0.22, 0.88, -0.25), a.call(-0.22, 1.12, 0.3), a.call(0.12, 0.1, 0.42), a.call(-0.12, 0.3, -0.42))
	return left.blend(right, 0.5 - 0.5 * cos(phase * PI))
