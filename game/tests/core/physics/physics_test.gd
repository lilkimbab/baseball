class_name PhysicsTest
extends GutTest
## Shared helpers for the physics regression tests. Target ranges are the verification table
## in docs/04-physics.md, section 12.

const RELEASE := Vector3(-0.55, 16.76, 1.80)
const PLATE_TARGET := Vector3(0.0, Field.PLATE_FRONT_Y, 0.75)

var cfg: PhysicsConfig


func before_all() -> void:
	cfg = PhysicsConfigIO.load_default()


func kmh(value: float) -> float:
	return value / 3.6


func rpm(value: float) -> float:
	return value * TAU / 60.0


## A ball leaving the bat along +y. Positive backspin_rpm = backspin.
func batted_ball(ev_kmh: float, launch_deg: float, backspin_rpm: float, spray_deg: float = 0.0, height: float = 1.0) -> BallSim:
	var ball := BallSim.new(cfg)
	var launch := deg_to_rad(launch_deg)
	var spray := deg_to_rad(spray_deg)
	var speed := kmh(ev_kmh)
	var forward := Vector3(sin(spray), cos(spray), 0.0)
	ball.pos = Vector3(0.0, 0.0, height)
	ball.vel = forward * (speed * cos(launch)) + Vector3(0.0, 0.0, speed * sin(launch))
	ball.spin = Vector3(forward.y, -forward.x, 0.0) * rpm(backspin_rpm)
	return ball


func standard_field() -> AnalyticField:
	return AnalyticField.create(FenceProfile.symmetric(100.0, 116.0, 122.0, 2.6))
