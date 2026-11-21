class_name StadiumBuilder
extends Node3D
## Builds a ballpark from its definition (docs/06 6.2, docs/13 S13): the playing surface and
## its markings, the infield, the fence with its padding, yellow line and distance signs, the
## foul poles and their screens, the backstop and its net, the dugouts, the bullpens, the
## batter's eye and the stands. The physics' collision model comes from the same definition,
## so what is drawn is what the ball hits.

const GRASS := Color(0.16, 0.42, 0.17)
const CHALK := Color(0.95, 0.95, 0.95)
const POLE_YELLOW := Color(0.98, 0.84, 0.1)
const DIRT := Color(0.56, 0.38, 0.24)
## Seats: rows of this depth (m) rising by depth × tan(rake); every AISLE_EVERY m of arc a
## stairway.
const ROW_DEPTH := 0.85
const AISLE_EVERY := 14.0
const AISLE_WIDTH := 1.4
## The wall along foul ground in front of the first row, and how high above the field the
## lower tier starts.
const FRONT_WALL := 1.3
const LOWER_LIP := 3.2
## Dugouts: from FROM to TO m along the line from home, sunk this far below the field.
const DUGOUT_FROM := 9.0
const DUGOUT_TO := 27.0
const DUGOUT_DEPTH := 3.2
const DUGOUT_SINK := 0.8
const DUGOUT_ROOF := 1.3
## The batter's eye covers centre field this many degrees either side, this high (m).
const EYE_HALF_DEG := 7.0
const EYE_HEIGHT := 14.0
## Foul poles stand this high (m) above the ground.
const POLE_HEIGHT := 16.0
## The scoreboard's screen (m); ad boards are AD_LENGTH m long, AD_SLOTS of them to a strip.
const SCREEN_SIZE := Vector2(28.0, 12.0)
const AD_LENGTH := 7.0
const AD_SLOTS := 8
## One person a seat this wide (m); the cheering sections run from CHEER_FROM to CHEER_TO
## degrees round from centre field, their first CHEER_ROWS rows.
const SEAT_PITCH := 0.5
const CHEER_FROM := 70.0
const CHEER_TO := 115.0
const CHEER_ROWS := 22
## Seats this far round (degrees from centre field) or more are behind home.
const BEHIND_HOME_FROM := 140.0

var def: StadiumDef
var fence: FenceProfile
## Collision model built from the same definition, so drawing and physics agree.
var collision: AnalyticField

var _surface: ShaderMaterial
var _rng := Rng.new(7)
var _lamp: StandardMaterial3D
## The suites' glass and the city's windows light up with the towers; the flags' cloth.
var _glass: StandardMaterial3D
## The world beyond the stands (null under a dome).
var backdrop: Backdrop
var _flags: ShaderMaterial
var _flag_spots: Array[Vector3] = []
## The scoreboard's screen: whatever is put in this viewport shows on it (MatchScene draws
## the game on it, docs/13 S13-6).
var scoreboard: SubViewport
## Every seat, as the stands are laid out (for the crowd, docs/13 S14): where it is (world),
## its azimuth, row, tier (0 lower, 1 upper) and zone (Crowd.Zone).
var seat_pos := PackedVector3Array()
var seat_az := PackedFloat32Array()
var seat_row := PackedInt32Array()
var seat_tier := PackedByteArray()
var seat_zone := PackedByteArray()
## Ad boards along the wall behind home and the upper tier's front, made as the stands are.
var _ads: SurfaceTool
var _ads_along := 0.0


func _init(park: StadiumDef = null) -> void:
	def = park


func _ready() -> void:
	if def == null:
		def = StadiumDef.standard()
	fence = def.fence()
	collision = def.analytic()
	_surface = _make_surface_material()
	_build_ground()
	_build_infield()
	_build_fence()
	_build_poles()
	_build_backstop()
	_build_dugouts()
	_build_bullpens()
	_build_batters_eye()
	_build_stands()
	_build_surroundings()
	_build_scoreboard()
	_build_ads()
	if def.roof == &"dome":
		_build_dome()
	else:
		_build_light_towers()


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
	material.set_shader_parameter("line_half_width", Field.LINE_WIDTH * 0.5)
	var distances := PackedFloat32Array()
	for degree: int in 91:
		distances.append(fence.distance_at(-45.0 + float(degree)))
	material.set_shader_parameter("fence_dist", distances)
	material.set_shader_parameter("mow", int(def.mow))
	material.set_shader_parameter("turf", 1.0 if def.surface == &"turf" else 0.0)
	if SurfaceLibrary.has("grass") and SurfaceLibrary.has("dirt"):
		material.set_shader_parameter("grass_tex", SurfaceLibrary.texture("grass", "color"))
		material.set_shader_parameter("grass_nrm", SurfaceLibrary.texture("grass", "normal"))
		material.set_shader_parameter("dirt_tex", SurfaceLibrary.texture("dirt", "color"))
		material.set_shader_parameter("dirt_nrm", SurfaceLibrary.texture("dirt", "normal"))
		material.set_shader_parameter("gravel_tex", SurfaceLibrary.texture("gravel", "color"))
		material.set_shader_parameter("detail", 1.0)
	if def.surface == &"turf":
		material.set_shader_parameter("grass_light", Color(0.13, 0.4, 0.17))
		material.set_shader_parameter("grass_dark", Color(0.11, 0.35, 0.15))
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


func _node(mesh: Mesh, material: Material, node_name: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	if node_name != "":
		mi.name = node_name
	# Readable names for the repeats (Dugout, Dugout2), so the parts can be found.
	add_child(mi, true)
	return mi


## A point at azimuth az (degrees, 0 centre field, + right) and distance r from home.
static func at_az(az_deg: float, r: float, height: float = 0.0) -> Vector3:
	var a := deg_to_rad(az_deg)
	return Vector3(r * sin(a), r * cos(a), height)


## World-space point on the edge of the field at an azimuth, pushed outward and raised.
func _rim(az_deg: float, outward: float, height: float) -> Vector3:
	return Field.to_world(at_az(az_deg, collision.boundary_distance(az_deg) + 0.25 + outward, height))


static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for corner: Vector3 in [a, b, c, a, c, d] as Array[Vector3]:
		tool.add_vertex(corner)


static func _quad_uv(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv_a: Vector2, uv_c: Vector2) -> void:
	var uv_b := Vector2(uv_c.x, uv_a.y)
	var uv_d := Vector2(uv_a.x, uv_c.y)
	var corners: Array[Vector3] = [a, b, c, a, c, d]
	var uvs: Array[Vector2] = [uv_a, uv_b, uv_c, uv_a, uv_c, uv_d]
	for i: int in 6:
		tool.set_uv(uvs[i])
		tool.add_vertex(corners[i])


static func _is_fair(az_deg: float) -> bool:
	return absf(az_deg) <= 45.0


# --- The playing surface ---


## The ground: one surface out to the walls (further behind the outfield fence, where the
## bullpens are), drawn by the field shader. The dugouts sink below it, so it stops at the
## walls rather than running on under the stands.
func _build_ground() -> void:
	const STEPS := 360
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Field.to_world(Vector3(0.0, 30.0, 0.0))
	var ring := PackedVector3Array()
	for i: int in STEPS:
		var az := -180.0 + 360.0 * i / STEPS
		var reach := collision.boundary_distance(az) + 0.3
		if absf(az) < 46.0:
			reach += def.outfield_setback + 1.0
		ring.append(Field.to_world(at_az(az, reach)))
	for i: int in STEPS:
		tool.add_vertex(centre)
		tool.add_vertex(ring[i])
		tool.add_vertex(ring[(i + 1) % STEPS])
	tool.generate_normals()
	var ground := _node(tool.commit(), _surface, "Ground")
	ground.mesh.surface_set_material(0, _surface)
	# Fan triangles may face down from here: draw both sides.
	ground.material_override = _surface
	_surface.render_priority = 0


func _build_infield() -> void:
	_build_mound(Vector2(0.0, Field.MOUND_CENTER_Y), 0.0, _surface)
	# Pitcher's plate: 24 by 6 inches, its front edge 60 ft 6 in from the apex of home plate.
	var rubber := BoxMesh.new()
	rubber.size = Vector3(0.6096, 0.03, 0.1524)
	_add(rubber, CHALK, Vector3(0.0, Field.RUBBER_Y + 0.0762, Field.MOUND_HEIGHT + 0.005))
	var base := BoxMesh.new()
	base.size = Vector3(Field.BASE_SIZE, Field.BASE_THICKNESS, Field.BASE_SIZE)
	for number: int in [1, 2, 3] as Array[int]:
		_add(base, CHALK, Field.base_centre(number) + Vector3(0.0, 0.0, Field.BASE_THICKNESS * 0.5), PI / 4.0)
	_build_plate(Vector2.ZERO, 0.0)


## Home plate: a five-sided slab of white rubber set level with the ground, at `at` facing
## `yaw` (the bullpens have their own).
func _build_plate(at: Vector2, yaw: float) -> void:
	const RISE := 0.012
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline := Field.PLATE_OUTLINE
	var count := outline.size()
	var turn := Transform2D(yaw, at)
	var middle := turn * Vector2(0.0, 0.25)
	for i: int in count:
		var a := turn * outline[i]
		var b := turn * outline[(i + 1) % count]
		for corner: Vector3 in [Vector3(middle.x, middle.y, RISE), Vector3(a.x, a.y, RISE), Vector3(b.x, b.y, RISE), Vector3(a.x, a.y, RISE), Vector3(a.x, a.y, 0.0), Vector3(b.x, b.y, RISE), Vector3(b.x, b.y, RISE), Vector3(a.x, a.y, 0.0), Vector3(b.x, b.y, 0.0)] as Array[Vector3]:
			tool.add_vertex(Field.to_world(corner))
	tool.generate_normals()
	var rubber := _material(CHALK, 0.7)
	rubber.cull_mode = BaseMaterial3D.CULL_DISABLED
	_node(tool.commit(), rubber)


## A mound as a surface over Field.ground_height() (the regulation shape), centred at
## `centre` and turned by `yaw` for the bullpens: rings round the centre of its circle.
func _build_mound(centre: Vector2, yaw: float, material: Material) -> void:
	const RINGS := 26
	const SPOKES := 72
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(0)
	var turn := Transform2D(yaw, centre - Vector2(0.0, Field.MOUND_CENTER_Y).rotated(yaw))
	var middle := turn * Vector2(0.0, Field.MOUND_CENTER_Y)
	tool.add_vertex(Field.to_world(Vector3(middle.x, middle.y, Field.ground_height(0.0, Field.MOUND_CENTER_Y))))
	for ring: int in range(1, RINGS + 1):
		var radius := Field.MOUND_RADIUS * ring / RINGS
		for spoke: int in SPOKES:
			var angle := TAU * spoke / SPOKES
			var x := sin(angle) * radius
			var y := Field.MOUND_CENTER_Y + cos(angle) * radius
			# The rim dips just under the field so there is no seam where the two meet.
			var z := Field.ground_height(x, y) if ring < RINGS else -0.01
			var p := turn * Vector2(x, y)
			tool.add_vertex(Field.to_world(Vector3(p.x, p.y, z)))
	for spoke: int in SPOKES:
		var next := (spoke + 1) % SPOKES
		# Clockwise seen from above, which is the side Godot draws.
		tool.add_index(0)
		tool.add_index(1 + spoke)
		tool.add_index(1 + next)
		for ring: int in range(1, RINGS):
			var inner := 1 + (ring - 1) * SPOKES
			var outer := 1 + ring * SPOKES
			tool.add_index(inner + spoke)
			tool.add_index(outer + spoke)
			tool.add_index(inner + next)
			tool.add_index(inner + next)
			tool.add_index(outer + spoke)
			tool.add_index(outer + next)
	tool.generate_normals()
	var mound := _node(tool.commit(), material, "Mound")
	mound.material_override = material


# --- The fence ---


## Padded panels with seams between them, darker toward the bottom, for the fence's face.
static func pad_texture(colour: Color) -> ImageTexture:
	var image := Image.create(64, 64, true, Image.FORMAT_RGBA8)
	for x: int in 64:
		for y: int in 64:
			var seam := 1.0 if x < 2 or x > 61 else 0.0
			var bulge := 1.0 - pow(absf(x - 31.5) / 31.5, 4.0) * 0.18
			var shade := lerpf(0.85, 1.05, float(y) / 63.0) * bulge * (1.0 - 0.45 * seam)
			image.set_pixel(x, 63 - y, Color(colour.r * shade, colour.g * shade, colour.b * shade))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## The outfield fence: padded panels 1.5 m wide, the yellow home-run line along the top, and
## the distance to it in metres at the lines, the alleys and centre (docs/13 S13-3).
func _build_fence() -> void:
	const STEPS := 180
	var face := SurfaceTool.new()
	face.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	for i: int in STEPS:
		var az0 := -45.0 + 90.0 * i / STEPS
		var az1 := -45.0 + 90.0 * (i + 1) / STEPS
		var d0 := fence.distance_at(az0)
		var d1 := fence.distance_at(az1)
		var h0 := fence.height_at(az0)
		var h1 := fence.height_at(az1)
		var span := at_az(az0, d0).distance_to(at_az(az1, d1))
		var a := Field.to_world(at_az(az0, d0))
		var b := Field.to_world(at_az(az1, d1))
		var a_top := Field.to_world(at_az(az0, d0, h0))
		var b_top := Field.to_world(at_az(az1, d1, h1))
		_quad_uv(face, a, b, b_top, a_top, Vector2(along / 1.5, 0.0), Vector2((along + span) / 1.5, maxf(h0, h1) / 2.6))
		# Back of the wall and its top, 0.4 m thick.
		var a_back := Field.to_world(at_az(az0, d0 + 0.4, h0))
		var b_back := Field.to_world(at_az(az1, d1 + 0.4, h1))
		_quad_uv(face, b, a, Field.to_world(at_az(az0, d0 + 0.4)), Field.to_world(at_az(az1, d1 + 0.4)), Vector2.ZERO, Vector2.ONE)
		_quad(top, a_top, b_top, b_back + Vector3.UP * 0.12, a_back + Vector3.UP * 0.12)
		_quad(top, a_top, a_top + Vector3.UP * 0.12, b_top + Vector3.UP * 0.12, b_top)
		along += span
	face.generate_normals()
	top.generate_normals()
	var pads := _material(Color.WHITE, 0.7)
	# Padded vinyl: a fine grain, a soft sheen.
	SurfaceLibrary.dress(pads, "leather", 1.6, 0.5)
	pads.albedo_texture = pad_texture(def.wall_color)
	pads.cull_mode = BaseMaterial3D.CULL_DISABLED
	_node(face.commit(), pads, "Fence")
	var line := _material(POLE_YELLOW, 0.6)
	line.cull_mode = BaseMaterial3D.CULL_DISABLED
	_node(top.commit(), line, "HomeRunLine")
	for az: float in [-45.0, -22.5, 0.0, 22.5, 45.0]:
		var d := fence.distance_at(az)
		var sign := Label3D.new()
		sign.text = str(roundi(d))
		sign.font_size = 160
		sign.pixel_size = 0.006
		sign.outline_size = 0
		sign.modulate = Color(0.97, 0.97, 0.95)
		sign.shaded = true
		sign.double_sided = false
		var inset := 1.6 if absf(az) > 44.0 else 0.0
		var spot := at_az(az - signf(az) * inset, fence.distance_at(az - signf(az) * inset) - 0.03, fence.height_at(az) * 0.55)
		sign.position = Field.to_world(spot)
		sign.rotation.y = -deg_to_rad(az - signf(az) * inset)
		sign.visibility_range_end = 260.0
		add_child(sign)


# --- Poles, backstop, dugouts, bullpens, batter's eye ---


## Foul poles at the ends of the fence, with a screen down their fair side.
func _build_poles() -> void:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.09
	pole.bottom_radius = 0.11
	pole.height = POLE_HEIGHT
	var screen := _material(Color(POLE_YELLOW, 0.55), 0.7)
	screen.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	screen.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side: float in [-1.0, 1.0]:
		var d := fence.distance_at(45.0 * side)
		_add(pole, POLE_YELLOW, at_az(45.0 * side, d + 0.1, POLE_HEIGHT * 0.5))
		var h := fence.height_at(45.0 * side)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.5, POLE_HEIGHT - h, 0.02)
		var spot := at_az(45.0 * side, d + 0.1) + Vector3(-side * 0.32, -0.32, h + (POLE_HEIGHT - h) * 0.5) * Vector3(0.7071, 0.7071, 1.0)
		var wing := _node(mesh, screen)
		wing.position = Field.to_world(spot)
		wing.rotation.y = -deg_to_rad(45.0 * side) + PI * 0.5


## A net seen as a fine grid that fades to a haze at a distance.
static func net_material() -> StandardMaterial3D:
	var image := Image.create(32, 32, true, Image.FORMAT_RGBA8)
	for x: int in 32:
		for y: int in 32:
			var wire := x < 2 or y < 2
			image.set_pixel(x, y, Color(0.12, 0.12, 0.13, 0.85 if wire else 0.0))
	image.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(image)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## The azimuth on the boundary level with `along` m down the first-base line (−: third).
func _line_az(along: float, side: float) -> float:
	var on_line := Vector2(along, along) * 0.7071
	var lo := 45.0
	var hi := 180.0
	# The boundary point straight out from the line: bisect on the azimuth.
	for i: int in 30:
		var mid := (lo + hi) * 0.5
		var p := at_az(mid, collision.boundary_distance(mid))
		var rel := Vector2(p.x, p.y) - on_line
		if rel.dot(Vector2(0.7071, 0.7071)) > 0.0:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5 * side


## The backstop's net: from behind home round to the ends of the dugouts, above the wall.
func _build_backstop() -> void:
	const HIGH := 8.0
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var reach := absf(_line_az(DUGOUT_FROM, 1.0))
	var steps := 90
	var along := 0.0
	for i: int in steps:
		var az0 := reach + (360.0 - 2.0 * reach) * i / steps
		var az1 := reach + (360.0 - 2.0 * reach) * (i + 1) / steps
		var a := _rim(az0, 0.0, FRONT_WALL)
		var b := _rim(az1, 0.0, FRONT_WALL)
		var span := a.distance_to(b)
		_quad_uv(tool, a, b, b + Vector3.UP * HIGH, a + Vector3.UP * HIGH, Vector2(along * 10.0, 0.0), Vector2((along + span) * 10.0, HIGH * 10.0))
		along += span
	_node(tool.commit(), net_material(), "BackstopNet")


## The dugouts along the lines, set into the wall with their floors below the field.
func _build_dugouts() -> void:
	var inside := _material(Color(0.2, 0.21, 0.24), 0.85)
	SurfaceLibrary.dress(inside, "concrete", 3.0, 0.9, true)
	inside.cull_mode = BaseMaterial3D.CULL_DISABLED
	var trim := _material(def.wall_color.lightened(0.1), 0.7)
	trim.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side: float in [-1.0, 1.0]:
		var az0 := _line_az(DUGOUT_FROM, side)
		var az1 := _line_az(DUGOUT_TO, side)
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var roof := SurfaceTool.new()
		roof.begin(Mesh.PRIMITIVE_TRIANGLES)
		const STEPS := 12
		for i: int in STEPS:
			var a0 := lerpf(az0, az1, float(i) / STEPS)
			var a1 := lerpf(az0, az1, float(i + 1) / STEPS)
			var front0 := _rim(a0, 0.0, 0.0)
			var front1 := _rim(a1, 0.0, 0.0)
			var back0 := _rim(a0, DUGOUT_DEPTH, 0.0)
			var back1 := _rim(a1, DUGOUT_DEPTH, 0.0)
			var down := Vector3.DOWN * DUGOUT_SINK
			# Floor, the step down from the field, the back wall, the roof.
			_quad(tool, front0 + down, front1 + down, back1 + down, back0 + down)
			_quad(tool, front0, front1, front1 + down, front0 + down)
			_quad(tool, back0 + down, back1 + down, back1 + Vector3.UP * DUGOUT_ROOF, back0 + Vector3.UP * DUGOUT_ROOF)
			_quad(roof, front0 + Vector3.UP * DUGOUT_ROOF, front1 + Vector3.UP * DUGOUT_ROOF, back1 + Vector3.UP * DUGOUT_ROOF, back0 + Vector3.UP * DUGOUT_ROOF)
			# Above the roof the wall goes on up to the stands.
			_quad(roof, front0 + Vector3.UP * DUGOUT_ROOF, front1 + Vector3.UP * DUGOUT_ROOF, front1 + Vector3.UP * LOWER_LIP, front0 + Vector3.UP * LOWER_LIP)
			# The bench along the back.
			var bench0 := _rim(a0, DUGOUT_DEPTH - 0.6, 0.0) + Vector3.DOWN * (DUGOUT_SINK - 0.45)
			var bench1 := _rim(a1, DUGOUT_DEPTH - 0.6, 0.0) + Vector3.DOWN * (DUGOUT_SINK - 0.45)
			_quad(tool, bench0, bench1, back1 + Vector3.DOWN * (DUGOUT_SINK - 0.45), back0 + Vector3.DOWN * (DUGOUT_SINK - 0.45))
		for end_az: float in [az0, az1]:
			var f := _rim(end_az, 0.0, 0.0)
			var b := _rim(end_az, DUGOUT_DEPTH, 0.0)
			_quad(tool, f + Vector3.DOWN * DUGOUT_SINK, b + Vector3.DOWN * DUGOUT_SINK, b + Vector3.UP * DUGOUT_ROOF, f + Vector3.UP * DUGOUT_ROOF)
		tool.generate_normals()
		roof.generate_normals()
		_node(tool.commit(), inside, "Dugout")
		_node(roof.commit(), trim, "DugoutRoof")


## Two mounds and plates for each side's relievers: behind the outfield fence, or out in
## foul ground along the lines, where they are in play.
func _build_bullpens() -> void:
	var dirt := _material(DIRT, 0.95)
	dirt.albedo_texture = grain_texture(false)
	dirt.uv1_triplanar = true
	dirt.uv1_scale = Vector3.ONE * 0.4
	for side: float in [-1.0, 1.0]:
		for lane: int in 2:
			var centre: Vector2
			var facing: float
			if def.bullpens == &"foul":
				# Along the line between the dugout and the pole, throwing toward home.
				var along := 62.0 + lane * 3.2
				var line := Vector2(along * 0.7071 * side, along * 0.7071)
				var out := Vector2(0.7071 * side, -0.7071)
				centre = line + out * 3.0
				facing = atan2(-line.x, -line.y)
			else:
				var az := 33.0 * side + lane * 4.0 * side
				var r := fence.distance_at(az) + def.outfield_setback * 0.5 + 0.4
				var p := at_az(az, r)
				centre = Vector2(p.x, p.y)
				facing = deg_to_rad(az) + (PI * 0.5 if side < 0.0 else -PI * 0.5)
			_build_mound(centre, -facing, dirt)
			var forward := Vector2(sin(facing), cos(facing))
			var plate := centre + forward * (Field.MOUND_CENTER_Y - 0.4)
			_build_plate(plate, -facing + PI)


## The batter's eye: a dark, plain face behind centre field, so the hitter sees the pitch
## against something that does not move (docs/13 S13-5).
func _build_batters_eye() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	const STEPS := 10
	for i: int in STEPS:
		var az0 := -EYE_HALF_DEG + 2.0 * EYE_HALF_DEG * i / STEPS
		var az1 := -EYE_HALF_DEG + 2.0 * EYE_HALF_DEG * (i + 1) / STEPS
		var r0 := fence.distance_at(az0) + def.outfield_setback + 0.5
		var r1 := fence.distance_at(az1) + def.outfield_setback + 0.5
		_quad(tool, Field.to_world(at_az(az0, r0)), Field.to_world(at_az(az1, r1)), Field.to_world(at_az(az1, r1, EYE_HEIGHT)), Field.to_world(at_az(az0, r0, EYE_HEIGHT)))
	tool.generate_normals()
	var eye := _material(Color(0.03, 0.06, 0.05), 0.98)
	eye.cull_mode = BaseMaterial3D.CULL_DISABLED
	_node(tool.commit(), eye, "BattersEye")


# --- Stands ---


## Whether an azimuth lies in a stand section (from > to runs through the seats behind home).
static func in_span(az: float, from_az: float, to_az: float) -> bool:
	if from_az <= to_az:
		return az >= from_az and az <= to_az
	return az >= from_az or az <= to_az


## The stands, section by section: a wall along the field, rows of seats stepping up at
## their rake with a stairway every AISLE_EVERY m, a rail along the front of each tier, the
## upper tier over the back of the lower one, and a roof over it where there is one.
func _build_stands() -> void:
	_ads = SurfaceTool.new()
	_ads.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seats := SurfaceTool.new()
	seats.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rails := SurfaceTool.new()
	rails.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roofs := SurfaceTool.new()
	roofs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := SurfaceTool.new()
	steps.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dug_from := absf(_line_az(DUGOUT_FROM, 1.0))
	var dug_to := absf(_line_az(DUGOUT_TO, 1.0))
	const STEP := 1.5
	var count := roundi(360.0 / STEP)
	for i: int in count:
		var az0 := -180.0 + STEP * i
		var az1 := az0 + STEP
		var mid := (az0 + az1) * 0.5
		for section: Dictionary in def.stands:
			if not in_span(mid, float(section["from_az"]), float(section["to_az"])):
				continue
			var fair := _is_fair(mid)
			if fair and absf(mid) < EYE_HALF_DEG + 0.5:
				continue
			var rows: Array = section.get("rows", [20])
			var rakes: Array = section.get("rake_deg", [24])
			var setback := (def.outfield_setback if fair else 0.0)
			var lip := 2.2 if fair else LOWER_LIP
			var front := 0.0 if fair else 0.6
			# The wall in front of the seats (not over a dugout's opening).
			var dugout := not fair and absf(mid) >= dug_from and absf(mid) <= dug_to
			if not fair and not dugout:
				_quad(walls, _rim(az0, 0.0, 0.0), _rim(az1, 0.0, 0.0), _rim(az1, 0.0, lip), _rim(az0, 0.0, lip))
			if fair:
				_quad(walls, _rim(az0, setback, 0.0), _rim(az1, setback, 0.0), _rim(az1, setback, lip), _rim(az0, setback, lip))
			var aisle := fmod(absf(mid) * deg_to_rad(1.0) * collision.boundary_distance(mid), AISLE_EVERY) < AISLE_WIDTH
			var out := setback + front
			var height := lip
			for tier: int in rows.size():
				var n := int(rows[tier])
				if n <= 0:
					continue
				var rise := ROW_DEPTH * tan(deg_to_rad(float(rakes[mini(tier, rakes.size() - 1)])))
				if tier == 1:
					# Behind the last row of the lower tier, under the upper one: a band of
					# glass (the suites and the press box), lit from inside at night.
					_quad(glass, _rim(az0, out, height + 0.3), _rim(az1, out, height + 0.3), _rim(az1, out, height + 2.3), _rim(az0, out, height + 2.3))
					_quad(walls, _rim(az0, out, height), _rim(az1, out, height), _rim(az1, out, height + 0.3), _rim(az0, out, height + 0.3))
					# The upper tier hangs over the back of the lower one, above a concourse;
					# its front carries a band of ads.
					out -= 6.0
					height += 4.5
					_quad(walls, _rim(az0, out, height - 2.2), _rim(az1, out, height - 2.2), _rim(az1, out, height - 1.4), _rim(az0, out, height - 1.4))
					_ad_quad(_rim(az0, out - 0.05, height - 1.4), _rim(az1, out - 0.05, height - 1.4), 1.3)
				_quad(rails, _rim(az0, out, height + 0.9), _rim(az1, out, height + 0.9), _rim(az1, out, height + 1.0), _rim(az0, out, height + 1.0))
				var berm := str(section.get("kind", "seats")) == "berm"
				for row: int in n:
					var shade := 0.97 + 0.03 * float(row % 2)
					var c := Color(0.42, 0.42, 0.44) if aisle else (def.seat_color * shade)
					if berm:
						# A grass bank to sit on: no seats, no aisles.
						c = Color(0.2, 0.42, 0.16) * shade
					var r0 := out + row * ROW_DEPTH
					var h0 := height + row * rise
					if aisle or berm:
						# Stairs, and grass banks: plain steps.
						var plain := steps if aisle else seats
						plain.set_color(c)
						plain.set_uv(Vector2(0.02, 0.98))
						_quad(plain, _rim(az0, r0, h0), _rim(az1, r0, h0), _rim(az1, r0, h0 + rise), _rim(az0, r0, h0 + rise))
						plain.set_color(c * 0.9)
						_quad(plain, _rim(az0, r0, h0 + rise), _rim(az1, r0, h0 + rise), _rim(az1, r0 + ROW_DEPTH, h0 + rise), _rim(az0, r0 + ROW_DEPTH, h0 + rise))
					else:
						# A row of seats: the riser shows their backs, the tread their
						# cushions, one seat every SEAT_PITCH metres (the seat picture's top
						# half is a back, its lower half a cushion).
						var across := deg_to_rad(STEP) * (collision.boundary_distance(mid) + r0) / SEAT_PITCH
						var u0 := floorf(float(i) * 7.3)
						seats.set_color(c)
						_quad_uv(seats, _rim(az0, r0, h0), _rim(az1, r0, h0), _rim(az1, r0, h0 + rise), _rim(az0, r0, h0 + rise), Vector2(u0, 0.5), Vector2(u0 + across, 0.0))
						_quad_uv(seats, _rim(az0, r0, h0 + rise), _rim(az1, r0, h0 + rise), _rim(az1, r0 + ROW_DEPTH, h0 + rise), _rim(az0, r0 + ROW_DEPTH, h0 + rise), Vector2(u0, 1.0), Vector2(u0 + across, 0.5))
					if not aisle and not berm:
						_add_seats(az0, STEP, r0 + ROW_DEPTH * 0.55, h0 + rise, row, tier, fair)
				out += n * ROW_DEPTH
				height += n * rise
			# The back wall, up to the roof where there is one, which it holds up.
			var roofed := bool(section.get("roof", false)) and not fair
			var lid := height + 6.0
			var top := lid + 1.0 if roofed else height + 2.5
			_quad(walls, _rim(az0, out, height), _rim(az1, out, height), _rim(az1, out, top), _rim(az0, out, top))
			_quad(walls, _rim(az0, out, top), _rim(az1, out, top), _rim(az1, out, 0.0), _rim(az0, out, 0.0))
			if roofed:
				_quad(roofs, _rim(az0, out - 18.0, lid), _rim(az1, out - 18.0, lid), _rim(az1, out + 1.0, lid + 1.0), _rim(az0, out + 1.0, lid + 1.0))
				# The roof's front edge is a deep beam, and every few metres a column stands
				# behind the last row to carry it.
				_quad(roofs, _rim(az0, out - 18.0, lid - 1.3), _rim(az1, out - 18.0, lid - 1.3), _rim(az1, out - 18.0, lid), _rim(az0, out - 18.0, lid))
				_quad(roofs, _rim(az0, out - 18.0, lid - 1.3), _rim(az1, out - 18.0, lid - 1.3), _rim(az1, out - 16.6, lid - 0.1), _rim(az0, out - 16.6, lid - 0.1))
				if i % 5 == 0:
					var half := rad_to_deg(0.28 / (collision.boundary_distance(mid) + out))
					_quad(walls, _rim(mid - half, out - 0.7, height), _rim(mid + half, out - 0.7, height), _rim(mid + half, out - 0.7, lid), _rim(mid - half, out - 0.7, lid))
					_quad(walls, _rim(mid, out - 1.0, height), _rim(mid, out - 0.4, height), _rim(mid, out - 0.4, lid), _rim(mid, out - 1.0, lid))
					# A raking strut from the column out under the roof.
					_quad(walls, _rim(mid - half, out - 0.7, lid - 5.0), _rim(mid + half, out - 0.7, lid - 5.0), _rim(mid + half, out - 9.0, lid - 0.6), _rim(mid - half, out - 9.0, lid - 0.6))
			elif fair and i % 6 == 0:
				_flag_spots.append(_rim(mid, out - 0.2, top))
	seats.generate_normals()
	walls.generate_normals()
	rails.generate_normals()
	roofs.generate_normals()
	glass.generate_normals()
	var seat_material := _material(Color.WHITE, 0.8)
	seat_material.vertex_color_use_as_albedo = true
	seat_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	seat_material.albedo_texture = seat_picture()
	seat_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_node(seats.commit(), seat_material, "Seats")
	steps.generate_normals()
	var step_material := _material(Color.WHITE, 0.9)
	step_material.vertex_color_use_as_albedo = true
	step_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	SurfaceLibrary.dress(step_material, "concrete", 3.0, 0.8)
	_node(steps.commit(), step_material, "Stairs")
	# Poured concrete (its colour pattern under the park's own wall colour).
	var wall_material := _material((def.wall_color.lerp(Color(0.35, 0.36, 0.38), 0.5) * 1.35).clamp(), 0.85)
	wall_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if def.facade == &"brick":
		wall_material.albedo_color = (def.wall_color.lerp(Color(0.62, 0.36, 0.26), 0.7) * 1.5).clamp()
		SurfaceLibrary.dress(wall_material, "bricks", 2.4, 1.0, true)
	else:
		SurfaceLibrary.dress(wall_material, "concrete", 4.0, 0.9, true)
	_node(walls.commit(), wall_material, "StandWalls")
	var rail_material := _material(Color(0.75, 0.76, 0.78), 0.4)
	rail_material.metallic = 0.6
	rail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	SurfaceLibrary.dress(rail_material, "metal", 1.5, 0.5)
	_node(rails.commit(), rail_material, "Rails")
	var roof_material := _material(Color(0.8, 0.81, 0.84), 0.5)
	roof_material.metallic = 0.3
	roof_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Ribbed sheet: the ribs break up what is otherwise one blank white plane from above.
	SurfaceLibrary.dress(roof_material, "container", 3.2, 1.0)
	_node(roofs.commit(), roof_material, "Roof")
	_glass = _material(Color(0.05, 0.07, 0.1), 0.08)
	_glass.metallic = 0.5
	_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glass.emission_enabled = true
	_glass.emission = Color(1.0, 0.86, 0.62)
	_glass.emission_energy_multiplier = 0.0
	_node(glass.commit(), _glass, "Suites")
	_build_flags()


## One seat as a picture, white to take the park's seat colour: the upper half its back seen
## from the front (rounded, darker toward the gap to the next seat and at the foot), the lower
## half its cushion seen from above. The far-left corner of the foot is plain (for surfaces
## with no seats on them).
static func seat_picture() -> ImageTexture:
	if _seat_picture != null:
		return _seat_picture
	const W := 64
	const H := 128
	var image := Image.create(W, H, true, Image.FORMAT_RGB8)
	for y: int in H:
		for x: int in W:
			var back := y < H / 2
			var u := (float(x) + 0.5) / W
			var v := (float(y % (H / 2)) + 0.5) / (H / 2)
			# How far inside the seat's rounded outline this point is (0 at its edge).
			var q := Vector2(absf(u - 0.5) - 0.34, absf(v - 0.5) - (0.36 if back else 0.3))
			var edge := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - 0.08
			var inside := 1.0 - smoothstep(-0.03, 0.03, edge)
			var light := (1.06 - 0.3 * v) if back else (0.86 + 0.12 * v)
			var shade := lerpf(0.3, light, inside)
			image.set_pixel(x, y, Color(shade, shade, shade))
	for y: int in range(H - 6, H):
		for x: int in 6:
			image.set_pixel(x, y, Color.WHITE)
	image.generate_mipmaps()
	_seat_picture = ImageTexture.create_from_image(image)
	return _seat_picture


static var _seat_picture: ImageTexture


## Flags along the top of the outfield stands (docs/13 S13): a pole every few sections, the
## cloths waving together in the wind (stadium/flag.gdshader; `wind` 0 slack to 2 a gale).
func _build_flags() -> void:
	if _flag_spots.is_empty():
		return
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.1
	pole.height = 9.0
	var poles := MultiMesh.new()
	poles.transform_format = MultiMesh.TRANSFORM_3D
	poles.mesh = pole
	poles.instance_count = _flag_spots.size()
	var cloth := PlaneMesh.new()
	cloth.orientation = PlaneMesh.FACE_Z
	cloth.size = Vector2(3.6, 2.2)
	cloth.center_offset = Vector3(1.8, 0.0, 0.0)
	cloth.subdivide_width = 12
	cloth.subdivide_depth = 2
	var cloths := MultiMesh.new()
	cloths.transform_format = MultiMesh.TRANSFORM_3D
	cloths.use_colors = true
	cloths.mesh = cloth
	cloths.instance_count = _flag_spots.size()
	var colours: Array[Color] = [def.seat_color.lightened(0.15), Color(0.86, 0.14, 0.16), Color(0.1, 0.2, 0.5), Color(0.98, 0.78, 0.2), Color(0.1, 0.5, 0.3)]
	# The wind comes in from left field: every flag flies the same way.
	var blow := Basis(Vector3.UP, deg_to_rad(-35.0))
	for i: int in _flag_spots.size():
		# (The spots are already in the world's own coordinates: _rim gives those.)
		var foot := _flag_spots[i]
		poles.set_instance_transform(i, Transform3D(Basis.IDENTITY, foot + Vector3(0.0, 4.5, 0.0)))
		cloths.set_instance_transform(i, Transform3D(blow, foot + Vector3(0.0, 7.8, 0.0)))
		cloths.set_instance_color(i, colours[i % colours.size()])
	var pole_node := MultiMeshInstance3D.new()
	pole_node.name = "FlagPoles"
	pole_node.multimesh = poles
	pole_node.material_override = _material(Color(0.8, 0.81, 0.83), 0.4)
	add_child(pole_node)
	_flags = ShaderMaterial.new()
	_flags.shader = load("res://stadium/flag.gdshader") as Shader
	var flag_node := MultiMeshInstance3D.new()
	flag_node.name = "Flags"
	flag_node.multimesh = cloths
	flag_node.material_override = _flags
	flag_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flag_node)


## How hard the wind blows on the flags: 0 slack, 1 a fresh breeze, 2 a gale.
func set_wind(strength: float) -> void:
	if _flags != null:
		_flags.set_shader_parameter(&"wind", clampf(strength, 0.0, 2.0))


# --- Around the park ---


## What lies beyond the stands (docs/13 S13-8): one of thirteen kinds of place, built by
## Backdrop from the park's `backdrop`.
func _build_surroundings() -> void:
	_build_landmark()
	if def.backdrop == &"none":
		return
	backdrop = Backdrop.new(def, collision.boundary_distance(0.0) + def.outfield_setback + 62.0)
	add_child(backdrop)


## A building that is part of the park: the long brick warehouse beyond right field.
func _build_landmark() -> void:
	if def.landmark != &"warehouse":
		return
	var size := Vector3(230.0, 34.0, 17.0)
	var middle := at_az(30.0, collision.boundary_distance(30.0) + def.outfield_setback + 30.0)
	var along := (at_az(46.0, 1.0) - at_az(14.0, 1.0)).normalized()
	var blocks := MultiMesh.new()
	blocks.transform_format = MultiMesh.TRANSFORM_3D
	blocks.use_colors = true
	blocks.use_custom_data = true
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	blocks.mesh = mesh
	blocks.instance_count = 1
	blocks.set_instance_transform(0, Transform3D(Basis(Vector3.UP, atan2(along.y, along.x)).scaled(size), Field.to_world(middle + Vector3(0.0, 0.0, size.y * 0.5))))
	blocks.set_instance_color(0, Color(0.78, 0.7, 0.66))
	blocks.set_instance_custom_data(0, Color(size.x, size.y, size.z, 0.0))
	var material := ShaderMaterial.new()
	material.shader = load("res://stadium/city.gdshader") as Shader
	material.set_shader_parameter(&"front", SurfaceLibrary.texture("facade_a", "color"))
	material.set_shader_parameter(&"night_front", SurfaceLibrary.texture("facade_night", "color"))
	material.set_shader_parameter(&"tile", 19.0)
	var node := MultiMeshInstance3D.new()
	node.name = "Warehouse"
	node.multimesh = blocks
	node.material_override = material
	add_child(node)


## Six light towers behind the stands, each a mast with a bank of lamps facing the field. The
## lamps glow when the lights are on (set_lights).
func _build_light_towers() -> void:
	# The lamps: rows of round floodlights in a frame, as a picture that also glows.
	var grid := _lamp_grid(10, 6)
	_lamp = _material(Color.WHITE, 0.45)
	_lamp.albedo_texture = grid
	_lamp.emission_enabled = true
	_lamp.emission = Color(1.0, 0.97, 0.9)
	_lamp.emission_texture = grid
	_lamp.emission_energy_multiplier = 0.0
	var steel := _material(Color(0.5, 0.51, 0.54), 0.45)
	steel.metallic = 0.5
	SurfaceLibrary.dress(steel, "metal", 2.0, 0.5)
	var mast := CylinderMesh.new()
	mast.top_radius = 0.55
	mast.bottom_radius = 1.0
	mast.height = 46.0
	var frame := BoxMesh.new()
	frame.size = Vector3(13.5, 7.6, 0.7)
	var face := QuadMesh.new()
	face.size = Vector2(13.0, 7.2)
	var arm := BoxMesh.new()
	arm.size = Vector3(0.3, 0.3, 3.2)
	var bearings := def.towers if not def.towers.is_empty() else PackedFloat32Array([-125.0, -70.0, -40.0, 40.0, 70.0, 125.0])
	for az: float in bearings:
		var reach := collision.boundary_distance(az) + (def.outfield_setback + 22.0 if _is_fair(az) else 40.0)
		var foot := at_az(az, reach)
		var pole := _node(mast, steel, "Mast")
		pole.position = Field.to_world(foot + Vector3(0.0, 0.0, 23.0))
		var bank := _node(frame, steel, "LampFrame")
		bank.position = Field.to_world(foot + Vector3(0.0, 0.0, 47.5))
		var toward := Field.to_world(Vector3(0.0, 40.0, 0.0))
		bank.look_at(Vector3(toward.x, bank.position.y - 20.0, toward.z))
		# The face with the lamps, on the side toward the field (a node looks along -Z).
		var lamps := MeshInstance3D.new()
		lamps.name = "Lamps"
		lamps.mesh = face
		lamps.material_override = _lamp
		lamps.position = Vector3(0.0, 0.0, -0.37)
		lamps.rotation.y = PI
		bank.add_child(lamps)
		# Two struts from the mast's head to the frame.
		for side: float in [-1.0, 1.0]:
			var strut := MeshInstance3D.new()
			strut.mesh = arm
			strut.material_override = steel
			strut.position = Vector3(side * 3.0, -2.6, 1.4)
			strut.rotation.x = deg_to_rad(40.0)
			bank.add_child(strut)


## A picture of a bank of floodlights: `columns` by `rows` round lamps in a dark frame.
static func _lamp_grid(columns: int, rows: int) -> ImageTexture:
	const CELL := 24
	var image := Image.create(columns * CELL, rows * CELL, true, Image.FORMAT_RGB8)
	image.fill(Color(0.07, 0.07, 0.08))
	for y: int in rows * CELL:
		for x: int in columns * CELL:
			var d := Vector2(float(x % CELL) + 0.5 - CELL * 0.5, float(y % CELL) + 0.5 - CELL * 0.5).length() / (CELL * 0.5)
			if d < 0.8:
				var k := 1.0 - smoothstep(0.55, 0.8, d)
				image.set_pixel(x, y, Color(0.07, 0.07, 0.08).lerp(Color(0.96, 0.96, 0.92), k))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Turns the towers' lamps on or off.
## `darkness`: how dark it is beyond the park (0 day, 0.5 dusk, 1 night).
func set_lights(on: bool, darkness: float = 0.0) -> void:
	if _lamp != null:
		_lamp.emission_energy_multiplier = 6.0 if on else 0.0
	if _glass != null:
		_glass.emission_energy_multiplier = 1.1 if on else 0.0
	if backdrop != null:
		backdrop.set_lights(on, darkness)


## A dome over the whole park: a shallow shell resting on the stands, light panels in its
## underside.
func _build_dome() -> void:
	var span := 190.0
	const RISE := 36.0
	const BASE := 9.0
	var centre := Vector3(0.0, 55.0, BASE)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	const RINGS := 16
	const SPOKES := 96
	for ring: int in RINGS:
		var t0 := PI * 0.5 * ring / RINGS
		var t1 := PI * 0.5 * (ring + 1) / RINGS
		for spoke: int in SPOKES:
			var p0 := TAU * spoke / SPOKES
			var p1 := TAU * (spoke + 1) / SPOKES
			var corner := func(t: float, p: float) -> Vector3:
				return Field.to_world(centre + Vector3(span * cos(t) * sin(p), span * cos(t) * cos(p), RISE * sin(t)))
			_quad(tool, corner.call(t0, p0), corner.call(t0, p1), corner.call(t1, p1), corner.call(t1, p0))
	tool.generate_normals()
	var m := _material(Color(0.78, 0.79, 0.82), 0.7)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = Color(0.9, 0.9, 0.92)
	m.emission_energy_multiplier = 0.35
	_node(tool.commit(), m, "Dome")
	# The wall it rests on, all the way round.
	var ring := CylinderMesh.new()
	ring.top_radius = span
	ring.bottom_radius = span
	ring.height = 10.0
	ring.cap_top = false
	ring.cap_bottom = false
	ring.radial_segments = 96
	var wall := _node(ring, m, "DomeWall")
	wall.position = Field.to_world(Vector3(0.0, 55.0, 4.5))


# --- The scoreboard and the ads ---


## A board for an ad strip from a to b (world, along the bottom edge), `high` m tall; the
## texture runs on along the strip, board after board.
func _ad_quad(a: Vector3, b: Vector3, high: float) -> void:
	var span := a.distance_to(b)
	var u0 := _ads_along / AD_LENGTH
	var u1 := (_ads_along + span) / AD_LENGTH
	_quad_uv(_ads, a + Vector3.UP * high, b + Vector3.UP * high, b, a, Vector2(u0 / float(AD_SLOTS), 0.0), Vector2(u1 / float(AD_SLOTS), 1.0))
	_ads_along += span


## The sponsors' boards: one strip of them drawn once into a viewport, and the bands that show
## it — along the wall behind home between the dugouts and along the upper tiers' fronts.
func _build_ads() -> void:
	var reach := absf(_line_az(DUGOUT_FROM, 1.0))
	const STEPS := 60
	for i: int in STEPS:
		var az0 := reach + (360.0 - 2.0 * reach) * i / STEPS
		var az1 := reach + (360.0 - 2.0 * reach) * (i + 1) / STEPS
		_ad_quad(_rim(az0, -0.03, 0.15), _rim(az1, -0.03, 0.15), 0.95)
	var strip := SubViewport.new()
	strip.size = Vector2i(AD_SLOTS * 256, 64)
	strip.render_target_update_mode = SubViewport.UPDATE_ONCE
	strip.transparent_bg = false
	var boards := AdStrip.new()
	boards.size = Vector2(strip.size)
	boards.sponsors = AdStrip.load_sponsors()
	boards.slots = AD_SLOTS
	strip.add_child(boards)
	add_child(strip)
	var m := StandardMaterial3D.new()
	m.albedo_texture = strip.get_texture()
	m.texture_repeat = true
	m.roughness = 0.6
	m.emission_enabled = true
	m.emission_texture = strip.get_texture()
	m.emission_energy_multiplier = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ads.generate_normals()
	_node(_ads.commit(), m, "Ads")


## The scoreboard: a screen 28 by 12 m on a frame above the outfield stands in left-centre,
## facing home.
func _build_scoreboard() -> void:
	var az := -21.0
	var rows := 14
	var rake := 22.0
	for section: Dictionary in def.stands:
		if in_span(az, float(section["from_az"]), float(section["to_az"])):
			rows = int((section.get("rows", [14]) as Array)[0])
			rake = float((section.get("rake_deg", [22]) as Array)[0])
	var r := fence.distance_at(az) + def.outfield_setback + rows * ROW_DEPTH + 5.0
	var bottom := 2.2 + rows * ROW_DEPTH * tan(deg_to_rad(rake)) + 3.0
	var centre := at_az(az, r, bottom + SCREEN_SIZE.y * 0.5)
	var facing := Field.to_world(Vector3(0.0, 0.0, bottom))
	scoreboard = SubViewport.new()
	scoreboard.size = Vector2i(1400, 600)
	scoreboard.transparent_bg = false
	scoreboard.render_target_update_mode = SubViewport.UPDATE_ONCE
	var blank := ColorRect.new()
	blank.color = Color(0.02, 0.02, 0.03)
	blank.size = Vector2(scoreboard.size)
	scoreboard.add_child(blank)
	var title := Label.new()
	title.text = def.name
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_font_override("font", UiTheme.font(700))
	title.position = Vector2(80.0, 240.0)
	blank.add_child(title)
	add_child(scoreboard)
	var frame := BoxMesh.new()
	frame.size = Vector3(SCREEN_SIZE.x + 1.6, SCREEN_SIZE.y + 1.6, 1.2)
	var back := _node(frame, _material(Color(0.12, 0.13, 0.15), 0.8), "ScoreboardFrame")
	back.position = Field.to_world(centre + at_az(az, 0.7) - at_az(az, 0.0))
	back.look_at(facing, Vector3.UP)
	var quad := QuadMesh.new()
	quad.size = SCREEN_SIZE
	var screen := StandardMaterial3D.new()
	screen.albedo_texture = scoreboard.get_texture()
	screen.emission_enabled = true
	screen.emission_texture = scoreboard.get_texture()
	screen.emission_energy_multiplier = 1.1
	screen.roughness = 0.4
	var face := _node(quad, screen, "Scoreboard")
	face.position = Field.to_world(centre)
	face.look_at(facing, Vector3.UP)
	face.rotate_object_local(Vector3.UP, PI)
	for side: float in [-1.0, 1.0]:
		var leg := BoxMesh.new()
		leg.size = Vector3(1.2, bottom, 1.2)
		var across := Vector3(cos(deg_to_rad(az)), -sin(deg_to_rad(az)), 0.0) * (SCREEN_SIZE.x * 0.35 * side)
		_add(leg, Color(0.2, 0.21, 0.23), at_az(az, r + 0.7) + across + Vector3(0.0, 0.0, bottom * 0.5))


# --- Seats for the crowd ---


## The seats along one row over an azimuth step, SEAT_PITCH apart.
func _add_seats(az0: float, step: float, outward: float, height: float, row: int, tier: int, fair: bool) -> void:
	var mid := az0 + step * 0.5
	var arc := deg_to_rad(step) * (collision.boundary_distance(mid) + 0.25 + outward)
	var n := int(arc / SEAT_PITCH)
	for k: int in n:
		var az := az0 + step * (k + 0.5) / n
		seat_pos.append(_rim(az, outward, height))
		seat_az.append(az)
		seat_row.append(row)
		seat_tier.append(tier)
		seat_zone.append(_zone_of(az, tier, row, fair))


## Which part of the crowd a seat is in (Crowd.Zone): the first-base side's cheering section
## is the home club's, the third-base side's the visitors'.
static func _zone_of(az: float, tier: int, row: int, fair: bool) -> int:
	if tier > 0:
		return Crowd.Zone.UPPER
	if fair:
		return Crowd.Zone.OUTFIELD
	if absf(az) >= BEHIND_HOME_FROM:
		return Crowd.Zone.BEHIND_HOME
	var cheering := absf(az) >= CHEER_FROM and absf(az) <= CHEER_TO and row < CHEER_ROWS
	if az > 0.0:
		return Crowd.Zone.HOME_CHEER if cheering else Crowd.Zone.FIRST
	return Crowd.Zone.AWAY_CHEER if cheering else Crowd.Zone.THIRD


## The azimuths (absolute) the dugouts span.
func dugout_span() -> Vector2:
	return Vector2(absf(_line_az(DUGOUT_FROM, 1.0)), absf(_line_az(DUGOUT_TO, 1.0)))


## Where a cheering section's stage stands: at the front of its first row (side 1 first base,
## −1 third), or INF when the park has no seats there.
func stage_spot(side: float) -> Vector3:
	var az := (CHEER_FROM + CHEER_TO) * 0.5 * side
	return _rim(az, 0.9, LOWER_LIP + 0.6)
