class_name BallActor
extends Node3D
## Draws the ball where BallSim says it is. Slightly larger than life so it reads on screen,
## with a blob shadow on the ground to show height.

const VISUAL_SCALE := 1.5

var _ball: MeshInstance3D
var _shadow: MeshInstance3D
var _radius := 0.0366


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = _radius * VISUAL_SCALE
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.97, 0.97, 0.94)
	white.roughness = 0.5
	_ball = MeshInstance3D.new()
	_ball.mesh = sphere
	_ball.material_override = white
	add_child(_ball)

	var disc := CylinderMesh.new()
	disc.top_radius = 0.09
	disc.bottom_radius = 0.09
	disc.height = 0.004
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.0, 0.0, 0.0, 0.45)
	dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow = MeshInstance3D.new()
	_shadow.mesh = disc
	_shadow.material_override = dark
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)


## Shows the ball at a field-space position.
func show_at(field_pos: Vector3) -> void:
	visible = true
	_ball.position = Field.to_world(field_pos)
	_shadow.position = Field.to_world(Vector3(field_pos.x, field_pos.y, 0.045))
	var fade := clampf(1.0 - field_pos.z / 25.0, 0.25, 1.0)
	_shadow.scale = Vector3(fade, 1.0, fade)


func world_position() -> Vector3:
	return _ball.global_position
