class_name Crowd
extends Node3D
## The people in the stands (docs/06 7, docs/13 S14): one in a seat the stadium builder laid
## out, three levels of detail by where they sit — people of some 600 triangles in the rows
## behind home and over the dugouts, figures of some 60 in the rest of the lower bowl, flat
## cut-outs in the outfield and the upper tiers. No bones: the crowd shader moves them, zone
## by zone. KBO style, the first-base side is the home side's cheering section and the
## third-base side the visitors', each with its stage at the front, and they stand and cheer
## while their team bats.

enum Zone { BEHIND_HOME, FIRST, THIRD, OUTFIELD, UPPER, HOME_CHEER, AWAY_CHEER, STAGE }
enum State { SEATED, STANDING, CHEERING, CLAPPING }

const SHADER := "res://stadium/crowd.gdshader"
## Ordinary clothes, for anyone not in his club's colours.
const CASUAL: Array[Color] = [
	Color(0.95, 0.95, 0.95), Color(0.12, 0.12, 0.13), Color(0.5, 0.52, 0.55), Color(0.15, 0.2, 0.38),
	Color(0.85, 0.78, 0.62), Color(0.75, 0.2, 0.2), Color(0.45, 0.65, 0.85), Color(0.3, 0.45, 0.3),
	Color(0.9, 0.75, 0.3), Color(0.6, 0.35, 0.55),
]
## Beats a second of the cheering songs.
const BEATS_PER_SECOND := 2.1

var park: StadiumBuilder
var home_colours: Array[Color] = [Color(0.95, 0.95, 0.96), Color(0.1, 0.2, 0.5)]
var away_colours: Array[Color] = [Color(0.2, 0.2, 0.22), Color(0.75, 0.15, 0.15)]
## The share of seats with someone in them (0..1), and the quality setting's share of those
## drawn (1, 0.6, 0.3).
var fill := 0.8
var density := 1.0
var seed_value := 1
## How many are drawn at each level of detail.
var counts := Vector3i.ZERO
var _materials: Array[ShaderMaterial] = []
var _states := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, State.CHEERING])
var _beat := 0.0


func _init(stadium: StadiumBuilder = null) -> void:
	park = stadium


func _ready() -> void:
	var mesh_material := _material(false)
	var flat_material := _material(true)
	var person := _person_mesh()
	var doll := _doll_mesh()
	var cutout := QuadMesh.new()
	cutout.size = Vector2(0.62, 1.24)
	cutout.center_offset = Vector3(0.0, 0.62, 0.0)
	var near := _multimesh(person)
	var mid := _multimesh(doll)
	var far := _multimesh(cutout)
	var rng := Rng.new(seed_value)
	var near_items: Array = []
	var mid_items: Array = []
	var far_items: Array = []
	var dug := park.dugout_span()
	for i: int in park.seat_pos.size():
		var zone := park.seat_zone[i]
		# The busier zones fill first; a full house fills them all.
		if not rng.chance(pow(clampf(fill, 0.0, 1.0), 1.0 / _zone_fill(zone)) * density):
			continue
		var tier := park.seat_tier[i]
		var row := park.seat_row[i]
		var az := park.seat_az[i]
		var item := [park.seat_pos[i], az, zone, rng.next_float(), rng]
		var near_row := tier == 0 and ((zone == Zone.BEHIND_HOME and row < 8) or (row < 4 and absf(az) >= dug.x and absf(az) <= dug.y))
		if near_row:
			near_items.append(item)
		elif tier == 0 and zone != Zone.OUTFIELD:
			mid_items.append(item)
		else:
			far_items.append(item)
	# The cheering stages: a cheer leader and two cheerleaders on each.
	for side: float in [1.0, -1.0]:
		var at := park.stage_spot(side)
		if at.is_finite():
			for k: int in 3:
				var spot := at + Vector3(0.0, 0.0, 0.0) + _across(at, (k - 1) * 0.9)
				near_items.append([spot, rad_to_deg(atan2(Field.to_field(at).x, Field.to_field(at).y)), Zone.STAGE, rng.next_float(), rng])
			_build_stage(at)
	_fill(near, near_items)
	_fill(mid, mid_items)
	_fill(far, far_items)
	counts = Vector3i(near.instance_count, mid.instance_count, far.instance_count)
	_add_instance(near, mesh_material, "NearCrowd")
	_add_instance(mid, mesh_material, "MidCrowd")
	_add_instance(far, flat_material, "FarCrowd")
	_materials = [mesh_material, flat_material]
	_push()


## How full a zone is next to the park as a whole: the cheering sections and the seats behind
## home fill first, the upper tiers and the outfield last.
static func _zone_fill(zone: int) -> float:
	match zone:
		Zone.HOME_CHEER, Zone.AWAY_CHEER:
			return 1.35
		Zone.BEHIND_HOME:
			return 1.15
		Zone.UPPER, Zone.OUTFIELD:
			return 0.75
	return 1.0


## Who wears what: in the cheering sections mostly the club's shirt; on that side of the park
## more of it than not; elsewhere a mix.
func _shirt(zone: int, rng: Rng) -> Color:
	var home_share := 0.25
	var away_share := 0.2
	match zone:
		Zone.HOME_CHEER:
			home_share = 0.8
			away_share = 0.03
		Zone.AWAY_CHEER:
			home_share = 0.05
			away_share = 0.75
		Zone.FIRST:
			home_share = 0.45
			away_share = 0.1
		Zone.THIRD:
			home_share = 0.15
			away_share = 0.4
		Zone.STAGE:
			return Color(0.95, 0.25, 0.4) if rng.chance(0.5) else Color(0.98, 0.98, 0.98)
	var roll := rng.next_float()
	if roll < home_share:
		return home_colours[rng.next_int(home_colours.size())]
	if roll < home_share + away_share:
		return away_colours[rng.next_int(away_colours.size())]
	return CASUAL[rng.next_int(CASUAL.size())]


func _fill(mm: MultiMesh, items: Array) -> void:
	mm.instance_count = items.size()
	for i: int in items.size():
		var it: Array = items[i]
		var at: Vector3 = it[0]
		var zone: int = it[2]
		var rng: Rng = it[4]
		# Facing home plate.
		var home := Field.to_world(Vector3.ZERO)
		var d := Vector3(home.x - at.x, 0.0, home.z - at.z).normalized()
		var yaw := atan2(-d.x, -d.z)
		var size := rng.next_range(0.92, 1.06)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), at))
		var skin := clampf(rng.next_normal() * 0.12 + 0.25, 0.0, 1.0)
		var shirt := _shirt(zone, rng)
		mm.set_instance_color(i, Color(shirt.r, shirt.g, shirt.b, skin))
		var stick := 1.0 if (zone == Zone.HOME_CHEER or zone == Zone.AWAY_CHEER) and rng.chance(0.8) else 0.0
		mm.set_instance_custom_data(i, Color(float(it[3]), float(zone), stick, rng.next_float() * rng.next_float()))


static func _multimesh(mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	return mm


func _add_instance(mm: MultiMesh, material: ShaderMaterial, node_name: String) -> void:
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.material_override = material
	# No shadows from the crowd: drawn again in each of the sun's cascades they cost a fifth of
	# the frame, and in the stands, under the roofs and upper tiers, they hardly show.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _material(flat: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER) as Shader
	m.set_shader_parameter("cutout", flat)
	if flat:
		m.set_shader_parameter("atlas", cutout_atlas())
	return m


## A sideways step of `metres` along the front of the stands at `at`.
static func _across(at: Vector3, metres: float) -> Vector3:
	var f := Field.to_field(at)
	var side := Vector2(f.y, -f.x).normalized() * metres
	return Field.to_world(Vector3(side.x, side.y, 0.0)) - Field.to_world(Vector3.ZERO)


func _build_stage(at: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(4.2, 0.6, 2.2)
	var stage := MeshInstance3D.new()
	stage.name = "CheerStage"
	stage.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.12, 0.2)
	stage.material_override = m
	add_child(stage)
	var home := Field.to_world(Vector3.ZERO)
	stage.look_at_from_position(at + Vector3.DOWN * 0.3, Vector3(home.x, at.y - 0.3, home.z), Vector3.UP)


# --- What the crowd does ---


## Sets what a zone is doing (State).
func set_zone(zone: int, state: int) -> void:
	if _states[zone] != float(state):
		_states[zone] = float(state)
		_push()


func zone_state(zone: int) -> int:
	return int(_states[zone])


## Moves the cheering on by `delta` seconds.
func tick(delta: float) -> void:
	_beat += delta * BEATS_PER_SECOND
	for m: ShaderMaterial in _materials:
		m.set_shader_parameter("beat", _beat)


func _push() -> void:
	for m: ShaderMaterial in _materials:
		m.set_shader_parameter("zone_state", _states)


# --- The meshes ---


## Seated person, some 600 triangles: legs bent at the seat, hands on the thighs, a cheering
## stick folded in the right hand (the shader shows it only for those who have one).
static func _person_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		# Thigh then shin: hip forward to the knee, down to the foot.
		_limb(tool, Vector3(side * 0.1, 0.45, 0.0), Vector3(side * 0.11, 0.47, -0.42), 0.075, 0.0, 0.0, 0.5)
		_limb(tool, Vector3(side * 0.11, 0.47, -0.42), Vector3(side * 0.11, 0.04, -0.48), 0.06, 0.0, 0.5, 1.0)
		# Upper arm down the side, forearm to the hand on the thigh.
		_limb(tool, Vector3(side * 0.2, 0.92, 0.0), Vector3(side * 0.22, 0.66, -0.06), 0.05, 3.0, 0.0, 0.45)
		_limb(tool, Vector3(side * 0.22, 0.66, -0.06), Vector3(side * 0.15, 0.55, -0.27), 0.045, 4.0, 0.45, 1.0)
	_limb(tool, Vector3(0.15, 0.55, -0.27), Vector3(0.15, 0.95, -0.3), 0.02, 5.0, 0.0, 1.0)
	_limb(tool, Vector3(0.0, 0.43, 0.02), Vector3(0.0, 0.96, 0.0), 0.17, 1.0, 0.0, 1.0)
	_ball(tool, Vector3(0.0, 1.09, -0.01), 0.105, 2.0, false)
	_ball(tool, Vector3(0.0, 1.12, 0.0), 0.11, 6.0, true)
	tool.generate_normals()
	return tool.commit()


## Mid-distance figure, some 60 triangles: boxes for the body, head, legs and arms.
static func _doll_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(tool, Vector3(0.0, 0.7, 0.0), Vector3(0.36, 0.52, 0.22), 1.0, 0.5)
	_box(tool, Vector3(0.0, 1.08, 0.0), Vector3(0.2, 0.22, 0.2), 2.0, 0.5)
	_box(tool, Vector3(0.0, 0.42, -0.22), Vector3(0.32, 0.14, 0.44), 0.0, 0.3)
	_box(tool, Vector3(0.0, 0.22, -0.44), Vector3(0.3, 0.42, 0.12), 0.0, 0.8)
	for side: float in [-1.0, 1.0]:
		_box(tool, Vector3(side * 0.22, 0.72, -0.06), Vector3(0.09, 0.4, 0.1), 4.0, 0.6)
	tool.generate_normals()
	return tool.commit()


static func _limb(tool: SurfaceTool, a: Vector3, b: Vector3, radius: float, part: float, along_a: float, along_b: float) -> void:
	const SIDES := 8
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := axis.cross(u)
	for k: int in SIDES:
		var t0 := TAU * k / SIDES
		var t1 := TAU * (k + 1) / SIDES
		var o0 := (u * cos(t0) + w * sin(t0)) * radius
		var o1 := (u * cos(t1) + w * sin(t1)) * radius
		var corners: Array[Vector3] = [a + o0, b + o0, b + o1, a + o0, b + o1, a + o1]
		var alongs: Array[float] = [along_a, along_b, along_b, along_a, along_b, along_a]
		for i: int in 6:
			tool.set_uv2(Vector2(part, alongs[i]))
			tool.add_vertex(corners[i])
	# Caps.
	for k: int in SIDES:
		var t0 := TAU * k / SIDES
		var t1 := TAU * (k + 1) / SIDES
		for end: Array in [[a, along_a], [b, along_b]]:
			var c: Vector3 = end[0]
			tool.set_uv2(Vector2(part, float(end[1])))
			tool.add_vertex(c)
			tool.set_uv2(Vector2(part, float(end[1])))
			tool.add_vertex(c + (u * cos(t0) + w * sin(t0)) * radius)
			tool.set_uv2(Vector2(part, float(end[1])))
			tool.add_vertex(c + (u * cos(t1) + w * sin(t1)) * radius)


static func _ball(tool: SurfaceTool, centre: Vector3, radius: float, part: float, top_only: bool) -> void:
	const RINGS := 6
	const SEGMENTS := 10
	var last_ring := RINGS / 2 if top_only else RINGS
	for r: int in last_ring:
		var p0 := PI * r / RINGS
		var p1 := PI * (r + 1) / RINGS
		for s: int in SEGMENTS:
			var q0 := TAU * s / SEGMENTS
			var q1 := TAU * (s + 1) / SEGMENTS
			var pt := func(p: float, q: float) -> Vector3:
				return centre + Vector3(sin(p) * cos(q), cos(p), sin(p) * sin(q)) * radius
			var corners: Array[Vector3] = [pt.call(p0, q0), pt.call(p1, q0), pt.call(p1, q1), pt.call(p0, q0), pt.call(p1, q1), pt.call(p0, q1)]
			for c: Vector3 in corners:
				tool.set_uv2(Vector2(part, 0.5))
				tool.add_vertex(c)


static func _box(tool: SurfaceTool, centre: Vector3, size: Vector3, part: float, along: float) -> void:
	var h := size * 0.5
	var faces: Array = [
		[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
		[Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)],
		[Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)],
		[Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)],
		[Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)],
	]
	for f: Array in faces:
		var q: Array[Vector3] = []
		for corner: Vector3 in f:
			q.append(centre + corner * h)
		for idx: int in [0, 1, 2, 0, 2, 3]:
			tool.set_uv2(Vector2(part, along))
			tool.add_vertex(q[idx])


## The far crowd's picture: two frames side by side, seated and arms up. Red is the shirt,
## green the skin, blue the hair; alpha where there is anyone.
static func cutout_atlas() -> ImageTexture:
	var image := Image.create(128, 128, true, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for frame: int in 2:
		var ox := frame * 64
		for x: int in 64:
			for y: int in 128:
				var c := Color(0, 0, 0, 0)
				var head := Vector2(x - 32, y - 30).length() < 12.0
				var hair := head and y < 26
				var torso := x >= 18 and x <= 46 and y >= 44 and y <= 96
				var legs := x >= 20 and x <= 44 and y > 96 and y <= 124
				var arms_down := (x >= 11 and x <= 18 or x >= 46 and x <= 53) and y >= 46 and y <= 86
				var hands_down := (x >= 11 and x <= 18 or x >= 46 and x <= 53) and y > 86 and y <= 92
				var arms_up := (x >= 9 and x <= 16 or x >= 48 and x <= 55) and y >= 8 and y <= 48
				var hands_up := (x >= 9 and x <= 16 or x >= 48 and x <= 55) and y >= 1 and y < 8
				var arm := arms_down if frame == 0 else arms_up
				var hand := hands_down if frame == 0 else hands_up
				if hair:
					c = Color(0, 0, 1, 1)
				elif head or hand:
					c = Color(0, 1, 0, 1)
				elif torso or arm:
					c = Color(1, 0, 0, 1)
				elif legs:
					c = Color(0.25, 0, 0.15, 1)
				image.set_pixel(ox + x, y, c)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
