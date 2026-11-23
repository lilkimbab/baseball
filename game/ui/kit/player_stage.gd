class_name PlayerStage
extends SubViewportContainer
## A player standing in the menus (docs/04 section 5; the reference's player screens): the game's
## own figure — his height and build, his face, his club's uniform and number — lit as in a
## studio, turning slowly, on a clear background so the ballpark shows behind him.

## How the camera frames him: the whole figure, head and chest, or a headshot (head and the
## top of the shoulders, as the reference games' lists show a player).
enum Framing { FULL, BUST, HEAD }

var framing: Framing = Framing.FULL
var turning := true
## Swinging instead of standing (the title's cover player): the batter's own recorded swing
## (MotionLibrary), round and round — set, the swing slowed for show, the finish held — or the
## game's key poses without the motion pack.
var swinging := false
var _swing: JointClip
var _launch := 0.0
var _contact := 0.0
var _finish := 0.0
## Which way the swinging batter is turned toward the viewer (radians; the capture tool tries
## others).
static var swing_turn := PI
var _viewport: SubViewport
var _puppet: SkinnedPuppet
var _camera: Camera3D
var _angle := -0.12
var _clock := 0.0
var _pending: Array = []


static func make(width: float, height: float, frame: Framing = Framing.FULL) -> PlayerStage:
	var stage := PlayerStage.new()
	stage.custom_minimum_size = Vector2(width, height)
	stage.framing = frame
	return stage


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.78)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	var world := WorldEnvironment.new()
	world.environment = env
	_viewport.add_child(world)
	# Key from the front left above, a cool rim from behind, a soft fill from the right.
	for spec: Array in [[Vector3(-38.0, -35.0, 0.0), Color(1.0, 0.95, 0.88), 1.5, true], [Vector3(-25.0, 150.0, 0.0), Color(0.7, 0.82, 1.0), 1.3, false], [Vector3(-10.0, 60.0, 0.0), Color(0.9, 0.9, 1.0), 0.35, false]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = spec[0]
		light.light_color = spec[1]
		light.light_energy = spec[2]
		light.shadow_enabled = spec[3]
		_viewport.add_child(light)
	_camera = Camera3D.new()
	_viewport.add_child(_camera)


## Shows a player in his club's uniform (home whites unless `home` is off).
func show_player(p: Player, team: Team, home: bool = true) -> void:
	_pending = [p, team, home]
	# The figure builds itself as it enters the scene: wait until the stage is in it.
	if is_inside_tree():
		_show()


func _ready() -> void:
	if not _pending.is_empty():
		_show()


func _show() -> void:
	var p: Player = _pending[0]
	var team: Team = _pending[1]
	var home: bool = _pending[2]
	_pending = []
	if not SkinnedPuppet.available():
		return
	if _puppet != null:
		_puppet.queue_free()
	_puppet = SkinnedPuppet.new()
	var style := UniformStyle.for_team(team, home) if team != null else UniformStyle.make(Color(0.94, 0.94, 0.96), Color(0.92, 0.92, 0.94), Color(0.1, 0.15, 0.35), Color(0.1, 0.15, 0.35), "")
	style.number = p.number
	style.player_name = p.name
	_puppet.uniform = style
	_puppet.set_colors(style.jersey, style.pants, style.cap)
	_puppet.uniform = style
	_puppet.show_glove = false
	_viewport.add_child(_puppet)
	_puppet.set_body(p.height_cm / 100.0, SkinnedPuppet.build_for(p.height_cm, p.weight_kg, p.primary_position()))
	_puppet.set_hair(1 + absi(hash(p.id)) % 4, MatchScene.hair_color_of(p))
	_puppet.set_face(p.id, 2026 - p.born)
	if team != null:
		_puppet.set_logo(style.cap_letter, style.cap_ink())
	_puppet.repaint()
	_puppet.apply(PuppetClips.standing())
	if swinging:
		# Both hands round the bat, as a batter in a game holds it (else the fingers stay open
		# and the bat floats off the palms).
		_puppet.show_bat = true
		_puppet.left_grip = Puppet.Grip.BAT
		_puppet.right_grip = Puppet.Grip.BAT
		var form := FormCatalog.swing_form(p, &"R")
		_swing = MotionLibrary.find(&"swing", StringName(form) if form != "" else &"default")
		if _swing == null:
			_swing = MotionLibrary.find(&"swing")
		if _swing != null:
			_contact = _swing.event(&"contact", _swing.duration * 0.8)
			_launch = _swing.event(&"launch", _contact - 0.13)
			_finish = minf(_swing.duration, _contact + 0.55)
	_frame(p.height_cm / 100.0)


func _frame(height: float) -> void:
	if swinging:
		# A little wider and lower than standing, for the bat's sweep.
		_camera.fov = 30.0
		_camera.look_at_from_position(Vector3(0.0, height * 0.5, 4.9), Vector3(0.0, height * 0.5, 0.0))
		return
	if framing == Framing.HEAD:
		_camera.fov = 16.0
		_camera.look_at_from_position(Vector3(0.0, height - 0.1, 1.45), Vector3(0.0, height - 0.15, 0.0))
	elif framing == Framing.BUST:
		_camera.fov = 20.0
		_camera.look_at_from_position(Vector3(0.0, height - 0.16, 2.3), Vector3(0.0, height - 0.2, 0.0))
	else:
		_camera.fov = 26.0
		_camera.look_at_from_position(Vector3(0.0, height * 0.56, 4.6), Vector3(0.0, height * 0.52, 0.0))


func _process(delta: float) -> void:
	if _puppet == null:
		return
	_clock += delta
	if swinging:
		_swing_pose()
		return
	# He turns a little one way and the other, never his back to the viewer.
	if turning:
		_angle = 0.28 * sin(_clock * 0.4) - 0.12
	# The figure faces away from the camera at rest: turned to face it.
	_puppet.rotation.y = PI + _angle


## One turn of the swing (s): the stance held (SET), the load and the swing at SLOW of its speed,
## the finish held (HOLD), then back into the stance (BACK).
const SET := 0.9
const SLOW := 0.55
const HOLD := 1.1
const BACK := 0.45


## The swing at this moment of its turn, the batter seen from the third-base side and in front,
## as a cover shot has him.
func _swing_pose() -> void:
	# (From behind the plate's side: his name and number in the finish, his chest at the set —
	# the user's pick of four, 2026-11-23.)
	_puppet.rotation.y = swing_turn
	if _swing == null:
		# Without the motion pack: the game's own key poses.
		var u := fmod(_clock, 3.2) / 3.2
		_puppet.apply(PuppetClips.swing(clampf((u - 0.3) * 2.2, 0.0, 1.0), 0.0, 0.8))
		return
	var start := maxf(_launch - 0.45, 0.0)
	var through := (_finish - start) / SLOW
	var turn := SET + through + HOLD + BACK
	var t := fmod(_clock, turn)
	var at := start
	if t >= SET and t < SET + through:
		at = start + (t - SET) * SLOW
	elif t >= SET + through:
		at = _finish
	var frame := _swing.sample(at)
	if t >= SET + through + HOLD:
		# Back into the stance: from the finish to the set position.
		var k := ease((t - SET - through - HOLD) / BACK, -1.8)
		var rest := _swing.sample(start)
		for joint: StringName in frame:
			if rest.has(joint):
				frame[joint] = frame[joint].lerp(rest[joint], k)
	_puppet.apply_joints(frame, _swing)
