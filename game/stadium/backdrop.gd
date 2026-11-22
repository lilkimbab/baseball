class_name Backdrop
extends Node3D
## What lies beyond a park's stands (docs/13 S13-8): thirteen kinds of place, each put
## together from the same parts — land and water, wooded ridges and bare mountains, buildings
## wearing photographs of real fronts (apartment complexes in ranks as round a Korean park,
## offices on a street grid, towers), a harbour, a river and its bridges, a beach, factories,
## a needle tower on its hill, an arena and its car park, a big wheel, wind turbines, fields
## and a village. A park names its kind (StadiumDef.backdrop); where things stand comes from
## the park's own id, so two parks of one kind are not the same place. Textures: CC0 scans
## (SurfaceLibrary).

## The kinds, with the names shown for them.
const KINDS := {
	&"forest_hills": "숲 능선", &"new_town": "신도시", &"downtown": "도심", &"harbour": "항구", &"riverside": "강변",
	&"beach": "해변", &"industrial": "공단", &"mountains": "고산", &"countryside": "전원", &"sports_complex": "종합운동장",
	&"tower_hill": "타워 언덕", &"amusement": "유원지", &"sea_bridge": "해상 대교",
}
## Older names for three of them.
const ALIASES := {&"hills": &"forest_hills", &"city": &"downtown", &"sea": &"harbour"}
## The kinds of building: [width, height, depth] ranges (m) and the fronts each may wear.
const BUILDINGS := {
	"apartment": [Vector2(40.0, 54.0), Vector2(52.0, 96.0), Vector2(11.5, 13.5), ["a", "b"]],
	"office": [Vector2(22.0, 36.0), Vector2(30.0, 78.0), Vector2(18.0, 28.0), ["c", "e", "b"]],
	"tower": [Vector2(26.0, 38.0), Vector2(95.0, 180.0), Vector2(24.0, 36.0), ["d", "e", "c"]],
	"low": [Vector2(18.0, 38.0), Vector2(8.0, 19.0), Vector2(13.0, 22.0), ["a", "c"]],
	"hotel": [Vector2(34.0, 60.0), Vector2(36.0, 70.0), Vector2(14.0, 18.0), ["b", "e"]],
}
## The photographed fronts (assets/materials/facade_*): one picture covers this many metres.
const FACADE_TILES := {"a": 19.0, "b": 23.0, "c": 17.0, "d": 46.0, "e": 27.0}
## Polar positions are taken about this point (field coordinates): the middle of the park.
const CENTRE := Vector3(0.0, 60.0, 0.0)

var def: StadiumDef
var kind: StringName = &"forest_hills"
## Where the outside of the outfield stands is, straight out (m from home plate).
var edge := 190.0
var _rng: Rng
var _buildings: Dictionary[String, Array] = {}
var _cities: Array[ShaderMaterial] = []
## Things that glow when the lights are on: [material, energy when on].
var _glows: Array[Array] = []
## Plain materials of the town (roof parts) that darken at night as its fronts do.
var _dimmed: Array[StandardMaterial3D] = []


func _init(park: StadiumDef, edge_distance: float) -> void:
	def = park
	edge = edge_distance
	kind = ALIASES.get(park.backdrop, park.backdrop)
	if not KINDS.has(kind):
		kind = &"forest_hills"
	_rng = Rng.new(hash(park.place_seed if park.place_seed != "" else park.id) + hash(String(kind)))
	name = "Backdrop"


func _ready() -> void:
	# Where the streets go is known first: nothing else is put on them.
	_plan_streets()
	match kind:
		&"forest_hills":
			_land("forest", Color(0.62, 0.74, 0.52), 60.0)
			_ridge(Color(0.52, 0.64, 0.46), 540.0, 30.0, 105.0, 3.0)
			_ridge(Color(0.6, 0.68, 0.7), 900.0, 70.0, 210.0, 1.7)
			_trees(340, Vector2(-180.0, 180.0), Vector2(edge + 30.0, edge + 260.0))
			for spot: Array in [[-34.0, 430.0], [8.0, 470.0], [44.0, 420.0]]:
				_complex(float(spot[0]) + _rng.next_range(-6.0, 6.0), float(spot[1]), 2, 3 + _rng.next_int(2), ["a", "b"][_rng.next_int(2)], _rng.next_range(16.0, 24.0))
		&"new_town":
			_land("asphalt", Color(0.5, 0.52, 0.5), 40.0)
			_ridge(Color(0.58, 0.66, 0.68), 1050.0, 60.0, 170.0, 1.8)
			var az := -96.0
			while az < 96.0:
				_complex(az + _rng.next_range(-4.0, 4.0), _rng.next_range(330.0, 420.0), 2 + _rng.next_int(2), 3 + _rng.next_int(3), ["a", "b", "b"][_rng.next_int(3)], _rng.next_range(20.0, 33.0))
				_complex(az + 9.0 + _rng.next_range(-4.0, 4.0), _rng.next_range(560.0, 680.0), 3, 4 + _rng.next_int(3), ["a", "b"][_rng.next_int(2)], _rng.next_range(24.0, 36.0))
				az += 24.0
			_scatter([["low", 0.7], ["office", 0.3]], 50, Vector2(-180.0, 180.0), Vector2(edge + 40.0, edge + 110.0))
			_trees(160, Vector2(-180.0, 180.0), Vector2(edge + 20.0, edge + 140.0))
		&"downtown":
			_land("asphalt", Color(0.46, 0.47, 0.5), 40.0)
			_ridge(Color(0.56, 0.62, 0.68), 1100.0, 20.0, 70.0, 2.0)
			_downtown(Vector2(-180.0, 180.0), Vector2(edge + 70.0, 760.0), 300, _rng.next_range(-25.0, 25.0), 200.0)
			_trees(60, Vector2(-180.0, 180.0), Vector2(edge + 15.0, edge + 60.0))
		&"harbour":
			_sea()
			_quay(edge + 62.0)
			_harbour(edge + 62.0)
			_islands(3)
			_ridge(Color(0.55, 0.64, 0.68), 1300.0, 30.0, 120.0, 2.0)
			_scatter([["low", 0.6], ["office", 0.4]], 60, Vector2(100.0, 260.0), Vector2(edge + 60.0, 520.0))
		&"riverside":
			_riverside()
		&"beach":
			_beach()
		&"industrial":
			_land("asphalt", Color(0.5, 0.5, 0.5), 40.0)
			_ridge(Color(0.56, 0.62, 0.64), 1000.0, 20.0, 90.0, 2.0)
			_industrial()
		&"mountains":
			_land("forest", Color(0.58, 0.7, 0.5), 60.0)
			_ridge(Color(0.48, 0.6, 0.44), 470.0, 60.0, 190.0, 3.5)
			_ridge(Color(0.62, 0.64, 0.62), 780.0, 170.0, 430.0, 2.6, "rock", 330.0)
			_ridge(Color(0.74, 0.78, 0.84), 1200.0, 320.0, 660.0, 1.9, "rock", 420.0)
			_village(70, Vector2(-70.0, 70.0), Vector2(edge + 50.0, edge + 190.0))
			_trees(420, Vector2(-180.0, 180.0), Vector2(edge + 20.0, edge + 280.0))
		&"countryside":
			_fields()
			_ridge(Color(0.54, 0.66, 0.5), 760.0, 40.0, 130.0, 2.4)
			_ridge(Color(0.62, 0.7, 0.72), 1150.0, 100.0, 270.0, 1.8)
			_village(110, Vector2(-110.0, 110.0), Vector2(edge + 40.0, edge + 330.0))
			_greenhouses(9, Vector2(-80.0, 80.0), Vector2(edge + 70.0, edge + 300.0))
			_turbines(7, Vector2(-60.0, 60.0), 700.0, 100.0)
			_trees(260, Vector2(-180.0, 180.0), Vector2(edge + 20.0, edge + 380.0))
		&"sports_complex":
			_land("asphalt", Color(0.44, 0.45, 0.47), 30.0)
			_ridge(Color(0.58, 0.66, 0.68), 1050.0, 50.0, 150.0, 1.8)
			_arena(36.0, edge + 150.0)
			_bowl(-30.0, edge + 200.0)
			_parking(Vector2(-4.0, 16.0), edge + 40.0, 9, 46)
			_parking(Vector2(-78.0, -56.0), edge + 40.0, 7, 40)
			for spot: Array in [[-66.0, 600.0], [-8.0, 640.0], [30.0, 620.0], [70.0, 560.0]]:
				_complex(float(spot[0]), float(spot[1]), 3, 4, ["a", "b"][_rng.next_int(2)], _rng.next_range(22.0, 32.0))
			_trees(140, Vector2(-180.0, 180.0), Vector2(edge + 20.0, edge + 120.0))
		&"tower_hill":
			_land("forest", Color(0.6, 0.72, 0.52), 60.0)
			_ridge(Color(0.58, 0.66, 0.68), 1100.0, 40.0, 130.0, 1.8)
			_needle_tower(_rng.next_range(-18.0, 22.0), 560.0)
			_downtown(Vector2(-120.0, 120.0), Vector2(edge + 80.0, 520.0), 170, 0.0, 95.0)
			_trees(200, Vector2(-180.0, 180.0), Vector2(edge + 20.0, edge + 200.0))
		&"amusement":
			_sea()
			_quay(edge + 190.0)
			_big_wheel(_rng.next_range(-30.0, -16.0), edge + 120.0)
			_scatter([["hotel", 0.5], ["low", 0.5]], 34, Vector2(8.0, 80.0), Vector2(edge + 50.0, edge + 170.0))
			_scatter([["low", 1.0]], 22, Vector2(-80.0, -34.0), Vector2(edge + 50.0, edge + 170.0))
			_trees(120, Vector2(-180.0, 180.0), Vector2(edge + 20.0, edge + 170.0))
			_islands(4)
			_ridge(Color(0.56, 0.64, 0.7), 1400.0, 20.0, 110.0, 2.0)
		&"sea_bridge":
			_sea()
			_quay(edge + 70.0)
			_sea_bridge(edge + 420.0)
			_islands(5)
			_ship(Vector3(-260.0, edge + 250.0, 0.0), deg_to_rad(8.0), 150.0)
			_ship(Vector3(330.0, edge + 600.0, 0.0), deg_to_rad(-5.0), 210.0)
			_scatter([["low", 0.6], ["hotel", 0.4]], 40, Vector2(100.0, 260.0), Vector2(edge + 60.0, 520.0))
			_trees(70, Vector2(-180.0, 180.0), Vector2(edge + 15.0, edge + 60.0))
	_draw_streets()
	_flush_buildings()
	_roofs()


## Turns on what glows at night; `darkness`: 0 day, about 0.5 at dusk, 1 at night.
func set_lights(on: bool, darkness: float) -> void:
	for city: ShaderMaterial in _cities:
		city.set_shader_parameter(&"lights", 1.0 if on else 0.0)
		city.set_shader_parameter(&"dark", darkness)
	for m: StandardMaterial3D in _dimmed:
		var keep := lerpf(1.0, 0.15, darkness)
		m.albedo_color = Color(keep, keep, keep) if m.vertex_color_use_as_albedo else Color(0.82, 0.84, 0.86) * keep
	for glow: Array in _glows:
		(glow[0] as StandardMaterial3D).emission_energy_multiplier = float(glow[1]) if on else 0.0
	for glow: Array in _spinning_glows:
		(glow[0] as ShaderMaterial).set_shader_parameter(&"glow", float(glow[1]) if on else 0.0)


# --- Helpers ---


## A point `r` metres from the park's middle at compass `az` (0 straight out, + toward right
## field), `h` up; field coordinates.
static func at(az: float, r: float, h: float = 0.0) -> Vector3:
	return CENTRE + StadiumBuilder.at_az(az, r, h)


func _mat(colour: Color, roughness: float = 0.9, surface: String = "", metres: float = 10.0, depth: float = 0.8, with_colour: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = roughness
	if surface != "":
		SurfaceLibrary.dress(m, surface, metres, depth, with_colour)
	return m


func _glowing(colour: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(colour, 0.3)
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = 0.0
	_glows.append([m, energy])
	return m


func _add(mesh: Mesh, material: Material, node_name: String, at_field: Vector3 = Vector3.ZERO, shadows: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.name = node_name
	mi.position = Field.to_world(at_field)
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi, true)
	return mi


## The turn about the vertical that points a box's long (z) side along a direction on the field.
static func _yaw(dir: Vector3) -> float:
	return atan2(dir.x, -dir.y)


static func _tool() -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	return tool


## A box added to a mesh being built: `size` (across, up, along), centred at `at_field`.
static func _box(tool: SurfaceTool, size: Vector3, at_field: Vector3, yaw: float = 0.0) -> void:
	var box := BoxMesh.new()
	box.size = size
	tool.append_from(box, 0, Transform3D(Basis(Vector3.UP, yaw), Field.to_world(at_field)))


## A straight member from one point to another (field coordinates), `width` thick.
static func _beam(tool: SurfaceTool, from: Vector3, to: Vector3, width: float) -> void:
	var a := Field.to_world(from)
	var b := Field.to_world(to)
	var along := b - a
	if along.length() < 0.01:
		return
	var up := Vector3.UP if absf(along.normalized().y) < 0.95 else Vector3.RIGHT
	var box := BoxMesh.new()
	box.size = Vector3(width, width, along.length())
	tool.append_from(box, 0, Transform3D(Basis.looking_at(along, up), (a + b) * 0.5))


static func _cylinder(tool: SurfaceTool, top: float, bottom: float, height: float, foot: Vector3, segments: int = 20) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	tool.append_from(mesh, 0, Transform3D(Basis.IDENTITY, Field.to_world(foot + Vector3(0.0, 0.0, height * 0.5))))


func _commit(tool: SurfaceTool, material: Material, node_name: String) -> MeshInstance3D:
	tool.generate_normals()
	return _add(tool.commit(), material, node_name)


## A picture of bands of two colours (a chimney, an aerial).
static func _bands(a: Color, b: Color, count: int) -> ImageTexture:
	var image := Image.create(4, count * 4, false, Image.FORMAT_RGB8)
	for y: int in count * 4:
		for x: int in 4:
			image.set_pixel(x, y, a if (y / 4) % 2 == 0 else b)
	return ImageTexture.create_from_image(image)


# --- Land and water ---


## Land everywhere, in one surface.
func _land(surface: String, colour: Color, metres: float) -> void:
	_land_rect(-1800.0, 1800.0, -1800.0, 1800.0, surface, colour, metres)


## Land between two lines across the view (y from/to) and two along it (x), just under the
## field's own ground.
func _land_rect(x0: float, x1: float, y0: float, y1: float, surface: String, colour: Color, metres: float, level: float = -0.6) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(x1 - x0, y1 - y0)
	_add(plane, _mat(colour, 1.0, surface, metres, 0.6), "Land", Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, level))


## The sea (or a river, a lake): water everywhere under the land, its ripples catching the sky.
func _sea() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(4200.0, 4200.0)
	var water := ShaderMaterial.new()
	water.shader = load("res://stadium/water.gdshader") as Shader
	var noise := FastNoiseLite.new()
	noise.frequency = 0.03
	noise.fractal_octaves = 4
	var ripples := NoiseTexture2D.new()
	ripples.width = 512
	ripples.height = 512
	ripples.seamless = true
	ripples.as_normal_map = true
	ripples.bump_strength = 5.0
	ripples.generate_mipmaps = true
	ripples.noise = noise
	water.set_shader_parameter(&"ripples", ripples)
	_add(plane, water, "Sea", Vector3(0.0, 0.0, -1.7))


## A ridge round the park (or across part of the view), `radius` metres off, its crest between
## `low` and `high`. Wooded, or bare rock with snow above `snow_line` metres.
func _ridge(colour: Color, radius: float, low: float, high: float, roughness: float, surface: String = "forest", snow_line: float = -1.0, sector: Vector2 = Vector2(-180.0, 180.0)) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = hash(def.id) + int(radius)
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var tool := _tool()
	const STEP := 0.5
	var a0 := sector.x
	while a0 < sector.y - 0.01:
		var a1 := a0 + STEP
		var h0 := lerpf(low, high, noise.get_noise_1d(a0 * roughness) * 0.5 + 0.5)
		var h1 := lerpf(low, high, noise.get_noise_1d(a1 * roughness) * 0.5 + 0.5)
		# Spurs and gullies: the slope comes forward and falls back along the ridge, so its
		# faces turn to and from the sun as a mountainside's do.
		var g0 := noise.get_noise_1d(a0 * roughness * 7.0 + 300.0)
		var g1 := noise.get_noise_1d(a1 * roughness * 7.0 + 300.0)
		var s0 := 1.0 + 0.3 * g0
		var s1 := 1.0 + 0.3 * g1
		var c0 := colour * (0.86 + 0.36 * g0)
		var c1 := colour * (0.86 + 0.36 * g1)
		var top0 := Color.WHITE if snow_line > 0.0 and h0 > snow_line else c0
		var top1 := Color.WHITE if snow_line > 0.0 and h1 > snow_line else c1
		var r_foot := radius * 0.74
		var r_low0 := radius * (0.86 + 0.05 * g0)
		var r_low1 := radius * (0.86 + 0.05 * g1)
		var r_mid0 := radius * (0.94 + 0.03 * g0)
		var r_mid1 := radius * (0.94 + 0.03 * g1)
		_quad_col(tool, at(a0, r_foot), at(a1, r_foot), at(a1, r_low1, h1 * 0.3 * s1), at(a0, r_low0, h0 * 0.3 * s0), colour, colour, c1, c0)
		_quad_col(tool, at(a0, r_low0, h0 * 0.3 * s0), at(a1, r_low1, h1 * 0.3 * s1), at(a1, r_mid1, h1 * 0.68 * s1), at(a0, r_mid0, h0 * 0.68 * s0), c0, c1, c1, c0)
		_quad_col(tool, at(a0, r_mid0, h0 * 0.68 * s0), at(a1, r_mid1, h1 * 0.68 * s1), at(a1, radius, h1), at(a0, radius, h0), c0, c1, top1, top0)
		a0 = a1
	var m := _mat(Color.WHITE, 1.0, surface, 85.0 if surface == "forest" else 130.0, 1.0)
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_commit(tool, m, "Ridge")


static func _quad_col(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	var pts: Array[Vector3] = [Field.to_world(a), Field.to_world(b), Field.to_world(c), Field.to_world(d)]
	var cols: Array[Color] = [ca, cb, cc, cd]
	for i: int in [0, 1, 2, 0, 2, 3]:
		tool.set_color(cols[i])
		tool.add_vertex(pts[i])


## Islands out on the water: wooded humps.
func _islands(count: int) -> void:
	var hump := SphereMesh.new()
	hump.radius = 1.0
	hump.height = 2.0
	hump.radial_segments = 20
	hump.rings = 8
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = hump
	mm.instance_count = count
	for i: int in count:
		var size := Vector3(_rng.next_range(90.0, 240.0), _rng.next_range(24.0, 70.0), _rng.next_range(70.0, 160.0))
		var p := at(_rng.next_range(-75.0, 75.0), _rng.next_range(620.0, 1150.0), -4.0)
		mm.set_instance_transform(i, Transform3D((Basis(Vector3.UP, _rng.next_range(0.0, PI)) * Basis.from_scale(size)), Field.to_world(p)))
	_multi(mm, _mat(Color(0.6, 0.72, 0.56), 1.0, "forest", 70.0, 1.0), "Islands")


func _multi(mm: MultiMesh, material: Material, node_name: String) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node, true)
	return node


## Trees as rounded crowns, in clumps: `count` of them within `sector` (degrees) at distances
## in `reach`, clear of buildings' feet only by chance (they stand among them, as in a town).
func _trees(count: int, sector: Vector2, reach: Vector2) -> void:
	var crown := SphereMesh.new()
	crown.radius = 1.0
	crown.height = 2.0
	crown.radial_segments = 8
	crown.rings = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = crown
	mm.instance_count = count
	var clump := at(0.0, reach.x)
	var spots: Array[Transform3D] = []
	var greens: Array[Color] = []
	for i: int in count:
		if i % 7 == 0:
			clump = at(_rng.next_range(sector.x, sector.y), _rng.next_range(reach.x, reach.y))
		var p := clump + Vector3(_rng.next_range(-16.0, 16.0), _rng.next_range(-16.0, 16.0), 0.0)
		var size := Vector3(_rng.next_range(3.5, 6.5), _rng.next_range(5.0, 9.0), _rng.next_range(3.5, 6.5))
		var turn := _rng.next_range(0.0, PI)
		var g := _rng.next_range(0.55, 0.9)
		# (None in the street.)
		if _on_a_street(p, Vector3(size.x, 0.0, size.z), 0.0):
			continue
		spots.append(Transform3D((Basis(Vector3.UP, turn) * Basis.from_scale(size)), Field.to_world(p + Vector3(0.0, 0.0, size.y * 0.7))))
		greens.append(Color(g * 0.8, g, g * 0.62))
	mm.instance_count = spots.size()
	for i: int in spots.size():
		mm.set_instance_transform(i, spots[i])
		mm.set_instance_color(i, greens[i])
	var m := _mat(Color.WHITE, 1.0, "forest", 9.0, 1.0)
	m.vertex_color_use_as_albedo = true
	_multi(mm, m, "Trees")


# --- Buildings ---


## One building: a box wearing the front named, standing on the ground at `foot`. (Turned,
## then sized along its own sides: sized along the world's axes after the turn, as it was, a
## turned box came out skewed.)
func _building(front: String, size: Vector3, foot: Vector3, yaw: float, tint: float = -1.0) -> void:
	var shade := tint if tint > 0.0 else _rng.next_range(0.58, 0.78)
	if not _buildings.has(front):
		_buildings[front] = []
	_buildings[front].append([Transform3D((Basis(Vector3.UP, yaw) * Basis.from_scale(size)), Field.to_world(foot + Vector3(0.0, 0.0, size.y * 0.5 - 1.0))),
		Color(shade, shade * _rng.next_range(0.96, 1.0), shade * _rng.next_range(0.92, 1.0)), size, foot, yaw])


## An apartment complex: ranks of the same slab, all facing one way, as they are built —
## `rows` ranks of `cols` blocks of about `floors` storeys, `r` metres out at compass `az`.
func _complex(az: float, r: float, rows: int, cols: int, front: String, floors: float) -> void:
	var middle := at(az, r)
	# The ranks face south-east or south-west of the line to the park, never square to it.
	var yaw := -deg_to_rad(az) + deg_to_rad(_rng.next_range(-35.0, 35.0))
	var across := Vector3(cos(yaw), sin(yaw), 0.0)
	var along := Vector3(-sin(yaw), cos(yaw), 0.0)
	var width := _rng.next_range(40.0, 54.0)
	var tint := _rng.next_range(0.62, 0.8)
	for row: int in rows:
		for col: int in cols:
			var storeys := floors + float(_rng.next_int(5)) - 2.0
			var foot := middle + across * ((col - (cols - 1) * 0.5) * (width + 16.0)) + along * ((row - (rows - 1) * 0.5) * 52.0)
			_building(front, Vector3(width, storeys * 2.9, 12.5), foot, yaw, tint)


## Buildings of the kinds in `mix` ([kind, share] each) here and there: `count` of them within
## `sector` (degrees) at distances in `reach`, on streets square to each other.
func _scatter(mix: Array, count: int, sector: Vector2, reach: Vector2) -> void:
	var grid := deg_to_rad(float(absi(hash(def.id)) % 40))
	for i: int in count:
		var roll := _rng.next_float()
		var which := str(mix[0][0])
		var share := 0.0
		for pair: Array in mix:
			share += float(pair[1])
			if roll <= share:
				which = str(pair[0])
				break
		var spec: Array = BUILDINGS[which]
		var fronts: Array = spec[3]
		var size := Vector3(_rng.next_range(spec[0].x, spec[0].y), _rng.next_range(spec[1].x, spec[1].y), _rng.next_range(spec[2].x, spec[2].y))
		_building(str(fronts[_rng.next_int(fronts.size())]), size, at(_rng.next_range(sector.x, sector.y), _rng.next_range(reach.x, reach.y)), grid + float(_rng.next_int(2)) * PI * 0.5)


## The middle of a city: buildings on a street grid, low at the edges and rising to towers
## round its core (at compass `core`), the tallest about `peak` metres.
func _downtown(sector: Vector2, reach: Vector2, count: int, core: float, peak: float) -> void:
	var grid := deg_to_rad(float(absi(hash(def.id)) % 40))
	var half := (sector.y - sector.x) * 0.5
	for i: int in count:
		var az := _rng.next_range(sector.x, sector.y)
		var r := _rng.next_range(reach.x, reach.y)
		var near_core := clampf(1.0 - absf(wrapf(az - core, -180.0, 180.0)) / minf(half, 110.0), 0.0, 1.0)
		var far := clampf((r - reach.x) / maxf(reach.y - reach.x, 1.0), 0.0, 1.0)
		var tall := near_core * (0.35 + 0.65 * far) * _rng.next_range(0.35, 1.0)
		var height := lerpf(18.0, peak, tall * tall) + _rng.next_range(0.0, 14.0)
		var fronts: Array = ["a", "c"] if height < 34.0 else (["c", "b", "e"] if height < 85.0 else ["d", "e", "c"])
		var base := _rng.next_range(22.0, 38.0)
		_building(str(fronts[_rng.next_int(fronts.size())]), Vector3(base, height, base * _rng.next_range(0.7, 1.1)), at(az, r), grid + float(_rng.next_int(2)) * PI * 0.5)


## Low houses with pitched roofs — blue and orange sheet roofs, as in a Korean village.
func _village(count: int, sector: Vector2, reach: Vector2) -> void:
	var wall := BoxMesh.new()
	wall.size = Vector3(1.0, 1.0, 1.0)
	var roof := PrismMesh.new()
	roof.size = Vector3(1.0, 1.0, 1.0)
	var walls := MultiMesh.new()
	var roofs := MultiMesh.new()
	for mm: MultiMesh in [walls, roofs]:
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.instance_count = count
	walls.mesh = wall
	roofs.mesh = roof
	var paints: Array[Color] = [Color(0.2, 0.36, 0.62), Color(0.78, 0.36, 0.16), Color(0.42, 0.2, 0.16), Color(0.3, 0.34, 0.38), Color(0.2, 0.42, 0.34)]
	var hamlet := at(0.0, reach.x)
	for i: int in count:
		if i % 9 == 0:
			hamlet = at(_rng.next_range(sector.x, sector.y), _rng.next_range(reach.x, reach.y))
		var foot := hamlet + Vector3(_rng.next_range(-42.0, 42.0), _rng.next_range(-42.0, 42.0), 0.0)
		var size := Vector3(_rng.next_range(8.0, 14.0), _rng.next_range(3.2, 6.0), _rng.next_range(6.0, 9.0))
		var turn := Basis(Vector3.UP, _rng.next_range(0.0, PI))
		walls.set_instance_transform(i, Transform3D((turn * Basis.from_scale(size)), Field.to_world(foot + Vector3(0.0, 0.0, size.y * 0.5))))
		var cream := _rng.next_range(0.75, 0.95)
		walls.set_instance_color(i, Color(cream, cream * 0.97, cream * 0.9))
		var pitch := Vector3(size.x + 1.0, _rng.next_range(1.6, 2.6), size.z + 1.0)
		roofs.set_instance_transform(i, Transform3D((turn * Basis.from_scale(pitch)), Field.to_world(foot + Vector3(0.0, 0.0, size.y + pitch.y * 0.5))))
		roofs.set_instance_color(i, paints[_rng.next_int(paints.size())])
	var wall_m := _mat(Color.WHITE, 0.9, "concrete", 6.0, 0.5)
	wall_m.vertex_color_use_as_albedo = true
	_multi(walls, wall_m, "Houses")
	var roof_m := _mat(Color.WHITE, 0.6, "container", 1.6, 0.9, false)
	roof_m.vertex_color_use_as_albedo = true
	_multi(roofs, roof_m, "Roofs")


func _flush_buildings() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	for front: String in _buildings:
		# Nothing stands in the street.
		var list: Array = (_buildings[front] as Array).filter(func(b: Array) -> bool: return not _on_a_street(b[3], b[2], b[4]))
		_buildings[front] = list
		var blocks := MultiMesh.new()
		blocks.transform_format = MultiMesh.TRANSFORM_3D
		blocks.use_colors = true
		blocks.use_custom_data = true
		blocks.mesh = mesh
		blocks.instance_count = list.size()
		for i: int in list.size():
			blocks.set_instance_transform(i, list[i][0])
			blocks.set_instance_color(i, list[i][1])
			var size: Vector3 = list[i][2]
			blocks.set_instance_custom_data(i, Color(size.x, size.y, size.z, 0.0))
		var material := ShaderMaterial.new()
		material.shader = load("res://stadium/city.gdshader") as Shader
		material.set_shader_parameter(&"front", SurfaceLibrary.texture("facade_" + front, "color"))
		material.set_shader_parameter(&"night_front", SurfaceLibrary.texture("facade_night", "color"))
		material.set_shader_parameter(&"tile", float(FACADE_TILES.get(front, 20.0)))
		_cities.append(material)
		_multi(blocks, material, "City")


# --- The town's streets and roofs (R2) ---
#
# What makes the town beyond the park read as a place from the stands and the high cameras:
# roofs with their parapets, plant rooms, air-conditioning units, water tanks and masts;
# streets with lane marks, the cars on them and the trees along them. All of it is a handful of
# MultiMesh batches with no shadows, faded out beyond what the cameras can make out.

## The ring road round the park and the avenues out from it: [from, to, width] in field
## coordinates (from, to on the ground).
var _street_lines: Array[Array] = []
## The ring road's centre line, all the way round (drawn as one strip: quads laid end to end
## left a wedge open at every joint).
var _ring_points: Array[Vector3] = []
## Kinds whose town has streets all round, and those by the water whose streets stay on land
## behind home plate.
const STREET_TOWNS: Array[StringName] = [&"new_town", &"downtown", &"tower_hill"]
const STREET_SHORES: Array[StringName] = [&"harbour", &"amusement", &"sea_bridge"]
## Kinds with no ring road (the park is on the water's edge or in fields).
const NO_RING: Array[StringName] = [&"riverside", &"beach"]
const RING_WIDTH := 16.0
const AVENUE_WIDTH := 14.0
## Small things on roofs and streets are not drawn beyond this (m from the camera).
const DETAIL_RANGE := 900.0


func _plan_streets() -> void:
	if NO_RING.has(kind):
		return
	var town := STREET_TOWNS.has(kind)
	var shore := STREET_SHORES.has(kind)
	# The ring: just outside the stands' back wall all round (from the park's middle, the
	# stands reach about edge - 60 toward centre field and some 100 m behind home).
	var ring := maxf(edge - 60.0, 112.0) + 14.0
	var steps := 72
	var prev := at(-180.0, ring)
	for i: int in steps:
		_ring_points.append(at(-180.0 + 360.0 * i / steps, ring))
	for i: int in range(1, steps + 1):
		var az := -180.0 + 360.0 * i / steps
		var p := at(az, ring)
		if not shore or az < -95.0 or az > 95.0 or _on_land(p):
			_street_lines.append([prev, p, RING_WIDTH])
		prev = p
	if town or shore:
		var grid := deg_to_rad(float(absi(hash(def.id)) % 40))
		var dirs: Array[float] = [grid, grid + PI * 0.5, grid + PI, grid + PI * 1.5]
		for d: float in dirs:
			for side: float in [-1.0, 1.0]:
				var out := Vector3(sin(d), cos(d), 0.0)
				var across := Vector3(out.y, -out.x, 0.0)
				var start := CENTRE + across * side * 70.0 + out * ring
				var length := 820.0
				var finish := start + out * length
				if shore:
					if out.y > -0.3:
						continue
				_street_lines.append([start, finish, AVENUE_WIDTH])


func _draw_streets() -> void:
	if _street_lines.is_empty():
		return
	_lay_streets()
	_cars()
	_street_trees()


## Whether a point is on land (not out in the water of a park by the sea).
func _on_land(p: Vector3) -> bool:
	return not STREET_SHORES.has(kind) or p.y < edge + 40.0


## A building's footprint on a street (with a few metres to spare)?
func _on_a_street(foot: Vector3, size: Vector3, _yaw_turn: float) -> bool:
	var reach := Vector2(size.x, size.z).length() * 0.5 + 3.0
	for line: Array in _street_lines:
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		var ab := Vector2(b.x - a.x, b.y - a.y)
		var f := clampf(Vector2(foot.x - a.x, foot.y - a.y).dot(ab) / maxf(ab.length_squared(), 1e-4), 0.0, 1.0)
		var near := Vector2(a.x, a.y) + ab * f
		if near.distance_to(Vector2(foot.x, foot.y)) < reach + float(line[2]) * 0.5:
			return true
	return false


## The roads themselves: asphalt with a broken centre line and solid edge lines, drawn by the
## road shader from the strip's own coordinates (across 0-1, along in metres).
func _lay_streets() -> void:
	var tool := _tool()
	var level := Vector3(0.0, 0.0, -0.5)
	# The ring: one strip, each joint mitred.
	var count := _ring_points.size()
	var run := 0.0
	for i: int in count:
		var p0 := _ring_points[i]
		var p1 := _ring_points[(i + 1) % count]
		var s0 := _ring_side(i)
		var s1 := _ring_side((i + 1) % count)
		var length := Vector2(p1.x - p0.x, p1.y - p0.y).length()
		var corners: Array[Vector3] = [p0 - s0 + level, p0 + s0 + level, p1 + s1 + level, p1 - s1 + level]
		var uvs: Array[Vector2] = [Vector2(0.0, run), Vector2(1.0, run), Vector2(1.0, run + length), Vector2(0.0, run + length)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			tool.set_normal(Vector3.UP)
			tool.set_uv(uvs[k])
			tool.add_vertex(Field.to_world(corners[k]))
		run += length
	for line: Array in _street_lines:
		if float(line[2]) == RING_WIDTH:
			continue
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		var half := float(line[2]) * 0.5
		var along := Vector3(b.x - a.x, b.y - a.y, 0.0)
		var length := along.length()
		if length < 0.5:
			continue
		var side := Vector3(along.y, -along.x, 0.0).normalized() * half
		var corners: Array[Vector3] = [a - side + level, a + side + level, b + side + level, b - side + level]
		var uvs: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, length), Vector2(0.0, length)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			tool.set_normal(Vector3.UP)
			tool.set_uv(uvs[k])
			tool.add_vertex(Field.to_world(corners[k]))
	var road := ShaderMaterial.new()
	road.shader = load("res://stadium/road.gdshader") as Shader
	road.set_shader_parameter(&"asphalt", SurfaceLibrary.texture("asphalt", "color"))
	_cities.append(road)
	# (Normals set by hand: the strips lie flat.)
	_add(tool.commit(), road, "Streets")


## Half the ring road's width across it at point i, square to the road there (the mean of
## the two segments meeting at it, lengthened so the width holds through the bend).
func _ring_side(i: int) -> Vector3:
	var count := _ring_points.size()
	var before := _ring_points[(i - 1 + count) % count]
	var after := _ring_points[(i + 1) % count]
	var along := Vector3(after.x - before.x, after.y - before.y, 0.0).normalized()
	return Vector3(along.y, -along.x, 0.0) * (RING_WIDTH * 0.5)


## Cars on the streets, in both directions, a car every so often: a body and a cabin.
func _cars() -> void:
	var spots: Array[Transform3D] = []
	for line: Array in _street_lines:
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		var along := Vector3(b.x - a.x, b.y - a.y, 0.0)
		var length := along.length()
		if length < 1.0:
			continue
		var dir := along / length
		var side := Vector3(dir.y, -dir.x, 0.0)
		var lanes := [-0.31, -0.12, 0.12, 0.31]
		var at_m := _rng.next_range(4.0, 30.0)
		while at_m < length:
			var lane: float = lanes[_rng.next_int(lanes.size())]
			var heading := dir if lane > 0.0 else -dir
			var p := a + dir * at_m + side * lane * float(line[2]) + Vector3(0.0, 0.0, -0.5)
			spots.append(Transform3D(Basis(Vector3.UP, _yaw(heading)), Field.to_world(p)))
			at_m += _rng.next_range(14.0, 55.0)
	if spots.is_empty():
		return
	var body := BoxMesh.new()
	body.size = Vector3(1.8, 0.75, 4.5)
	var cabin := BoxMesh.new()
	cabin.size = Vector3(1.6, 0.6, 2.3)
	var paints: Array[Color] = [Color(0.92, 0.92, 0.92), Color(0.07, 0.07, 0.08), Color(0.52, 0.54, 0.57), Color(0.76, 0.77, 0.79), Color(0.58, 0.09, 0.09), Color(0.12, 0.2, 0.44), Color(0.85, 0.85, 0.82)]
	var bodies := MultiMesh.new()
	var cabins := MultiMesh.new()
	for mm: MultiMesh in [bodies, cabins]:
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.instance_count = spots.size()
	bodies.mesh = body
	cabins.mesh = cabin
	for i: int in spots.size():
		var t := spots[i]
		bodies.set_instance_transform(i, t.translated_local(Vector3(0.0, 0.62, 0.0)))
		cabins.set_instance_transform(i, t.translated_local(Vector3(0.0, 1.27, 0.25)))
		var paint := paints[_rng.next_int(paints.size())]
		bodies.set_instance_color(i, paint)
		cabins.set_instance_color(i, paint.darkened(0.55))
	var shell := _mat(Color.WHITE, 0.35)
	shell.vertex_color_use_as_albedo = true
	shell.metallic = 0.4
	for node: MultiMeshInstance3D in [_multi(bodies, shell, "Cars"), _multi(cabins, shell, "CarCabins")]:
		node.visibility_range_end = DETAIL_RANGE
		node.visibility_range_end_margin = 80.0
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## A tree every dozen metres along both sides of each avenue (not the ring: the park's own
## plaza is open).
func _street_trees() -> void:
	var spots: Array[Transform3D] = []
	for line: Array in _street_lines:
		if float(line[2]) != AVENUE_WIDTH:
			continue
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		var along := Vector3(b.x - a.x, b.y - a.y, 0.0)
		var length := along.length()
		var dir := along / maxf(length, 1e-3)
		var side := Vector3(dir.y, -dir.x, 0.0)
		var at_m := 6.0
		while at_m < length:
			for s: float in [-1.0, 1.0]:
				var p := a + dir * at_m + side * s * (AVENUE_WIDTH * 0.5 + 2.5)
				if _on_land(p):
					var size := Vector3(_rng.next_range(3.0, 4.2), _rng.next_range(5.0, 7.0), _rng.next_range(3.0, 4.2))
					spots.append(Transform3D((Basis(Vector3.UP, _rng.next_range(0.0, PI)) * Basis.from_scale(size)), Field.to_world(p + Vector3(0.0, 0.0, size.y * 0.6))))
			at_m += 12.0
	if spots.is_empty():
		return
	var crown := SphereMesh.new()
	crown.radius = 1.0
	crown.height = 2.0
	crown.radial_segments = 8
	crown.rings = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = crown
	mm.instance_count = spots.size()
	for i: int in spots.size():
		mm.set_instance_transform(i, spots[i])
		var g := _rng.next_range(0.6, 0.85)
		mm.set_instance_color(i, Color(g * 0.78, g, g * 0.6))
	var m := _mat(Color.WHITE, 1.0, "forest", 9.0, 1.0)
	m.vertex_color_use_as_albedo = true
	var node := _multi(mm, m, "StreetTrees")
	node.visibility_range_end = DETAIL_RANGE
	node.visibility_range_end_margin = 80.0
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## What stands on the roofs: a parapet round the edge, a plant room over the stairs and lifts,
## air-conditioning units, a water tank on most apartment blocks and a mast on the towers.
func _roofs() -> void:
	var boxes: Array[Array] = []
	var tanks: Array[Transform3D] = []
	for front: String in _buildings:
		for b: Array in _buildings[front]:
			var size: Vector3 = b[2]
			var foot: Vector3 = b[3]
			var yaw: float = b[4]
			var tint: Color = b[1]
			var turn := Basis(Vector3.UP, yaw)
			var top := Field.to_world(foot) + Vector3(0.0, size.y - 1.0, 0.0)
			var put := func(part: Vector3, offset: Vector3, colour: Color) -> void:
				boxes.append([Transform3D((turn * Basis.from_scale(part)), top + turn * offset), colour])
			var concrete := Color(tint.r * 0.95, tint.g * 0.95, tint.b * 0.95)
			var rim := 0.35
			var high := 1.1
			put.call(Vector3(size.x, high, rim), Vector3(0.0, high * 0.5, size.z * 0.5 - rim * 0.5), concrete)
			put.call(Vector3(size.x, high, rim), Vector3(0.0, high * 0.5, -size.z * 0.5 + rim * 0.5), concrete)
			put.call(Vector3(rim, high, size.z), Vector3(size.x * 0.5 - rim * 0.5, high * 0.5, 0.0), concrete)
			put.call(Vector3(rim, high, size.z), Vector3(-size.x * 0.5 + rim * 0.5, high * 0.5, 0.0), concrete)
			var room_x := minf(size.x * 0.3, 7.5)
			var room_z := minf(size.z * 0.45, 6.0)
			if size.y > 14.0 and size.x > 10.0:
				var where := Vector3(_rng.next_range(-0.3, 0.3) * size.x, 1.6, _rng.next_range(-0.2, 0.2) * size.z)
				put.call(Vector3(room_x, 3.2, room_z), where, concrete)
				if (front == "a" or front == "b") and _rng.next_float() < 0.7:
					tanks.append(Transform3D((turn * Basis.from_scale(Vector3(2.0, 2.4, 2.0))), top + turn * (where + Vector3(0.0, 3.2 + 1.2, 0.0))))
			var units := clampi(int(size.x * size.z / 260.0), 1, 6)
			for u: int in units:
				var w := _rng.next_range(1.6, 3.6)
				var d := _rng.next_range(1.2, 2.8)
				var h := _rng.next_range(1.0, 2.0)
				var spot := Vector3(_rng.next_range(-0.5, 0.5) * maxf(size.x - w - 2.0, 0.0), h * 0.5, _rng.next_range(-0.5, 0.5) * maxf(size.z - d - 2.0, 0.0))
				var grey := _rng.next_range(0.68, 0.86)
				put.call(Vector3(w, h, d), spot, Color(grey, grey, grey * 1.02))
			if size.y > 90.0:
				put.call(Vector3(0.6, size.y * 0.12, 0.6), Vector3(0.0, size.y * 0.06, 0.0), Color(0.75, 0.76, 0.78))
	if not boxes.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		mm.mesh = box
		mm.instance_count = boxes.size()
		for i: int in boxes.size():
			mm.set_instance_transform(i, boxes[i][0])
			mm.set_instance_color(i, boxes[i][1])
		var m := _mat(Color.WHITE, 0.9, "concrete", 4.0, 0.4)
		m.vertex_color_use_as_albedo = true
		_dimmed.append(m)
		var node := _multi(mm, m, "Roofs")
		node.visibility_range_end = DETAIL_RANGE * 1.4
		node.visibility_range_end_margin = 100.0
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if not tanks.is_empty():
		var tank := CylinderMesh.new()
		tank.top_radius = 0.5
		tank.bottom_radius = 0.5
		tank.height = 1.0
		tank.radial_segments = 10
		tank.rings = 1
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = tank
		mm.instance_count = tanks.size()
		for i: int in tanks.size():
			mm.set_instance_transform(i, tanks[i])
		var m := _mat(Color(0.82, 0.84, 0.86), 0.5)
		m.metallic = 0.4
		_dimmed.append(m)
		var node := _multi(mm, m, "RoofTanks")
		node.visibility_range_end = DETAIL_RANGE
		node.visibility_range_end_margin = 80.0
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


# --- By the water ---


## The quay a park by the water stands on: land out to `shore` metres beyond home plate.
func _quay(shore: float) -> void:
	_land_rect(-1800.0, 1800.0, -1800.0, shore, "concrete", Color(0.62, 0.63, 0.65), 14.0)
	var tool := _tool()
	_box(tool, Vector3(3600.0, 1.4, 3.0), Vector3(0.0, shore, -1.0))
	_commit(tool, _mat(Color(0.5, 0.51, 0.53), 0.95, "concrete", 8.0), "QuayWall")


## A working harbour beyond the quay's edge: a breakwater ending in a lighthouse, gantry
## cranes and stacked containers, a ship alongside.
func _harbour(shore: float) -> void:
	var stone := _tool()
	for k: int in 16:
		var t := float(k) / 15.0
		_box(stone, Vector3(62.0, 3.2, 10.0), Vector3(560.0 - 840.0 * t, shore + 90.0 + 230.0 * sin(t * PI * 0.5), -0.4), deg_to_rad(-24.0 * cos(t * PI * 0.5)))
	_commit(stone, _mat(Color(0.56, 0.57, 0.58), 0.95, "rock", 12.0, 1.0), "Breakwater")
	_lighthouse(Vector3(-285.0, shore + 320.0, 1.2))
	_yachts(8, Vector2(-500.0, 100.0), Vector2(shore + 80.0, shore + 300.0))
	_cranes(4, Vector3(140.0, shore - 20.0, 0.0), 96.0)
	_containers(Vector3(110.0, shore - 54.0, 0.0), 26, 6)
	_ship(Vector3(330.0, shore + 34.0, 0.0), 0.0, 230.0)


func _lighthouse(foot: Vector3) -> void:
	var white := _tool()
	_cylinder(white, 2.6, 4.2, 24.0, foot)
	_cylinder(white, 5.5, 6.5, 5.0, foot + Vector3(0.0, 0.0, -4.0))
	_commit(white, _mat(Color(0.93, 0.93, 0.9), 0.7, "concrete", 5.0, 0.4), "Lighthouse")
	var red := _tool()
	_cylinder(red, 3.0, 3.0, 1.2, foot + Vector3(0.0, 0.0, 24.0))
	_cylinder(red, 0.2, 2.1, 1.9, foot + Vector3(0.0, 0.0, 28.2))
	_commit(red, _mat(Color(0.75, 0.12, 0.12), 0.6), "LighthouseTrim")
	var lamp := _tool()
	_cylinder(lamp, 1.6, 1.8, 3.0, foot + Vector3(0.0, 0.0, 25.2))
	_commit(lamp, _glowing(Color(1.0, 0.95, 0.75), 9.0), "Beacon")


## Gantry cranes in a row: legs, girders, a boom reaching out over the water.
func _cranes(count: int, first: Vector3, apart: float) -> void:
	var steel := _tool()
	for k: int in count:
		var base := first + Vector3(apart * k, 0.0, 0.0)
		for sx: float in [-13.0, 13.0]:
			for sy: float in [-11.0, 11.0]:
				_beam(steel, base + Vector3(sx, sy, 0.0), base + Vector3(sx, sy, 52.0), 2.2)
			_beam(steel, base + Vector3(sx, -11.0, 50.0), base + Vector3(sx, 11.0, 50.0), 2.4)
			_beam(steel, base + Vector3(sx, -11.0, 8.0), base + Vector3(sx, 11.0, 30.0), 1.2)
		for sy: float in [-11.0, 11.0]:
			_beam(steel, base + Vector3(-15.0, sy, 50.0), base + Vector3(15.0, sy, 50.0), 3.6)
		_beam(steel, base + Vector3(0.0, -22.0, 55.0), base + Vector3(0.0, 78.0, 55.0), 4.4)
		_beam(steel, base + Vector3(0.0, -4.0, 55.0), base + Vector3(0.0, -4.0, 76.0), 3.2)
		_beam(steel, base + Vector3(0.0, -4.0, 75.0), base + Vector3(0.0, 70.0, 57.0), 0.8)
		_beam(steel, base + Vector3(0.0, -4.0, 75.0), base + Vector3(0.0, -20.0, 57.0), 0.8)
		_box(steel, Vector3(9.0, 6.0, 11.0), base + Vector3(0.0, 2.0, 51.0))
	var paint := _mat([Color(0.82, 0.24, 0.16), Color(0.16, 0.36, 0.66), Color(0.86, 0.6, 0.12)][_rng.next_int(3)], 0.55, "metal", 6.0, 0.6, false)
	paint.metallic = 0.3
	_commit(steel, paint, "Cranes")


## Shipping containers in stacks: `along` stacks in each of `rows` rows.
func _containers(first: Vector3, along: int, rows: int) -> void:
	var crate := BoxMesh.new()
	crate.size = Vector3(12.2, 2.6, 2.44)
	var spots: Array[Transform3D] = []
	for row: int in rows:
		for k: int in along:
			for level: int in 1 + _rng.next_int(4):
				spots.append(Transform3D(Basis.IDENTITY, Field.to_world(first + Vector3(k * 13.0, -row * 6.2, 1.3 + level * 2.6))))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = crate
	mm.instance_count = spots.size()
	var paints: Array[Color] = [Color(0.7, 0.2, 0.16), Color(0.16, 0.32, 0.6), Color(0.2, 0.46, 0.3), Color(0.74, 0.5, 0.14), Color(0.5, 0.52, 0.55), Color(0.85, 0.85, 0.82)]
	for i: int in spots.size():
		mm.set_instance_transform(i, spots[i])
		mm.set_instance_color(i, paints[_rng.next_int(paints.size())])
	var m := _mat(Color.WHITE, 0.6, "container", 2.4, 1.0, false)
	m.vertex_color_use_as_albedo = true
	m.metallic = 0.2
	_multi(mm, m, "Containers")


## A cargo ship: a dark hull with a red waterline, a white house aft, a funnel.
func _ship(foot: Vector3, yaw: float, length: float) -> void:
	var across := Vector3(cos(yaw), sin(yaw), 0.0)
	var hull := _tool()
	_box(hull, Vector3(length, 11.0, length * 0.14), foot + Vector3(0.0, 0.0, 3.0), yaw)
	_commit(hull, _mat(Color(0.1, 0.12, 0.16), 0.6, "metal", 8.0, 0.5, false), "Hull")
	var line := _tool()
	_box(line, Vector3(length * 1.002, 2.4, length * 0.141), foot + Vector3(0.0, 0.0, -1.0), yaw)
	_commit(line, _mat(Color(0.5, 0.1, 0.08), 0.7), "Waterline")
	var house := _tool()
	_box(house, Vector3(length * 0.13, 16.0, length * 0.13), foot - across * (length * 0.36) + Vector3(0.0, 0.0, 16.0), yaw)
	_box(house, Vector3(length * 0.05, 8.0, length * 0.05), foot - across * (length * 0.4) + Vector3(0.0, 0.0, 28.0), yaw)
	_commit(house, _mat(Color(0.9, 0.9, 0.88), 0.6), "ShipHouse")
	_containers(foot - across * (length * 0.24) + Vector3(-sin(yaw), cos(yaw), 0.0) * 6.0 + Vector3(0.0, 0.0, 8.0), int(length * 0.55 / 13.0), 3)


## A park on a river: wooded banks, the water crossing the view beyond the outfield, a
## cable-stayed bridge and a plain one over it, and a city on the far bank.
func _riverside() -> void:
	_sea()
	var near := edge + 70.0
	var far := near + _rng.next_range(210.0, 280.0)
	_land_rect(-1800.0, 1800.0, -1800.0, near, "forest", Color(0.62, 0.74, 0.52), 60.0)
	_land_rect(-1800.0, 1800.0, far, 2200.0, "asphalt", Color(0.5, 0.52, 0.5), 40.0)
	var banks := _tool()
	_box(banks, Vector3(3600.0, 2.0, 5.0), Vector3(0.0, near, -1.0))
	_box(banks, Vector3(3600.0, 2.0, 5.0), Vector3(0.0, far, -1.0))
	_commit(banks, _mat(Color(0.55, 0.56, 0.57), 0.95, "concrete", 8.0), "Banks")
	var x := _rng.next_range(140.0, 240.0) * (1.0 if _rng.next_float() < 0.5 else -1.0)
	_cable_bridge(Vector3(x, near - 60.0, 0.0), Vector3(x, far + 60.0, 0.0), 22.0, 92.0, 2)
	_girder_bridge(Vector3(-x * 1.9, near - 40.0, 0.0), Vector3(-x * 1.9, far + 40.0, 0.0), 16.0)
	_trees(150, Vector2(-180.0, 180.0), Vector2(edge + 15.0, edge + 62.0))
	# The far bank: a city, rising toward its middle.
	var grid := deg_to_rad(float(absi(hash(def.id)) % 30))
	var core := _rng.next_range(-180.0, 180.0)
	for i: int in 190:
		var px := _rng.next_range(-900.0, 900.0)
		var py := far + 30.0 + _rng.next_range(0.0, 420.0)
		var tall := clampf(1.0 - absf(px - core) / 520.0, 0.0, 1.0) * _rng.next_range(0.3, 1.0)
		var height := lerpf(20.0, 175.0, tall * tall) + _rng.next_range(0.0, 12.0)
		var fronts: Array = ["a", "c"] if height < 34.0 else (["c", "b", "e"] if height < 85.0 else ["d", "e", "c"])
		var base := _rng.next_range(22.0, 38.0)
		_building(str(fronts[_rng.next_int(fronts.size())]), Vector3(base, height, base * _rng.next_range(0.7, 1.1)), Vector3(px, py, 0.0), grid + float(_rng.next_int(2)) * PI * 0.5)
	_ridge(Color(0.56, 0.62, 0.68), 1250.0, 30.0, 120.0, 2.0)


## A cable-stayed bridge from `from` to `to` (field coordinates): a deck `deck_h` up on piers,
## `towers` pylons `tower_h` tall with fans of cables, lights along the deck at night.
func _cable_bridge(from: Vector3, to: Vector3, deck_h: float, tower_h: float, towers: int) -> void:
	var up := Vector3(0.0, 0.0, 1.0)
	var along := (to - from).normalized()
	var side := along.cross(up).normalized()
	var length := from.distance_to(to)
	var deck := _tool()
	_beam(deck, from + up * deck_h, to + up * deck_h, 3.0)
	for s: float in [-1.0, 1.0]:
		_beam(deck, from + up * (deck_h + 0.5) + side * s * 10.0, to + up * (deck_h + 0.5) + side * s * 10.0, 2.2)
	_beam(deck, from + up * (deck_h - 0.2) - side * 10.0, from + up * (deck_h - 0.2) + side * 10.0, 0.1)
	var slab := _tool()
	var mid := (from + to) * 0.5 + up * deck_h
	_box(slab, Vector3(20.0, 1.4, length), mid, _yaw(along))
	_commit(slab, _mat(Color(0.42, 0.43, 0.45), 0.9, "asphalt", 12.0, 0.5), "BridgeDeck")
	var piers := _tool()
	var n := int(length / 70.0)
	for k: int in n + 1:
		var p := from + along * (length * k / maxf(n, 1.0))
		_beam(piers, p + up * -3.0, p + up * (deck_h - 0.7), 4.6)
	var cables := _tool()
	for t: int in towers:
		var base := from + along * (length * (t + 1.0) / (towers + 1.0))
		for s: float in [-1.0, 1.0]:
			_beam(piers, base + side * s * 11.0 + up * -3.0, base + side * s * 5.0 + up * tower_h, 4.2)
		_beam(piers, base - side * 9.0 + up * (deck_h + 22.0), base + side * 9.0 + up * (deck_h + 22.0), 3.0)
		_beam(piers, base - side * 5.4 + up * (tower_h - 4.0), base + side * 5.4 + up * (tower_h - 4.0), 3.0)
		var span := length / (towers + 1.0) * 0.46
		for k: int in 9:
			var out := span * (k + 1.0) / 9.0
			var high := tower_h - 6.0 - (tower_h - deck_h - 20.0) * (1.0 - (k + 1.0) / 9.0) * 0.5
			for dir: float in [-1.0, 1.0]:
				for s: float in [-1.0, 1.0]:
					_beam(cables, base + side * s * 5.6 + up * high, base + along * dir * out + side * s * 9.6 + up * (deck_h + 0.8), 0.32)
	_commit(piers, _mat(Color(0.84, 0.85, 0.86), 0.8, "concrete", 9.0, 0.5), "BridgePiers")
	_commit(cables, _mat(Color(0.92, 0.92, 0.9), 0.5), "BridgeCables")
	_commit(deck, _glowing(Color(1.0, 0.86, 0.6), 2.2), "BridgeRails")


## A plain bridge: a deck on a row of piers.
func _girder_bridge(from: Vector3, to: Vector3, deck_h: float) -> void:
	var up := Vector3(0.0, 0.0, 1.0)
	var along := (to - from).normalized()
	var length := from.distance_to(to)
	var tool := _tool()
	_box(tool, Vector3(16.0, 2.6, length), (from + to) * 0.5 + up * deck_h, _yaw(along))
	for k: int in int(length / 45.0) + 1:
		var p := from + along * minf(45.0 * k, length)
		_beam(tool, p + up * -3.0, p + up * (deck_h - 1.0), 3.6)
	_commit(tool, _mat(Color(0.6, 0.61, 0.62), 0.9, "concrete", 9.0, 0.6), "GirderBridge")


## A great bridge across the horizon out at sea, `out` metres from home plate.
func _sea_bridge(out: float) -> void:
	var tilt := _rng.next_range(-0.08, 0.08)
	_cable_bridge(Vector3(-1250.0, out - 1250.0 * tilt, 0.0), Vector3(1250.0, out + 1250.0 * tilt, 0.0), 42.0, 168.0, 2)
	_lighthouse(Vector3(_rng.next_range(-420.0, -260.0), edge + 170.0, 0.5))
	var rock := SphereMesh.new()
	rock.radius = 16.0
	rock.height = 9.0
	_add(rock, _mat(Color(0.5, 0.5, 0.48), 1.0, "rock", 10.0, 1.0), "Rock", Vector3(-340.0, edge + 170.0, -1.0))


## A beach on a bay: sand between the park and the sea, a headland to either side with
## hotels along it and hills behind, parasols on the sand, a pier, yachts and islands out on
## the water.
func _beach() -> void:
	_sea()
	var shore := edge + 120.0
	_land_rect(-1800.0, 1800.0, -1800.0, edge + 40.0, "asphalt", Color(0.5, 0.52, 0.5), 40.0)
	_land_rect(-330.0, 330.0, edge + 40.0, shore, "sand", Color(1.0, 0.95, 0.82), 18.0, -0.75)
	# The headlands that close the bay, left and right.
	for s: float in [-1.0, 1.0]:
		var x0 := 330.0 * s
		var x1 := 1800.0 * s
		_land_rect(minf(x0, x1), maxf(x0, x1), edge + 40.0, shore + 520.0, "forest", Color(0.62, 0.72, 0.52), 60.0)
		_ridge(Color(0.5, 0.62, 0.46), 640.0, 40.0, 150.0, 3.0, "forest", -1.0, Vector2(30.0, 100.0) if s > 0.0 else Vector2(-100.0, -30.0))
		for i: int in 16:
			var spec: Array = BUILDINGS["hotel"]
			var size := Vector3(_rng.next_range(spec[0].x, spec[0].y), _rng.next_range(spec[1].x, spec[1].y), _rng.next_range(spec[2].x, spec[2].y))
			var foot := Vector3(s * _rng.next_range(350.0, 760.0), _rng.next_range(shore - 40.0, shore + 420.0), 0.0)
			_building(["b", "e"][_rng.next_int(2)], size, foot, _rng.next_range(-0.4, 0.4))
	# Parasols on the sand.
	var shade := CylinderMesh.new()
	shade.top_radius = 0.1
	shade.bottom_radius = 1.9
	shade.height = 0.9
	shade.radial_segments = 8
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = shade
	mm.instance_count = 220
	var paints: Array[Color] = [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.85), Color(0.95, 0.8, 0.2), Color(0.95, 0.95, 0.92), Color(0.2, 0.7, 0.5)]
	for i: int in mm.instance_count:
		var p := Vector3(_rng.next_range(-320.0, 320.0), _rng.next_range(edge + 52.0, shore - 14.0), 1.9)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Field.to_world(p)))
		mm.set_instance_color(i, paints[_rng.next_int(paints.size())])
	var cloth := _mat(Color.WHITE, 0.8)
	cloth.vertex_color_use_as_albedo = true
	_multi(mm, cloth, "Parasols")
	# A pier out over the water.
	var pier := _tool()
	var px := _rng.next_range(-180.0, 180.0)
	_box(pier, Vector3(7.0, 0.8, 150.0), Vector3(px, shore + 70.0, 2.4))
	for k: int in 12:
		_beam(pier, Vector3(px, shore + 4.0 + k * 12.5, -2.0), Vector3(px, shore + 4.0 + k * 12.5, 2.2), 1.0)
	_commit(pier, _mat(Color(0.5, 0.4, 0.3), 0.85, "bricks", 3.0, 0.5, false), "Pier")
	_yachts(26, Vector2(-300.0, 300.0), Vector2(shore + 60.0, shore + 520.0))
	_trees(90, Vector2(-180.0, 180.0), Vector2(edge + 12.0, edge + 40.0))
	_islands(4)
	_ridge(Color(0.56, 0.64, 0.7), 1500.0, 20.0, 90.0, 2.0)


## Sailing boats on the water: a white hull and a tall sail each.
func _yachts(count: int, across: Vector2, out: Vector2) -> void:
	var hulls := _tool()
	var sails := _tool()
	for i: int in count:
		var at_sea := Vector3(_rng.next_range(across.x, across.y), _rng.next_range(out.x, out.y), 0.0)
		var yaw := _rng.next_range(0.0, TAU)
		_box(hulls, Vector3(3.4, 1.6, 11.0), at_sea + Vector3(0.0, 0.0, -0.9), yaw)
		var mast := at_sea + Vector3(0.0, 0.0, 15.0)
		var boom := Vector3(sin(yaw), -cos(yaw), 0.0) * 5.5
		var pts: Array[Vector3] = [Field.to_world(at_sea + Vector3(0.0, 0.0, 0.6)), Field.to_world(mast), Field.to_world(at_sea + boom + Vector3(0.0, 0.0, 0.9))]
		for k: int in [0, 1, 2, 2, 1, 0]:
			sails.add_vertex(pts[k])
	_commit(hulls, _mat(Color(0.95, 0.95, 0.96), 0.4), "Yachts")
	var cloth := _mat(Color(0.97, 0.97, 0.95), 0.9)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	_commit(sails, cloth, "Sails")


# --- Works and landmarks ---


## A factory district: long sheds, banded chimneys, storage tanks, cooling towers.
func _industrial() -> void:
	var sheds := _tool()
	for i: int in 46:
		var foot := at(_rng.next_range(-110.0, 110.0), _rng.next_range(edge + 50.0, 600.0))
		var size := Vector3(_rng.next_range(40.0, 110.0), _rng.next_range(9.0, 18.0), _rng.next_range(22.0, 44.0))
		_box(sheds, size, foot + Vector3(0.0, 0.0, size.y * 0.5), float(_rng.next_int(2)) * PI * 0.5 + 0.3)
	_commit(sheds, _mat([Color(0.62, 0.66, 0.7), Color(0.5, 0.58, 0.66)][_rng.next_int(2)], 0.6, "container", 3.0, 1.0, false), "Sheds")
	var stripes := _mat(Color.WHITE, 0.8)
	stripes.albedo_texture = _bands(Color(0.8, 0.14, 0.12), Color(0.93, 0.93, 0.9), 8)
	stripes.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var stacks := _tool()
	for i: int in 7:
		_cylinder(stacks, 2.4, 3.8, _rng.next_range(70.0, 130.0), at(_rng.next_range(-70.0, 70.0), _rng.next_range(edge + 120.0, 560.0)), 14)
	_commit(stacks, stripes, "Chimneys")
	var tanks := _tool()
	for i: int in 16:
		var foot := at(_rng.next_range(-90.0, 90.0), _rng.next_range(edge + 60.0, 420.0))
		var r := _rng.next_range(9.0, 19.0)
		for k: int in 1 + _rng.next_int(3):
			_cylinder(tanks, r, r, _rng.next_range(12.0, 20.0), foot + Vector3(k * (r * 2.3), 0.0, 0.0), 22)
	_commit(tanks, _mat(Color(0.86, 0.87, 0.86), 0.5, "metal", 5.0, 0.5, false), "Tanks")
	var towers := _tool()
	for i: int in 2 + _rng.next_int(2):
		var foot := at(_rng.next_range(-50.0, 50.0), _rng.next_range(400.0, 620.0))
		_cylinder(towers, 26.0, 40.0, 50.0, foot, 26)
		_cylinder(towers, 30.0, 26.0, 34.0, foot + Vector3(0.0, 0.0, 50.0), 26)
	_commit(towers, _mat(Color(0.8, 0.8, 0.78), 0.95, "concrete", 12.0, 0.6), "CoolingTowers")
	_containers(at(-30.0, edge + 70.0), 18, 4)
	_scatter([["low", 0.8], ["office", 0.2]], 40, Vector2(-180.0, 180.0), Vector2(edge + 50.0, 520.0))


## A needle tower on a wooded hill, the city's landmark: shaft, a round deck near the top
## (lit at night), an aerial banded red and white.
func _needle_tower(az: float, r: float) -> void:
	var foot := at(az, r)
	var hill := CylinderMesh.new()
	hill.top_radius = 46.0
	hill.bottom_radius = 300.0
	hill.height = 125.0
	hill.radial_segments = 28
	_add(hill, _mat(Color(0.6, 0.72, 0.54), 1.0, "forest", 70.0, 1.0), "TowerHill", foot + Vector3(0.0, 0.0, 61.0))
	var top := 125.0
	var shaft := _tool()
	_cylinder(shaft, 3.2, 6.0, 118.0, foot + Vector3(0.0, 0.0, top), 18)
	_cylinder(shaft, 14.0, 9.0, 6.0, foot + Vector3(0.0, 0.0, top + 86.0), 24)
	_cylinder(shaft, 9.0, 14.0, 5.0, foot + Vector3(0.0, 0.0, top + 98.0), 24)
	_commit(shaft, _mat(Color(0.86, 0.86, 0.84), 0.8, "concrete", 8.0, 0.4), "Tower")
	var deck := _tool()
	_cylinder(deck, 14.2, 14.2, 6.0, foot + Vector3(0.0, 0.0, top + 92.0), 24)
	_commit(deck, _glowing(Color(0.75, 0.9, 1.0), 2.4), "TowerDeck")
	var aerial := _tool()
	_cylinder(aerial, 0.5, 1.4, 62.0, foot + Vector3(0.0, 0.0, top + 118.0), 8)
	var stripes := _mat(Color.WHITE, 0.7)
	stripes.albedo_texture = _bands(Color(0.85, 0.15, 0.12), Color(0.95, 0.95, 0.93), 6)
	stripes.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_commit(aerial, stripes, "TowerAerial")


## An indoor arena: a low drum under a shallow dome.
func _arena(az: float, r: float) -> void:
	var foot := at(az, r)
	var drum := _tool()
	_cylinder(drum, 62.0, 62.0, 16.0, foot, 40)
	_commit(drum, _mat(Color(0.78, 0.79, 0.8), 0.8, "concrete", 10.0, 0.6), "ArenaWall")
	var dome := SphereMesh.new()
	dome.radius = 62.0
	dome.height = 44.0
	dome.is_hemisphere = true
	dome.radial_segments = 40
	dome.rings = 10
	var skin := _mat(Color(0.88, 0.9, 0.92), 0.35, "metal", 9.0, 0.6, false)
	skin.metallic = 0.5
	_add(dome, skin, "ArenaDome", foot + Vector3(0.0, 0.0, 16.0))
	var band := _tool()
	_cylinder(band, 62.3, 62.3, 2.2, foot + Vector3(0.0, 0.0, 9.0), 40)
	_commit(band, _glowing(Color(0.5, 0.75, 1.0), 1.6), "ArenaBand")


## The athletics stadium next door: an oval bowl under a ring of roof, four masts of lights.
func _bowl(az: float, r: float) -> void:
	var foot := at(az, r)
	var wall := _tool()
	_cylinder(wall, 118.0, 104.0, 24.0, foot, 44)
	_commit(wall, _mat(Color(0.72, 0.73, 0.75), 0.85, "concrete", 12.0, 0.7), "BowlWall")
	var roof := _tool()
	_cylinder(roof, 122.0, 118.0, 3.0, foot + Vector3(0.0, 0.0, 24.0), 44)
	var white := _mat(Color(0.92, 0.93, 0.94), 0.4, "metal", 9.0, 0.5, false)
	white.metallic = 0.4
	_commit(roof, white, "BowlRoof")
	var masts := _tool()
	var lamps := _tool()
	for k: int in 4:
		var p := foot + Vector3(cos(PI * 0.25 + k * PI * 0.5), sin(PI * 0.25 + k * PI * 0.5), 0.0) * 128.0
		_beam(masts, p, p + Vector3(0.0, 0.0, 58.0), 2.0)
		_box(lamps, Vector3(12.0, 7.0, 1.0), p + Vector3(0.0, 0.0, 60.0), _yaw(p - foot))
	_commit(masts, _mat(Color(0.55, 0.56, 0.58), 0.5), "BowlMasts")
	_commit(lamps, _glowing(Color(1.0, 0.97, 0.9), 5.0), "BowlLamps")


## A car park: rows of cars on tarmac, between compass bearings `sector` just outside the park.
func _parking(sector: Vector2, near: float, rows: int, per_row: int) -> void:
	var car := BoxMesh.new()
	car.size = Vector3(1.8, 1.45, 4.4)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = car
	var spots: Array[Transform3D] = []
	var mid := (sector.x + sector.y) * 0.5
	var out := Vector3(sin(deg_to_rad(mid)), cos(deg_to_rad(mid)), 0.0)
	var yaw := _yaw(out)
	var across := Vector3(out.y, -out.x, 0.0)
	var origin := at(mid, near)
	for row: int in rows:
		for k: int in per_row:
			if _rng.next_float() < 0.22:
				continue
			var p := origin + across * ((k - per_row * 0.5) * 2.6) + out * (row * 8.4 + (5.2 if row % 2 == 1 else 0.0)) + Vector3(0.0, 0.0, 0.2)
			spots.append(Transform3D(Basis(Vector3.UP, yaw), Field.to_world(p)))
	mm.instance_count = spots.size()
	var paints: Array[Color] = [Color(0.9, 0.9, 0.9), Color(0.08, 0.08, 0.09), Color(0.55, 0.57, 0.6), Color(0.75, 0.76, 0.78), Color(0.6, 0.1, 0.1), Color(0.12, 0.2, 0.45)]
	for i: int in spots.size():
		mm.set_instance_transform(i, spots[i])
		mm.set_instance_color(i, paints[_rng.next_int(paints.size())])
	var paint := _mat(Color.WHITE, 0.3)
	paint.vertex_color_use_as_albedo = true
	paint.metallic = 0.5
	_multi(mm, paint, "Cars")


## A big wheel on the front: a rim on spokes, cabins round it, turning slowly; lit at night.
func _big_wheel(az: float, r: float) -> void:
	var hub := at(az, r, 58.0)
	var face := Vector3(CENTRE.x - hub.x, CENTRE.y - hub.y, 0.0).normalized()
	var across := Vector3(face.y, -face.x, 0.0)
	var up := Vector3(0.0, 0.0, 1.0)
	var radius := 50.0
	var legs := _tool()
	for s: float in [-1.0, 1.0]:
		for d: float in [-1.0, 1.0]:
			_beam(legs, hub + face * d * 7.0, hub + across * s * 26.0 + face * d * 12.0 - up * 58.0, 2.4)
	_beam(legs, hub - face * 8.0, hub + face * 8.0, 4.0)
	_commit(legs, _mat(Color(0.9, 0.9, 0.92), 0.5, "metal", 6.0, 0.4, false), "WheelLegs")
	# The wheel itself is built about its hub and turned by its shader.
	var wheel := _tool()
	var rim := _tool()
	var cabins := _tool()
	const SPOKES := 24
	for k: int in SPOKES:
		var a := TAU * k / SPOKES
		var b := TAU * (k + 1) / SPOKES
		var pa := (across * cos(a) + up * sin(a)) * radius
		var pb := (across * cos(b) + up * sin(b)) * radius
		_beam(wheel, Vector3.ZERO, pa, 0.5)
		for d: float in [-1.0, 1.0]:
			_beam(rim, pa + face * d * 2.0, pb + face * d * 2.0, 0.9)
		_beam(wheel, pa - face * 2.0, pa + face * 2.0, 0.5)
		_box(cabins, Vector3(3.4, 3.8, 3.4), pa * 1.07, _yaw(face))
	var spin := load("res://stadium/spin.gdshader") as Shader
	for part: Array in [[wheel, Color(0.92, 0.92, 0.94), 0.0, "Wheel"], [rim, Color(1.0, 0.5, 0.7), 2.6, "WheelRim"], [cabins, Color(0.95, 0.75, 0.2), 0.0, "WheelCabins"]]:
		var tool: SurfaceTool = part[0]
		tool.generate_normals()
		var material := ShaderMaterial.new()
		material.shader = spin
		material.set_shader_parameter(&"colour", part[1])
		material.set_shader_parameter(&"axis", Field.to_world(face))
		material.set_shader_parameter(&"speed", 0.07)
		material.set_shader_parameter(&"glow", 0.0)
		if float(part[2]) > 0.0:
			_spinning_glows.append([material, float(part[2])])
		_add(tool.commit(), material, str(part[3]), hub)


var _spinning_glows: Array[Array] = []


## Wind turbines along a ridge: `count` of them `r` metres out, their blades turning.
func _turbines(count: int, sector: Vector2, r: float, ground: float) -> void:
	var masts := _tool()
	var spin := load("res://stadium/spin.gdshader") as Shader
	for i: int in count:
		var foot := at(lerpf(sector.x, sector.y, (i + 0.5) / count) + _rng.next_range(-3.0, 3.0), r + _rng.next_range(-40.0, 40.0), ground)
		_cylinder(masts, 1.6, 2.8, 86.0, foot, 12)
		var hub := foot + Vector3(0.0, 0.0, 88.0)
		var face := Vector3(CENTRE.x - hub.x, CENTRE.y - hub.y, 0.0).normalized()
		var across := Vector3(face.y, -face.x, 0.0)
		_box(masts, Vector3(4.0, 4.0, 10.0), hub - face * 3.0, _yaw(face))
		# Each rotor is its own mesh, turned about its hub.
		var rotor := _tool()
		for k: int in 3:
			var a := TAU * k / 3.0 + _rng.next_range(0.0, 1.0)
			_beam(rotor, face * 2.4, face * 2.4 + (across * cos(a) + Vector3(0.0, 0.0, 1.0) * sin(a)) * 46.0, 1.5)
		rotor.generate_normals()
		var material := ShaderMaterial.new()
		material.shader = spin
		material.set_shader_parameter(&"colour", Color(0.95, 0.95, 0.96))
		material.set_shader_parameter(&"axis", Field.to_world(face))
		material.set_shader_parameter(&"speed", _rng.next_range(0.7, 1.1))
		_add(rotor.commit(), material, "Rotor", hub)
	_commit(masts, _mat(Color(0.94, 0.94, 0.95), 0.6), "TurbineMasts")


## Farmland: a patchwork of paddies and fields under everything.
func _fields() -> void:
	const N := 512
	var image := Image.create(N, N, true, Image.FORMAT_RGB8)
	image.fill(Color(0.36, 0.5, 0.24))
	var paints: Array[Color] = [Color(0.4, 0.56, 0.24), Color(0.52, 0.6, 0.26), Color(0.66, 0.62, 0.3), Color(0.34, 0.46, 0.22), Color(0.5, 0.42, 0.28), Color(0.44, 0.6, 0.3)]
	var patches := Rng.new(hash(def.id) + 77)
	for i: int in 420:
		var w := 10 + patches.next_int(34)
		var h := 8 + patches.next_int(26)
		var x := patches.next_int(N - w)
		var y := patches.next_int(N - h)
		var c := paints[patches.next_int(paints.size())] * patches.next_range(0.85, 1.1)
		image.fill_rect(Rect2i(x, y, w, h), Color(c.r, c.g, c.b))
		# A dyke round each field.
		image.fill_rect(Rect2i(x, y, w, 1), Color(0.3, 0.36, 0.2))
		image.fill_rect(Rect2i(x, y, 1, h), Color(0.3, 0.36, 0.2))
	image.generate_mipmaps()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3200.0, 3200.0)
	var m := _mat(Color.WHITE, 1.0)
	m.albedo_texture = ImageTexture.create_from_image(image)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.detail_enabled = true
	m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.detail_albedo = SurfaceLibrary.texture("grass", "color")
	m.uv2_triplanar = true
	m.uv2_world_triplanar = true
	m.uv2_scale = Vector3.ONE / 14.0
	m.albedo_color = Color(2.6, 2.6, 2.6)
	_add(plane, m, "Fields", Vector3(0.0, 0.0, -0.6))


## Plastic greenhouses in rows: long white tunnels.
func _greenhouses(groups: int, sector: Vector2, reach: Vector2) -> void:
	var tunnel := CapsuleMesh.new()
	tunnel.radius = 3.2
	tunnel.height = 46.0
	tunnel.radial_segments = 10
	tunnel.rings = 3
	var spots: Array[Transform3D] = []
	for g: int in groups:
		var origin := at(_rng.next_range(sector.x, sector.y), _rng.next_range(reach.x, reach.y))
		var yaw := _rng.next_range(0.0, PI)
		var lie := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)
		var across := Vector3(cos(yaw), sin(yaw), 0.0)
		for k: int in 4 + _rng.next_int(5):
			spots.append(Transform3D(lie, Field.to_world(origin + across * (k * 7.4) + Vector3(0.0, 0.0, -0.4))))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tunnel
	mm.instance_count = spots.size()
	for i: int in spots.size():
		mm.set_instance_transform(i, spots[i])
	_multi(mm, _mat(Color(0.9, 0.93, 0.92), 0.25), "Greenhouses")
