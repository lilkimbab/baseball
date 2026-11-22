class_name BatWood
extends RefCounted
## The wood every bat is made of (match/bat_wood.gdshader): the batter's, the one left lying
## by the plate, the on-deck batter's, and the bat that shows the player where his swing will
## pass. `material(alpha)` below 1 gives the see-through one (the ball shows behind it).

const SHADER := "res://match/bat_wood.gdshader"

static var _solid: ShaderMaterial
static var _ghosts: Dictionary[float, ShaderMaterial] = {}


static func material(alpha: float = 1.0) -> ShaderMaterial:
	if alpha >= 1.0:
		if _solid == null:
			_solid = ShaderMaterial.new()
			_solid.shader = load(SHADER) as Shader
		return _solid
	if not _ghosts.has(alpha):
		var see_through := Shader.new()
		see_through.code = (load(SHADER) as Shader).code.replace("// SEE_THROUGH", "#define SEE_THROUGH\nrender_mode depth_draw_always;")
		var m := ShaderMaterial.new()
		m.shader = see_through
		m.set_shader_parameter("alpha", alpha)
		_ghosts[alpha] = m
	return _ghosts[alpha]


## The bat's mesh (assets/props/bat.glb), or a plain stick when the props have not been built.
static func mesh() -> Mesh:
	var path: String = SkinnedPuppet.PROPS[&"bat"]
	if ResourceLoader.exists(path):
		var scene := (load(path) as PackedScene).instantiate()
		var found := (scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		scene.free()
		return found
	var stick := CylinderMesh.new()
	stick.top_radius = 0.033
	stick.bottom_radius = 0.013
	stick.height = PuppetClips.BAT_LENGTH
	return stick
