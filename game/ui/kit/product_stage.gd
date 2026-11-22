class_name ProductStage
extends SubViewportContainer
## A shop's product on show (the user: "real 3D models, a little flashy, so it feels like
## buying the real thing"): the item's own model — the game's bat in its wood, the gloves and
## mitts made to the rules, the spikes and the elbow guard the players wear — or one made here
## (a rosin bag, dumbbells, a stack of gold coins), on a glossy turntable under a spotlight, a
## ring of light round its foot and a soft bloom, turning slowly.
##
## Three grades (the user: dearer items better-made, finer without being garish), as real gear
## goes: 0 standard (natural ash, tan leather, black spikes), 1 pro (a stained barrel, darker
## leather, white spikes with coloured laces, a glossy guard), 2 elite (a black lacquered
## barrel, black glossy leather, patent spikes on a metal plate, a gunmetal guard); the ring
## round the turntable silver, blue, gold.
##
## `still` renders one frame and stops (the shelf's thumbnails: cheap); otherwise it turns.

## Standard silver, pro blue, elite gold; signature (earned by achievements) violet.
const GRADE_RINGS: Array[Color] = [Color(0.78, 0.8, 0.86), Color(0.25, 0.55, 1.0), Color(1.0, 0.74, 0.26), Color(0.78, 0.42, 1.0)]

const PLAYER_MODEL := "res://assets/characters/player_base.glb"

var still := false
var _viewport: SubViewport
var _pivot: Node3D
var _camera: Camera3D
var _ring_material: StandardMaterial3D
var _pending := ""
var _accent := Color(0.88, 0.13, 0.17)
var _grade := 0
var _clock := 0.0


static func make(width: float, height: float, frozen: bool = false) -> ProductStage:
	var stage := ProductStage.new()
	stage.custom_minimum_size = Vector2(width, height)
	stage.still = frozen
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
	env.ambient_light_color = Color(0.55, 0.58, 0.68)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	var world := WorldEnvironment.new()
	world.environment = env
	_viewport.add_child(world)
	# A spot from above in front, a warm and a cool rim from behind either side.
	var spot := SpotLight3D.new()
	spot.position = Vector3(0.3, 1.6, 1.0)
	spot.look_at_from_position(spot.position, Vector3(0.0, 0.15, 0.0))
	spot.spot_range = 4.0
	spot.spot_angle = 32.0
	spot.light_energy = 4.5
	spot.shadow_enabled = true
	_viewport.add_child(spot)
	for spec: Array in [[Vector3(-1.2, 0.8, -1.0), Color(1.0, 0.62, 0.42), 2.2], [Vector3(1.2, 0.7, -1.0), Color(0.5, 0.7, 1.0), 2.0]]:
		var rim := OmniLight3D.new()
		rim.position = spec[0]
		rim.light_color = spec[1]
		rim.light_energy = spec[2]
		rim.omni_range = 3.0
		_viewport.add_child(rim)
	# The turntable: a glossy dark disc with a ring of light round its foot.
	var disc := CylinderMesh.new()
	disc.top_radius = 0.25
	disc.bottom_radius = 0.265
	disc.height = 0.05
	disc.radial_segments = 64
	var gloss := StandardMaterial3D.new()
	gloss.albedo_color = Color(0.06, 0.065, 0.08)
	gloss.metallic = 0.7
	gloss.roughness = 0.18
	var table := MeshInstance3D.new()
	table.mesh = disc
	table.material_override = gloss
	table.position.y = -0.025
	_viewport.add_child(table)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.262
	torus.outer_radius = 0.274
	torus.rings = 64
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.albedo_color = _accent
	_ring_material.emission_enabled = true
	_ring_material.emission = _accent
	_ring_material.emission_energy_multiplier = 3.0
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = _ring_material
	ring.position.y = -0.03
	_viewport.add_child(ring)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_viewport.add_child(_camera)
	_camera.look_at_from_position(Vector3(0.0, 0.36, 1.05), Vector3(0.0, 0.2, 0.0))
	if still:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Shows an item: "light_bat", "heavy_bat", "glove", "pitcher_glove", "mitt", "spikes",
## "elbow_guard", "helmet", "rosin", "training", "coins", at a grade (0..3, 3 the signature).
func show_item(kind: String, grade: int = 0) -> void:
	_pending = kind
	_grade = clampi(grade, 0, 3)
	_accent = GRADE_RINGS[_grade]
	if is_inside_tree():
		_show()


func _ready() -> void:
	if _pending != "":
		_show()


func _show() -> void:
	for c: Node in _pivot.get_children():
		c.queue_free()
	_ring_material.albedo_color = _accent
	_ring_material.emission = _accent
	var item := _build(_pending)
	if item != null:
		_pivot.add_child(item)
		_fit(item)
	if still:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## The model for an item, standing on the turntable.
func _build(kind: String) -> Node3D:
	match kind:
		"light_bat", "heavy_bat":
			var bat := MeshInstance3D.new()
			bat.mesh = BatWood.mesh()
			var wood := BatWood.material().duplicate() as ShaderMaterial
			if kind == "heavy_bat":
				# Denser, darker wood for the heavy one.
				wood.set_shader_parameter("pale", Color(0.6, 0.4, 0.22))
				wood.set_shader_parameter("late", Color(0.36, 0.22, 0.12))
			match _grade:
				1:
					# A stained barrel over a natural handle (cherry on the light bat, black on the heavy).
					wood.set_shader_parameter("barrel", Color(0.3, 0.07, 0.04) if kind == "light_bat" else Color(0.05, 0.045, 0.045))
					wood.set_shader_parameter("barrel_from", 0.5)
					wood.set_shader_parameter("gloss", 0.45)
				2:
					# Black lacquer from the handle up, glossy.
					wood.set_shader_parameter("barrel", Color(0.03, 0.03, 0.035))
					wood.set_shader_parameter("barrel_from", 0.42 if kind == "light_bat" else 0.12)
					wood.set_shader_parameter("barrel_cover", 0.97)
					wood.set_shader_parameter("gloss", 0.9)
				3:
					# The signature: a pearl-white barrel (deep plum on the heavy one), mirror gloss.
					wood.set_shader_parameter("barrel", Color(0.9, 0.88, 0.84) if kind == "light_bat" else Color(0.2, 0.05, 0.16))
					wood.set_shader_parameter("barrel_from", 0.3)
					wood.set_shader_parameter("barrel_cover", 1.0)
					wood.set_shader_parameter("gloss", 1.0)
			bat.material_override = wood
			var hold := Node3D.new()
			hold.add_child(bat)
			# Leaning on its knob, barrel up and to the side.
			bat.rotation_degrees = Vector3(0.0, 0.0, -40.0 if kind == "light_bat" else 40.0)
			return hold
		"glove", "pitcher_glove", "mitt":
			var path: String = SkinnedPuppet.PROPS[&"mitt" if kind == "mitt" else &"glove"]
			var node := _prop(path)
			if node != null:
				# Tan, chestnut, black leather; a pitcher's glove black, navy-black, black gloss.
				# The signature: white leather; a pitcher's in camel.
				var tints: Array = [Color(0.6, 0.38, 0.2), Color(0.36, 0.2, 0.11), Color(0.1, 0.09, 0.09), Color(0.88, 0.86, 0.82)] if kind != "pitcher_glove" else [Color(0.11, 0.11, 0.12), Color(0.07, 0.08, 0.14), Color(0.06, 0.06, 0.07), Color(0.6, 0.42, 0.2)]
				var rough: Array = [0.65, 0.45, 0.26, 0.3] if kind != "pitcher_glove" else [0.7, 0.45, 0.22, 0.28]
				_recolour(node, tints[_grade], rough[_grade])
			return node
		"spikes":
			var shoes := _part("Shoes")
			if shoes != null:
				var looks: Array = [
					[[Color(0.06, 0.06, 0.07), 0.7, 0.0], [Color(0.95, 0.95, 0.95), 0.6, 0.0], [Color(0.95, 0.95, 0.95), 0.8, 0.0]],
					[[Color(0.95, 0.95, 0.96), 0.45, 0.0], [Color(0.07, 0.07, 0.08), 0.5, 0.0], [Color(0.85, 0.12, 0.14), 0.7, 0.0]],
					[[Color(0.02, 0.02, 0.025), 0.12, 0.0], [Color(0.72, 0.73, 0.76), 0.22, 0.85], [Color(0.96, 0.96, 0.96), 0.8, 0.0]],
					[[Color(0.96, 0.96, 0.97), 0.25, 0.0], [Color(0.85, 0.68, 0.3), 0.22, 0.9], [Color(0.08, 0.08, 0.09), 0.6, 0.0]],
				]
				_dress(shoes, "Shoes", looks[_grade])
			return shoes
		"elbow_guard":
			var guard := _part("ElbowGuard")
			if guard != null:
				var looks: Array = [
					[[Color(0.05, 0.05, 0.06), 0.75, 0.0], [Color(0.2, 0.2, 0.21), 0.9, 0.0], [Color(0.2, 0.2, 0.21), 0.9, 0.0]],
					[[Color(0.07, 0.11, 0.3), 0.22, 0.1], [Color(0.12, 0.12, 0.13), 0.9, 0.0], [Color(0.12, 0.12, 0.13), 0.9, 0.0]],
					[[Color(0.16, 0.17, 0.19), 0.2, 0.75], [Color(0.05, 0.05, 0.06), 0.8, 0.0], [Color(0.05, 0.05, 0.06), 0.8, 0.0]],
					[[Color(0.85, 0.68, 0.3), 0.18, 0.9], [Color(0.95, 0.95, 0.96), 0.4, 0.0], [Color(0.95, 0.95, 0.96), 0.4, 0.0]],
				]
				_dress(guard, "ElbowGuard", looks[_grade])
			return guard
		"helmet":
			return _part("Helmet")
		"rosin":
			return _rosin()
		"training":
			return _dumbbells()
		"coins":
			return _coins()
	return null


func _prop(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	return (load(path) as PackedScene).instantiate() as Node3D


## One part of the players' own model (their spikes, their elbow guard), the rest hidden.
func _part(name: String) -> Node3D:
	var model := _prop(PLAYER_MODEL)
	if model == null:
		return null
	for m: Node in model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).visible = m.name == name or (name == "Helmet" and String(m.name).begins_with("HelmetFlap"))
	return model


static func _recolour(node: Node3D, colour: Color, roughness: float = 0.45) -> void:
	for m: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (m as MeshInstance3D).mesh
		for s: int in mesh.get_surface_count():
			var base := mesh.surface_get_material(s) as StandardMaterial3D
			var dyed := (base.duplicate() as StandardMaterial3D) if base != null else StandardMaterial3D.new()
			dyed.albedo_color = colour
			dyed.roughness = roughness
			(m as MeshInstance3D).set_surface_override_material(s, dyed)


## A part's surfaces each in [colour, roughness, metallic] (upper, sole, laces; shell, pads).
static func _dress(node: Node3D, part: String, looks: Array) -> void:
	for m: Node in node.find_children("*", "MeshInstance3D", true, false):
		if m.name != part:
			continue
		var mesh := (m as MeshInstance3D).mesh
		for s: int in mini(mesh.get_surface_count(), looks.size()):
			var base := mesh.surface_get_material(s) as StandardMaterial3D
			var dyed := (base.duplicate() as StandardMaterial3D) if base != null else StandardMaterial3D.new()
			var look: Array = looks[s]
			dyed.albedo_texture = null if s == 0 else dyed.albedo_texture
			dyed.albedo_color = look[0]
			dyed.roughness = look[1]
			dyed.metallic = look[2]
			if float(look[1]) < 0.2:
				dyed.clearcoat_enabled = true
				dyed.clearcoat = 0.8
			(m as MeshInstance3D).set_surface_override_material(s, dyed)


## A rosin bag: a soft white cloth pouch with ROSIN printed on it.
func _rosin() -> Node3D:
	var root := Node3D.new()
	var pouch := SphereMesh.new()
	pouch.radius = 0.06
	pouch.height = 0.05
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.84, 0.83, 0.8)
	cloth.roughness = 1.0
	var bag := MeshInstance3D.new()
	bag.mesh = pouch
	bag.material_override = cloth
	bag.scale = Vector3(1.5, 0.9, 1.1)
	bag.position.y = 0.028
	root.add_child(bag)
	var word := Label3D.new()
	word.text = "ROSIN"
	word.font = UiTheme.numeric(false, true)
	word.font_size = 64
	word.pixel_size = 0.0007
	word.modulate = [Color(0.12, 0.18, 0.4), Color(0.75, 0.1, 0.12), Color(0.72, 0.55, 0.18), Color(0.55, 0.25, 0.8)][_grade]
	word.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	word.position = Vector3(0.0, 0.054, 0.0)
	root.add_child(word)
	return root


## Training: a pair of dumbbells in chrome and black.
func _dumbbells() -> Node3D:
	var root := Node3D.new()
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.85, 0.86, 0.9)
	chrome.metallic = 1.0
	chrome.roughness = 0.15
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.05, 0.05, 0.06)
	black.roughness = 0.5
	if _grade == 0:
		# Plain iron.
		chrome.albedo_color = Color(0.3, 0.3, 0.32)
		chrome.metallic = 0.6
		chrome.roughness = 0.5
	var spots: Array = [[Vector3(-0.09, 0.045, 0.0), 20.0], [Vector3(0.09, 0.045, 0.02), -20.0]]
	if _grade >= 1:
		spots.append([Vector3(0.0, 0.045, -0.1), 90.0])
	if _grade >= 2:
		spots.append([Vector3(0.0, 0.135, -0.02), 5.0])
	for spot: Array in spots:
		var one := Node3D.new()
		one.position = spot[0]
		one.rotation_degrees.y = float(spot[1])
		root.add_child(one)
		var bar := CylinderMesh.new()
		bar.top_radius = 0.012
		bar.bottom_radius = 0.012
		bar.height = 0.22
		var bar_node := MeshInstance3D.new()
		bar_node.mesh = bar
		bar_node.material_override = chrome
		bar_node.rotation_degrees.x = 90.0
		one.add_child(bar_node)
		for end: float in [-0.085, 0.085]:
			var plate := CylinderMesh.new()
			plate.top_radius = 0.045
			plate.bottom_radius = 0.045
			plate.height = 0.05
			var plate_node := MeshInstance3D.new()
			plate_node.mesh = plate
			plate_node.material_override = black
			plate_node.rotation_degrees.x = 90.0
			plate_node.position.z = end
			one.add_child(plate_node)
	return root


## The club's funds: stacks of gold coins.
func _coins() -> Node3D:
	var root := Node3D.new()
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.78, 0.3)
	gold.metallic = 1.0
	gold.roughness = 0.22
	gold.emission_enabled = true
	gold.emission = Color(0.35, 0.22, 0.02)
	var coin := CylinderMesh.new()
	coin.top_radius = 0.035
	coin.bottom_radius = 0.035
	coin.height = 0.008
	coin.radial_segments = 32
	var stacks: Array = [[[Vector3(-0.04, 0.0, 0.0), 6], [Vector3(0.04, 0.0, -0.02), 9]],
		[[Vector3(-0.07, 0.0, 0.0), 11], [Vector3(0.03, 0.0, -0.04), 16], [Vector3(0.06, 0.0, 0.06), 7]],
		[[Vector3(-0.09, 0.0, 0.02), 14], [Vector3(0.0, 0.0, -0.06), 20], [Vector3(0.08, 0.0, 0.03), 12], [Vector3(-0.02, 0.0, 0.08), 6]]][mini(_grade, 2)]
	if _grade >= 2:
		# And two gold bars.
		var bar := BoxMesh.new()
		bar.size = Vector3(0.1, 0.022, 0.045)
		for i: int in 2:
			var b := MeshInstance3D.new()
			b.mesh = bar
			b.material_override = gold
			b.position = Vector3(0.1, 0.011 + 0.023 * i, -0.07)
			b.rotation_degrees.y = 25.0 + 8.0 * i
			root.add_child(b)
	for stack: Array in stacks:
		for k: int in int(stack[1]):
			var c := MeshInstance3D.new()
			c.mesh = coin
			c.material_override = gold
			c.position = (stack[0] as Vector3) + Vector3(sin(k * 1.7) * 0.003, 0.004 + k * 0.0085, cos(k * 1.3) * 0.003)
			root.add_child(c)
	return root


## Scales and lifts the item to stand on the turntable, filling the view.
func _fit(item: Node3D) -> void:
	var box := AABB()
	var first := true
	for m: Node in item.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var b := (item.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb() if mi.is_inside_tree() else mi.transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	# A pair of spikes stands apart as on a player's feet: framed by one shoe's size.
	var across := box.size.x * (0.62 if _pending == "spikes" else 0.8)
	var tallest := maxf(box.size.y, maxf(across, box.size.z * 0.8))
	var k := (0.52 if _pending.ends_with("bat") else 0.46) / maxf(tallest, 0.01)
	item.scale = Vector3.ONE * k
	item.position = Vector3(-box.get_center().x * k, -box.position.y * k + 0.002, -box.get_center().z * k)


func _process(delta: float) -> void:
	if still:
		return
	_clock += delta
	_pivot.rotation.y = _clock * 0.6
