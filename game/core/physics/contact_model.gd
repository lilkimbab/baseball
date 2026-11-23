class_name ContactModel
extends RefCounted
## Bat-ball collision as a closed-form model (docs/03, section 7). The bat is not a physics
## object: the swing is reduced to where and how the barrel meets the ball.


## ball_vel, ball_spin : the pitch at contact.
## bat_speed          : barrel speed at the contact point (m/s).
## attack_rad         : upward angle of the swing path.
## yaw_rad            : how far the bat has rotated past square. Positive = contact out in
##                      front = pulled (toward third base for a right-handed batter).
## offset_up          : height of the ball's centre above the bat's axis (m). Positive = the
##                      bat gets under the ball.
## along_bat          : distance from the tip of the bat to the contact point (m).
static func resolve(cfg: PhysicsConfig, ball_vel: Vector3, ball_spin: Vector3, bat_speed: float,
		attack_rad: float, yaw_rad: float, offset_up: float, along_bat: float, bats_left: bool = false) -> ContactResult:
	var result := ContactResult.new()
	var radius := cfg.ball_radius
	var sin_t := offset_up / (radius + cfg.bat_radius)
	if absf(sin_t) >= 1.0:
		return result

	var yaw := -yaw_rad if bats_left else yaw_rad
	var axis := Vector3(cos(yaw), sin(yaw), 0.0)
	var forward := Vector3(0.0, 0.0, 1.0).cross(axis).normalized()
	var bat_vel := forward * (bat_speed * cos(attack_rad)) + Vector3(0.0, 0.0, bat_speed * sin(attack_rad))
	var n := (forward * sqrt(1.0 - sin_t * sin_t) + Vector3(0.0, 0.0, sin_t)).normalized()

	var rel := ball_vel - bat_vel
	var vn := rel.dot(n)
	if vn >= 0.0:
		return result
	var rel_t := rel - n * vn
	var slip := rel_t + ball_spin.cross(n * -radius) * cfg.spin_memory
	var grip := cfg.friction_transfer
	var out_rel := n * (-cfg.bat_efficiency(along_bat) * vn) + rel_t - slip * (2.0 / 7.0 * grip)

	result.made_contact = true
	result.velocity = bat_vel + out_rel
	result.spin = ball_spin * cfg.spin_memory + n.cross(slip) * (5.0 / 7.0 * grip / radius)
	return result


## Barrel speed (m/s) at the sweet spot from the power rating (1-99), docs/03 section 7.2.
static func bat_speed_from_power(power: float) -> float:
	return lerpf(104.5, 128.5, clampf(power / 100.0, 0.0, 1.0)) / 3.6
