class_name Crowd
extends Node3D
## The people in the stands (docs/05 7): one in a seat the stadium builder laid
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
## On each stage: the cheer leader at the front and five women cheerleaders in a line behind
## him (the user, 2026-11-23).
const STAGE_CREW := 6
## The fan who leads the cheering: one of the men in the atlas (by name, crowd_atlas.txt).
const LEADER_NAME := "kr_m02"

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
## How many people the atlas has, and how many of them are fans (the rest cheerleaders).
var _people := 13
var _fans := 13
var _cheer_scale := 1.0
var _leader := 6


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
	# Where the cheering stages stand nobody sits (the stage is built over those seats).
	var stages: Array = []
	for side: float in [1.0, -1.0]:
		var spot := park.stage_spot(side)
		if spot.is_finite():
			var home := Field.to_world(Vector3.ZERO)
			stages.append([spot, Vector3(home.x - spot.x, 0.0, home.z - spot.z).normalized()])
	for i: int in park.seat_pos.size():
		var zone := park.seat_zone[i]
		# The busier zones fill first; a full house fills them all.
		if not rng.chance(pow(clampf(fill, 0.0, 1.0), 1.0 / _zone_fill(zone)) * density):
			continue
		if _under_stage(park.seat_pos[i], stages):
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
	# The cheering stages: the cheer leader at the front, the cheerleaders behind him, all in
	# the club's colours (KBO).
	var info := atlas_info()
	_people = int(info.get("people", 13))
	_fans = int(info.get("fans", _people))
	_cheer_scale = float(info.get("cheer_scale", 1.0))
	var names: PackedStringArray = info.get("names", PackedStringArray())
	_leader = names.find(LEADER_NAME) if names.has(LEADER_NAME) else 6
	for side: float in [1.0, -1.0]:
		var at := park.stage_spot(side)
		if at.is_finite():
			var home := Field.to_world(Vector3.ZERO)
			var forward := Vector3(home.x - at.x, 0.0, home.z - at.z).normalized()
			for k: int in STAGE_CREW:
				var spot: Vector3
				var who: int
				if k == 0:
					# The leader at the front of the deck.
					spot = at + forward * 0.6
					who = _leader
				else:
					# The cheerleaders in a line along their riser behind him (the atlas's
					# cheerleaders by turns; an old atlas without them: its women).
					var across: Array[float] = [-2.5, -1.25, 0.0, 1.25, 2.5]
					spot = at - forward * (DECK_DEPTH * 0.5 + 0.55) + _across(at, across[k - 1]) + Vector3.UP * RISER_UP
					who = _fans + k % (_people - _fans) if _people > _fans else (k - 1) % 5
				near_items.append([spot, rad_to_deg(atan2(Field.to_field(at).x, Field.to_field(at).y)), Zone.STAGE, rng.next_float(), rng, who, side])
			_build_stage(at, side)
	_fill(near, near_items)
	_fill(mid, mid_items)
	_fill(far, far_items)
	counts = Vector3i(near.instance_count, mid.instance_count, far.instance_count)
	_add_instance(near, material, "NearCrowd")
	_add_instance(mid, material, "MidCrowd")
	_add_instance(far, material, "FarCrowd")
	_materials = [material]
	_push()


## A seat the cheering stage stands over: within its width and from its front back past the
## riser (and a little to spare).
static func _under_stage(seat: Vector3, stages: Array) -> bool:
	for st: Array in stages:
		var at: Vector3 = st[0]
		var forward: Vector3 = st[1]
		var d := Vector3(seat.x - at.x, 0.0, seat.z - at.z)
		var along := d.dot(forward)
		var across := absf(d.dot(Vector3(forward.z, 0.0, -forward.x)))
		if across < STAGE_WIDTH * 0.5 + 0.4 and along > -(DECK_DEPTH * 0.5 + RISER_DEPTH + 0.6) and along < DECK_DEPTH + 0.5:
			return true
	return false


## The livelier of a club's two colours (the stage's lights, the squad's outfits): white or
## grey is a poor LED and a dull uniform.
static func vivid(colours: Array[Color]) -> Color:
	var best := colours[0]
	for c: Color in colours:
		if c.s * c.v > best.s * best.v:
			best = c
	return best


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
		var person := rng.next_float() * float(_fans) / float(maxi(_people, 1))
		if it.size() > 5:
			# Someone on a stage: who he is, in his side's colours. A cheerleader's picture
			# covers more than a fan's (her arms reach wide): her card is that much bigger.
			person = (float(it[5]) + 0.5) / float(maxi(_people, 1))
			if int(it[5]) >= _fans:
				mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size * _cheer_scale), at))
			var colours := home_colours if float(it[6]) > 0.0 else away_colours
			# The squad in matching outfits of the club's colour, the leader in its other one.
			var squad := vivid(colours)
			var other := colours[0] if colours[0] != squad else colours[1 % colours.size()]
			shirt = other if int(it[5]) == _leader else squad
		# Everyone's top is dyed: the club's colours in the cheering sections, ordinary colours
		# elsewhere (the Korean crowd's people share a few suits: undyed, rows of the same shirt).
		var dyed := 1.0
		mm.set_instance_color(i, Color(shirt.r, shirt.g, shirt.b, 1.0))
		mm.set_instance_custom_data(i, Color(float(it[3]), float(zone), dyed, person))


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
	m.set_shader_parameter("fans", info.get("fans", info.get("people", 13)))
	m.set_shader_parameter("poses", info.get("poses", 8))
	m.set_shader_parameter("columns", info.get("columns", 8))
	m.set_shader_parameter("rows", info.get("rows", 13))
	# Each person from the back as well (an atlas of two views): shown when the eye is behind.
	m.set_shader_parameter("views", info.get("views", 1))
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
		elif parts.size() == 2 and parts[1].is_valid_float():
			out[parts[0]] = float(parts[1])
		elif parts.size() >= 2 and parts[0] == "names":
			out["names"] = PackedStringArray(parts.slice(1))
		elif parts.size() >= 2 and parts[0] == "poses":
			# The pictures of each person, by name: how many there are.
			out["poses"] = parts.size() - 1
	return out


## A sideways step of `metres` along the front of the stands at `at`.
static func _across(at: Vector3, metres: float) -> Vector3:
	var f := Field.to_field(at)
	var side := Vector2(f.y, -f.x).normalized() * metres
	return Field.to_world(Vector3(side.x, side.y, 0.0)) - Field.to_world(Vector3.ZERO)


## The cheering stage (KBO: a raised platform at the front of the infield stands): a low front
## deck where the cheer leader stands, and behind it the cheerleaders' own riser, higher, so the
## squad dances above the crowd; the fronts of both lit in the club's colour like LED boards,
## a white band across. `side` 1 the home side's, -1 the visitors'.
const STAGE_WIDTH := 6.6
const DECK_DEPTH := 1.3
const RISER_DEPTH := 1.7
## How much higher the riser stands than the deck (m).
const RISER_UP := 1.3


func _build_stage(at: Vector3, side: float = 1.0) -> void:
	var home := Field.to_world(Vector3.ZERO)
	var forward := Vector3(home.x - at.x, 0.0, home.z - at.z).normalized()
	var colours := home_colours if side > 0.0 else away_colours
	var lit := vivid(colours)
	# The deck: its top at `at`, reaching forward toward the field.
	_stage_block("CheerDeck", at + forward * 0.45, Vector3(STAGE_WIDTH, 1.2, DECK_DEPTH), at.y, forward, Color(0.12, 0.12, 0.14), lit)
	# The riser behind it.
	_stage_block("CheerRiser", at - forward * (DECK_DEPTH * 0.5 + RISER_DEPTH * 0.5 - 0.2), Vector3(STAGE_WIDTH, 1.2 + RISER_UP, RISER_DEPTH), at.y + RISER_UP, forward, Color(0.12, 0.12, 0.14), lit)


## A block of the stage with its top at `top`, its front face (toward the field) a lit panel.
func _stage_block(node_name: String, centre: Vector3, size: Vector3, top: float, forward: Vector3, body: Color, lit: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	var block := MeshInstance3D.new()
	block.name = node_name
	block.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = body
	m.roughness = 0.6
	block.material_override = m
	add_child(block)
	var c := Vector3(centre.x, top - size.y * 0.5, centre.z)
	block.look_at_from_position(c, c - forward, Vector3.UP)
	# The front: an LED face in the club's colour with a white band.
	var face := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size.x - 0.1, size.y - 0.15)
	face.mesh = quad
	var fm := StandardMaterial3D.new()
	fm.albedo_color = lit
	fm.emission_enabled = true
	fm.emission = lit
	fm.emission_energy_multiplier = 1.6
	face.material_override = fm
	add_child(face)
	var front := c + forward * (size.z * 0.5 + 0.01)
	face.look_at_from_position(front, front - forward, Vector3.UP)
	var band := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(size.x - 0.1, 0.1)
	band.mesh = bq
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.95, 0.95, 0.95)
	bm.emission_enabled = true
	bm.emission = Color(0.95, 0.95, 0.95)
	bm.emission_energy_multiplier = 1.4
	band.material_override = bm
	add_child(band)
	var band_at := front + forward * 0.005 + Vector3.UP * (size.y * 0.5 - 0.22)
	band.look_at_from_position(band_at, band_at - forward, Vector3.UP)


# --- What the crowd does ---


## Sets what a zone is doing (State).
func set_zone(zone: int, state: int) -> void:
	if _states[zone] != float(state):
		_states[zone] = float(state)
		_push()


func zone_state(zone: int) -> int:
	return int(_states[zone])


## The cheering's beat clock (beats so far): the sound's drums keep to it (CheerSequencer).
func beat() -> float:
	return _beat


## Moves the cheering on by `delta` seconds.
func tick(delta: float) -> void:
	_beat += delta * BEATS_PER_SECOND
	for m: ShaderMaterial in _materials:
		m.set_shader_parameter("beat", _beat)


func _push() -> void:
	for m: ShaderMaterial in _materials:
		m.set_shader_parameter("zone_state", _states)
