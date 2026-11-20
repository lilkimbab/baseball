class_name GreyboxField
extends Node3D
## Placeholder ballpark built from primitives: grass, infield dirt, bases, mound, foul lines
## and an outfield wall. Replaced by the stadium generator (docs/06, stage S13); until then it
## gives cameras, physics and UI something correctly sized to work against.

## Outfield fence. The same profile builds the collision model (AnalyticField), so what is
## drawn and what the ball hits always agree.
var fence := FenceProfile.symmetric(100.0, 116.0, 122.0, 2.6)

const GRASS := Color(0.16, 0.42, 0.17)
const INFIELD_GRASS := Color(0.2, 0.5, 0.2)
const DIRT := Color(0.62, 0.42, 0.26)
const WALL := Color(0.05, 0.2, 0.15)
const CHALK := Color(0.95, 0.95, 0.95)


## Collision model built from the same fence, so drawing and physics agree.
var collision: AnalyticField


func _ready() -> void:
	collision = AnalyticField.create(fence)
	_surface = _make_surface_material()
	_build_ground()
	_build_infield()
	_build_foul_lines()
	_build_wall()
	_build_bowl()


var _surface: ShaderMaterial


## One noise texture shared by anything that wants fine surface variation.
static func grain_texture(as_normal: bool) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_octaves = 4
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	texture.generate_mipmaps = true
	texture.as_normal_map = as_normal
	texture.bump_strength = 5.0
	texture.noise = noise
	return texture


func _make_surface_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://stadium/field.gdshader") as Shader
	material.set_shader_parameter("grain", grain_texture(false))
	material.set_shader_parameter("grain_normal", grain_texture(true))
	var distances := PackedFloat32Array()
	for degree: int in 91:
		distances.append(fence.distance_at(-45.0 + float(degree)))
	material.set_shader_parameter("fence_dist", distances)
	return material


func _material(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


## Adds a mesh at a field-space position. yaw is a rotation about the vertical axis.
func _add(mesh: Mesh, color: Color, at: Vector3, yaw: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(color)
	mi.position = Field.to_world(at)
	mi.rotation.y = yaw
	add_child(mi)
	return mi


## The whole playing surface is one plane; the shader draws grass, dirt and chalk on it.
func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(520.0, 520.0)
	_add(plane, GRASS, Vector3(0.0, 60.0, 0.0)).material_override = _surface


func _build_infield() -> void:
	var mound := CylinderMesh.new()
	mound.top_radius = 1.2
	mound.bottom_radius = Field.MOUND_RADIUS
	mound.height = Field.MOUND_HEIGHT
	_add(mound, DIRT, Vector3(0.0, Field.MOUND_CENTER_Y, Field.MOUND_HEIGHT * 0.5)).material_override = _surface
	var rubber := BoxMesh.new()
	rubber.size = Vector3(0.61, 0.03, 0.15)
	_add(rubber, CHALK, Vector3(0.0, Field.RUBBER_Y + 0.075, Field.MOUND_HEIGHT + 0.015))

	var base := BoxMesh.new()
	base.size = Vector3(0.457, 0.08, 0.457)
	var bases: Array[Vector3] = [Field.FIRST_BASE, Field.SECOND_BASE, Field.THIRD_BASE]
	for b: Vector3 in bases:
		_add(base, CHALK, b + Vector3(0.0, 0.0, 0.04), PI / 4.0)
	var plate := BoxMesh.new()
	plate.size = Vector3(Field.PLATE_WIDTH, 0.02, Field.PLATE_FRONT_Y)
	_add(plate, CHALK, Vector3(0.0, Field.PLATE_FRONT_Y * 0.5, 0.01))


func _build_foul_lines() -> void:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.08
	pole.bottom_radius = 0.08
	pole.height = 12.0
	var corner := fence.distance_at(45.0) / sqrt(2.0)
	_add(pole, Color(0.95, 0.85, 0.1), Vector3(corner, corner, 6.0))
	_add(pole, Color(0.95, 0.85, 0.1), Vector3(-corner, corner, 6.0))


func _build_wall() -> void:
	const SEGMENTS := 60
	var step_deg := 90.0 / SEGMENTS
	for i: int in SEGMENTS:
		var az_deg := -45.0 + step_deg * (float(i) + 0.5)
		var a := deg_to_rad(az_deg)
		var d := fence.distance_at(az_deg)
		var h := fence.height_at(az_deg)
		var seg := BoxMesh.new()
		seg.size = Vector3(d * deg_to_rad(step_deg) * 1.1, h, 0.4)
		_add(seg, WALL, Vector3((d + 0.2) * sin(a), (d + 0.2) * cos(a), h * 0.5), -a)
		var rail := BoxMesh.new()
		rail.size = Vector3(seg.size.x, 0.12, 0.44)
		_add(rail, Color(0.95, 0.8, 0.12), Vector3((d + 0.2) * sin(a), (d + 0.2) * cos(a), h + 0.06), -a)


## Placeholder seating bowl: a wall along the edge of the field all the way round and a
## sloping bank of stands behind it. It closes off the horizon and gives the cameras a
## backdrop until the real stands and crowd arrive (stages S13 and S14).
func _build_bowl() -> void:
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stands := SurfaceTool.new()
	stands.begin(Mesh.PRIMITIVE_TRIANGLES)
	const STEP := 2.0
	var count := roundi(360.0 / STEP)
	for i: int in count:
		var az0 := -180.0 + STEP * i
		var az1 := az0 + STEP
		var outfield := absf(az0 + STEP * 0.5) <= 45.0
		var lip := 2.6 if outfield else 3.2
		var depth := 20.0 if outfield else 32.0
		var rise := 9.0 if outfield else 17.0
		var a := _rim(az0, 0.0, 0.0)
		var b := _rim(az1, 0.0, 0.0)
		var a_top := _rim(az0, 0.0, lip)
		var b_top := _rim(az1, 0.0, lip)
		if not outfield:
			_quad(wall, a, b, b_top, a_top)
		_quad(stands, _rim(az0, 0.6, lip), _rim(az1, 0.6, lip), _rim(az1, depth, lip + rise), _rim(az0, depth, lip + rise))
		_quad(stands, _rim(az0, depth, lip + rise), _rim(az1, depth, lip + rise), _rim(az1, depth, 0.0), _rim(az0, depth, 0.0))
	wall.generate_normals()
	stands.generate_normals()

	var wall_material := _material(Color(0.12, 0.36, 0.5), 0.8)
	wall_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wall_node := MeshInstance3D.new()
	wall_node.mesh = wall.commit()
	wall_node.material_override = wall_material
	add_child(wall_node)

	# Seats seen from far away: a blue-grey bank broken up with noise.
	var seats := _material(Color(0.36, 0.42, 0.52), 0.9)
	seats.cull_mode = BaseMaterial3D.CULL_DISABLED
	seats.albedo_texture = grain_texture(false)
	seats.uv1_triplanar = true
	seats.uv1_scale = Vector3.ONE * 0.6
	var stands_node := MeshInstance3D.new()
	stands_node.mesh = stands.commit()
	stands_node.material_override = seats
	add_child(stands_node)


## World-space point on the edge of the field at an azimuth, pushed outward and raised.
func _rim(az_deg: float, outward: float, height: float) -> Vector3:
	var radius := collision.boundary_distance(az_deg) + 0.25 + outward
	var a := deg_to_rad(az_deg)
	return Field.to_world(Vector3(radius * sin(a), radius * cos(a), height))


static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for corner: Vector3 in [a, b, c, a, c, d] as Array[Vector3]:
		tool.add_vertex(corner)
