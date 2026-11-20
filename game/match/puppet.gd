class_name Puppet
extends Node3D
## Greybox mannequin: capsules and spheres placed between joint positions that are worked
## out from a PuppetPose with two-bone IK. Joint names follow the final skeleton's bone names
## so the same poses can drive the real player model from stage S3b on.

const HEAD_RADIUS := 0.115

## Body proportions in metres. SkinnedPuppet replaces these with the model's own.
var spine := 0.5
var shoulder_half := 0.19
## How far below the top of the spine the shoulder joints sit.
var shoulder_drop := 0.07
var hip_half := 0.1
var upper_arm := 0.29
var lower_arm := 0.27
var upper_leg := 0.44
var lower_leg := 0.43

@export var jersey := Color(0.9, 0.9, 0.93)
@export var pants := Color(0.82, 0.82, 0.85)
@export var cap := Color(0.1, 0.15, 0.35)
@export var skin := Color(0.85, 0.66, 0.52)
@export var show_bat := false
@export var show_glove := true

## How a hand is held. Only the skinned model has fingers; the mannequin ignores this.
enum Grip { RELAXED, BAT, BALL, GLOVE }

var left_grip: Grip = Grip.RELAXED
var right_grip: Grip = Grip.RELAXED
## &"cap" or &"helmet".
var headgear: StringName = &"cap"
## Extra equipment worn over the uniform: any of &"Mask", &"ChestProtector", &"ShinGuards".
var gear: Array[StringName] = []
## Point the head should face, in the puppet's space. Used when has_look_target is true.
var look_target := Vector3.ZERO
var has_look_target := false

## Joint positions from the last apply(), keyed by bone name, in the puppet's space.
var joints: Dictionary[StringName, Vector3] = {}

var _parts: Dictionary[StringName, MeshInstance3D] = {}


func _ready() -> void:
	_limb(&"Torso", 0.16, spine + 0.1, jersey)
	_ball(&"Hips", 0.15, pants)
	_ball(&"Head", HEAD_RADIUS, skin)
	_ball(&"Cap", HEAD_RADIUS * 1.04, cap)
	for side: String in ["Left", "Right"]:
		_limb(StringName(side + "UpperArm"), 0.052, upper_arm, jersey)
		_limb(StringName(side + "LowerArm"), 0.043, lower_arm, skin)
		_limb(StringName(side + "UpperLeg"), 0.078, upper_leg, pants)
		_limb(StringName(side + "LowerLeg"), 0.058, lower_leg, pants)
		_ball(StringName(side + "Hand"), 0.05, skin)
		_box(StringName(side + "Foot"), Vector3(0.1, 0.07, 0.26), Color(0.08, 0.08, 0.08))
	_build_props()
	apply(PuppetClips.fielder_ready())


func _build_props() -> void:
	_limb(&"Bat", 0.03, PuppetClips.BAT_LENGTH, Color(0.72, 0.56, 0.36))
	_ball(&"Glove", 0.085, Color(0.42, 0.25, 0.12))


func set_colors(jersey_color: Color, pants_color: Color, cap_color: Color) -> void:
	jersey = jersey_color
	pants = pants_color
	cap = cap_color


## Frames worked out by solve(), in the puppet's space.
var hip_basis := Basis.IDENTITY
var chest_basis := Basis.IDENTITY
var spine_dir := Vector3.UP


## Makes the head face a point given in world space.
func look_at_world(world_point: Vector3) -> void:
	look_target = to_local(world_point)
	has_look_target = true


## Name and number shown on the back of the jersey. The mannequin has no jersey to print on.
func set_back_lettering(_number: int, _player_name: String, _ink: Color = Color.BLACK) -> void:
	pass


func apply(pose: PuppetPose) -> void:
	solve(pose)
	_place_limb(&"Torso", pose.hips - spine_dir * 0.05, joints[&"Chest"] + spine_dir * 0.05)
	_place(&"Hips", pose.hips)
	_place(&"Head", joints[&"Head"])
	_place(&"Cap", joints[&"Head"] + spine_dir * 0.035 + chest_basis * Vector3.FORWARD * 0.012)
	for side: String in ["Left", "Right"]:
		_place_limb(StringName(side + "UpperArm"), joints[StringName(side + "UpperArm")], joints[StringName(side + "LowerArm")])
		_place_limb(StringName(side + "LowerArm"), joints[StringName(side + "LowerArm")], joints[StringName(side + "Hand")])
		_place(StringName(side + "Hand"), joints[StringName(side + "Hand")])
		_place_limb(StringName(side + "UpperLeg"), joints[StringName(side + "UpperLeg")], joints[StringName(side + "LowerLeg")])
		_place_limb(StringName(side + "LowerLeg"), joints[StringName(side + "LowerLeg")], joints[StringName(side + "Foot")])
		var foot := _parts[StringName(side + "Foot")]
		foot.transform = Transform3D(hip_basis, joints[StringName(side + "Foot")] + hip_basis * Vector3.FORWARD * 0.07 - Vector3.UP * 0.045)
	_place_props(pose)


## Works out every joint position for a pose with two-bone IK and stores them in `joints`.
func solve(pose: PuppetPose) -> void:
	hip_basis = Basis(Vector3.UP, pose.hips_yaw)
	chest_basis = Basis(Vector3.UP, pose.hips_yaw + pose.twist)
	var forward := hip_basis * Vector3.FORWARD
	spine_dir = (Vector3.UP * cos(pose.lean) + forward * sin(pose.lean)).normalized()
	var chest_top := pose.hips + spine_dir * spine
	var chest_right := chest_basis * Vector3.RIGHT
	var chest_forward := chest_basis * Vector3.FORWARD
	var hip_right := hip_basis * Vector3.RIGHT

	joints[&"Hips"] = pose.hips
	joints[&"Chest"] = chest_top
	joints[&"Head"] = chest_top + spine_dir * (0.1 + HEAD_RADIUS)
	for side: int in [-1, 1] as Array[int]:
		var name := "Right" if side > 0 else "Left"
		var shoulder := chest_top - spine_dir * shoulder_drop + chest_right * (shoulder_half * side)
		var hand_target := pose.r_hand if side > 0 else pose.l_hand
		var elbow_hint := chest_right * (0.5 * side) - Vector3.UP - chest_forward * 0.5
		var hand := _reach(shoulder, hand_target, upper_arm + lower_arm)
		joints[StringName(name + "UpperArm")] = shoulder
		joints[StringName(name + "LowerArm")] = _two_bone(shoulder, hand, upper_arm, lower_arm, elbow_hint)
		joints[StringName(name + "Hand")] = hand

		var hip := pose.hips + hip_right * (hip_half * side)
		var foot_target := pose.r_foot if side > 0 else pose.l_foot
		var ankle := _reach(hip, foot_target, upper_leg + lower_leg)
		joints[StringName(name + "UpperLeg")] = hip
		joints[StringName(name + "LowerLeg")] = _two_bone(hip, ankle, upper_leg, lower_leg, forward + hip_right * (0.3 * side))
		joints[StringName(name + "Foot")] = ankle


## Places the bat along the pose's bat direction from the hands, and the glove on the left hand.
func _place_props(pose: PuppetPose) -> void:
	var bat := _parts[&"Bat"]
	bat.visible = show_bat and pose.bat_dir.length() > 0.1
	if bat.visible:
		var grip: Vector3 = joints[&"LeftHand"].lerp(joints[&"RightHand"], 0.5)
		_place_limb(&"Bat", grip - pose.bat_dir * 0.08, grip + pose.bat_dir * (PuppetClips.BAT_LENGTH - 0.08))
	var glove := _parts[&"Glove"]
	glove.visible = show_glove and not bat.visible
	glove.position = joints[&"LeftHand"]


## Position of the bat's barrel (the sweet spot) in world space, or the right hand if no bat.
func barrel_world() -> Vector3:
	return global_transform * joints.get(&"RightHand", Vector3.ZERO)


static func _reach(root: Vector3, target: Vector3, max_length: float) -> Vector3:
	var to := target - root
	var d := to.length()
	if d <= max_length * 0.999:
		return target
	return root + to / d * (max_length * 0.999)


## Middle joint of a two-bone chain from a to c; hint says which way the joint bends.
static func _two_bone(a: Vector3, c: Vector3, l1: float, l2: float, hint: Vector3) -> Vector3:
	var ac := c - a
	var d := clampf(ac.length(), 0.001, l1 + l2 - 0.0005)
	var dir := ac / maxf(ac.length(), 0.001)
	var x := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - x * x, 0.0))
	var perp := hint - dir * hint.dot(dir)
	if perp.length() < 1e-5:
		perp = dir.cross(Vector3.RIGHT)
	return a + dir * x + perp.normalized() * h


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	return m


func _add_part(part: StringName, mesh: Mesh, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(color)
	add_child(mi)
	_parts[part] = mi


func _limb(part: StringName, radius: float, length: float, color: Color) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = length + radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 4
	_add_part(part, mesh, color)


func _ball(part: StringName, radius: float, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	_add_part(part, mesh, color)


func _box(part: StringName, size: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add_part(part, mesh, color)


func _place(part: StringName, at: Vector3) -> void:
	_parts[part].position = at


func _place_limb(part: StringName, from: Vector3, to: Vector3) -> void:
	var axis := to - from
	var length := axis.length()
	if length < 1e-5:
		return
	var y := axis / length
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 1e-4:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	_parts[part].transform = Transform3D(Basis(x, y, x.cross(y)), from + axis * 0.5)
