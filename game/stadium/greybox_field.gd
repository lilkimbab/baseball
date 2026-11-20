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
const WALL := Color(0.08, 0.2, 0.36)
const CHALK := Color(0.95, 0.95, 0.95)


func _ready() -> void:
	_build_ground()
	_build_infield()
	_build_foul_lines()
	_build_wall()


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


func _build_ground() -> void:
	var grass := PlaneMesh.new()
	grass.size = Vector2(320.0, 320.0)
	_add(grass, GRASS, Vector3(0.0, 60.0, 0.0))


func _build_infield() -> void:
	var half := Field.BASE_DIAGONAL
	var dirt := PlaneMesh.new()
	dirt.size = Vector2(Field.BASE_DISTANCE + 11.0, Field.BASE_DISTANCE + 11.0)
	_add(dirt, DIRT, Vector3(0.0, half, 0.01), PI / 4.0)
	var inner := PlaneMesh.new()
	inner.size = Vector2(Field.BASE_DISTANCE - 2.4, Field.BASE_DISTANCE - 2.4)
	_add(inner, INFIELD_GRASS, Vector3(0.0, half, 0.02), PI / 4.0)

	var mound := CylinderMesh.new()
	mound.top_radius = 1.2
	mound.bottom_radius = Field.MOUND_RADIUS
	mound.height = Field.MOUND_HEIGHT
	_add(mound, DIRT, Vector3(0.0, Field.MOUND_CENTER_Y, Field.MOUND_HEIGHT * 0.5))
	var rubber := BoxMesh.new()
	rubber.size = Vector3(0.61, 0.03, 0.15)
	_add(rubber, CHALK, Vector3(0.0, Field.RUBBER_Y + 0.075, Field.MOUND_HEIGHT + 0.015))

	var home_circle := CylinderMesh.new()
	home_circle.top_radius = 3.96
	home_circle.bottom_radius = 3.96
	home_circle.height = 0.02
	_add(home_circle, DIRT, Vector3(0.0, 0.2, 0.02))

	var base := BoxMesh.new()
	base.size = Vector3(0.457, 0.08, 0.457)
	var bases: Array[Vector3] = [Field.FIRST_BASE, Field.SECOND_BASE, Field.THIRD_BASE]
	for b: Vector3 in bases:
		_add(base, CHALK, b + Vector3(0.0, 0.0, 0.07), PI / 4.0)
	var plate := BoxMesh.new()
	plate.size = Vector3(Field.PLATE_WIDTH, 0.02, Field.PLATE_FRONT_Y)
	_add(plate, CHALK, Vector3(0.0, Field.PLATE_FRONT_Y * 0.5, 0.04))


func _build_foul_lines() -> void:
	var length := fence.distance_at(45.0)
	var line := BoxMesh.new()
	line.size = Vector3(0.1, 0.01, length)
	var mid := length * 0.5 / sqrt(2.0)
	_add(line, CHALK, Vector3(mid, mid, 0.035), -PI / 4.0)
	_add(line, CHALK, Vector3(-mid, mid, 0.035), PI / 4.0)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.08
	pole.bottom_radius = 0.08
	pole.height = 12.0
	var corner := length / sqrt(2.0)
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
