class_name BallSim
extends RefCounted
## State and free-flight integration of the baseball, in field coordinates.
##
## The ball is not an engine rigid body: drag and Magnus force are integrated here so the
## same code can run headless and can fast-forward a whole trajectory for prediction.
## Constants are validated in docs/04-physics.md (section 12).

const G := 9.81
const RHO := 1.2
const M := 0.145
const R := 0.0366
const K := RHO * PI * R * R / (2.0 * M)
const CD0 := 0.33
const CD_SPIN := 0.02
const CL0 := 0.583
const CL1 := 2.333
const CL2 := 1.05
const SPIN_TAU := 25.0

var pos := Vector3.ZERO
var vel := Vector3.ZERO
## Angular velocity (rad/s). Magnus force direction is spin x velocity.
var spin := Vector3.ZERO


## Aerodynamic acceleration (drag + Magnus), without gravity.
static func aero(v: Vector3, w: Vector3) -> Vector3:
	var sp := v.length()
	if sp < 1e-6:
		return Vector3.ZERO
	var vh := v / sp
	var w_perp := w - vh * w.dot(vh)
	var w_rpm := w.length() * 60.0 / TAU
	var cd := CD0 + CD_SPIN * (w_rpm / 1000.0)
	var wp := w_perp.length()
	var acc := v * (-K * cd * sp)
	if wp > 1e-6:
		var s := R * wp / sp
		var cl := CL2 * s / (CL0 + CL1 * s)
		acc += w_perp.cross(v).normalized() * (K * cl * sp * sp)
	return acc


static func accel(v: Vector3, w: Vector3) -> Vector3:
	return aero(v, w) + Vector3(0.0, 0.0, -G)


## One RK4 step of free flight. Updates velocity and spin; returns the proposed new position
## so the caller can test the swept segment for collisions before committing it.
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
	spin *= exp(-dt / SPIN_TAU)
	return new_pos


## Impulse bounce of a solid sphere off a massive surface with Coulomb-limited friction.
## n = surface normal (unit), e = restitution, mu = friction coefficient.
func bounce(n: Vector3, e: float, mu: float) -> void:
	var vn := vel.dot(n)
	if vn >= 0.0:
		return
	var v_t := vel - n * vn
	var u := v_t + spin.cross(n * -R)
	var jn := -(1.0 + e) * vn
	var ul := u.length()
	vel = v_t + n * (-e * vn)
	if ul > 1e-6:
		var dir := u / ul
		var jt := minf(2.0 / 7.0 * ul, mu * jn)
		vel -= dir * jt
		spin += n.cross(dir) * (2.5 * jt / R)
