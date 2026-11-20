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

var _skeleton: Skeleton3D
var _mesh: MeshInstance3D
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
	_mesh = model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var node: Node3D = _skeleton
	while node != self:
		_to_puppet = node.transform * _to_puppet
		node = node.get_parent() as Node3D
	_to_skeleton = _to_puppet.affine_inverse()
	_measure()
	_paint()
	_build_props()
	apply(PuppetClips.fielder_ready())


func set_colors(jersey_color: Color, pants_color: Color, cap_color: Color) -> void:
	super.set_colors(jersey_color, pants_color, cap_color)
	if _mesh != null:
		_paint()


func apply(pose: PuppetPose) -> void:
	solve(pose)
	var basis_for: Dictionary[int, Basis] = {}

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
	var globals := _walk(basis_for, pose)
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
	globals = _walk(basis_for, pose)
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
func _walk(basis_for: Dictionary[int, Basis], pose: PuppetPose) -> Array[Transform3D]:
	var globals: Array[Transform3D] = []
	globals.resize(_rest.size())
	var hips := _bone[&"Hips"]
	for i: int in _rest.size():
		var parent_global := Transform3D.IDENTITY if _parent[i] < 0 else globals[_parent[i]]
		var g := parent_global * _local_rest[i]
		if basis_for.has(i):
			g.basis = basis_for[i]
		if i == hips:
			g.origin = _to_skeleton * pose.hips + g.basis * (_rest[i].basis.inverse() * _hips_offset)
		globals[i] = g
	return globals


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


func _paint() -> void:
	var colours := {
		"Skin": skin, "Jersey": jersey, "Pants": pants, "Socks": cap, "Cap": cap,
		"Shoes": Color(0.06, 0.06, 0.07), "Belt": Color(0.05, 0.05, 0.06),
	}
	for surface: int in _mesh.mesh.get_surface_count():
		var source := _mesh.mesh.surface_get_material(surface)
		var material := StandardMaterial3D.new()
		material.albedo_color = colours.get(source.resource_name, Color.WHITE)
		material.roughness = 0.55 if source.resource_name == "Skin" else 0.8
		if source.resource_name == "Cap":
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mesh.set_surface_override_material(surface, material)
