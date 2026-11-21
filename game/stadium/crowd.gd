class_name Crowd
extends Node3D
## The people in the stands (docs/06 7, docs/13 S14): one in a seat the stadium builder laid
## out, each a picture of a real-looking person on a card facing the field
## (assets/crowd/crowd_atlas.png, rendered by tools/blender/make_crowd.py from Microsoft
## Rocketbox's people, MIT licence), seated, standing, arms up or clapping as the crowd shader
## picks, zone by zone. Kept in three lots by where they sit (the rows behind home and over
## the dugouts, the rest of the lower bowl, the outfield and upper tiers) so each lot is drawn
## only when it is in view. KBO style, the first-base side is the home side's cheering
## section and the third-base side the visitors', each with its stage at the front, and they
## stand and cheer while their team bats; their tops are dyed in the club's colour.

enum Zone { BEHIND_HOME, FIRST, THIRD, OUTFIELD, UPPER, HOME_CHEER, AWAY_CHEER, STAGE }
enum State { SEATED, STANDING, CHEERING, CLAPPING }

const SHADER := "res://stadium/crowd.gdshader"
const ATLAS := "res://assets/crowd/crowd_atlas.png"
const MASK := "res://assets/crowd/crowd_mask.png"
const ATLAS_INFO := "res://assets/crowd/crowd_atlas.txt"
## A card: the picture covers 2 m of height (crowd_atlas.txt) and half that across.
const CARD := Vector2(1.0, 2.0)
## Ordinary clothes, for anyone not in his club's colours.
const CASUAL: Array[Color] = [
	Color(0.95, 0.95, 0.95), Color(0.12, 0.12, 0.13), Color(0.5, 0.52, 0.55), Color(0.15, 0.2, 0.38),
	Color(0.85, 0.78, 0.62), Color(0.75, 0.2, 0.2), Color(0.45, 0.65, 0.85), Color(0.3, 0.45, 0.3),
	Color(0.9, 0.75, 0.3), Color(0.6, 0.35, 0.55),
]
## Beats a second of the cheering songs.
const BEATS_PER_SECOND := 2.1

var park: StadiumBuilder
var home_colours: Array[Color] = [Color(0.95, 0.95, 0.96), Color(0.1, 0.2, 0.5)]
var away_colours: Array[Color] = [Color(0.2, 0.2, 0.22), Color(0.75, 0.15, 0.15)]
## The share of seats with someone in them (0..1), and the quality setting's share of those
## drawn (1, 0.6, 0.3).
var fill := 0.8
var density := 1.0
var seed_value := 1
## How many are drawn at each level of detail.
var counts := Vector3i.ZERO
var _materials: Array[ShaderMaterial] = []
var _states := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, State.CHEERING])
var _beat := 0.0


func _init(stadium: StadiumBuilder = null) -> void:
	park = stadium


func _ready() -> void:
	var material := _material()
	var card := QuadMesh.new()
	card.size = CARD
	card.center_offset = Vector3(0.0, CARD.y * 0.5, 0.0)
	var near := _multimesh(card)
	var mid := _multimesh(card)
	var far := _multimesh(card)
	var rng := Rng.new(seed_value)
	var near_items: Array = []
	var mid_items: Array = []
	var far_items: Array = []
	var dug := park.dugout_span()
	for i: int in park.seat_pos.size():
		var zone := park.seat_zone[i]
		# The busier zones fill first; a full house fills them all.
		if not rng.chance(pow(clampf(fill, 0.0, 1.0), 1.0 / _zone_fill(zone)) * density):
			continue
		var tier := park.seat_tier[i]
		var row := park.seat_row[i]
		var az := park.seat_az[i]
		var item := [park.seat_pos[i], az, zone, rng.next_float(), rng]
		var near_row := tier == 0 and ((zone == Zone.BEHIND_HOME and row < 8) or (row < 4 and absf(az) >= dug.x and absf(az) <= dug.y))
		if near_row:
			near_items.append(item)
		elif tier == 0 and zone != Zone.OUTFIELD:
			mid_items.append(item)
		else:
			far_items.append(item)
	# The cheering stages: a cheer leader and two cheerleaders on each.
	for side: float in [1.0, -1.0]:
		var at := park.stage_spot(side)
		if at.is_finite():
			for k: int in 3:
				var spot := at + Vector3(0.0, 0.0, 0.0) + _across(at, (k - 1) * 0.9)
				near_items.append([spot, rad_to_deg(atan2(Field.to_field(at).x, Field.to_field(at).y)), Zone.STAGE, rng.next_float(), rng])
			_build_stage(at)
	_fill(near, near_items)
	_fill(mid, mid_items)
	_fill(far, far_items)
	counts = Vector3i(near.instance_count, mid.instance_count, far.instance_count)
	_add_instance(near, material, "NearCrowd")
	_add_instance(mid, material, "MidCrowd")
	_add_instance(far, material, "FarCrowd")
	_materials = [material]
	_push()


## How full a zone is next to the park as a whole: the cheering sections and the seats behind
## home fill first, the upper tiers and the outfield last.
static func _zone_fill(zone: int) -> float:
	match zone:
		Zone.HOME_CHEER, Zone.AWAY_CHEER:
			return 1.35
		Zone.BEHIND_HOME:
			return 1.15
		Zone.UPPER, Zone.OUTFIELD:
			return 0.75
	return 1.0


## Who wears what: in the cheering sections mostly the club's shirt; on that side of the park
## more of it than not; elsewhere a mix.
func _shirt(zone: int, rng: Rng) -> Color:
	var home_share := 0.25
	var away_share := 0.2
	match zone:
		Zone.HOME_CHEER:
			home_share = 0.8
			away_share = 0.03
		Zone.AWAY_CHEER:
			home_share = 0.05
			away_share = 0.75
		Zone.FIRST:
			home_share = 0.45
			away_share = 0.1
		Zone.THIRD:
			home_share = 0.15
			away_share = 0.4
		Zone.STAGE:
			return Color(0.95, 0.25, 0.4) if rng.chance(0.5) else Color(0.98, 0.98, 0.98)
	var roll := rng.next_float()
	if roll < home_share:
		return home_colours[rng.next_int(home_colours.size())]
	if roll < home_share + away_share:
		return away_colours[rng.next_int(away_colours.size())]
	return CASUAL[rng.next_int(CASUAL.size())]


func _fill(mm: MultiMesh, items: Array) -> void:
	mm.instance_count = items.size()
	for i: int in items.size():
		var it: Array = items[i]
		var at: Vector3 = it[0]
		var zone: int = it[2]
		var rng: Rng = it[4]
		# Facing home plate.
		var home := Field.to_world(Vector3.ZERO)
		var d := Vector3(home.x - at.x, 0.0, home.z - at.z).normalized()
		var yaw := atan2(-d.x, -d.z)
		var size := rng.next_range(0.92, 1.06)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), at))
		var shirt := _shirt(zone, rng)
		# Only club colours are dyed in; anyone else keeps the clothes he came in.
		var dyed := 1.0 if shirt in home_colours or shirt in away_colours or zone == Zone.STAGE else 0.0
		mm.set_instance_color(i, Color(shirt.r, shirt.g, shirt.b, 1.0))
		mm.set_instance_custom_data(i, Color(float(it[3]), float(zone), dyed, rng.next_float()))


static func _multimesh(mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	return mm


func _add_instance(mm: MultiMesh, material: ShaderMaterial, node_name: String) -> void:
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.material_override = material
	# No shadows from the crowd: drawn again in each of the sun's cascades they cost a fifth of
	# the frame, and in the stands, under the roofs and upper tiers, they hardly show.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER) as Shader
	m.set_shader_parameter("atlas", load(ATLAS) as Texture2D)
	m.set_shader_parameter("mask", load(MASK) as Texture2D)
	var info := atlas_info()
	m.set_shader_parameter("people", info.get("people", 13))
	m.set_shader_parameter("poses", info.get("poses", 8))
	m.set_shader_parameter("columns", info.get("columns", 8))
	m.set_shader_parameter("rows", info.get("rows", 13))
	m.set_shader_parameter("card", CARD)
	return m


## How the atlas is laid out (crowd_atlas.txt: people, columns, rows).
static func atlas_info() -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(ATLAS_INFO):
		return out
	for line: String in FileAccess.get_file_as_string(ATLAS_INFO).split("\n"):
		var parts := line.split(" ", false)
		if parts.size() >= 2 and parts[1].is_valid_int():
			out[parts[0]] = int(parts[1])
		elif parts.size() >= 2 and parts[0] == "poses":
			# The pictures of each person, by name: how many there are.
			out["poses"] = parts.size() - 1
	return out


## A sideways step of `metres` along the front of the stands at `at`.
static func _across(at: Vector3, metres: float) -> Vector3:
	var f := Field.to_field(at)
	var side := Vector2(f.y, -f.x).normalized() * metres
	return Field.to_world(Vector3(side.x, side.y, 0.0)) - Field.to_world(Vector3.ZERO)


func _build_stage(at: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(4.2, 0.6, 2.2)
	var stage := MeshInstance3D.new()
	stage.name = "CheerStage"
	stage.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.12, 0.2)
	stage.material_override = m
	add_child(stage)
	var home := Field.to_world(Vector3.ZERO)
	stage.look_at_from_position(at + Vector3.DOWN * 0.3, Vector3(home.x, at.y - 0.3, home.z), Vector3.UP)


# --- What the crowd does ---


## Sets what a zone is doing (State).
func set_zone(zone: int, state: int) -> void:
	if _states[zone] != float(state):
		_states[zone] = float(state)
		_push()


func zone_state(zone: int) -> int:
	return int(_states[zone])


## Moves the cheering on by `delta` seconds.
func tick(delta: float) -> void:
	_beat += delta * BEATS_PER_SECOND
	for m: ShaderMaterial in _materials:
		m.set_shader_parameter("beat", _beat)


func _push() -> void:
	for m: ShaderMaterial in _materials:
		m.set_shader_parameter("zone_state", _states)
