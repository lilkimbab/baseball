class_name SkinnedPuppet
extends Puppet
## The same poses as Puppet, shown on the skinned player model instead of capsules.
##
## Puppet.solve() gives joint positions; this turns them into bone rotations: the spine is
## bent between the pelvis and chest frames, each limb bone is aimed at the next joint, and
## feet and head keep their rest orientation turned to the body's heading.

const MODEL := "res://assets/characters/player_base.glb"
const LIMBS: Array[Array] = [
	[&"LeftUpperArm", &"LeftLowerArm"], [&"LeftLowerArm", &"LeftHand"],
	[&"RightUpperArm", &"RightLowerArm"], [&"RightLowerArm", &"RightHand"],
	[&"LeftUpperLeg", &"LeftLowerLeg"], [&"LeftLowerLeg", &"LeftFoot"],
	[&"RightUpperLeg", &"RightLowerLeg"], [&"RightLowerLeg", &"RightFoot"],
]

const FINGERS: Array[String] = ["Index", "Middle", "Ring", "Little"]
## Curl in degrees for [finger base, middle, tip, thumb] per grip.
const CURL := {
	Grip.RELAXED: [18.0, 22.0, 14.0, 10.0],
	Grip.BAT: [72.0, 84.0, 58.0, 34.0],
	Grip.BALL: [38.0, 44.0, 28.0, 30.0],
	Grip.GLOVE: [26.0, 30.0, 20.0, 16.0],
}
## Distance from the spine to the surface of the jersey's back, and heights of the lettering.
const BACK_DEPTH := 0.142
const NUMBER_HEIGHT := 1.245
const NAME_HEIGHT := 1.385

var _skeleton: Skeleton3D
var _mesh: MeshInstance3D
var _cap: MeshInstance3D
var _helmet: MeshInstance3D
var _number_label: Label3D
var _name_label: Label3D
## Axis (skeleton space, at rest) each finger bone curls about, by bone index.
var _curl_axis: Dictionary[int, Vector3] = {}
## Skeleton space -> puppet space, and back.
var _to_puppet := Transform3D.IDENTITY
var _to_skeleton := Transform3D.IDENTITY
var _bone: Dictionary[StringName, int] = {}
var _rest: Array[Transform3D] = []
var _local_rest: Array[Transform3D] = []
var _parent: PackedInt32Array = PackedInt32Array()
## Rest direction (skeleton space) from each limb bone to the next joint.
var _aim_rest: Dictionary[StringName, Vector3] = {}
## Pelvis bone origin relative to the midpoint of the hip joints, at rest.
var _hips_offset := Vector3.ZERO


static func available() -> bool:
	return ResourceLoader.exists(MODEL)


func _ready() -> void:
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	# glTF characters face +Z; the puppet's space faces -Z.
	model.rotation.y = PI
	add_child(model)
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_mesh = model.find_child("Player", true, false) as MeshInstance3D
	_cap = model.find_child("Cap", true, false) as MeshInstance3D
	_helmet = model.find_child("Helmet", true, false) as MeshInstance3D
	var node: Node3D = _skeleton
	while node != self:
		_to_puppet = node.transform * _to_puppet
		node = node.get_parent() as Node3D
	_to_skeleton = _to_puppet.affine_inverse()
	_measure()
	_measure_fingers()
	_paint()
	_build_props()
	_build_lettering()
	apply(PuppetClips.fielder_ready())


func set_colors(jersey_color: Color, pants_color: Color, cap_color: Color) -> void:
	super.set_colors(jersey_color, pants_color, cap_color)
	if _mesh != null:
		_paint()


func set_back_lettering(number: int, player_name: String, ink: Color = Color.BLACK) -> void:
	_number_label.text = str(number)
	_name_label.text = player_name
	_number_label.modulate = ink
	_name_label.modulate = ink


func apply(pose: PuppetPose) -> void:
	solve(pose)
	_cap.visible = headgear != &"helmet"
	_helmet.visible = headgear == &"helmet"
	var basis_for: Dictionary[int, Basis] = {}
	var curl := _finger_curls()

	# Spine: from the pelvis frame (heading plus a little lean) to the chest frame.
	var hip_right := hip_basis * Vector3.RIGHT
	var pelvis := Basis(hip_right, -pose.lean * 0.3) * hip_basis
	var chest := Basis(hip_right, -pose.lean) * chest_basis
	var pelvis_q := pelvis.get_rotation_quaternion()
	var chest_q := chest.get_rotation_quaternion()
	_turn(basis_for, &"Hips", pelvis)
	_turn(basis_for, &"Spine", Basis(pelvis_q.slerp(chest_q, 0.34)))
	_turn(basis_for, &"Chest", Basis(pelvis_q.slerp(chest_q, 0.67)))
	_turn(basis_for, &"UpperChest", chest)
	_turn(basis_for, &"Neck", Basis(pelvis_q.slerp(chest_q, 0.6)))
	_turn(basis_for, &"Head", chest_basis)
	_turn(basis_for, &"LeftFoot", hip_basis)
	_turn(basis_for, &"RightFoot", hip_basis)

	# First pass: bend the spine, then read where the model's own shoulders and hips ended
	# up and solve the arms and legs again from there, so hands and feet land on target.
	var globals := _walk(basis_for, curl, pose)
	if has_look_target:
		_aim_head(basis_for, _to_puppet * globals[_bone[&"Head"]].origin)
	var elbow_out := chest_basis * Vector3.RIGHT
	var back := chest_basis * Vector3.BACK
	for side: int in [-1, 1] as Array[int]:
		var name := "Right" if side > 0 else "Left"
		var shoulder := _to_puppet * globals[_bone[StringName(name + "UpperArm")]].origin
		var hand := _reach(shoulder, pose.r_hand if side > 0 else pose.l_hand, upper_arm + lower_arm)
		joints[StringName(name + "UpperArm")] = shoulder
		joints[StringName(name + "LowerArm")] = _two_bone(shoulder, hand, upper_arm, lower_arm, elbow_out * (0.5 * side) - Vector3.UP + back * 0.5)
		joints[StringName(name + "Hand")] = hand
		var hip := _to_puppet * globals[_bone[StringName(name + "UpperLeg")]].origin
		var ankle := _reach(hip, pose.r_foot if side > 0 else pose.l_foot, upper_leg + lower_leg)
		joints[StringName(name + "UpperLeg")] = hip
		joints[StringName(name + "LowerLeg")] = _two_bone(hip, ankle, upper_leg, lower_leg, hip_basis * Vector3.FORWARD + hip_right * (0.3 * side))
		joints[StringName(name + "Foot")] = ankle

	# Limbs: aim each bone from its joint toward the next one.
	for pair: Array in LIMBS:
		var from: StringName = pair[0]
		var to: StringName = pair[1]
		var want := _to_skeleton.basis * (joints[to] - joints[from])
		if want.length() < 1e-5:
			continue
		var index := _bone[from]
		basis_for[index] = Basis(Quaternion(_aim_rest[from], want.normalized())) * _rest[index].basis

	# Second pass: final bone poses.
	globals = _walk(basis_for, curl, pose)
	for i: int in _rest.size():
		var parent_global := Transform3D.IDENTITY if _parent[i] < 0 else globals[_parent[i]]
		var local := parent_global.affine_inverse() * globals[i]
		_skeleton.set_bone_pose_position(i, local.origin)
		_skeleton.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())

	# Report where the model's hands really are, so the ball and bat sit in them.
	for side: String in ["Left", "Right"]:
		var hand := StringName(side + "Hand")
		var middle: int = _bone.get(StringName(side + "MiddleProximal"), _bone[hand])
		joints[hand] = _to_puppet * globals[_bone[hand]].origin.lerp(globals[middle].origin, 0.7)
	_place_props(pose)


## Global transform of every bone (skeleton space) for the given target orientations,
## walking parent-first. Bones without a target keep their rest pose relative to the parent.
func _walk(basis_for: Dictionary[int, Basis], curl: Dictionary[int, Basis], pose: PuppetPose) -> Array[Transform3D]:
	var globals: Array[Transform3D] = []
	globals.resize(_rest.size())
	var hips := _bone[&"Hips"]
	for i: int in _rest.size():
		var parent_global := Transform3D.IDENTITY if _parent[i] < 0 else globals[_parent[i]]
		var g := parent_global * _local_rest[i]
		if basis_for.has(i):
			g.basis = basis_for[i]
		elif curl.has(i):
			# A curl is given in rest space; carry it along with however the parent has moved.
			g.basis = parent_global.basis * _rest[_parent[i]].basis.inverse() * curl[i] * _rest[i].basis
		if i == hips:
			g.origin = _to_skeleton * pose.hips + g.basis * (_rest[i].basis.inverse() * _hips_offset)
		globals[i] = g
	return globals


## Turns the head (and half as much the neck) toward look_target, within what a neck can do.
func _aim_head(basis_for: Dictionary[int, Basis], head_at: Vector3) -> void:
	var to_target := chest_basis.inverse() * (look_target - head_at)
	if to_target.length() < 0.05:
		return
	var yaw := clampf(atan2(to_target.x, -to_target.z), deg_to_rad(-85.0), deg_to_rad(85.0))
	var pitch := clampf(atan2(to_target.y, Vector2(to_target.x, to_target.z).length()), deg_to_rad(-35.0), deg_to_rad(30.0))
	_turn(basis_for, &"Head", chest_basis * Basis(Vector3.UP, -yaw) * Basis(Vector3.RIGHT, pitch))
	_turn(basis_for, &"Neck", chest_basis * Basis(Vector3.UP, -yaw * 0.5) * Basis(Vector3.RIGHT, pitch * 0.5))


## Rest-space rotations that close the fingers for the current grips.
func _finger_curls() -> Dictionary[int, Basis]:
	var out: Dictionary[int, Basis] = {}
	for side: String in ["Left", "Right"]:
		var degrees: Array = CURL[left_grip if side == "Left" else right_grip]
		for finger: String in FINGERS:
			var parts: Array[String] = ["Proximal", "Intermediate", "Distal"]
			for part: int in parts.size():
				_add_curl(out, StringName(side + finger + parts[part]), degrees[part])
		for part: String in ["ThumbMetacarpal", "ThumbProximal", "ThumbDistal"]:
			_add_curl(out, StringName(side + part), degrees[3])
	return out


func _add_curl(out: Dictionary[int, Basis], bone: StringName, degrees: float) -> void:
	if not _bone.has(bone):
		return
	var index := _bone[bone]
	if _curl_axis.has(index):
		out[index] = Basis(_curl_axis[index], deg_to_rad(degrees))


## Finds, for each finger bone, the axis it bends about. The resting hand is slightly curled,
## which shows which way the palm faces.
func _measure_fingers() -> void:
	for side: String in ["Left", "Right"]:
		var hand := _origin(StringName(side + "Hand"))
		var palm := Vector3.ZERO
		for finger: String in FINGERS:
			var a := _origin(StringName(side + finger + "Proximal"))
			var b := _origin(StringName(side + finger + "Intermediate"))
			var c := _origin(StringName(side + finger + "Distal"))
			var first := (b - a).normalized()
			var bend := (c - b).normalized() - first
			palm += bend - first * bend.dot(first)
		if palm.length() < 0.02:
			var across := _origin(StringName(side + "IndexProximal")) - _origin(StringName(side + "LittleProximal"))
			palm = across.cross(_origin(StringName(side + "MiddleProximal")) - hand) * (1.0 if side == "Left" else -1.0)
		palm = palm.normalized()
		for finger: String in FINGERS:
			var chain: Array[StringName] = [StringName(side + finger + "Proximal"), StringName(side + finger + "Intermediate"), StringName(side + finger + "Distal")]
			for i: int in chain.size():
				var from := _origin(chain[mini(i, 1)])
				var to := _origin(chain[mini(i, 1) + 1])
				_curl_axis[_bone[chain[i]]] = (to - from).normalized().cross(palm).normalized()
		# The thumb closes across the palm, toward the base of the index finger.
		var thumb: Array[StringName] = [StringName(side + "ThumbMetacarpal"), StringName(side + "ThumbProximal"), StringName(side + "ThumbDistal")]
		var toward := _origin(StringName(side + "IndexProximal")) - _origin(thumb[1])
		for i: int in thumb.size():
			var from := _origin(thumb[mini(i, 1)])
			var to := _origin(thumb[mini(i, 1) + 1])
			var along := (to - from).normalized()
			_curl_axis[_bone[thumb[i]]] = along.cross((toward - along * toward.dot(along)).normalized() + palm * 0.6).normalized()


## Name and number on the back of the jersey, carried by the upper spine.
func _build_lettering() -> void:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = "UpperChest"
	_skeleton.add_child(attachment)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Pretendard", "Noto Sans KR", "Noto Sans CJK KR", "Malgun Gothic", "NanumGothic"])
	font.font_weight = 800
	var bone_rest := _rest[_bone[&"UpperChest"]]
	_number_label = _back_label(attachment, font, bone_rest, NUMBER_HEIGHT, 150, 0.00135)
	_name_label = _back_label(attachment, font, bone_rest, NAME_HEIGHT, 64, 0.00115)


func _back_label(parent: Node3D, font: Font, bone_rest: Transform3D, height: float, font_size: int, pixel_size: float) -> Label3D:
	var label := Label3D.new()
	label.font = font
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# The model faces +Z in skeleton space, so the back is -Z; turn the text to face that way.
	var on_back := Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, height, bone_rest.origin.z - BACK_DEPTH))
	label.transform = bone_rest.affine_inverse() * on_back
	parent.add_child(label)
	return label


## Sets a bone's target orientation: its rest orientation carried along by a rotation of the
## body given in puppet space.
func _turn(basis_for: Dictionary[int, Basis], bone: StringName, body_rotation: Basis) -> void:
	var index := _bone[bone]
	basis_for[index] = _to_skeleton.basis * body_rotation * _to_puppet.basis * _rest[index].basis


func _measure() -> void:
	var count := _skeleton.get_bone_count()
	_rest.resize(count)
	_local_rest.resize(count)
	_parent.resize(count)
	for i: int in count:
		_bone[StringName(_skeleton.get_bone_name(i))] = i
		_rest[i] = _skeleton.get_bone_global_rest(i)
		_local_rest[i] = _skeleton.get_bone_rest(i)
		_parent[i] = _skeleton.get_bone_parent(i)
	for pair: Array in LIMBS:
		var from: StringName = pair[0]
		var to: StringName = pair[1]
		_aim_rest[from] = (_origin(to) - _origin(from)).normalized()

	upper_arm = _origin(&"LeftUpperArm").distance_to(_origin(&"LeftLowerArm"))
	lower_arm = _origin(&"LeftLowerArm").distance_to(_origin(&"LeftHand"))
	upper_leg = _origin(&"LeftUpperLeg").distance_to(_origin(&"LeftLowerLeg"))
	lower_leg = _origin(&"LeftLowerLeg").distance_to(_origin(&"LeftFoot"))
	shoulder_half = absf(_origin(&"LeftUpperArm").x - _origin(&"RightUpperArm").x) * 0.5
	hip_half = absf(_origin(&"LeftUpperLeg").x - _origin(&"RightUpperLeg").x) * 0.5
	var hip_mid := _origin(&"LeftUpperLeg").lerp(_origin(&"RightUpperLeg"), 0.5)
	var shoulder_mid := _origin(&"LeftUpperArm").lerp(_origin(&"RightUpperArm"), 0.5)
	spine = shoulder_mid.distance_to(hip_mid) + shoulder_drop
	_hips_offset = _origin(&"Hips") - hip_mid


func _origin(bone: StringName) -> Vector3:
	return _rest[_bone[bone]].origin


static var _shared_grain: NoiseTexture2D


static func _grain() -> NoiseTexture2D:
	if _shared_grain == null:
		_shared_grain = GreyboxField.grain_texture(true)
	return _shared_grain


func _paint() -> void:
	var colours := {
		"Skin": skin, "Jersey": jersey, "Pants": pants, "Socks": cap, "Cap": cap, "Helmet": cap,
		"Shoes": Color(0.06, 0.06, 0.07), "Belt": Color(0.05, 0.05, 0.06),
	}
	for part: MeshInstance3D in [_mesh, _cap, _helmet] as Array[MeshInstance3D]:
		for surface: int in part.mesh.get_surface_count():
			var source := part.mesh.surface_get_material(surface).resource_name
			var material := StandardMaterial3D.new()
			material.albedo_color = colours.get(source, Color.WHITE)
			material.roughness = {"Skin": 0.5, "Helmet": 0.22, "Shoes": 0.45, "Belt": 0.4}.get(source, 0.85)
			if source == "Helmet":
				material.clearcoat_enabled = true
				material.clearcoat = 0.6
			else:
				# Fine surface grain so cloth and skin catch the light unevenly instead of
				# reading as flat paint. Projected in object space, so it needs no UVs.
				material.normal_enabled = true
				material.normal_texture = _grain()
				material.normal_scale = 0.18 if source == "Skin" else 0.5
				material.uv1_triplanar = true
				material.uv1_scale = Vector3.ONE * (22.0 if source == "Skin" else 13.0)
				material.rim_enabled = true
				material.rim = 0.18
				material.rim_tint = 0.6
			if source == "Cap" or source == "Helmet":
				material.cull_mode = BaseMaterial3D.CULL_DISABLED
			part.set_surface_override_material(surface, material)
