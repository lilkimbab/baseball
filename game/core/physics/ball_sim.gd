class_name BallSim
extends RefCounted
## State and motion of the baseball, in field coordinates.
##
## The ball is not an engine rigid body: drag and Magnus force are integrated here so the
## same code runs headless and can fast-forward a whole trajectory for prediction.
## Model and constants: docs/04-physics.md.

## After a bounce on the ground, normal speed below this (m/s) switches the ball to rolling.
const ROLL_ENTER_SPEED := 0.5
## A rolling ball slower than this (m/s) is at rest.
const STOP_SPEED := 0.2

var cfg: PhysicsConfig
var pos := Vector3.ZERO
var vel := Vector3.ZERO
## Angular velocity (rad/s). The Magnus force points along spin x velocity.
var spin := Vector3.ZERO
var rolling := false
var stopped := false
## Off the bat: flies by the batted-ball coefficients, which depend on the launch speed.
var batted := false
var _batted_cd := 0.0
## Seconds simulated by advance().
var time := 0.0


func _init(config: PhysicsConfig) -> void:
	cfg = config


func clone() -> BallSim:
	var copy := BallSim.new(cfg)
	copy.pos = pos
	copy.vel = vel
	copy.spin = spin
	copy.batted = batted
	copy._batted_cd = _batted_cd
	copy.rolling = rolling
	copy.stopped = stopped
	copy.time = time
	return copy


## Marks the ball as just hit at its present velocity (sets the batted-ball drag).
func hit() -> void:
	batted = true
	var mph := vel.length() / 0.44704
	_batted_cd = cfg.bat_cd0 * (1.0 + cfg.bat_cd_per_mph * (100.0 - mph))


## Aerodynamic acceleration (drag + Magnus), without gravity.
func aero(v: Vector3, w: Vector3) -> Vector3:
	var sp := v.length()
	if sp < 1e-6:
		return Vector3.ZERO
	if batted:
		return _batted_aero(v, w, sp)
	var vh := v / sp
	var w_perp := w - vh * w.dot(vh)
	var w_rpm := w.length() * 60.0 / TAU
	var cd := cfg.cd0 + cfg.cd_per_1000_rpm * (w_rpm / 1000.0)
	var wp := w_perp.length()
	var acc := v * (-cfg.aero_k * cd * sp)
	if wp > 1e-6:
		var s := cfg.ball_radius * wp / sp
		var cl := cfg.cl2 * s / (cfg.cl0 + cfg.cl1 * s)
		acc += w_perp.cross(v).normalized() * (cfg.aero_k * cl * sp * sp)
	return acc


## Nathan's Statcast fit: Cd = cd0 (1 + k (100 - launch mph)) (1 + c S^2), Cl = 1/(a + b/S).
func _batted_aero(v: Vector3, w: Vector3, sp: float) -> Vector3:
	var wl := w.length()
	var s := cfg.ball_radius * wl / sp
	var cd := _batted_cd * (1.0 + cfg.bat_cd_spin * s * s)
	var acc := v * (-cfg.aero_k * cd * sp)
	if s > 1e-6:
		var cl := 1.0 / (cfg.bat_cl_a + cfg.bat_cl_b / s)
		var lift := w.cross(v)
		var n := lift.length()
		if n > 1e-9:
			acc += lift * (cfg.aero_k * cl * sp * sp / n)
	return acc


func accel(v: Vector3, w: Vector3) -> Vector3:
	return aero(v, w) + Vector3(0.0, 0.0, -cfg.gravity)


## One RK4 step of free flight. Updates velocity and spin and returns the proposed new
## position; the caller commits it (or tests the swept segment for collisions first).
func integrate(dt: float) -> Vector3:
	var k1v := accel(vel, spin)
	var v2 := vel + k1v * (dt * 0.5)
	var k2v := accel(v2, spin)
	var v3 := vel + k2v * (dt * 0.5)
	var k3v := accel(v3, spin)
	var v4 := vel + k3v * dt
	var k4v := accel(v4, spin)
	var new_pos := pos + (vel + v2 * 2.0 + v3 * 2.0 + v4) * (dt / 6.0)
	vel += (k1v + k2v * 2.0 + k3v * 2.0 + k4v) * (dt / 6.0)
	spin *= exp(-dt / cfg.spin_decay_tau)
	return new_pos


## Impulse bounce of a solid sphere off a massive surface with Coulomb-limited friction.
## n = unit surface normal, e = restitution, mu = friction coefficient.
func bounce(n: Vector3, e: float, mu: float) -> void:
	var vn := vel.dot(n)
	if vn >= 0.0:
		return
	var radius := cfg.ball_radius
	var v_t := vel - n * vn
	var u := v_t + spin.cross(n * -radius)
	var jn := -(1.0 + e) * vn
	var ul := u.length()
	vel = v_t + n * (-e * vn)
	if ul > 1e-6:
		var dir := u / ul
		var jt := minf(2.0 / 7.0 * ul, mu * jn)
		vel -= dir * jt
		spin += n.cross(dir) * (2.5 * jt / radius)


## Advances the ball by dt including collisions with the field: flight, bounces, rolling and
## coming to rest. Returns the contact made during this step, or null.
func advance(dt: float, field: CollisionProvider) -> SweepHit:
	time += dt
	if stopped:
		return null
	if rolling:
		return _advance_rolling(dt, field)

	var new_pos := integrate(dt)
	var hit := field.sweep(pos, new_pos, cfg.ball_radius)
	if hit == null:
		pos = new_pos
		return null

	var surface := cfg.surface(hit.surface)
	pos = hit.point
	bounce(hit.normal, surface.restitution, surface.friction)
	var normal_speed := vel.dot(hit.normal)
	if surface.is_ground and normal_speed < ROLL_ENTER_SPEED:
		rolling = true
		vel -= hit.normal * normal_speed
	else:
		pos += vel * (dt * (1.0 - hit.fraction))
	return hit


func _advance_rolling(dt: float, field: CollisionProvider) -> SweepHit:
	var horizontal := Vector3(vel.x, vel.y, 0.0)
	var speed := horizontal.length()
	if speed < STOP_SPEED:
		vel = Vector3.ZERO
		spin = Vector3.ZERO
		stopped = true
		return null

	var surface := cfg.surface(field.surface_at(pos))
	var new_speed := maxf(speed - (surface.roll_decel + surface.roll_drag * speed) * dt, 0.0)
	vel = horizontal * (new_speed / speed)
	# Rolling without slipping: spin axis is horizontal, perpendicular to the motion.
	spin = Vector3(-vel.y, vel.x, 0.0) / cfg.ball_radius

	var new_pos := pos + vel * dt
	var hit := field.sweep(pos, new_pos, cfg.ball_radius)
	if hit == null:
		pos = new_pos
		return null
	pos = hit.point
	var wall := cfg.surface(hit.surface)
	var vn := vel.dot(hit.normal)
	if vn < 0.0:
		vel -= hit.normal * ((1.0 + wall.restitution) * vn)
	return hit
