extends GutTest
## Regression checks for ball flight. Target ranges come from docs/04-physics.md, section 12.
## Stage S2 extends this file to cover the whole table (pitches, contact model, bounces).

const DT := 1.0 / 240.0


## Flies a batted ball from 1 m above the plate until it comes down. Returns (carry m, hang s).
func _fly(ev_kmh: float, launch_deg: float, backspin_rpm: float) -> Vector2:
	var ball := BallSim.new()
	var launch := deg_to_rad(launch_deg)
	var speed := ev_kmh / 3.6
	ball.pos = Vector3(0.0, 0.0, 1.0)
	ball.vel = Vector3(0.0, speed * cos(launch), speed * sin(launch))
	ball.spin = Vector3(backspin_rpm * TAU / 60.0, 0.0, 0.0)
	var t := 0.0
	while t < 15.0:
		ball.pos = ball.integrate(DT)
		t += DT
		if ball.pos.z <= BallSim.R:
			break
	return Vector2(ball.pos.y, t)


func test_fly_ball_160_kmh_28_deg_carries_about_121_m() -> void:
	var r := _fly(160.0, 28.0, 2000.0)
	assert_between(r.x, 118.0, 124.0, "carry (m)")
	assert_between(r.y, 4.8, 5.4, "hang time (s)")


func test_fly_ball_170_kmh_28_deg() -> void:
	assert_between(_fly(170.0, 28.0, 2200.0).x, 126.0, 134.0, "carry (m)")


func test_fly_ball_150_kmh_30_deg() -> void:
	assert_between(_fly(150.0, 30.0, 2200.0).x, 108.0, 116.0, "carry (m)")


func test_backspin_adds_carry() -> void:
	var with_spin := _fly(160.0, 28.0, 2000.0).x
	var without_spin := _fly(160.0, 28.0, 0.0).x
	assert_gt(with_spin, without_spin + 5.0, "backspin should add several metres of carry")


func test_drag_shortens_flight_versus_vacuum() -> void:
	var speed := 160.0 / 3.6
	var vacuum_range := speed * speed * sin(deg_to_rad(56.0)) / BallSim.G
	assert_lt(_fly(160.0, 28.0, 0.0).x, vacuum_range * 0.8, "drag should cost well over 20% of range")


func test_same_input_gives_identical_result() -> void:
	var a := _fly(155.0, 24.0, 1800.0)
	var b := _fly(155.0, 24.0, 1800.0)
	assert_eq(a, b, "simulation must be deterministic")


func test_bounce_off_ground_reverses_vertical_speed_and_loses_energy() -> void:
	var ball := BallSim.new()
	ball.vel = Vector3(0.0, 20.0, -10.0)
	var speed_before := ball.vel.length()
	ball.bounce(Vector3(0.0, 0.0, 1.0), 0.45, 0.55)
	assert_almost_eq(ball.vel.z, 4.5, 0.001, "restitution 0.45 on 10 m/s")
	assert_lt(ball.vel.length(), speed_before, "bounce must not add energy")
	assert_gt(ball.vel.y, 0.0, "ball keeps moving forward")


func test_bounce_ignores_a_ball_moving_away_from_the_surface() -> void:
	var ball := BallSim.new()
	ball.vel = Vector3(0.0, 20.0, 3.0)
	ball.bounce(Vector3(0.0, 0.0, 1.0), 0.45, 0.55)
	assert_eq(ball.vel, Vector3(0.0, 20.0, 3.0))
