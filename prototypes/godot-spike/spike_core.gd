extends SceneTree
## (a) pure-script ball sim on an analytic field: numbers must match prototypes/physics-check.

const DT := 1.0 / 240.0

func kmh(v: float) -> float:
	return v / 3.6

func rpm(v: float) -> float:
	return v * TAU / 60.0

func fly(b: BallSim, e: float, mu: float, roll_decel: float, marks: Array[float]) -> Dictionary:
	var out := {"first": -1.0, "first_t": -1.0, "bounces": 0, "marks": {}}
	while b.t < 12.0:
		if b.rolling:
			var hs := Vector2(b.vel.x, b.vel.y).length()
			if hs < 0.3:
				break
			var dec := BallSim.aero(b.vel, Vector3.ZERO) - Vector3(b.vel.x, b.vel.y, 0.0) / hs * roll_decel
			b.vel += Vector3(dec.x, dec.y, 0.0) * DT
			b.pos += b.vel * DT
		else:
			var np := b.integrate(DT)
			if np.z <= BallSim.R and b.vel.z < 0.0:
				np.z = BallSim.R
				if out.first < 0.0:
					out.first = Vector2(np.x, np.y).length()
					out.first_t = b.t + DT
				out.bounces += 1
				b.bounce(Vector3(0, 0, 1), e, mu)
				if absf(b.vel.z) < 0.5:
					b.rolling = true
					b.vel.z = 0.0
			b.pos = np
		b.t += DT
		for m in marks:
			if not out.marks.has(m) and Vector2(b.pos.x, b.pos.y).length() >= m:
				out.marks[m] = b.t
	out["rest"] = Vector2(b.pos.x, b.pos.y).length()
	out["t"] = b.t
	return out

func make(ev_kmh: float, la_deg: float, spin_rpm: float, z0: float) -> BallSim:
	var b := BallSim.new()
	var la := deg_to_rad(la_deg)
	b.pos = Vector3(0, 0.6, z0)
	b.vel = Vector3(0, kmh(ev_kmh) * cos(la), kmh(ev_kmh) * sin(la))
	b.spin = Vector3(rpm(spin_rpm), 0, 0)
	return b

func _initialize() -> void:
	print("== Godot ", Engine.get_version_info().string, " | physics engine: ", ProjectSettings.get_setting("physics/3d/physics_engine"))
	var none: Array[float] = []
	var b := make(160, 28, 2000, 1.0)
	b.pos.y = 0.0
	var r := fly(b, 0.45, 0.55, 3.0, none)
	print("fly 160km/h 28deg 2000rpm: first bounce %.2f m @ %.2f s (prototype RK4: 120.78 m @ 5.09 s)" % [r.first, r.first_t])
	var marks: Array[float] = [20.0, 30.0, 40.0]
	for cfg: Array in [[150, -5], [160, 2], [120, -10], [140, 8]]:
		var g := make(cfg[0], cfg[1], -1500, 0.8)
		var rr := fly(g, 0.45, 0.55, 3.0, marks)
		print("grounder EV %d LA %d: first %.1f m, t@20=%.2f t@30=%.2f t@40=%.2f, bounces=%d, rest %.0f m after %.1f s" % [cfg[0], cfg[1], rr.first, rr.marks.get(20.0, -1.0), rr.marks.get(30.0, -1.0), rr.marks.get(40.0, -1.0), rr.bounces, rr.rest, rr.t])
	# determinism
	var h1 := str(fly(make(150, -5, -1500, 0.8), 0.45, 0.55, 3.0, marks))
	var h2 := str(fly(make(150, -5, -1500, 0.8), 0.45, 0.55, 3.0, marks))
	print("deterministic repeat: ", h1 == h2)
	# throughput of the typed-GDScript RK4 step
	var p := make(160, 28, 2000, 1.0)
	var n := 400000
	var t0 := Time.get_ticks_usec()
	for i in n:
		p.pos = p.integrate(DT)
		if p.pos.z < 0.0:
			p = make(160, 28, 2000, 1.0)
	var us := Time.get_ticks_usec() - t0
	print("GDScript RK4: %.2f us/step -> %.0fk steps/s (= %.0fx realtime for one ball at 240 Hz)" % [float(us) / n, n / (us / 1e6) / 1000.0, n / 240.0 / (us / 1e6)])
	quit()
