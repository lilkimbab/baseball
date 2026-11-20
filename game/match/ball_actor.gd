class_name BallActor
extends Node3D
## Draws the ball where BallSim says it is, at its real size (73 mm across) with its stitched
## cover, and a small blob shadow on the ground to show height.

const COVER := "res://assets/props/ball.png"

var _ball: MeshInstance3D
var _shadow: MeshInstance3D
var _radius := 0.0366


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = _radius
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.97, 0.97, 0.94)
	white.roughness = 0.5
	if ResourceLoader.exists(COVER):
		white.albedo_color = Color.WHITE
		white.albedo_texture = load(COVER) as Texture2D
	_ball = MeshInstance3D.new()
	_ball.mesh = sphere
	_ball.material_override = white
	add_child(_ball)

	var disc := CylinderMesh.new()
	disc.top_radius = 0.06
	disc.bottom_radius = 0.06
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
