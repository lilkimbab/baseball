extends SceneTree
## Photographs a player standing, turned to several angles side by side without perspective:
## a tailor's view of the figure, for checking proportions and the cut of the uniform against
## photographs (docs/09 section 4).
##
##   ./dev tool-win figure_shots build/figure/now [--build standard] [--team 22] [--away]
##       [--headgear cap|helmet|none] [--height 1.83] [--views 0,35,90,180] [--pose standing|stance|ready]
##       [--player 3] [--mirror] [--bare] [--veins 0..1] [--umpire plate|base] [--sleeves] [--socks] [--guards] [--zoom head|top|arm|legs]
##
## --bare hides the cap and lettering details (the body and plain uniform alone).

var _out := "user://figure.png"
var _frames := 0
var _args: Dictionary = {}


func _initialize() -> void:
	_args = CmdArgs.parse(OS.get_cmdline_user_args())
	_out = str(_args.get("out", _out))
	if not _out.ends_with(".png"):
		_out += ".png"


## (Built on the first frame: a figure loads its model as it enters a running scene.)
func _build() -> void:
	var views: Array[float] = []
	for text: String in str(_args.get("views", "0,35,90,180")).split(","):
		views.append(float(text))
	var clubs := RosterIO.load_pack(LeagueSession.PACK)
	var team: Team = clubs[int(str(_args.get("team", "22"))) % clubs.size()]
	var player: Player = team.players[int(str(_args.get("player", "3"))) % team.players.size()]
	var height := float(str(_args.get("height", "1.83")))
	var build := StringName(str(_args.get("build", "standard")))
	var zoom := str(_args.get("zoom", ""))

	var stage := Node3D.new()
	root.add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.23, 0.24, 0.27)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.74, 0.82)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	var world := WorldEnvironment.new()
	world.environment = env
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.shadow_blur = 0.7
	stage.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, 140.0, 0.0)
	fill.light_color = Color(0.75, 0.84, 1.0)
	fill.light_energy = 0.5
	stage.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	floor_mesh.mesh = plane
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.2, 0.21, 0.24)
	ground.roughness = 0.95
	floor_mesh.material_override = ground
	stage.add_child(floor_mesh)

	var spacing := 1.15 if zoom == "" else (0.36 if zoom == "head" else 0.62)
	for i: int in views.size():
		var puppet := SkinnedPuppet.new()
		var style := UniformStyle.for_team(team, not _args.has("away"))
		style.number = player.number
		style.player_name = player.name
		var umpire := str(_args.get("umpire", ""))
		if umpire != "":
			style = UniformStyle.for_official(27)
			puppet.gear = (SkinnedPuppet.PLATE_UMPIRE_GEAR if umpire == "plate" else SkinnedPuppet.UMPIRE_GEAR).duplicate()
			if umpire == "plate":
				_args["headgear"] = "none"
		puppet.uniform = style
		puppet.set_colors(style.jersey, style.pants, style.cap)
		puppet.uniform = style
		puppet.show_glove = false
		puppet.headgear = StringName(str(_args.get("headgear", "cap")))
		stage.add_child(puppet)
		puppet.set_body(height, build)
		puppet.set_hair(1 + absi(hash(player.id)) % 4, MatchScene.hair_color_of(player))
		puppet.set_face(player.id)
		# How he wears it, forced for the picture (otherwise as the player does).
		if _args.has("sleeves") or _args.has("socks") or _args.has("guards"):
			puppet.long_sleeves = _args.has("sleeves")
			puppet.high_socks = _args.has("socks")
			puppet.guards.clear()
			if _args.has("guards"):
				puppet.guards.assign(SkinnedPuppet.BATTER_GUARDS)
			puppet.repaint()
		if _args.has("veins"):
			(puppet.find_child("Body", true, false) as MeshInstance3D).set_instance_shader_parameter(&"veins", float(str(_args["veins"])))
		if not _args.has("bare"):
			puppet.set_logo(style.cap_letter, style.cap_ink())
		puppet.repaint()
		match str(_args.get("pose", "standing")):
			"stance":
				puppet.show_bat = true
				puppet.apply(PuppetClips.stance())
			"ready":
				puppet.show_glove = true
				puppet.apply(PuppetClips.fielder_ready())
			_:
				puppet.apply(PuppetClips.standing())
		puppet.position = Vector3((i - (views.size() - 1) * 0.5) * spacing, 0.0, 0.0)
		# The figure faces away from the camera at rest.
		puppet.rotation.y = PI + deg_to_rad(views[i])
		# A left-hander is drawn as his own mirror image (--mirror).
		if _args.has("mirror"):
			puppet.scale.x = -1.0

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var span := spacing * views.size()
	var window := root.get_visible_rect().size
	var tall := height * 1.12
	var centre := height * 0.5
	if zoom == "head":
		tall = 0.46
		centre = height - 0.15
	elif zoom == "top":
		tall = 0.95
		centre = height - 0.4
	elif zoom == "arm":
		tall = 0.5
		centre = height * 0.56
	elif zoom == "legs":
		tall = 1.05
		centre = 0.5
	camera.size = maxf(tall, span * window.y / window.x)
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, centre, 8.0), Vector3(0.0, centre, 0.0))
	camera.make_current()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_build()
	if _frames < 40:
		return false
	root.get_texture().get_image().save_png(_out)
	print("figure_shots: ", _out)
	return true
