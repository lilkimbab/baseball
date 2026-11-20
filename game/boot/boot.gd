extends Node3D
## Entry scene for stage S1: an empty ballpark with a camera, sky, sun and a frame-rate readout.
## Later stages replace this with the title screen and hub.

## Camera placement in field coordinates (docs/05, "batting, third person"): low and just
## behind the plate on the first-base side, so a right-handed batter fills the left third.
@export var camera_position := Vector3(0.55, -2.7, 0.9)
@export var camera_target := Vector3(-0.2, 18.4, -0.45)
@export_range(10.0, 90.0) var camera_fov := 45.0

var _fps_label: Label


func _ready() -> void:
	_build_environment()
	add_child(GreyboxField.new())
	_build_placeholder_players()
	_build_camera()
	_build_overlay()


func _process(_delta: float) -> void:
	_fps_label.text = "%d fps" % Engine.get_frames_per_second()


func _build_environment() -> void:
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)


## Eight fielders at standard depth plus a batter, so scale and framing can be judged.
## The catcher is left out: the batting camera sits where he crouches.
func _build_placeholder_players() -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.28
	capsule.height = 1.82
	var half_height := capsule.height * 0.5
	var fielders: Array[Vector3] = [
		Vector3(0.0, Field.RUBBER_Y - 0.2, Field.MOUND_HEIGHT),
		Vector3(21.0, 24.0, 0.0),
		Vector3(9.0, 36.0, 0.0),
		Vector3(-21.0, 24.0, 0.0),
		Vector3(-9.0, 36.0, 0.0),
		Vector3(-45.0, 75.0, 0.0),
		Vector3(0.0, 95.0, 0.0),
		Vector3(45.0, 75.0, 0.0),
	]
	for p: Vector3 in fielders:
		_add_capsule(capsule, Color(0.92, 0.92, 0.95), p + Vector3(0.0, 0.0, half_height))
	_add_capsule(capsule, Color(0.75, 0.12, 0.12), Vector3(-0.9, 0.3, half_height))


func _add_capsule(mesh: Mesh, color: Color, at: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = Field.to_world(at)
	add_child(mi)


func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.fov = camera_fov
	cam.far = 600.0
	add_child(cam)
	cam.look_at_from_position(Field.to_world(camera_position), Field.to_world(camera_target))
	cam.make_current()


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_fps_label = Label.new()
	_fps_label.position = Vector2(12.0, 8.0)
	layer.add_child(_fps_label)
