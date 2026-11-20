extends SceneTree
## (b) same ball sim, but collisions come from engine space queries against scene colliders.
## The whole flight is simulated inside ONE physics frame (this is what trajectory prediction needs).

const DT := 1.0 / 240.0
var frame := 0
var shape := SphereShape3D.new()

static func to_world(f: Vector3) -> Vector3:
	return Vector3(f.x, f.z, -f.y)

static func to_field(w: Vector3) -> Vector3:
	return Vector3(w.x, -w.z, w.y)

func add_box(size: Vector3, center_field: Vector3, surface: String) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.z, size.y)
	cs.shape = box
	body.add_child(cs)
	body.position = to_world(center_field)
	body.set_meta("surface", surface)
	root.add_child(body)

func _initialize() -> void:
	shape.radius = BallSim.R
	add_box(Vector3(400, 400, 1.0), Vector3(0, 100, -0.5), "grass")
	add_box(Vector3(120, 0.6, 2.6), Vector3(0, 122.3, 1.3), "wall_pad")

func simulate(space: PhysicsDirectSpaceState3D, b: BallSim) -> Dictionary:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	var log := {"events": [], "queries": 0}
	while b.t < 12.0 and not b.rolling:
		var np := b.integrate(DT)
		q.transform = Transform3D(Basis.IDENTITY, to_world(b.pos))
		q.motion = to_world(np) - to_world(b.pos)
		var frac := space.cast_motion(q)
		log.queries += 1
		if frac[1] < 1.0:
			var hit_w := to_world(b.pos) + q.motion * frac[1]
			q.transform = Transform3D(Basis.IDENTITY, hit_w)
			q.motion = Vector3.ZERO
			var info := space.get_rest_info(q)
			log.queries += 1
			if info.is_empty():
				b.pos = np
			else:
				var n := to_field(info.normal)
				var surface: String = instance_from_id(info.collider_id).get_meta("surface")
				b.pos = to_field(to_world(b.pos) + (to_world(np) - to_world(b.pos)) * frac[0])
				var e := 0.45 if surface == "grass" else 0.35
				b.bounce(n, e, 0.55)
				log.events.append("%s @%.2fs pos=(%.1f, %.1f, %.2f) n=(%.1f, %.1f, %.1f)" % [surface, b.t, b.pos.x, b.pos.y, b.pos.z, n.x, n.y, n.z])
				if surface == "grass" and absf(b.vel.z) < 0.5:
					b.rolling = true
				if log.events.size() >= 6:
					break
		else:
			b.pos = np
		b.t += DT
	return log

func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	var space := root.get_world_3d().direct_space_state
	for cfg: Array in [[160, 28, 2000], [150, 22, 1500], [150, -5, -1500]]:
		var b := BallSim.new()
		var la := deg_to_rad(cfg[1])
		b.pos = Vector3(0, 0.0, 1.0)
		b.vel = Vector3(0, cfg[0] / 3.6 * cos(la), cfg[0] / 3.6 * sin(la))
		b.spin = Vector3(cfg[2] * TAU / 60.0, 0, 0)
		var t0 := Time.get_ticks_usec()
		var log := simulate(space, b)
		var us := Time.get_ticks_usec() - t0
		print("EV %d LA %d: %d queries in %.2f ms (all inside one physics frame)" % [cfg[0], cfg[1], log.queries, us / 1000.0])
		for ev: String in log.events:
			print("   hit ", ev)
	return true
