class_name SurfaceLibrary
extends RefCounted
## Real surfaces for the parks and the equipment: CC0 texture sets (ambientCG; fetched by
## tools/assets/fetch_materials.sh into assets/materials) — grass, dirt, gravel, concrete,
## leather, plastic, painted metal, chain-link fence — laid on by position (triplanar), so no
## mesh needs unwrapping. Without the files the materials stay plain.

const DIR := "res://assets/materials/"

static var _cache: Dictionary[String, Texture2D] = {}


static func texture(name: String, map: String) -> Texture2D:
	var key := "%s_%s" % [name, map]
	if not _cache.has(key):
		var path := DIR + key + ".jpg"
		_cache[key] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _cache[key]


static func has(name: String) -> bool:
	return texture(name, "normal") != null


## Gives a material a surface's relief and roughness, one tile every `metres`; with
## `with_colour` its colour pattern too (the material's own colour then tints it). `world`:
## laid on by position in the world (things that stand still) or in the mesh's own space
## (things that move).
static func dress(m: StandardMaterial3D, name: String, metres: float, depth: float = 1.0, with_colour: bool = false, world: bool = true) -> StandardMaterial3D:
	var normal := texture(name, "normal")
	if normal == null:
		return m
	m.normal_enabled = true
	m.normal_texture = normal
	m.normal_scale = depth
	var rough := texture(name, "rough")
	if rough != null:
		# The map scales the material's own roughness; the scans average about 0.8.
		m.roughness_texture = rough
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.roughness = minf(m.roughness * 1.2, 1.0)
	if with_colour:
		m.albedo_texture = texture(name, "color")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world
	m.uv1_scale = Vector3.ONE / maxf(metres, 0.01)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
