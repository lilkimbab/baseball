extends SceneTree
## (c) can this environment render a 3D frame and save it, so visuals can be checked from the terminal?
var frame := 0

static func to_world(f: Vector3) -> Vector3:
	return Vector3(f.x, f.z, -f.y)

func mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func add_mesh(mesh: Mesh, m: Material, pos_field: Vector3, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = to_world(pos_field)
	mi.rotation.y = rot_y
	root.add_child(mi)
	return mi

func _initialize() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	# outfield grass
	var grass := PlaneMesh.new()
	grass.size = Vector2(260, 260)
	add_mesh(grass, mat(Color(0.16, 0.42, 0.17)), Vector3(0, 60, 0))
	# infield dirt diamond (square rotated 45 deg) + grass inner square
	var dirt := PlaneMesh.new()
	dirt.size = Vector2(38, 38)
	add_mesh(dirt, mat(Color(0.62, 0.42, 0.26)), Vector3(0, 19.4, 0.01), PI / 4)
	var inner := PlaneMesh.new()
	inner.size = Vector2(25, 25)
	add_mesh(inner, mat(Color(0.2, 0.5, 0.2)), Vector3(0, 19.4, 0.02), PI / 4)
	# mound, bases, plate
	var mound := CylinderMesh.new()
	mound.top_radius = 1.2; mound.bottom_radius = 2.74; mound.height = 0.25
	add_mesh(mound, mat(Color(0.62, 0.42, 0.26)), Vector3(0, 18.0, 0.125))
	var base := BoxMesh.new()
	base.size = Vector3(0.46, 0.08, 0.46)
	for p: Vector3 in [Vector3(19.4, 19.4, 0.06), Vector3(0, 38.8, 0.06), Vector3(-19.4, 19.4, 0.06), Vector3(0, 0.2, 0.04)]:
		add_mesh(base, mat(Color.WHITE), p, PI / 4)
	# outfield wall: arc of boxes
	var seg := BoxMesh.new()
	seg.size = Vector3(6.4, 2.6, 0.4)
	for i in 31:
		var a := deg_to_rad(-45.0 + 3.0 * i)
		var d := 100.0 + 22.0 * cos(a * 2.0)
		add_mesh(seg, mat(Color(0.08, 0.2, 0.36)), Vector3(d * sin(a), d * cos(a), 1.3), -a)
	# 9 fielders + batter as capsules
	var cap := CapsuleMesh.new()
	cap.radius = 0.28; cap.height = 1.82
	var spots: Array[Vector3] = [Vector3(0, 18.2, 1.16), Vector3(0, -1.2, 0.7), Vector3(21, 24, 0.91), Vector3(9, 36, 0.91), Vector3(-21, 24, 0.91), Vector3(-9, 36, 0.91), Vector3(-45, 75, 0.91), Vector3(0, 95, 0.91), Vector3(45, 75, 0.91)]
	for p in spots:
		add_mesh(cap, mat(Color(0.92, 0.92, 0.95), 0.6), p)
	add_mesh(cap, mat(Color(0.75, 0.12, 0.12), 0.6), Vector3(-0.9, 0.3, 0.91))
	var cam := Camera3D.new()
	cam.fov = 38
	root.add_child(cam)
	cam.look_at_from_position(to_world(Vector3(1.2, -7.5, 3.2)), to_world(Vector3(0, 30, 1.0)))
	cam.make_current()

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 30:
		var img := root.get_texture().get_image()
		var path := OS.get_environment("SPIKE_OUT")
		img.save_png(path)
		print("saved ", path, " ", img.get_size(), " | renderer: ", RenderingServer.get_current_rendering_method(), " / ", RenderingServer.get_current_rendering_driver_name(), " | adapter: ", RenderingServer.get_video_adapter_name())
		return true
	return false
