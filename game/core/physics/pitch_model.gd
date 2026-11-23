class_name PitchModel
extends RefCounted
## Turns "throw this pitch at that spot" into a ball state at release (docs/03, section 5).

const DT := 1.0 / 240.0
const MAX_AIM_ITERATIONS := 8
## Close enough (m): far below any pitcher's precision.
const AIM_TOLERANCE := 0.002


## Spin vector for a pitch travelling along `dir` (unit vector from release toward the plate).
static func spin_vector(dir: Vector3, spin_rpm: float, efficiency: float, tilt_deg: float, throws_left: bool) -> Vector3:
	var back := -dir
	var right := back.cross(Vector3(0.0, 0.0, 1.0)).normalized()
	var up := right.cross(back).normalized()
	var tilt := deg_to_rad(-tilt_deg if throws_left else tilt_deg)
	var force_dir := up * cos(tilt) + right * sin(tilt)
	var omega := spin_rpm * TAU / 60.0
	var active := dir.cross(force_dir).normalized() * (omega * efficiency)
	var gyro := dir * (omega * sqrt(maxf(0.0, 1.0 - efficiency * efficiency)))
	return active - gyro if throws_left else active + gyro


## The seam-shifted wake's push for a pitch travelling along `dir`: `accel` m/s² in the
## direction `deg` (measured like tilt_deg, mirrored for a left-hander).
static func ssw_vector(dir: Vector3, accel: float, deg: float, throws_left: bool) -> Vector3:
	if accel == 0.0:
		return Vector3.ZERO
	var back := -dir
	var right := back.cross(Vector3(0.0, 0.0, 1.0)).normalized()
	var up := right.cross(back).normalized()
	var a := deg_to_rad(-deg if throws_left else deg)
	return (up * cos(a) + right * sin(a)) * accel


## Flies a ball from release until it crosses the front edge of the plate, noting on the way
## where it crosses the plane at `contact_y` (if that is in front of the plate).
static func fly_to_plate(cfg: PhysicsConfig, release: Vector3, velocity: Vector3, spin: Vector3, contact_y: float = -INF, ssw: Vector3 = Vector3.ZERO) -> PitchFlight:
	var ball := BallSim.new(cfg)
	ball.pos = release
	ball.vel = velocity
	ball.spin = spin
	ball.ssw = ssw
	var out := PitchFlight.new()
	out.release_pos = release
	out.release_vel = velocity
	out.spin = spin
	out.ssw = ssw
	if NativePhysics.enabled:
		var native := NativePhysics.fly_to_plate(release, velocity, spin, ssw, contact_y, Field.PLATE_FRONT_Y, DT, cfg.native)
		out.plate_pos = native["plate_pos"]
		out.plate_vel = native["plate_vel"]
		out.flight_time = native["flight_time"]
		if native.has("contact_pos"):
			out.contact_pos = native["contact_pos"]
			out.contact_time = native["contact_time"]
		return out

	var t := 0.0
	while t < 3.0:
		var prev_pos := ball.pos
		var prev_vel := ball.vel
		var new_pos := ball.integrate(DT)
		if prev_pos.y > contact_y and new_pos.y <= contact_y:
			var g := (prev_pos.y - contact_y) / (prev_pos.y - new_pos.y)
			out.contact_pos = prev_pos.lerp(new_pos, g)
			out.contact_time = t + DT * g
		if new_pos.y <= Field.PLATE_FRONT_Y:
			var f := (prev_pos.y - Field.PLATE_FRONT_Y) / (prev_pos.y - new_pos.y)
			out.plate_pos = prev_pos.lerp(new_pos, f)
			out.plate_vel = prev_vel.lerp(ball.vel, f)
			out.flight_time = t + DT * f
			return out
		ball.pos = new_pos
		t += DT
	out.plate_pos = ball.pos
	out.plate_vel = ball.vel
	out.flight_time = t
	return out


## Solves for the release direction that makes the pitch cross the plate at `target`
## (a point on the plane of the plate's front edge), allowing for gravity, drag and break.
static func throw_at(cfg: PhysicsConfig, release: Vector3, target: Vector3, speed_kmh: float,
		spin_rpm: float, efficiency: float, tilt_deg: float, throws_left: bool = false,
		contact_y: float = -INF, with_movement: bool = true, ssw_accel: float = 0.0, ssw_deg: float = 0.0) -> PitchFlight:
	var speed := speed_kmh / 3.6
	var aim := target
	var flight: PitchFlight = null
	for i: int in MAX_AIM_ITERATIONS:
		var dir := (aim - release).normalized()
		var spin := spin_vector(dir, spin_rpm, efficiency, tilt_deg, throws_left)
		flight = fly_to_plate(cfg, release, dir * speed, spin, contact_y, ssw_vector(dir, ssw_accel, ssw_deg, throws_left))
		var miss := Vector3(target.x - flight.plate_pos.x, 0.0, target.z - flight.plate_pos.z)
		if miss.length() < AIM_TOLERANCE:
			break
		aim += miss
	if with_movement:
		var no_spin := fly_to_plate(cfg, release, flight.release_vel, Vector3.ZERO)
		flight.movement = Vector2(flight.plate_pos.x - no_spin.plate_pos.x, flight.plate_pos.z - no_spin.plate_pos.z)
	return flight


## Points along a pitch's flight from the hand to the front of the plate, `step` seconds
## apart, the last one where it crosses the plate (for drawing the path it will take).
static func path(cfg: PhysicsConfig, flight: PitchFlight, step: float = 0.04) -> PackedVector3Array:
	var ball := BallSim.new(cfg)
	ball.pos = flight.release_pos
	ball.vel = flight.release_vel
	ball.spin = flight.spin
	ball.ssw = flight.ssw
	var out := PackedVector3Array([ball.pos])
	var t := 0.0
	var next := step
	while t < flight.flight_time:
		ball.pos = ball.integrate(DT)
		t += DT
		if t >= next:
			out.append(ball.pos)
			next += step
	out.append(flight.plate_pos)
	return out


## Throws a catalogue pitch with its reference speed and spin.
## ssw_scale: the pitcher's feel for the seam-shifted wake (1 the pitch type's own).
static func throw_type(cfg: PhysicsConfig, type: PitchType, release: Vector3, target: Vector3, throws_left: bool = false, ssw_scale: float = 1.0) -> PitchFlight:
	return throw_at(cfg, release, target, type.speed_kmh, type.spin_rpm, type.efficiency, type.tilt_deg, throws_left,
		-INF, true, type.ssw_accel * ssw_scale, type.ssw_deg)


## Where the pitcher actually aims after execution error: `target` moved by a random miss in
## the plane of the plate. sigma_m = standard deviation of the miss per axis (metres).
static func apply_execution_error(target: Vector3, sigma_m: float, rng: Rng) -> Vector3:
	return target + Vector3(rng.next_normal() * sigma_m, 0.0, rng.next_normal() * sigma_m)


## Miss size (metres, per axis) from the command rating (1-99), per docs/03 section 5.2.
static func command_sigma(command: float) -> float:
	return lerpf(0.26, 0.09, clampf(command / 100.0, 0.0, 1.0))
