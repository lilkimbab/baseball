class_name MenuBackdrop
extends CanvasLayer
## What is behind the menus (docs/04 section 5): the ballpark itself, live — stands, crowd,
## lights — seen by a camera that drifts slowly and moves to another vantage as the screen
## changes (behind the plate for the hub, the outfield for a quick game, the mound for the
## practice field). It sits under every menu screen and stays through the changes between
## them; when a game starts it goes away (the game builds its own park).
##
## Not made when there is no display (tests).

## Each vantage: where the camera is, what it looks at (field coordinates: x first base, y
## centre field, z up), its field of view, and how far it drifts side to side (m).
const VIEWS := {
	&"title": [Vector3(0.0, -46.0, 30.0), Vector3(0.0, 62.0, 0.0), 48.0, 5.0],
	&"home": [Vector3(5.0, -9.0, 5.5), Vector3(-2.0, 48.0, 5.0), 60.0, 2.0],
	&"field": [Vector3(13.0, 3.0, 2.3), Vector3(-22.0, 62.0, 7.0), 54.0, 1.2],
	&"outfield": [Vector3(-28.0, 124.0, 24.0), Vector3(2.0, 18.0, 0.0), 42.0, 4.0],
	&"mound": [Vector3(3.2, 27.0, 3.4), Vector3(0.0, 0.0, 1.2), 44.0, 0.8],
	&"dugout": [Vector3(-15.0, -7.0, 2.2), Vector3(14.0, 38.0, 6.0), 58.0, 1.2],
	&"stands": [Vector3(46.0, 30.0, 16.0), Vector3(-6.0, 22.0, 0.0), 50.0, 2.5],
}
const MOVE_SECONDS := 1.6

static var _instance: MenuBackdrop

var view: StringName = &"home"
var _camera: Camera3D
var _from: Array = []
var _to: Array = []
var _moved := MOVE_SECONDS
var _clock := 0.0
var _viewport: SubViewport


## Shows the backdrop behind a menu screen, from this vantage.
static func show_for(screen: Node, vantage: StringName) -> void:
	if DisplayServer.get_name() == "headless" or not screen.is_inside_tree():
		return
	if _instance == null or not is_instance_valid(_instance):
		_instance = MenuBackdrop.new()
		_instance.view = vantage
		screen.get_tree().root.add_child.call_deferred(_instance)
	else:
		_instance.go(vantage)


static func active() -> bool:
	return _instance != null and is_instance_valid(_instance)


func _ready() -> void:
	layer = -10
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	# The picture is behind glass panels and out of focus: three quarters of the size will do.
	_viewport.scaling_3d_scale = 0.75
	holder.add_child(_viewport)
	var def := _park()
	var park := StadiumBuilder.new(def)
	_viewport.add_child(park)
	# A bright afternoon: the lobby is the park on a game day.
	var lighting := ParkLighting.new(def, &"day")
	_viewport.add_child(lighting)
	park.set_lights(lighting.lights_on(), lighting.darkness())
	var crowd := Crowd.new(park)
	crowd.fill = 0.75
	crowd.density = [0.3, 0.6, 1.0][clampi(Settings.quality, 0, 2)]
	_viewport.add_child(crowd)
	_camera = Camera3D.new()
	_camera.far = 900.0
	var lens := CameraAttributesPractical.new()
	lens.dof_blur_far_enabled = true
	lens.dof_blur_far_distance = 60.0
	lens.dof_blur_far_transition = 80.0
	lens.dof_blur_amount = 0.035
	_camera.attributes = lens
	_viewport.add_child(_camera)
	_to = VIEWS.get(view, VIEWS[&"home"])
	_from = _to
	_place(0.0)
	# The park dimmed toward the edges, so the menus read over it.
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec2 c = UV - vec2(0.5);\n\tfloat edge = smoothstep(0.35, 0.9, length(c * vec2(1.0, 1.2)));\n\tCOLOR = vec4(0.015, 0.018, 0.025, 0.2 + 0.5 * edge);\n}\n"
	material.shader = shader
	shade.material = material
	add_child(shade)


## The park of the club being managed, if a league is on; otherwise the first of the parks.
static func _park() -> StadiumDef:
	var ids := StadiumIO.ids()
	if ids.is_empty():
		return StadiumDef.standard()
	if LeagueSession.season != null:
		return MatchScene.home_def(LeagueSession.season.teams[LeagueSession.season.my_team])
	# No club yet: the first club's own park.
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	return MatchScene.home_def(clubs[0]) if not clubs.is_empty() else StadiumIO.load_park(ids[0])


## Moves the camera to another vantage.
func go(vantage: StringName) -> void:
	if vantage == view or not VIEWS.has(vantage):
		return
	_from = _now()
	_to = VIEWS[vantage]
	view = vantage
	_moved = 0.0


func _now() -> Array:
	var k := ease(clampf(_moved / MOVE_SECONDS, 0.0, 1.0), -2.2)
	return [(_from[0] as Vector3).lerp(_to[0], k), (_from[1] as Vector3).lerp(_to[1], k), lerpf(_from[2], _to[2], k), lerpf(_from[3], _to[3], k)]


func _place(delta: float) -> void:
	_clock += delta
	_moved = minf(_moved + delta, MOVE_SECONDS)
	var at := _now()
	var eye: Vector3 = at[0]
	var target: Vector3 = at[1]
	var across := (target - eye).cross(Vector3(0.0, 0.0, 1.0)).normalized()
	eye += across * sin(_clock * 0.11) * float(at[3]) + Vector3(0.0, 0.0, sin(_clock * 0.07) * float(at[3]) * 0.25)
	_camera.fov = float(at[2])
	_camera.look_at_from_position(Field.to_world(eye), Field.to_world(target))


func _process(delta: float) -> void:
	# A scene that is not a menu has started (a game): the backdrop goes.
	var scene := get_tree().current_scene
	if scene != null and not scene.is_in_group(&"menu"):
		_instance = null
		queue_free()
		return
	_place(delta)
