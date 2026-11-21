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


## Catcher in his crouch. The mitt is held up as a target at `mitt_height` (m above the
## ground at the plate); the default is the middle of the zone.
static func catcher(mitt_height: float = 0.72) -> PuppetPose:
	var a := PuppetPose.at
	var mitt := clampf(mitt_height, 0.35, 1.25)
	return _pose(a.call(0.0, 0.46, 0.0), 0.0, 0.0, 24.0, a.call(0.22, 0.55, 0.1), a.call(-0.04, mitt, 0.5), a.call(0.3, 0.08, 0.12), a.call(-0.3, 0.08, 0.12))


## The catcher putting down the sign: right hand deep between his thighs, mitt on his left
## knee to screen it from the first-base coach.
static func catcher_sign() -> PuppetPose:
	var a := PuppetPose.at
	return _pose(a.call(0.0, 0.46, 0.0), 0.0, 0.0, 18.0, a.call(0.02, 0.4, 0.12), a.call(-0.28, 0.5, 0.3), a.call(0.3, 0.08, 0.12), a.call(-0.3, 0.08, 0.12))


## The catcher blocking a pitch in the dirt: down on both knees, square to the ball, the mitt
## between his knees and his chin tucked so the ball drops in front of him.
static func catcher_block() -> PuppetPose:
	var a := PuppetPose.at
	return _pose(a.call(0.0, 0.52, 0.05), 0.0, 0.0, 28.0, a.call(0.12, 0.3, 0.35), a.call(-0.02, 0.12, 0.42), a.call(0.28, 0.1, -0.42), a.call(-0.28, 0.1, -0.42))


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


# --- Fielding, throwing, running and umpiring (docs/13 S12, stage A key poses) ---


## How high (m) a foot comes up when it steps.
const STEP_LIFT := 0.06
## A ball this far (m) to one side of a fielder is dived for.
const DIVE_WIDTH := 1.1


## Fielder's ready position as the pitch is delivered: lower, weight forward on the balls of
## the feet, glove open in front.
static func fielder_crouch() -> PuppetPose:
	var a := PuppetPose.at
	return _pose(a.call(0.0, 0.74, 0.05), 0.0, 0.0, 30.0, a.call(0.26, 0.62, 0.38), a.call(-0.26, 0.6, 0.4), a.call(0.38, 0.08, 0.02), a.call(-0.38, 0.08, 0.02))


## A fielder stepping in as the pitch is delivered, k from 0 (ready, where he stood) to 1 (in
## his crouch, `distance` m nearer the plate). The body moves at an even pace; the right foot
## steps first, then the left, each planted while the other moves, so neither slides.
static func creep(k: float, distance: float) -> PuppetPose:
	var u := clampf(k, 0.0, 1.0)
	var ready := fielder_ready()
	var crouch := fielder_crouch()
	var pose := ready.blend(crouch, smoothstep(0.4, 1.0, u))
	var body := distance * u
	# Each foot widens to the crouch only while it is in the air.
	var right := smoothstep(0.0, 1.0, clampf(2.0 * u, 0.0, 1.0))
	var left := smoothstep(0.0, 1.0, clampf(2.0 * u - 1.0, 0.0, 1.0))
	pose.r_foot = ready.r_foot.lerp(crouch.r_foot, right) + Vector3(0.0, STEP_LIFT * sin(PI * right), body - distance * right)
	pose.l_foot = ready.l_foot.lerp(crouch.l_foot, left) + Vector3(0.0, STEP_LIFT * sin(PI * left), body - distance * left)
	return pose


## One shuffle step of a runner's secondary lead, u from 0 to 1, moving `length` m to his
## right (`side` 1) or left (-1): the trailing foot comes in, then the leading foot goes out.
## The body moves at an even pace and each foot stays put while the other moves.
static func shuffle(u: float, length: float, side: float = 1.0) -> PuppetPose:
	var v := clampf(u, 0.0, 1.0)
	var pose := lead_off()
	var body := length * v
	var trail := length * smoothstep(0.0, 1.0, clampf(2.0 * v, 0.0, 1.0)) - body
	var lead := length * smoothstep(0.0, 1.0, clampf(2.0 * v - 1.0, 0.0, 1.0)) - body
	var up := Vector3.UP * STEP_LIFT
	var trail_up := up * sin(PI * clampf(2.0 * v, 0.0, 1.0))
	var lead_up := up * sin(PI * clampf(2.0 * v - 1.0, 0.0, 1.0))
	if side >= 0.0:
		pose.l_foot += Vector3(trail, 0.0, 0.0) + trail_up
		pose.r_foot += Vector3(lead, 0.0, 0.0) + lead_up
	else:
		pose.r_foot += Vector3(-trail, 0.0, 0.0) + trail_up
		pose.l_foot += Vector3(-lead, 0.0, 0.0) + lead_up
	return pose


## Running at `speed` (0 a jog, 1 a sprint): longer strides, more lean and arm swing as it
## goes up. phase advances one stride per unit.
static func run_at(phase: float, speed: float) -> PuppetPose:
	var s := clampf(speed, 0.0, 1.0)
	var a := PuppetPose.at
	var reach := lerpf(0.3, 0.55, s)
	var lift := lerpf(0.18, 0.32, s)
	var arm := lerpf(0.12, 0.3, s)
	var lean := lerpf(8.0, 18.0, s)
	var left := _pose(a.call(0.0, 0.93, 0.05), 0.0, 8.0, lean, a.call(0.22, 0.98 + arm, arm + 0.1), a.call(-0.22, 0.98 - arm * 0.5, -arm), a.call(0.12, lift, -reach), a.call(-0.12, 0.1, reach))
	var right := _pose(a.call(0.0, 0.93, 0.05), 0.0, -8.0, lean, a.call(0.22, 0.98 - arm * 0.5, -arm), a.call(-0.22, 0.98 + arm, arm + 0.1), a.call(0.12, 0.1, reach), a.call(-0.12, lift, -reach))
	return left.blend(right, 0.5 - 0.5 * cos(phase * PI))


## Coming to a stop: the weight back, the feet wide.
static func braking() -> PuppetPose:
	var a := PuppetPose.at
	return _pose(a.call(0.0, 0.82, -0.08), 0.0, 0.0, 6.0, a.call(0.3, 0.9, 0.15), a.call(-0.3, 0.9, 0.15), a.call(0.3, 0.08, 0.3), a.call(-0.3, 0.08, -0.25))


## Fielding a ground ball: knees bent, glove down in front of the body, out to the glove side
## for a forehand (`side` < 0) or across to the throwing-hand side for a backhand (`side` > 0).
static func ground_catch(side: float = 0.0) -> PuppetPose:
	var a := PuppetPose.at
	var reach := clampf(side, -1.0, 1.0)
	var p := _pose(a.call(-0.12 * reach, 0.6, 0.05), -20.0 * reach, 0.0, 48.0, a.call(0.18, 0.3, 0.45), a.call(-0.06 - 0.45 * maxf(-reach, 0.0) + 0.3 * maxf(reach, 0.0), 0.12, 0.55), a.call(0.42, 0.08, 0.05), a.call(-0.42, 0.08, 0.15))
	return p


## The catch for a ball at `local` (in the fielder's own space, as PuppetPose.at gives it)
## and `height` above the ground: a dive for one well wide of him and low enough, a ground
## ball, chest-high, or overhead.
static func catch_for(local: Vector3, height: float) -> PuppetPose:
	if absf(local.x) > DIVE_WIDTH and height < 1.3:
		return dive(signf(local.x))
	if height < 0.5:
		return ground_catch(clampf(local.x / 0.6, -1.0, 1.0))
	if height < 1.7:
		return chest_catch()
	return overhead_catch()


## Catching at chest height, both hands up in front.
static func chest_catch() -> PuppetPose:
	var a := PuppetPose.at
	return _pose(a.call(0.0, 0.92, 0.0), 0.0, 0.0, 8.0, a.call(0.12, 1.3, 0.38), a.call(-0.08, 1.38, 0.42), a.call(0.25, 0.08, 0.0), a.call(-0.25, 0.08, 0.12))


## A fly ball over the head: glove up high, the throwing hand ready beside it.
static func overhead_catch() -> PuppetPose:
	var a := PuppetPose.at
	return _pose(a.call(0.0, 0.95, 0.0), 0.0, 0.0, -6.0, a.call(0.16, 1.95, 0.2), a.call(-0.1, 2.15, 0.22), a.call(0.22, 0.08, 0.0), a.call(-0.22, 0.08, 0.1))


## A dive: laid out toward the glove side, glove reaching for the ball.
static func dive(side: float = -1.0) -> PuppetPose:
	var a := PuppetPose.at
	var s := signf(side) if side != 0.0 else -1.0
	return _pose(a.call(0.4 * s, 0.35, 0.3), 70.0 * s, 0.0, 62.0, a.call(0.2 * s, 0.4, 0.7), a.call(1.1 * s, 0.32, 0.75), a.call(-0.2 * s, 0.25, -0.6), a.call(-0.05 * s, 0.15, -0.75))


## A throw, t in seconds from the release (negative before): the glove arm points at the
## target as the ball goes back, the body turns through, and follows through.
static func throw_at(t: float) -> PuppetPose:
	var a := PuppetPose.at
	var times := PackedFloat32Array([-0.35, -0.12, 0.0, 0.18, 0.45])
	var poses: Array[PuppetPose] = [
		_pose(a.call(0.0, 0.9, 0.0), -60.0, -20.0, 6.0, a.call(0.1, 1.2, 0.15), a.call(-0.05, 1.2, 0.25), a.call(0.25, 0.08, -0.05), a.call(-0.25, 0.08, 0.25)),
		_pose(a.call(0.0, 0.88, -0.05), -75.0, -35.0, 4.0, a.call(0.45, 1.55, -0.35), a.call(-0.5, 1.3, 0.35), a.call(0.2, 0.08, -0.15), a.call(-0.3, 0.12, 0.55)),
		_pose(a.call(0.02, 0.86, 0.25), 10.0, 25.0, 30.0, a.call(0.4, 1.6, 0.55), a.call(-0.35, 1.05, 0.2), a.call(0.18, 0.14, -0.2), a.call(-0.2, 0.08, 0.6)),
		_pose(a.call(0.0, 0.82, 0.35), 30.0, 30.0, 45.0, a.call(-0.2, 0.75, 0.8), a.call(-0.35, 0.95, 0.15), a.call(0.25, 0.35, 0.2), a.call(-0.2, 0.08, 0.6)),
		fielder_ready(),
	]
	return _sample(times, poses, t)


## A feet-first slide into a base, the body back and the lead leg out.
static func slide() -> PuppetPose:
	var a := PuppetPose.at
	return _pose(a.call(0.0, 0.32, -0.15), 0.0, 0.0, -55.0, a.call(0.35, 0.55, -0.35), a.call(-0.35, 0.6, -0.3), a.call(0.15, 0.12, 0.95), a.call(-0.2, 0.25, 0.35))


## A head-first slide (diving back to a base, or into one).
static func head_first() -> PuppetPose:
	var a := PuppetPose.at
	return _pose(a.call(0.0, 0.28, -0.2), 0.0, 0.0, 80.0, a.call(0.2, 0.25, 0.85), a.call(-0.2, 0.25, 0.85), a.call(0.15, 0.2, -0.85), a.call(-0.15, 0.2, -0.85))


## A runner's lead off a base: wide stance, low, hands loose, facing home.
static func lead_off() -> PuppetPose:
	var a := PuppetPose.at
	return _pose(a.call(0.0, 0.78, 0.0), 0.0, 0.0, 22.0, a.call(0.25, 0.75, 0.2), a.call(-0.25, 0.75, 0.2), a.call(0.42, 0.08, 0.0), a.call(-0.42, 0.08, 0.0))


## Umpire signals, t seconds after the call. Strike or out: the right fist punched up. Safe:
## both arms swept out flat. Foul: both arms up. Home run: right hand circling over the head.
## Infield fly: the right arm straight up. Time: both hands up, palms out.
static func umpire_signal(kind: StringName, t: float) -> PuppetPose:
	var a := PuppetPose.at
	var stand := _pose(a.call(0.0, 0.95, 0.0), 0.0, 0.0, 4.0, a.call(0.22, 0.88, 0.05), a.call(-0.22, 0.88, 0.05), a.call(0.18, 0.08, 0.0), a.call(-0.18, 0.08, 0.0))
	var sign: PuppetPose
	match kind:
		&"strike", &"out":
			sign = _pose(a.call(0.0, 0.95, 0.0), -20.0, 0.0, 2.0, a.call(0.35, 1.75, 0.0), a.call(-0.15, 1.0, 0.15), a.call(0.2, 0.08, 0.0), a.call(-0.2, 0.08, 0.05))
		&"safe":
			sign = _pose(a.call(0.0, 0.88, 0.0), 0.0, 0.0, 20.0, a.call(0.85, 1.2, 0.25), a.call(-0.85, 1.2, 0.25), a.call(0.3, 0.08, 0.0), a.call(-0.3, 0.08, 0.0))
		&"foul":
			sign = _pose(a.call(0.0, 0.95, 0.0), 0.0, 0.0, 0.0, a.call(0.3, 2.05, 0.05), a.call(-0.3, 2.05, 0.05), a.call(0.2, 0.08, 0.0), a.call(-0.2, 0.08, 0.0))
		&"infield_fly":
			sign = _pose(a.call(0.0, 0.95, 0.0), 0.0, 0.0, 0.0, a.call(0.12, 2.15, 0.12), a.call(-0.2, 0.9, 0.05), a.call(0.2, 0.08, 0.0), a.call(-0.2, 0.08, 0.0))
		&"time":
			sign = _pose(a.call(0.0, 0.95, 0.0), 0.0, 0.0, 0.0, a.call(0.35, 1.95, 0.25), a.call(-0.35, 1.95, 0.25), a.call(0.2, 0.08, 0.0), a.call(-0.2, 0.08, 0.0))
		&"home_run":
			var turn := t * TAU * 1.5
			sign = _pose(a.call(0.0, 0.95, 0.0), 0.0, 0.0, 0.0, a.call(0.2 + 0.08 * cos(turn), 2.05, 0.08 * sin(turn)), a.call(-0.2, 0.9, 0.05), a.call(0.2, 0.08, 0.0), a.call(-0.2, 0.08, 0.0))
		_:
			return stand
	var up := smoothstep(0.0, 0.25, t)
	var down := 1.0 - smoothstep(1.2, 1.6, t)
	return stand.blend(sign, minf(up, down))


## Walking, for the pitcher coming back to the rubber and anyone strolling. phase as run().
static func walk(phase: float) -> PuppetPose:
	var a := PuppetPose.at
	var left := _pose(a.call(0.0, 0.95, 0.0), 0.0, 4.0, 3.0, a.call(0.24, 0.86, 0.12), a.call(-0.24, 0.86, -0.1), a.call(0.12, 0.1, -0.28), a.call(-0.12, 0.08, 0.28))
	var right := _pose(a.call(0.0, 0.95, 0.0), 0.0, -4.0, 3.0, a.call(0.24, 0.86, -0.1), a.call(-0.24, 0.86, 0.12), a.call(0.12, 0.08, 0.28), a.call(-0.12, 0.1, -0.28))
	return left.blend(right, 0.5 - 0.5 * cos(phase * PI))
